package api

import (
	"context"
	"errors"
	"fmt"
	"net/http"

	"github.com/jackc/pgx/v5"

	"github.com/nc1107/new-me/server/internal/db"
	"github.com/nc1107/new-me/server/internal/engine"
	"github.com/nc1107/new-me/server/internal/push"
	"github.com/nc1107/new-me/server/internal/together"
)

var errNoHabitProposal = newErr(http.StatusNotFound, codeNotFound, "no such proposal")

// partnerOf is the other person on the server, nil when the caller is alone.
func (s *Server) partnerOf(ctx context.Context, q db.Querier, userID int64) (*db.User, error) {
	users, err := db.ListUsers(ctx, q)
	if err != nil {
		return nil, err
	}
	for i := range users {
		if users[i].ID != userID {
			return &users[i], nil
		}
	}
	return nil, nil
}

// notifyProposal tells the partner that a habit's gems wait for their answer.
func (s *Server) notifyProposal(to, from db.User, h db.Habit) {
	body := fmt.Sprintf("%s wants %s worth %d gems", from.Name, h.Name, *h.ProposedPoints)
	if h.ProposedMinutes != nil {
		body += fmt.Sprintf(" (%d min)", *h.ProposedMinutes)
	}
	s.together.Notify(to, push.Message{Kind: together.EventHabitProposal, Title: "Habit to approve", Body: body})
}

type habitProposalJSON struct {
	HabitID int64  `json:"habitId"`
	Name    string `json:"name"`
	Icon    string `json:"icon"`
	// Points and Minutes are what is proposed; Minutes is null for a proposal to only track.
	Points        int    `json:"points"`
	Minutes       *int   `json:"minutes"`
	CurrentPoints int    `json:"currentPoints"`
	At            string `json:"at"`
}

// handleHabitProposals lists the partner's habit changes that wait for the caller.
func (s *Server) handleHabitProposals(w http.ResponseWriter, r *http.Request) {
	c := callerFrom(r)
	ctx := r.Context()
	out := []habitProposalJSON{}
	from := ""
	partner, err := s.partnerOf(ctx, s.db.Pool, c.user.ID)
	if err == nil && partner != nil {
		from = partner.Name
		var pending []db.Habit
		if pending, err = db.PendingProposals(ctx, s.db.Pool, partner.ID); err == nil {
			for _, h := range pending {
				out = append(out, habitProposalJSON{HabitID: h.ID, Name: h.Name, Icon: h.Icon,
					Points: *h.ProposedPoints, Minutes: h.ProposedMinutes, CurrentPoints: h.Points,
					At: wireTime(*h.ProposedAt)})
			}
		}
	}
	if err != nil {
		fail(w, r, err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"from": from, "proposals": out})
}

func (s *Server) handleApproveHabit(w http.ResponseWriter, r *http.Request) {
	s.answerHabit(w, r, true)
}
func (s *Server) handleDeclineHabit(w http.ResponseWriter, r *http.Request) {
	s.answerHabit(w, r, false)
}

// answerHabit approves or declines the partner's pending change to a habit. Approving moves the
// proposed gems and minutes onto the habit and rescores the partner's open days like any other
// habit change; finalized days keep what they were finalized with. Declining only clears it.
func (s *Server) answerHabit(w http.ResponseWriter, r *http.Request, approve bool) {
	id, herr := habitID(r)
	if herr != nil {
		fail(w, r, herr)
		return
	}
	c := callerFrom(r)
	ctx := r.Context()
	partner, err := s.partnerOf(ctx, s.db.Pool, c.user.ID)
	if err != nil {
		fail(w, r, err)
		return
	}
	if partner == nil {
		fail(w, r, errNoHabitProposal)
		return
	}
	ploc, err := partner.Location()
	if err != nil {
		fail(w, r, err)
		return
	}
	var habit db.Habit
	err = s.db.WithTx(ctx, func(tx pgx.Tx) error {
		if err := db.LockHabits(ctx, tx, partner.ID); err != nil {
			return err
		}
		h, err := db.GetHabit(ctx, tx, partner.ID, id)
		if errors.Is(err, db.ErrNotFound) || (err == nil && h.ProposedAt == nil) {
			return errNoHabitProposal
		}
		if err != nil {
			return err
		}
		if approve {
			h.Points, h.Minutes = *h.ProposedPoints, h.ProposedMinutes
		}
		h.ProposedPoints, h.ProposedMinutes, h.ProposedAt = nil, nil, nil
		if habit, err = db.UpdateHabit(ctx, tx, h); err != nil {
			return err
		}
		if !approve {
			return nil
		}
		for _, date := range s.openDates(*partner, ploc) {
			if _, err := engine.ScoreAt(ctx, tx, partner.ID, date, ploc, s.now()); err != nil {
				return err
			}
		}
		return nil
	})
	if err != nil {
		fail(w, r, err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"habit": toHabitJSON(habit)})
}
