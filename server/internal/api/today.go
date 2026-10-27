package api

import (
	"math"
	"net/http"

	"github.com/jackc/pgx/v5"

	"github.com/nc1107/new-me/server/internal/db"
	"github.com/nc1107/new-me/server/internal/engine"
	"github.com/nc1107/new-me/server/internal/score"
)

type streakJSON struct {
	Current       int         `json:"current"`
	RestAvailable bool        `json:"restAvailable"`
	RestUsedOn    *score.Date `json:"restUsedOn"`
}

type foodJSON struct {
	Kcal    int         `json:"kcal"`
	Protein float64     `json:"protein"`
	Carbs   float64     `json:"carbs"`
	Fat     float64     `json:"fat"`
	Fiber   float64     `json:"fiber"`
	Burned  int         `json:"burned"`
	Targets targetsJSON `json:"targets"`
}

type healthStatusJSON struct {
	StepsEverSynced bool    `json:"stepsEverSynced"`
	SyncedAt        *string `json:"syncedAt"`
}

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
			Fiber: round1(in.FiberG), Burned: int(math.Round(in.ActiveEnergy)), Targets: toTargetsJSON(c.user),
		},
		Health: healthStatusJSON{StepsEverSynced: in.StepsConnected, SyncedAt: wireTimePtr(syncedAt)},
	})
}

// toStreakJSON reports the weekly rest allowance next to the count: it is ready while a streak
// is running and none has been spent in the current ISO week.
func toStreakJSON(streak score.StreakResult, today score.Date) streakJSON {
	out := streakJSON{Current: streak.Count}
	if used, ok := streak.RestUsedIn(score.WeekStart(today)); ok {
		out.RestUsedOn = &used
	}
	out.RestAvailable = streak.Count > 0 && out.RestUsedOn == nil
	return out
}
