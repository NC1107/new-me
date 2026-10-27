package api

import (
	"errors"
	"math"
	"net/http"

	"github.com/jackc/pgx/v5"

	"github.com/nc1107/new-me/server/internal/coach"
	"github.com/nc1107/new-me/server/internal/db"
	"github.com/nc1107/new-me/server/internal/engine"
	"github.com/nc1107/new-me/server/internal/plan"
	"github.com/nc1107/new-me/server/internal/readiness"
	"github.com/nc1107/new-me/server/internal/score"
)

type foodJSON struct {
	Kcal    int         `json:"kcal"`
	Protein float64     `json:"protein"`
	Carbs   float64     `json:"carbs"`
	Fat     float64     `json:"fat"`
	Fiber   float64     `json:"fiber"`
	Burned  int         `json:"burned"`
	Targets targetsJSON `json:"targets"`
}

type latestJSON struct {
	Value float64    `json:"value"`
	Date  score.Date `json:"date"`
}

type healthStatusJSON struct {
	StepsEverSynced bool                  `json:"stepsEverSynced"`
	SyncedAt        *string               `json:"syncedAt"`
	Metrics         map[string]float64    `json:"metrics"`
	Latest          map[string]latestJSON `json:"latest"`
}

// latestMetrics are the slow-moving body measurements worth showing as of their last reading.
var latestMetrics = []string{"weight_kg", "body_fat_pct", "lean_mass_kg", "vo2max"}

type todayJSON struct {
	Date          score.Date       `json:"date"`
	LocalToday    score.Date       `json:"localToday"`
	BackdateUntil *string          `json:"backdateUntil"`
	ServerNow     string           `json:"serverNow"`
	Quests        []questJSON      `json:"quests"`
	Day           dayJSON          `json:"day"`
	Streak        streakJSON       `json:"streak"`
	Food          foodJSON         `json:"food"`
	Health        healthStatusJSON `json:"health"`
	Listening     listeningJSON    `json:"listening"`
	// Habits are the day's due, unpaused habits with their state, in the person's order.
	Habits []habitStateJSON `json:"habits"`
	// Cheers are what the partner sent on the caller's local day.
	Cheers []cheerJSON `json:"cheers"`
	// Readiness and Plan are only for the caller's local today, and Readiness is null while
	// there is neither sleep nor a comparable heart reading to base it on.
	Readiness *readiness.Result `json:"readiness"`
	Plan      *planJSON         `json:"plan"`
	// Freezes, Repair and Away are the streak forgiveness state. Repair is the open window to
	// repair yesterday, null otherwise, and only on the caller's local today.
	Freezes score.Freezes `json:"freezes"`
	Repair  *repairJSON   `json:"repair"`
	Away    awayJSON      `json:"away"`
	// NewMilestones are the milestones reached yesterday or today, for a one-off celebration.
	NewMilestones []milestoneJSON `json:"newMilestones"`
}

type planJSON struct {
	Items   []plan.Item `json:"items"`
	Summary string      `json:"summary"`
}

// listeningJSON is the day's Audiobookshelf listening, already counted in the reading quest.
type listeningJSON struct {
	Minutes int `json:"minutes"`
	// SyncedAt is when Audiobookshelf was last read successfully; null while not linked.
	SyncedAt *string `json:"syncedAt"`
}

