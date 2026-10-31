package api

import (
	"encoding/json"
	"errors"
	"net/http"
	"regexp"
	"slices"
	"strconv"
	"strings"
	"time"
	"unicode/utf8"

	"github.com/go-chi/chi/v5"
	"github.com/jackc/pgx/v5"

	"github.com/nc1107/new-me/server/internal/db"
	"github.com/nc1107/new-me/server/internal/engine"
	"github.com/nc1107/new-me/server/internal/score"
)

// Habit limits. They mirror the table checks, and are enforced here first so the caller gets a
// 422 that names the field.
const (
	maxSlots      = 8
	maxSlotLabel  = 24
	maxHabitCount = 50
	maxMarkCount  = 1000
)

// habitIcons is the fixed set of icon keys a habit may use. They are Material (rounded) icon
// names, so the app can map each one to an icon without a lookup table of its own.
var habitIcons = []string{
	"check_circle", "brush", "clean_hands", "bathtub", "medication", "vaccines", "water_drop",
	"local_cafe", "restaurant", "lunch_dining", "fitness_center", "directions_walk",
	"directions_run", "directions_bike", "sports_gymnastics", "self_improvement", "spa", "bedtime",
	"wb_sunny", "menu_book", "edit_note", "favorite", "bolt", "eco", "star", "pets",
	// The v18 household chores.
	"local_laundry_service", "cleaning_services", "delete", "shopping_cart", "home",
}

var slotTime = regexp.MustCompile(`^([01][0-9]|2[0-3]):[0-5][0-9]$`)

type slotJSON struct {
	Label string  `json:"label"`
	Time  *string `json:"time"`
}

type habitJSON struct {
	ID       int64      `json:"id"`
	Name     string     `json:"name"`
	Icon     string     `json:"icon"`
	Kind     string     `json:"kind"`
	Weekdays []int      `json:"weekdays"`
	Slots    []slotJSON `json:"slots"`
	Target   *int       `json:"target"`
	Position int        `json:"position"`
	Paused   bool       `json:"paused"`
	// Points is the habit's worth in gems toward the daily goal, 0 to 100. Minutes is how long
	// it takes, null when it is only tracked. ProposedPoints and ProposedMinutes are a change
	// that waits for the partner's approval; both are null when nothing is pending, and
	// proposedMinutes is also null for a proposal to only track.
	Points          int  `json:"points"`
	Minutes         *int `json:"minutes"`
	ProposedPoints  *int `json:"proposedPoints"`
	ProposedMinutes *int `json:"proposedMinutes"`
}

func toHabitJSON(h db.Habit) habitJSON {
	slots := make([]slotJSON, len(h.Slots))
	for i, s := range h.Slots {
		slots[i] = slotJSON{Label: s.Label, Time: s.Time}
	}
	return habitJSON{ID: h.ID, Name: h.Name, Icon: h.Icon, Kind: h.Kind, Weekdays: score.ISOWeekdays(h.Weekdays),
		Slots: slots, Target: h.Target, Position: h.Position, Paused: h.Paused, Points: h.Points,
		Minutes: h.Minutes, ProposedPoints: h.ProposedPoints, ProposedMinutes: h.ProposedMinutes}
}

type stateSlotJSON struct {
	Index int     `json:"index"`
	Label string  `json:"label"`
	Time  *string `json:"time"`
	Done  bool    `json:"done"`
}

// habitStateJSON is a habit due on a day, with what has been done on it. Target is null for a
// check habit and slots is empty for a count habit.
type habitStateJSON struct {
	ID     int64           `json:"id"`
	Name   string          `json:"name"`
	Icon   string          `json:"icon"`
	Kind   string          `json:"kind"`
	Slots  []stateSlotJSON `json:"slots"`
	Target *int            `json:"target"`
	Count  int             `json:"count"`
	Points int             `json:"points"`
}

