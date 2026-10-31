package api

import (
	"bytes"
	"context"
	"errors"
	"fmt"
	"io"
	"net/http"
	"slices"
	"strconv"
	"strings"
	"time"

	"github.com/go-chi/chi/v5"
	"github.com/jackc/pgx/v5"

	"github.com/nc1107/new-me/server/internal/db"
	"github.com/nc1107/new-me/server/internal/engine"
	"github.com/nc1107/new-me/server/internal/push"
	"github.com/nc1107/new-me/server/internal/score"
	"github.com/nc1107/new-me/server/internal/together"
)

var errNoSharedHabit = newErr(http.StatusNotFound, codeNotFound, "no such shared habit")

type sharedScheduleJSON struct {
	Kind      string `json:"kind"`
	Weekdays  []int  `json:"weekdays"`
	EveryDays *int   `json:"everyDays"`
}

// sharedDoerJSON is one person who did a chore and the gems they got for it.
type sharedDoerJSON struct {
	UserID int64  `json:"userId"`
	Name   string `json:"name"`
	Gems   int    `json:"gems"`
}

// sharedLastJSON is the latest completion. UserID is who marked it, the only person who can undo
// it; Doers are the people it counts for, one alone or both when it was done together.
type sharedLastJSON struct {
	UserID   int64            `json:"userId"`
	Name     string           `json:"name"`
	At       string           `json:"at"`
	Together bool             `json:"together"`
	Doers    []sharedDoerJSON `json:"doers"`
}

func sharedDoers(m db.SharedMark, names map[int64]string) []sharedDoerJSON {
	marker := sharedDoerJSON{UserID: m.UserID, Name: names[m.UserID], Gems: m.Points}
	if m.OtherUserID == nil {
		return []sharedDoerJSON{marker}
	}
	other := sharedDoerJSON{UserID: *m.OtherUserID, Name: names[*m.OtherUserID], Gems: m.OtherPoints}
	if m.DoneBy == score.SharedByPartner {
		return []sharedDoerJSON{other}
	}
	return []sharedDoerJSON{marker, other}
}

// sharedHabitJSON is a shared habit as one viewer sees it: DueOn and DaysFromToday are in the
// viewer's own zone, DaysFromToday being negative when overdue.
type sharedHabitJSON struct {
	ID       int64              `json:"id"`
	Name     string             `json:"name"`
	Icon     string             `json:"icon"`
	Schedule sharedScheduleJSON `json:"schedule"`
	// Last is who did it last and when, null while it never was.
	Last          *sharedLastJSON `json:"last"`
	State         string          `json:"state"`
	DueOn         score.Date      `json:"dueOn"`
	DaysFromToday int             `json:"daysFromToday"`
	// DoneToday is true when anyone did it on the viewer's today; DoneByMe when that was the viewer.
	DoneToday bool `json:"doneToday"`
	DoneByMe  bool `json:"doneByMe"`
	// Gems is the worth both people agreed on. ProposedWorth is a number waiting for an answer
	// from the person who did not propose it; until then Gems is what a completion pays.
	Gems           int    `json:"gems"`
	ProposedWorth  *int   `json:"proposedWorth"`
	ProposedBy     *int64 `json:"proposedBy"`
	ProposedByName string `json:"proposedByName"`
}

