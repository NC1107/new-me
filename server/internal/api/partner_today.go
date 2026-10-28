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
	err = s.db.WithTx(ctx, func(tx pgx.Tx) error {
		var err error
		if scored, err = engine.ScoreAt(ctx, tx, partner.ID, today, loc, now); err != nil {
			return err
		}
		streak, err = engine.StreakFor(ctx, tx, *partner, now, loc)
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
		Quests: toQuestsJSON(scored), Day: toDayJSON(scored), Streak: toStreakJSON(streak, today),
		Habits: toHabitStatesJSON(habits),
	})
}