func toHabitStatesJSON(states []db.HabitState) []habitStateJSON {
	out := make([]habitStateJSON, 0, len(states))
	for _, st := range states {
		h := st.Habit
		slots := make([]stateSlotJSON, len(h.Slots))
		for i, s := range h.Slots {
			slots[i] = stateSlotJSON{Index: i, Label: s.Label, Time: s.Time, Done: st.Done[i]}
		}
		out = append(out, habitStateJSON{ID: h.ID, Name: h.Name, Icon: h.Icon, Kind: h.Kind, Slots: slots,
			Target: h.Target, Count: st.Count, Points: h.Points})
	}
	return out
}

type habitRequest struct {
	Name     *string     `json:"name"`
	Icon     *string     `json:"icon"`
	Kind     *string     `json:"kind"`
	Weekdays *[]int      `json:"weekdays"`
	Slots    *[]slotJSON `json:"slots"`
	Target   *int        `json:"target"`
	Paused   *bool       `json:"paused"`
	// Points is the pre-v11 field, still accepted from older builds.
	Points  *int   `json:"points"`
	Minutes optInt `json:"minutes"`
}

// optInt tells a missing field from an explicit null, which for minutes means only tracked.
type optInt struct {
	Set bool
	Val *int
}

func (o *optInt) UnmarshalJSON(b []byte) error {
	o.Set = true
	return json.Unmarshal(b, &o.Val)
}

// apply writes the fields present in the request onto h and then checks the result as a whole,
// which is what lets a PATCH change a schedule without restating the rest.
func (req habitRequest) apply(h *db.Habit, creating, partner bool, now time.Time) (proposed bool, herr *httpError) {
	if req.Kind != nil {
		if !creating && *req.Kind != h.Kind {
			return false, invalid("kind cannot be changed")
		}
		h.Kind = *req.Kind
	}
	if req.Name != nil {
		name, herr := cleanName(*req.Name)
		if herr != nil {
			return false, invalid("name must be 1 to 40 characters without control characters")
		}
		h.Name = name
	}
	if req.Icon != nil {
		h.Icon = *req.Icon
	}
	if req.Weekdays != nil {
		mask, ok := score.WeekdaysFromISO(*req.Weekdays)
		if !ok {
			return false, invalid("weekdays must list days from 1 (Monday) to 7 (Sunday)")
		}
		h.Weekdays = mask
	}
	if req.Slots != nil {
		h.Slots = make([]db.HabitSlot, len(*req.Slots))
		for i, s := range *req.Slots {
			h.Slots[i] = db.HabitSlot{Label: strings.TrimSpace(s.Label), Time: s.Time}
		}
	}
	if req.Target != nil {
		h.Target = req.Target
	}
	if req.Paused != nil {
		h.Paused = *req.Paused
	}
	prop, herr := req.worth(h, creating, partner, now)
	if herr != nil {
		return false, herr
	}
	if herr := validateHabit(*h); herr != nil {
		return false, herr
	}
	return prop, nil
}

// worth sets the habit's gems from minutes, or from the older points field. With a partner a
// change is only proposed, so the habit keeps its gems (a new one starts at zero) until it is
// approved. It reports whether a proposal differing from the pending one was made.
func (req habitRequest) worth(h *db.Habit, creating, partner bool, now time.Time) (bool, *httpError) {
	var gems int
	var minutes *int
	changed := true
	switch {
	case req.Minutes.Set:
		minutes = req.Minutes.Val
		if minutes != nil && (*minutes < 1 || *minutes > score.HabitMaxMinutes) {
			return false, invalid("minutes must be between 1 and 30, or null for a habit that is only tracked")
		}
		gems = score.HabitGems(zeroIfNil(minutes))
		changed = !equalInt(minutes, h.Minutes)
		if creating && minutes == nil {
			// A new habit that is only tracked has nothing to approve.
			h.Points = 0
			return false, nil
		}
	case req.Points != nil:
		if !slices.Contains(score.HabitWorths, *req.Points) {
			return false, invalid("points must be 0, 10, 25 or 50")
		}
		gems = *req.Points
		changed = creating || gems != h.Points
	case creating:
		gems = score.HabitWorthDefault
	default:
		return false, nil
	}
	if !changed {
		if req.Minutes.Set {
			h.ProposedPoints, h.ProposedMinutes, h.ProposedAt = nil, nil, nil
		}
		return false, nil
	}
	if !partner {
		h.Points, h.Minutes = gems, minutes
		h.ProposedPoints, h.ProposedMinutes, h.ProposedAt = nil, nil, nil
		return false, nil
	}
	fresh := h.ProposedPoints == nil || *h.ProposedPoints != gems || !equalInt(h.ProposedMinutes, minutes)
	if creating {
		h.Points, h.Minutes = 0, nil
	}
	h.ProposedPoints, h.ProposedMinutes = &gems, minutes
	if fresh {
		h.ProposedAt = &now
	}
	return fresh, nil
}

