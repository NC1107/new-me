package api

import (
	"errors"
	"net/http"
	"slices"
	"strconv"
	"strings"

	"github.com/go-chi/chi/v5"
	"github.com/jackc/pgx/v5"

	"github.com/nc1107/new-me/server/internal/db"
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

type sharedLastJSON struct {
	UserID int64  `json:"userId"`
	Name   string `json:"name"`
	At     string `json:"at"`
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
	Gems      int  `json:"gems"`
}

func (s *Server) toSharedHabitJSON(h db.SharedHabit, last *db.SharedMark, names map[int64]string, c caller) sharedHabitJSON {
	today := score.LocalToday(s.now(), c.loc)
	var lastDay *score.Date
	var lastJSON *sharedLastJSON
	doneToday, doneByMe := false, false
	if last != nil {
		d := score.DateOf(last.DoneAt.In(c.loc))
		lastDay = &d
		lastJSON = &sharedLastJSON{UserID: last.UserID, Name: names[last.UserID], At: wireTime(last.DoneAt)}
		doneToday = d == today
		doneByMe = doneToday && last.UserID == c.user.ID
	}
	st := score.SharedDue(h.Schedule(), h.StartOn, lastDay, today)
	return sharedHabitJSON{ID: h.ID, Name: h.Name, Icon: h.Icon,
		Schedule: sharedScheduleJSON{Kind: h.Kind, Weekdays: score.ISOWeekdays(h.Weekdays), EveryDays: h.EveryDays},
		Last:     lastJSON, State: st.State, DueOn: st.DueOn, DaysFromToday: st.Days,
		DoneToday: doneToday, DoneByMe: doneByMe, Gems: score.SharedHabitGems}
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

// handleCreateSharedHabit adds a household habit that both people see.
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
	h := db.SharedHabit{CreatedBy: c.user.ID, StartOn: score.LocalToday(s.now(), c.loc), Weekdays: score.AllWeekdays}
	if herr := req.apply(&h); herr != nil {
		fail(w, r, herr)
		return
	}
	ctx := r.Context()
	var out sharedHabitJSON
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
		created, err := db.CreateSharedHabit(ctx, tx, h)
		if err != nil {
			return err
		}
		out, err = s.oneShared(r, tx, c, created.ID)
		return err
	})
	if err != nil {
		fail(w, r, err)
		return
	}
	writeJSON(w, http.StatusCreated, map[string]any{"habit": out})
}

// handlePatchSharedHabit edits a household habit. Either person may.
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
	var out sharedHabitJSON
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
		if _, err := db.UpdateSharedHabit(ctx, tx, h); err != nil {
			return err
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

// handleDoneSharedHabit records that the caller did the chore and credits them the gems. When it
// was already done on the caller's day, by either person, nothing changes and nothing is paid, so
// a stale screen or a double tap cannot earn twice.
func (s *Server) handleDoneSharedHabit(w http.ResponseWriter, r *http.Request) {
	id, herr := sharedHabitID(r)
	if herr != nil {
		fail(w, r, herr)
		return
	}
	c := callerFrom(r)
	ctx := r.Context()
	now := s.now()
	today := score.LocalToday(now, c.loc)
	var (
		out     sharedHabitJSON
		created bool
		habit   db.SharedHabit
	)
	err := s.db.WithTx(ctx, func(tx pgx.Tx) error {
		var err error
		if habit, err = db.GetSharedHabit(ctx, tx, id, true); err != nil {
			if errors.Is(err, db.ErrNotFound) {
				return errNoSharedHabit
			}
			return err
		}
		last, err := db.PeekLastSharedMark(ctx, tx, id)
		switch {
		case err == nil && score.DateOf(last.DoneAt.In(c.loc)) == today:
		case err != nil && !errors.Is(err, db.ErrNotFound):
			return err
		default:
			if !s.writable(c.user, c.loc, today) {
				return errDateClosed
			}
			if err := db.LockUserDay(ctx, tx, c.user.ID, today); err != nil {
				return err
			}
			if _, err := db.InsertSharedMark(ctx, tx, db.SharedMark{SharedHabitID: id, UserID: c.user.ID,
				LocalDate: today, DoneAt: now, Points: score.SharedHabitGems}); err != nil {
				return err
			}
			if _, err := s.scoreDay(ctx, tx, c, today); err != nil {
				return err
			}
			created = true
		}
		out, err = s.oneShared(r, tx, c, id)
		return err
	})
	if err != nil {
		fail(w, r, err)
		return
	}
	earned := 0
	if created {
		earned = score.SharedHabitGems
		s.notifySharedDone(r, c.user, habit)
	}
	writeJSON(w, http.StatusOK, map[string]any{"habit": out, "gemsEarned": earned})
}

// notifySharedDone tells the partner a chore was taken care of. Quiet hours and the partner's
// switches are applied by the notifier.
func (s *Server) notifySharedDone(r *http.Request, from db.User, h db.SharedHabit) {
	partner, err := s.partnerOf(r.Context(), s.db.Pool, from.ID)
	if err != nil || partner == nil {
		return
	}
	s.together.Notify(*partner, push.Message{Kind: together.EventSharedHabit,
		Title: from.Name + " did " + h.Name, Body: "One less thing on the shared list"})
}

// handleUndoSharedHabit takes back the caller's own latest mark of the chore, while the day it
// counted on is still open and the partner has not marked it since.
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
		if err := db.LockUserDay(ctx, tx, c.user.ID, last.LocalDate); err != nil {
			return err
		}
		if err := db.DeleteSharedMark(ctx, tx, last.ID); err != nil {
			return err
		}
		if _, err := s.scoreDay(ctx, tx, c, last.LocalDate); err != nil {
			return err
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
