package api

import (
	"net/http"

	"github.com/jackc/pgx/v5"

	"github.com/nc1107/new-me/server/internal/db"
	"github.com/nc1107/new-me/server/internal/engine"
	"github.com/nc1107/new-me/server/internal/score"
)

var errNoPartner = newErr(http.StatusNotFound, codeNotFound, "no partner yet")

// partnerTodayJSON is what the partner has done on their own local today: the same quests,
// day and habits their Today screen draws, without their food, health or plan detail.
type partnerTodayJSON struct {
	ID     int64            `json:"id"`
	Name   string           `json:"name"`
	Date   score.Date       `json:"date"`
	Quests []questJSON      `json:"quests"`
	Day    dayJSON          `json:"day"`
	Streak streakJSON       `json:"streak"`
	Habits []habitStateJSON `json:"habits"`
}

// handlePartnerToday scores the partner's today in their own time zone, as their own Today
// read would, so both people see the same numbers.
func (s *Server) handlePartnerToday(w http.ResponseWriter, r *http.Request) {
	c := callerFrom(r)
	ctx := r.Context()
	partner, err := s.partnerOf(ctx, s.db.Pool, c.user.ID)
	if err != nil {
		fail(w, r, err)
		return
	}
	if partner == nil {
		fail(w, r, errNoPartner)
		return
	}
	loc, err := partner.Location()
	if err != nil {
		fail(w, r, err)
		return
	}
	now := s.now()
	today := score.LocalToday(now, loc)
	var (
		scored engine.Scored
		streak score.StreakResult
	)
	// This rescores and stores the partner's day exactly as their own Today read would, repair
	// included; scoring is deterministic, so reading it early changes nothing they would see.
	err = s.db.WithTx(ctx, func(tx pgx.Tx) error {
		var err error
		scored, streak, err = engine.ScoreWithStreak(ctx, tx, *partner, today, loc, now)
		return err
	})
	if err != nil {
		fail(w, r, err)
		return
	}
	habits, err := db.DueHabits(ctx, s.db.Pool, partner.ID, today)
	if err != nil {
		fail(w, r, err)
		return
	}
	writeJSON(w, http.StatusOK, partnerTodayJSON{
		ID: partner.ID, Name: partner.Name, Date: today,
		Quests: countingQuests(scored), Day: toDayJSON(scored), Streak: toStreakJSON(streak, today),
		Habits: toHabitStatesJSON(habits),
	})
}

// countingQuests leaves out quests that are not part of the day yet; the partner cannot
// connect Health for them, so "0 of 8,000 steps" would only read as a missed quest.
func countingQuests(s engine.Scored) []questJSON {
	out := make([]questJSON, 0, len(s.Score.Quests))
	for _, q := range toQuestsJSON(s) {
		if s.Counts(q.Key) {
			out = append(out, q)
		}
	}
	return out
}