func equalInt(a, b *int) bool {
	if a == nil || b == nil {
		return a == b
	}
	return *a == *b
}

func validateHabit(h db.Habit) *httpError {
	if !slices.Contains(habitIcons, h.Icon) {
		return invalid("icon must be one of: " + strings.Join(habitIcons, ", "))
	}
	switch h.Kind {
	case db.HabitCheck:
		if n := len(h.Slots); n < 1 || n > maxSlots {
			return invalid("a check habit needs 1 to 8 slots")
		}
		if h.Target != nil {
			return invalid("target is only for count habits")
		}
		for _, s := range h.Slots {
			if n := utf8.RuneCountInString(s.Label); n < 1 || n > maxSlotLabel || hasControlChars(s.Label) {
				return invalid("a slot label must be 1 to 24 characters without control characters")
			}
			if s.Time != nil && !slotTime.MatchString(*s.Time) {
				return invalid("a slot time must be HH:MM")
			}
		}
	case db.HabitCount:
		if len(h.Slots) != 0 {
			return invalid("a count habit has a target, not slots")
		}
		if h.Target == nil || *h.Target < 1 || *h.Target > maxHabitCount {
			return invalid("target must be between 1 and 50")
		}
	default:
		return invalid("kind must be check or count")
	}
	return nil
}

// handleListHabits lists the caller's habits, paused ones included.
func (s *Server) handleListHabits(w http.ResponseWriter, r *http.Request) {
	habits, err := db.ListHabits(r.Context(), s.db.Pool, callerFrom(r).user.ID)
	if err != nil {
		fail(w, r, err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"habits": toHabitsJSON(habits)})
}

func toHabitsJSON(habits []db.Habit) []habitJSON {
	out := make([]habitJSON, len(habits))
	for i, h := range habits {
		out[i] = toHabitJSON(h)
	}
	return out
}

// handleCreateHabit adds a habit at the end of the caller's list.
func (s *Server) handleCreateHabit(w http.ResponseWriter, r *http.Request) {
	var req habitRequest
	if err := decodeJSON(r, &req); err != nil {
		fail(w, r, err)
		return
	}
	if req.Name == nil || req.Icon == nil || req.Kind == nil {
		fail(w, r, invalid("name, icon and kind are required"))
		return
	}
	c := callerFrom(r)
	h := db.Habit{UserID: c.user.ID, Weekdays: score.AllWeekdays, Slots: []db.HabitSlot{}}
	ctx := r.Context()
	partner, err := s.partnerOf(ctx, s.db.Pool, c.user.ID)
	if err != nil {
		fail(w, r, err)
		return
	}
	proposed, herr := req.apply(&h, true, partner != nil, s.now())
	if herr != nil {
		fail(w, r, herr)
		return
	}
	var created db.Habit
	err = s.db.WithTx(ctx, func(tx pgx.Tx) error {
		if err := db.LockHabits(ctx, tx, c.user.ID); err != nil {
			return err
		}
		n, err := db.CountHabits(ctx, tx, c.user.ID)
		if err != nil {
			return err
		}
		if n >= db.MaxHabits {
			return invalid("at most 30 habits")
		}
		if created, err = db.CreateHabit(ctx, tx, h); err != nil {
			return err
		}
		return s.rescoreOpenDays(r, tx, c)
	})
	if err != nil {
		fail(w, r, err)
		return
	}
	if proposed {
		s.notifyProposal(*partner, c.user, created)
	}
	writeJSON(w, http.StatusCreated, map[string]any{"habit": toHabitJSON(created)})
}

