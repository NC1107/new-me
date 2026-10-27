package api

import (
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

// Per-entry caps. They match the table checks, and are enforced here first so the caller gets
// a 422 that names the field.
const (
	maxReps       = 500
	maxPages      = 2000
	maxMinutes    = 1440
	maxKcal       = 10000
	maxMacroGrams = 5000
	maxMealName   = 80
	maxNote       = 200
)

var uuidShape = regexp.MustCompile(`^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$`)

type createLogRequest struct {
	ClientOpID string  `json:"clientOpId"`
	Date       *string `json:"date"`
	Kind       string  `json:"kind"`
	Type       string  `json:"type"`
	Unit       string  `json:"unit"`
	Quantity   int     `json:"quantity"`
	Note       *string `json:"note"`
	Name       string  `json:"name"`
	Kcal       int     `json:"kcal"`
	Protein    float64 `json:"protein"`
	Carbs      float64 `json:"carbs"`
	Fat        float64 `json:"fat"`
	Fiber      float64 `json:"fiber"`
}

// logJSON is the tagged union of an activity or a meal entry; fields of the other kind are
// left out.
type logJSON struct {
	ID        int64      `json:"id"`
	Kind      string     `json:"kind"`
	LocalDate score.Date `json:"localDate"`
	LoggedAt  string     `json:"loggedAt"`

	Type     string `json:"type,omitempty"`
	Quantity int    `json:"quantity,omitempty"`
	Unit     string `json:"unit,omitempty"`

	Name    string   `json:"name,omitempty"`
	Kcal    *int     `json:"kcal,omitempty"`
	Protein *float64 `json:"protein,omitempty"`
	Carbs   *float64 `json:"carbs,omitempty"`
	Fat     *float64 `json:"fat,omitempty"`
	Fiber   *float64 `json:"fiber,omitempty"`
}

// wireActivity maps the stored activity types onto the wire's type and unit.
var wireActivity = map[string][2]string{
	db.ActivityPushups:        {"pushups", "reps"},
	db.ActivityReadingMinutes: {"reading", "minutes"},
	db.ActivityReadingPages:   {"reading", "pages"},
	db.ActivityYogaMinutes:    {"yoga", "minutes"},
}

// storedActivity resolves the wire's type and unit to a stored type. The stored names are
// accepted as types too, with the unit implied.
func storedActivity(typ, unit string) (string, bool) {
	if wire, ok := wireActivity[typ]; ok {
		return typ, unit == "" || unit == wire[1]
	}
	switch {
	case typ == "reading" && unit == "minutes":
		return db.ActivityReadingMinutes, true
	case typ == "reading" && unit == "pages":
		return db.ActivityReadingPages, true
	case typ == "yoga" && (unit == "" || unit == "minutes"):
		return db.ActivityYogaMinutes, true
	}
	return "", false
}

func activityCap(stored string) int {
	switch stored {
	case db.ActivityPushups:
		return maxReps
	case db.ActivityReadingPages:
		return maxPages
	}
	return maxMinutes
}

func toActivityJSON(l db.ActivityLog) logJSON {
	wire := wireActivity[l.Type]
	return logJSON{ID: l.ID, Kind: db.KindActivity, LocalDate: l.LocalDate, LoggedAt: wireTime(l.LoggedAt),
		Type: wire[0], Quantity: l.Quantity, Unit: wire[1]}
}

func toMealJSON(l db.MealLog) logJSON {
	return logJSON{ID: l.ID, Kind: db.KindMeal, LocalDate: l.LocalDate, LoggedAt: wireTime(l.LoggedAt),
		Name: l.Name, Kcal: &l.Kcal, Protein: &l.ProteinG, Carbs: &l.CarbsG, Fat: &l.FatG, Fiber: &l.FiberG}
}

// validated is a create request that passed every field check.
type validated struct {
	opID     string
	activity *db.NewActivityLog
	meal     *db.NewMealLog
}

func validateLog(req createLogRequest) (validated, *httpError) {
	if !uuidShape.MatchString(req.ClientOpID) {
		return validated{}, invalid("clientOpId must be a UUID")
	}
	v := validated{opID: strings.ToLower(req.ClientOpID)}
	if req.Note != nil && utf8.RuneCountInString(*req.Note) > maxNote {
		return v, invalid("note is too long")
	}
	switch req.Kind {
	case db.KindActivity:
		stored, ok := storedActivity(req.Type, req.Unit)
		if !ok {
			return v, invalid("type must be pushups, reading (with unit minutes or pages) or yoga")
		}
		if req.Quantity < 1 || req.Quantity > activityCap(stored) {
			return v, invalid("quantity is out of range for " + req.Type)
		}
		v.activity = &db.NewActivityLog{Type: stored, Quantity: req.Quantity, ClientOpID: v.opID}
	case db.KindMeal:
		name := strings.TrimSpace(req.Name)
		if n := utf8.RuneCountInString(name); n < 1 || n > maxMealName {
			return v, invalid("name must be 1 to 80 characters")
		}
		if req.Kcal < 1 || req.Kcal > maxKcal {
			return v, invalid("kcal must be between 1 and 10000")
		}
		for _, grams := range []float64{req.Protein, req.Carbs, req.Fat, req.Fiber} {
			if grams < 0 || grams > maxMacroGrams {
				return v, invalid("macros must be between 0 and 5000 grams")
			}
		}
		v.meal = &db.NewMealLog{Name: name, Kcal: req.Kcal, ProteinG: req.Protein, CarbsG: req.Carbs,
			FatG: req.Fat, FiberG: req.Fiber, ClientOpID: v.opID}
	default:
		return v, invalid("kind must be activity or meal")
	}
	return v, nil
}

// handleCreateLog stores an entry exactly once per clientOpId: 201 the first time, 200 with the
// stored entry on a replay. A replay never undeletes and is not held to the day window, since
// it changes nothing.
func (s *Server) handleCreateLog(w http.ResponseWriter, r *http.Request) {
	var req createLogRequest
	if err := decodeJSON(r, &req); err != nil {
		fail(w, r, err)
		return
	}
	v, herr := validateLog(req)
	if herr != nil {
		fail(w, r, herr)
		return
	}
	c := callerFrom(r)
	date, herr := parseDateParam(deref(req.Date), score.LocalToday(s.now(), c.loc))
	if herr != nil {
		fail(w, r, herr)
		return
	}

	requested := date
	ctx := r.Context()
	var (
		entry   logJSON
		created bool
		scored  engine.Scored
	)
	err := s.db.WithTx(ctx, func(tx pgx.Tx) error {
		if err := db.LockUserDay(ctx, tx, c.user.ID, date); err != nil {
			return err
		}
		var err error
		if v.activity != nil {
			n := *v.activity
			n.UserID, n.LocalDate = c.user.ID, date
			var l db.ActivityLog
			if l, created, err = db.InsertActivityLog(ctx, tx, n); err != nil {
				return err
			}
			entry, date = toActivityJSON(l), l.LocalDate
		} else {
			n := *v.meal
			n.UserID, n.LocalDate = c.user.ID, date
			var l db.MealLog
			if l, created, err = db.InsertMealLog(ctx, tx, n); err != nil {
				return err
			}
			entry, date = toMealJSON(l), l.LocalDate
		}
		if created && !s.writable(c.user, c.loc, requested) {
			return errDateClosed
		}
		scored, err = s.scoreDay(ctx, tx, c, date)
		return err
	})
	if err != nil {
		fail(w, r, err)
		return
	}
	status := http.StatusOK
	if created {
		status = http.StatusCreated
	}
	writeJSON(w, status, map[string]any{"log": entry, "day": toDayDetailJSON(date, scored)})
}

// handleListLogs returns the caller's live entries for one day, oldest first.
func (s *Server) handleListLogs(w http.ResponseWriter, r *http.Request) {
	c := callerFrom(r)
	date, herr := parseDateParam(r.URL.Query().Get("date"), score.LocalToday(s.now(), c.loc))
	if herr != nil {
		fail(w, r, herr)
		return
	}
	ctx := r.Context()
	activities, err := db.ListActivityLogs(ctx, s.db.Pool, c.user.ID, date)
	if err != nil {
		fail(w, r, err)
		return
	}
	meals, err := db.ListMealLogs(ctx, s.db.Pool, c.user.ID, date)
	if err != nil {
		fail(w, r, err)
		return
	}
	type stamped struct {
		at time.Time
		logJSON
	}
	merged := make([]stamped, 0, len(activities)+len(meals))
	for _, l := range activities {
		merged = append(merged, stamped{l.LoggedAt, toActivityJSON(l)})
	}
	for _, l := range meals {
		merged = append(merged, stamped{l.LoggedAt, toMealJSON(l)})
	}
	slices.SortFunc(merged, func(a, b stamped) int {
		if c := a.at.Compare(b.at); c != 0 {
			return c
		}
		return int(a.ID - b.ID)
	})
	logs := make([]logJSON, 0, len(merged))
	for _, m := range merged {
		logs = append(logs, m.logJSON)
	}
	writeJSON(w, http.StatusOK, map[string]any{"date": date, "logs": logs})
}

// handleDeleteLog hides one of the caller's entries, under the same day window as creating it.
func (s *Server) handleDeleteLog(w http.ResponseWriter, r *http.Request) {
	id, err := strconv.ParseInt(chi.URLParam(r, "id"), 10, 64)
	if err != nil || id < 1 {
		fail(w, r, newErr(http.StatusNotFound, codeNotFound, "no such log"))
		return
	}
	c := callerFrom(r)
	ctx := r.Context()
	var (
		date   score.Date
		scored engine.Scored
	)
	err = s.db.WithTx(ctx, func(tx pgx.Tx) error {
		deleted, err := db.SoftDeleteLog(ctx, tx, c.user.ID, id)
		if errors.Is(err, db.ErrNotFound) {
			return newErr(http.StatusNotFound, codeNotFound, "no such log")
		}
		if err != nil {
			return err
		}
		date = deleted.LocalDate
		if !s.writable(c.user, c.loc, date) {
			return errDateClosed
		}
		scored, err = s.scoreDay(ctx, tx, c, date)
		return err
	})
	if err != nil {
		fail(w, r, err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"day": toDayDetailJSON(date, scored)})
}

type recentMealJSON struct {
	Name    string  `json:"name"`
	Kcal    int     `json:"kcal"`
	Protein float64 `json:"protein"`
	Carbs   float64 `json:"carbs"`
	Fat     float64 `json:"fat"`
	Fiber   float64 `json:"fiber"`
}

const (
	defaultRecentMeals = 20
	maxRecentMeals     = 50
)

// handleRecentMeals lists the newest distinct meals of everyone, so one person can repeat what
// the other entered.
func (s *Server) handleRecentMeals(w http.ResponseWriter, r *http.Request) {
	limit := defaultRecentMeals
	if raw := r.URL.Query().Get("limit"); raw != "" {
		n, err := strconv.Atoi(raw)
		if err != nil || n < 1 || n > maxRecentMeals {
			fail(w, r, invalid("limit must be between 1 and 50"))
			return
		}
		limit = n
	}
	meals, err := db.RecentMeals(r.Context(), s.db.Pool, limit)
	if err != nil {
		fail(w, r, err)
		return
	}
	out := make([]recentMealJSON, 0, len(meals))
	for _, m := range meals {
		out = append(out, recentMealJSON{Name: m.Name, Kcal: m.Kcal, Protein: m.ProteinG, Carbs: m.CarbsG,
			Fat: m.FatG, Fiber: m.FiberG})
	}
	writeJSON(w, http.StatusOK, map[string]any{"meals": out})
}