func (s *Server) toSharedHabitJSON(h db.SharedHabit, last *db.SharedMark, names map[int64]string, c caller) sharedHabitJSON {
	today := score.LocalToday(s.now(), c.loc)
	var lastDay *score.Date
	var lastJSON *sharedLastJSON
	doneToday, doneByMe := false, false
	if last != nil {
		d := score.DateOf(last.DoneAt.In(c.loc))
		lastDay = &d
		lastJSON = &sharedLastJSON{UserID: last.UserID, Name: names[last.UserID], At: wireTime(last.DoneAt),
			Together: last.DoneBy == score.SharedByTogether, Doers: sharedDoers(*last, names)}
		doneToday = d == today
		doneByMe = doneToday && last.UserID == c.user.ID
	}
	st := score.SharedDue(h.Schedule(), h.StartOn, lastDay, today)
	days := []int{}
	if h.Kind == score.SharedWeekdays {
		days = score.ISOWeekdays(h.Weekdays)
	}
	out := sharedHabitJSON{ID: h.ID, Name: h.Name, Icon: h.Icon,
		Schedule: sharedScheduleJSON{Kind: h.Kind, Weekdays: days, EveryDays: h.EveryDays},
		Last:     lastJSON, State: st.State, DueOn: st.DueOn, DaysFromToday: st.Days,
		DoneToday: doneToday, DoneByMe: doneByMe, Gems: h.Worth}
	if h.ProposedWorth != nil && h.ProposedBy != nil {
		out.ProposedWorth, out.ProposedBy, out.ProposedByName = h.ProposedWorth, h.ProposedBy, names[*h.ProposedBy]
	}
	return out
}

// sortShared puts overdue first (longest overdue first), then due today, then the upcoming ones
// by how soon they come round.
func sortShared(list []sharedHabitJSON) {
	slices.SortStableFunc(list, func(a, b sharedHabitJSON) int {
		if a.DaysFromToday != b.DaysFromToday {
			return a.DaysFromToday - b.DaysFromToday
		}
		return int(a.ID - b.ID)
	})
}

type sharedHabitRequest struct {
	Name     *string             `json:"name"`
	Icon     *string             `json:"icon"`
	Schedule *sharedScheduleJSON `json:"schedule"`
	// Worth is a number of gems the caller proposes for the chore.
	Worth *int `json:"worth"`
}

func (req sharedHabitRequest) apply(h *db.SharedHabit) *httpError {
	if req.Name != nil {
		name, herr := cleanName(*req.Name)
		if herr != nil {
			return herr
		}
		h.Name = name
	}
	if req.Icon != nil {
		h.Icon = *req.Icon
	}
	if req.Schedule != nil {
		sc := req.Schedule
		h.Kind, h.Weekdays, h.EveryDays = sc.Kind, score.AllWeekdays, nil
		if sc.Kind == score.SharedWeekdays {
			mask, ok := score.WeekdaysFromISO(sc.Weekdays)
			if !ok {
				return invalid("weekdays must list days from 1 (Monday) to 7 (Sunday)")
			}
			h.Weekdays = mask
		}
		if sc.Kind == score.SharedEveryN {
			h.EveryDays = sc.EveryDays
		}
	}
	if !slices.Contains(habitIcons, h.Icon) {
		return invalid("icon must be one of: " + strings.Join(habitIcons, ", "))
	}
	every := 0
	if h.EveryDays != nil {
		every = *h.EveryDays
	}
	if !score.ValidSharedSchedule(score.SharedSchedule{Kind: h.Kind, Weekdays: h.Weekdays, EveryDays: every}) {
		return invalid("schedule must be daily, weekdays with days, weekly, or every_n with everyDays from 2 to 365")
	}
	return nil
}

// proposeWorth records the caller's answer about a chore's worth and reports whether the partner
// has a new proposal to look at. With nobody to agree with, the number is simply set. The agreed
// worth changes only when the partner's own pending number is repeated back to them.
func proposeWorth(h *db.SharedHabit, worth int, from int64, hasPartner bool, now time.Time) (proposed bool, herr *httpError) {
	if !score.ValidSharedWorth(worth) {
		return false, invalid(fmt.Sprintf("worth must be from %d to %d gems", score.SharedMinWorth, score.SharedMaxWorth))
	}
	repeatsPartner := h.ProposedWorth != nil && *h.ProposedWorth == worth && h.ProposedBy != nil && *h.ProposedBy != from
	if !hasPartner || worth == h.Worth || repeatsPartner {
		h.Worth = worth
		h.ProposedWorth, h.ProposedBy, h.ProposedAt = nil, nil, nil
		return false, nil
	}
	h.ProposedWorth, h.ProposedBy, h.ProposedAt = &worth, &from, &now
	return true, nil
}