// rescoreOpenDays refreshes the days a habit change can still touch. Finalized days keep the
// score they were finalized with.
func (s *Server) rescoreOpenDays(r *http.Request, tx pgx.Tx, c caller) error {
	for _, date := range s.openDates(c.user, c.loc) {
		if _, err := s.scoreDay(r.Context(), tx, c, date); err != nil {
			return err
		}
	}
	return nil
}

func habitID(r *http.Request) (int64, *httpError) {
	id, err := strconv.ParseInt(chi.URLParam(r, "id"), 10, 64)
	if err != nil || id < 1 {
		return 0, newErr(http.StatusNotFound, codeNotFound, "no such habit")
	}
	return id, nil
}

var errNoHabit = newErr(http.StatusNotFound, codeNotFound, "no such habit")

// handlePatchHabit edits any of a habit's fields, including pausing it.
func (s *Server) handlePatchHabit(w http.ResponseWriter, r *http.Request) {
	id, herr := habitID(r)
	if herr != nil {
		fail(w, r, herr)
		return
	}
	var req habitRequest
	if err := decodeJSON(r, &req); err != nil {
		fail(w, r, err)
		return
	}
	c := callerFrom(r)
	ctx := r.Context()
	partner, err := s.partnerOf(ctx, s.db.Pool, c.user.ID)
	if err != nil {
		fail(w, r, err)
		return
	}
	var (
		updated  db.Habit
		proposed bool
	)
	err = s.db.WithTx(ctx, func(tx pgx.Tx) error {
		h, err := db.GetHabit(ctx, tx, c.user.ID, id)
		if errors.Is(err, db.ErrNotFound) {
			return errNoHabit
		}
		if err != nil {
			return err
		}
		var herr *httpError
		if proposed, herr = req.apply(&h, false, partner != nil, s.now()); herr != nil {
			return herr
		}
		if updated, err = db.UpdateHabit(ctx, tx, h); err != nil {
			return err
		}
		return s.rescoreOpenDays(r, tx, c)
	})
	if err != nil {
		fail(w, r, err)
		return
	}
	if proposed {
		s.notifyProposal(*partner, c.user, updated)
	}
	writeJSON(w, http.StatusOK, map[string]any{"habit": toHabitJSON(updated)})
}