// handleToday scores the requested day (today unless ?date= names an earlier one the user has
// lived) and returns everything the Today screen draws. Reads rescore, so they are never stale.
func (s *Server) handleToday(w http.ResponseWriter, r *http.Request) {
	c := callerFrom(r)
	now := s.now()
	localToday := score.LocalToday(now, c.loc)
	date, herr := parseDateParam(r.URL.Query().Get("date"), localToday)
	if herr != nil {
		fail(w, r, herr)
		return
	}
	if date.After(localToday) || date.Before(c.user.JoinedOn) {
		fail(w, r, invalid("date must be between the day you joined and today"))
		return
	}

	ctx := r.Context()
	// Milestones are recorded where they are shown, so a streak that just reached 7 days is
	// celebrated on the Today that follows.
	s.milestones.RunQuietly(ctx)
	var (
		scored engine.Scored
		streak score.StreakResult
	)
	err := s.db.WithTx(ctx, func(tx pgx.Tx) error {
		var err error
		if scored, err = s.scoreDay(ctx, tx, c, date); err != nil {
			return err
		}
		streak, err = engine.StreakFor(ctx, tx, c.user, now, c.loc)
		return err
	})
	if err != nil {
		fail(w, r, err)
		return
	}
	syncedAt, err := db.LastHealthSync(ctx, s.db.Pool, c.user.ID)
	if err != nil {
		fail(w, r, err)
		return
	}

	latestRows, err := db.LatestHealth(ctx, s.db.Pool, c.user.ID, date, latestMetrics)
	if err != nil {
		fail(w, r, err)
		return
	}
	latest := make(map[string]latestJSON, len(latestRows))
	for key, m := range latestRows {
		latest[key] = latestJSON{Value: m.Value, Date: m.Date}
	}

	habits, err := db.DueHabits(ctx, s.db.Pool, c.user.ID, date)
	if err != nil {
		fail(w, r, err)
		return
	}
	cheers, err := s.cheersToday(ctx, c, localToday)
	if err != nil {
		fail(w, r, err)
		return
	}

	away, err := s.awayFor(ctx, s.db.Pool, c.user.ID, localToday)
	if err != nil {
		fail(w, r, err)
		return
	}
	recent, err := db.MilestonesSince(ctx, s.db.Pool, c.user.ID, localToday.AddDays(-1))
	if err != nil {
		fail(w, r, err)
		return
	}
	var repair *repairJSON
	if date == localToday {
		repair = toRepairJSON(engine.RepairFor(streak, c.user, now, c.loc), scored.Row.Percent)
	}

	var listenSyncedAt *string
	if s.listen != nil {
		acct, err := db.GetABSAccount(ctx, s.db.Pool, c.user.ID)
		if err != nil && !errors.Is(err, db.ErrNotFound) {
			fail(w, r, err)
			return
		}
		if err == nil {
			listenSyncedAt = wireTimePtr(acct.SyncedAt)
		}
	}
	var (
		ready   *readiness.Result
		planOut *planJSON
	)
	if date == localToday {
		day, err := coach.Load(ctx, s.db.Pool, c.user, c.loc, scored, habits, now)
		if err != nil {
			fail(w, r, err)
			return
		}
		ready = day.Readiness
		planOut = &planJSON{Items: day.Plan.Items, Summary: s.polisher.Summary(ctx, c.user, date, day)}
	}

	in := scored.Inputs
	writeJSON(w, http.StatusOK, todayJSON{
		Date:          date,
		LocalToday:    localToday,
		BackdateUntil: s.backdateUntil(c.user, c.loc),
		ServerNow:     wireTime(now),
		Quests:        toQuestsJSON(scored),
		Day:           toDayJSON(scored),
		Streak:        toStreakJSON(streak, localToday),
		Food: foodJSON{
			Kcal: in.Kcal, Protein: round1(in.ProteinG), Carbs: round1(in.CarbsG), Fat: round1(in.FatG),
			Fiber: round1(in.FiberG), Burned: int(math.Round(in.Metric(db.MetricActiveEnergy))), Targets: toTargetsJSON(c.user),
		},
		Health: healthStatusJSON{
			StepsEverSynced: in.Connected(db.MetricSteps), SyncedAt: wireTimePtr(syncedAt),
			Metrics: in.Metrics, Latest: latest,
		},
		Listening: listeningJSON{Minutes: in.ListeningMinutes, SyncedAt: listenSyncedAt},
		Habits:    toHabitStatesJSON(habits),
		Cheers:    cheers,
		Readiness: ready,
		Plan:      planOut,

		Freezes:       streak.Freezes,
		Repair:        repair,
		Away:          away,
		NewMilestones: toMilestonesJSON(recent),
	})
}