// notifyWorthProposal asks the partner to agree on what a chore is worth.
func (s *Server) notifyWorthProposal(to, from db.User, h db.SharedHabit) {
	s.together.Notify(to, push.Message{Kind: together.EventSharedHabit,
		Title: fmt.Sprintf("%s suggests %d gems for %s", from.Name, *h.ProposedWorth, h.Name),
		Body:  fmt.Sprintf("It pays %d for now. Agree, or suggest another number", h.Worth)})
}

func (s *Server) notifyWorthAgreed(to, from db.User, h db.SharedHabit) {
	s.together.Notify(to, push.Message{Kind: together.EventSharedHabit,
		Title: fmt.Sprintf("%s agreed: %s is worth %d gems", from.Name, h.Name, h.Worth),
		Body:  "Whoever does it earns that"})
}

func sharedHabitID(r *http.Request) (int64, *httpError) {
	id, err := strconv.ParseInt(chi.URLParam(r, "id"), 10, 64)
	if err != nil || id < 1 {
		return 0, errNoSharedHabit
	}
	return id, nil
}

// handleListSharedHabits lists the household's habits for the caller, due ones first.
func (s *Server) handleListSharedHabits(w http.ResponseWriter, r *http.Request) {
	c := callerFrom(r)
	list, err := s.sharedHabitsFor(r, s.db.Pool, c)
	if err != nil {
		fail(w, r, err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"habits": list})
}

func (s *Server) sharedHabitsFor(r *http.Request, q db.Querier, c caller) ([]sharedHabitJSON, error) {
	ctx := r.Context()
	habits, err := db.ListSharedHabits(ctx, q)
	if err != nil {
		return nil, err
	}
	marks, err := db.LastSharedMarks(ctx, q)
	if err != nil {
		return nil, err
	}
	users, err := db.ListUsers(ctx, q)
	if err != nil {
		return nil, err
	}
	names := make(map[int64]string, len(users))
	for _, u := range users {
		names[u.ID] = u.Name
	}
	out := make([]sharedHabitJSON, 0, len(habits))
	for _, h := range habits {
		var last *db.SharedMark
		if m, ok := marks[h.ID]; ok {
			last = &m
		}
		out = append(out, s.toSharedHabitJSON(h, last, names, c))
	}
	sortShared(out)
	return out, nil
}

// oneShared is the habit with the given id as the caller sees it now.
func (s *Server) oneShared(r *http.Request, q db.Querier, c caller, id int64) (sharedHabitJSON, error) {
	list, err := s.sharedHabitsFor(r, q, c)
	if err != nil {
		return sharedHabitJSON{}, err
	}
	for _, h := range list {
		if h.ID == id {
			return h, nil
		}
	}
	return sharedHabitJSON{}, errNoSharedHabit
}

// handleCreateSharedHabit adds a household habit that both people see. A worth other than the
// default is a proposal, and pays the default until the partner agrees.
func (s *Server) handleCreateSharedHabit(w http.ResponseWriter, r *http.Request) {
	var req sharedHabitRequest
	if err := decodeJSON(r, &req); err != nil {
		fail(w, r, err)
		return
	}
	if req.Name == nil || req.Icon == nil || req.Schedule == nil {
		fail(w, r, invalid("name, icon and schedule are required"))
		return
	}
	c := callerFrom(r)
	h := db.SharedHabit{CreatedBy: c.user.ID, StartOn: score.LocalToday(s.now(), c.loc),
		Weekdays: score.AllWeekdays, Worth: score.SharedHabitGems}
	if herr := req.apply(&h); herr != nil {
		fail(w, r, herr)
		return
	}
	ctx := r.Context()
	var (
		out      sharedHabitJSON
		proposed bool
		partner  *db.User
	)
	err := s.db.WithTx(ctx, func(tx pgx.Tx) error {
		if err := db.LockSharedHabits(ctx, tx); err != nil {
			return err
		}
		n, err := db.CountSharedHabits(ctx, tx)
		if err != nil {
			return err
		}
		if n >= db.MaxSharedHabits {
			return invalid("at most 40 shared habits")
		}
		if partner, err = s.partnerOf(ctx, tx, c.user.ID); err != nil {
			return err
		}
		if req.Worth != nil {
			var herr *httpError
			if proposed, herr = proposeWorth(&h, *req.Worth, c.user.ID, partner != nil, s.now()); herr != nil {
				return herr
			}
		}
		created, err := db.CreateSharedHabit(ctx, tx, h)
		if err != nil {
			return err
		}
		h = created
		out, err = s.oneShared(r, tx, c, created.ID)
		return err
	})
	if err != nil {
		fail(w, r, err)
		return
	}
	if proposed {
		s.notifyWorthProposal(*partner, c.user, h)
	}
	writeJSON(w, http.StatusCreated, map[string]any{"habit": out})
}