// handleDeleteHabit hides a habit. Its marks stay, so history is not rewritten.
func (s *Server) handleDeleteHabit(w http.ResponseWriter, r *http.Request) {
	id, herr := habitID(r)
	if herr != nil {
		fail(w, r, herr)
		return
	}
	c := callerFrom(r)
	ctx := r.Context()
	err := s.db.WithTx(ctx, func(tx pgx.Tx) error {
		if err := db.SoftDeleteHabit(ctx, tx, c.user.ID, id); err != nil {
			if errors.Is(err, db.ErrNotFound) {
				return errNoHabit
			}
			return err
		}
		return s.rescoreOpenDays(r, tx, c)
	})
	if err != nil {
		fail(w, r, err)
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

// handleOrderHabits sets the order of the caller's habits. The ids must be all of them, once.
func (s *Server) handleOrderHabits(w http.ResponseWriter, r *http.Request) {
	var req struct {
		IDs []int64 `json:"ids"`
	}
	if err := decodeJSON(r, &req); err != nil {
		fail(w, r, err)
		return
	}
	c := callerFrom(r)
	ctx := r.Context()
	var habits []db.Habit
	err := s.db.WithTx(ctx, func(tx pgx.Tx) error {
		if err := db.LockHabits(ctx, tx, c.user.ID); err != nil {
			return err
		}
		current, err := db.ListHabits(ctx, tx, c.user.ID)
		if err != nil {
			return err
		}
		have := make([]int64, len(current))
		for i, h := range current {
			have[i] = h.ID
		}
		want := slices.Clone(req.IDs)
		slices.Sort(have)
		slices.Sort(want)
		if !slices.Equal(have, want) {
			return invalid("ids must list each of your habits exactly once")
		}
		if err := db.SetHabitOrder(ctx, tx, c.user.ID, req.IDs); err != nil {
			return err
		}
		habits, err = db.ListHabits(ctx, tx, c.user.ID)
		return err
	})
	if err != nil {
		fail(w, r, err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"habits": toHabitsJSON(habits)})
}

type markRequest struct {
	Slot  *int  `json:"slot"`
	Done  *bool `json:"done"`
	Count *int  `json:"count"`
}

// handlePutHabitMark sets a slot done or undone, or a count habit's total, for one day under
// the same window as logs. Setting what is already set changes nothing.
func (s *Server) handlePutHabitMark(w http.ResponseWriter, r *http.Request) {
	id, herr := habitID(r)
	if herr != nil {
		fail(w, r, herr)
		return
	}
	date, err := score.ParseDate(chi.URLParam(r, "date"))
	if err != nil {
		fail(w, r, invalid("date must be YYYY-MM-DD"))
		return
	}
	var req markRequest
	if err := decodeJSON(r, &req); err != nil {
		fail(w, r, err)
		return
	}
	c := callerFrom(r)
	ctx := r.Context()
	var (
		scored engine.Scored
		states []db.HabitState
	)
	err = s.db.WithTx(ctx, func(tx pgx.Tx) error {
		h, err := db.GetHabit(ctx, tx, c.user.ID, id)
		if errors.Is(err, db.ErrNotFound) {
			return errNoHabit
		}
		if err != nil {
			return err
		}
		if herr := checkMark(h, req, date); herr != nil {
			return herr
		}
		if !s.writable(c.user, c.loc, date) {
			return errDateClosed
		}
		if err := db.LockUserDay(ctx, tx, c.user.ID, date); err != nil {
			return err
		}
		switch {
		case h.Kind == db.HabitCount:
			err = db.SetHabitCount(ctx, tx, h.ID, date, *req.Count)
		case *req.Done:
			err = db.MarkSlot(ctx, tx, h.ID, date, *req.Slot)
		default:
			err = db.UnmarkSlot(ctx, tx, h.ID, date, *req.Slot)
		}
		if err != nil {
			return err
		}
		if scored, err = s.scoreDay(ctx, tx, c, date); err != nil {
			return err
		}
		states, err = db.DueHabits(ctx, tx, c.user.ID, date)
		return err
	})
	if err != nil {
		fail(w, r, err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{
		"date": date, "habits": toHabitStatesJSON(states), "day": toDayDetailJSON(date, scored)})
}

func checkMark(h db.Habit, req markRequest, date score.Date) *httpError {
	if h.Paused {
		return invalid("that habit is paused")
	}
	if !score.HabitDue(h.Weekdays, date) {
		return invalid("that habit is not scheduled on that day")
	}
	if h.Kind == db.HabitCount {
		if req.Count == nil || req.Slot != nil || req.Done != nil {
			return invalid("a count habit takes only count")
		}
		if *req.Count < 0 || *req.Count > maxMarkCount {
			return invalid("count must be between 0 and 1000")
		}
		return nil
	}
	if req.Slot == nil || req.Done == nil || req.Count != nil {
		return invalid("a check habit takes slot and done")
	}
	if *req.Slot < 0 || *req.Slot >= len(h.Slots) {
		return invalid("slot is out of range for this habit")
	}
	return nil
}

func zeroIfNil(p *int) int {
	if p == nil {
		return 0
	}
	return *p
}