// handlePatchSharedHabit edits a household habit. Either person may. A worth is a proposal for
// the partner, who can accept it by repeating it or counter with another.
func (s *Server) handlePatchSharedHabit(w http.ResponseWriter, r *http.Request) {
	id, herr := sharedHabitID(r)
	if herr != nil {
		fail(w, r, herr)
		return
	}
	var req sharedHabitRequest
	if err := decodeJSON(r, &req); err != nil {
		fail(w, r, err)
		return
	}
	c := callerFrom(r)
	ctx := r.Context()
	var (
		out      sharedHabitJSON
		habit    db.SharedHabit
		partner  *db.User
		proposed bool
		agreed   bool
	)
	err := s.db.WithTx(ctx, func(tx pgx.Tx) error {
		h, err := db.GetSharedHabit(ctx, tx, id, true)
		if errors.Is(err, db.ErrNotFound) {
			return errNoSharedHabit
		}
		if err != nil {
			return err
		}
		if herr := req.apply(&h); herr != nil {
			return herr
		}
		if req.Worth != nil {
			if partner, err = s.partnerOf(ctx, tx, c.user.ID); err != nil {
				return err
			}
			before := h.Worth
			var herr *httpError
			if proposed, herr = proposeWorth(&h, *req.Worth, c.user.ID, partner != nil, s.now()); herr != nil {
				return herr
			}
			agreed = !proposed && partner != nil && h.Worth != before
		}
		if habit, err = db.UpdateSharedHabit(ctx, tx, h); err != nil {
			return err
		}
		out, err = s.oneShared(r, tx, c, id)
		return err
	})
	if err != nil {
		fail(w, r, err)
		return
	}
	switch {
	case proposed:
		s.notifyWorthProposal(*partner, c.user, habit)
	case agreed:
		s.notifyWorthAgreed(*partner, c.user, habit)
	}
	writeJSON(w, http.StatusOK, map[string]any{"habit": out})
}

// handleAcceptSharedWorth agrees to the worth the partner proposed for a chore.
func (s *Server) handleAcceptSharedWorth(w http.ResponseWriter, r *http.Request) {
	id, herr := sharedHabitID(r)
	if herr != nil {
		fail(w, r, herr)
		return
	}
	c := callerFrom(r)
	ctx := r.Context()
	var (
		out     sharedHabitJSON
		habit   db.SharedHabit
		partner *db.User
	)
	err := s.db.WithTx(ctx, func(tx pgx.Tx) error {
		h, err := db.GetSharedHabit(ctx, tx, id, true)
		if errors.Is(err, db.ErrNotFound) {
			return errNoSharedHabit
		}
		if err != nil {
			return err
		}
		if h.ProposedWorth == nil || h.ProposedBy == nil || *h.ProposedBy == c.user.ID {
			return invalid("there is no worth from your partner to agree to")
		}
		h.Worth = *h.ProposedWorth
		h.ProposedWorth, h.ProposedBy, h.ProposedAt = nil, nil, nil
		if habit, err = db.UpdateSharedHabit(ctx, tx, h); err != nil {
			return err
		}
		if partner, err = s.partnerOf(ctx, tx, c.user.ID); err != nil {
			return err
		}
		out, err = s.oneShared(r, tx, c, id)
		return err
	})
	if err != nil {
		fail(w, r, err)
		return
	}
	if partner != nil {
		s.notifyWorthAgreed(*partner, c.user, habit)
	}
	writeJSON(w, http.StatusOK, map[string]any{"habit": out})
}

// handleDeleteSharedHabit removes a household habit for both people. Gems already earned from it
// stay, because they are on days that may be finalized.
func (s *Server) handleDeleteSharedHabit(w http.ResponseWriter, r *http.Request) {
	id, herr := sharedHabitID(r)
	if herr != nil {
		fail(w, r, herr)
		return
	}
	if err := db.SoftDeleteSharedHabit(r.Context(), s.db.Pool, id); err != nil {
		if errors.Is(err, db.ErrNotFound) {
			err = errNoSharedHabit
		}
		fail(w, r, err)
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

type sharedDoneRequest struct {
	// By is who did it: self (the default), partner or together.
	By *string `json:"by"`
}

// decodeOptionalJSON reads a body that may be empty, which older clients send for a plain tap.
func decodeOptionalJSON(r *http.Request, v any) error {
	raw, err := io.ReadAll(r.Body)
	if err != nil {
		return newErr(http.StatusBadRequest, codeInvalidJSON, "request body could not be read")
	}
	if len(bytes.TrimSpace(raw)) == 0 {
		return nil
	}
	r.Body = io.NopCloser(bytes.NewReader(raw))
	return decodeJSON(r, v)
}

// lockDays takes the day locks of every (person, day) the write touches in one fixed order, so two
// people marking different chores at once cannot wait on each other.
func lockDays(ctx context.Context, tx pgx.Tx, days map[int64]score.Date) error {
	ids := make([]int64, 0, len(days))
	for id := range days {
		ids = append(ids, id)
	}
	slices.Sort(ids)
	for _, id := range ids {
		if err := db.LockUserDay(ctx, tx, id, days[id]); err != nil {
			return err
		}
	}
	return nil
}

// handleDoneSharedHabit records that the chore was done, by the caller, by their partner or by
// both, and credits the gems. When it was already done on the caller's day, by either person,
// nothing changes and nothing is paid, so a stale screen or a double tap cannot earn twice.
func (s *Server) handleDoneSharedHabit(w http.ResponseWriter, r *http.Request) {
	id, herr := sharedHabitID(r)
	if herr != nil {
		fail(w, r, herr)
		return
	}
	var req sharedDoneRequest
	if err := decodeOptionalJSON(r, &req); err != nil {
		fail(w, r, err)
		return
	}
	by := score.SharedBySelf
	if req.By != nil {
		by = *req.By
	}
	c := callerFrom(r)
	ctx := r.Context()
	now := s.now()
	today := score.LocalToday(now, c.loc)
	var (
		out          sharedHabitJSON
		mark         *db.SharedMark
		habit        db.SharedHabit
		partner      *db.User
		mine, theirs int
	)
	err := s.db.WithTx(ctx, func(tx pgx.Tx) error {
		var err error
		if habit, err = db.GetSharedHabit(ctx, tx, id, true); err != nil {
			if errors.Is(err, db.ErrNotFound) {
				return errNoSharedHabit
			}
			return err
		}
		var ok bool
		if mine, theirs, ok = score.SharedCredit(by, habit.Worth); !ok {
			return invalid("by must be self, partner or together")
		}
		if partner, err = s.partnerOf(ctx, tx, c.user.ID); err != nil {
			return err
		}
		if by != score.SharedBySelf && partner == nil {
			return invalid("there is nobody else to share the chore with")
		}
		last, err := db.PeekLastSharedMark(ctx, tx, id)
		switch {
		case err == nil && score.DateOf(last.DoneAt.In(c.loc)) == today:
			mine, theirs = 0, 0
		case err != nil && !errors.Is(err, db.ErrNotFound):
			return err
		default:
			if !s.writable(c.user, c.loc, today) {
				return errDateClosed
			}
			m := db.SharedMark{SharedHabitID: id, UserID: c.user.ID, LocalDate: today, DoneAt: now,
				Points: mine, DoneBy: by}
			days := map[int64]score.Date{c.user.ID: today}
			var ploc *time.Location
			if by != score.SharedBySelf {
				if ploc, err = partner.Location(); err != nil {
					return err
				}
				pday := score.LocalToday(now, ploc)
				m.OtherUserID, m.OtherLocalDate, m.OtherPoints = &partner.ID, &pday, theirs
				days[partner.ID] = pday
			}
			if err := lockDays(ctx, tx, days); err != nil {
				return err
			}
			inserted, err := db.InsertSharedMark(ctx, tx, m)
			if err != nil {
				return err
			}
			mark = &inserted
			if _, err := s.scoreDay(ctx, tx, c, today); err != nil {
				return err
			}
			if mark.OtherLocalDate != nil {
				if _, err := engine.ScoreAt(ctx, tx, partner.ID, *mark.OtherLocalDate, ploc, now); err != nil {
					return err
				}
			}
		}
		out, err = s.oneShared(r, tx, c, id)
		return err
	})
	if err != nil {
		fail(w, r, err)
		return
	}
	if mark != nil {
		s.notifySharedDone(c.user, partner, habit, *mark)
	}
	writeJSON(w, http.StatusOK, map[string]any{"habit": out, "gemsEarned": mine, "partnerGems": theirs})
}

// notifySharedDone tells the partner a chore was taken care of, and what it paid them when it
// counts for them too. Quiet hours and the partner's switches are applied by the notifier.
func (s *Server) notifySharedDone(from db.User, partner *db.User, h db.SharedHabit, m db.SharedMark) {
	if partner == nil {
		return
	}
	msg := push.Message{Kind: together.EventSharedHabit, Title: from.Name + " did " + h.Name,
		Body: "One less thing on the shared list"}
	switch m.DoneBy {
	case score.SharedBySelf:
	case score.SharedByTogether:
		msg.Title = from.Name + " did " + h.Name + " with you"
		msg.Body = fmt.Sprintf("You earned %d gems", m.OtherPoints)
	default:
		msg.Title = from.Name + " marked " + h.Name + " done for you"
		msg.Body = fmt.Sprintf("You earned %d gems", m.OtherPoints)
	}
	s.together.Notify(*partner, msg)
}

// handleUndoSharedHabit takes back the caller's own latest mark of the chore, while the day it
// counted on is still open and the partner has not marked it since. Gems leave both people.
func (s *Server) handleUndoSharedHabit(w http.ResponseWriter, r *http.Request) {
	id, herr := sharedHabitID(r)
	if herr != nil {
		fail(w, r, herr)
		return
	}
	c := callerFrom(r)
	ctx := r.Context()
	var out sharedHabitJSON
	err := s.db.WithTx(ctx, func(tx pgx.Tx) error {
		if _, err := db.GetSharedHabit(ctx, tx, id, true); err != nil {
			if errors.Is(err, db.ErrNotFound) {
				return errNoSharedHabit
			}
			return err
		}
		last, err := db.PeekLastSharedMark(ctx, tx, id)
		if errors.Is(err, db.ErrNotFound) || (err == nil && last.UserID != c.user.ID) {
			return invalid("there is nothing of yours to undo on that habit")
		}
		if err != nil {
			return err
		}
		if !s.writable(c.user, c.loc, last.LocalDate) {
			return errDateClosed
		}
		days := map[int64]score.Date{c.user.ID: last.LocalDate}
		if last.OtherUserID != nil {
			days[*last.OtherUserID] = *last.OtherLocalDate
		}
		if err := lockDays(ctx, tx, days); err != nil {
			return err
		}
		if err := db.DeleteSharedMark(ctx, tx, last.ID); err != nil {
			return err
		}
		if _, err := s.scoreDay(ctx, tx, c, last.LocalDate); err != nil {
			return err
		}
		if last.OtherUserID != nil {
			other, err := db.GetUser(ctx, tx, *last.OtherUserID)
			if err != nil {
				return err
			}
			oloc, err := other.Location()
			if err != nil {
				return err
			}
			if _, err := engine.ScoreAt(ctx, tx, other.ID, *last.OtherLocalDate, oloc, s.now()); err != nil {
				return err
			}
		}
		out, err = s.oneShared(r, tx, c, id)
		return err
	})
	if err != nil {
		fail(w, r, err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"habit": out})
}
