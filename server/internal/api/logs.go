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
	maxReps            = 500
	maxPages           = 2000
	maxMinutes         = 1440
	maxWaterML         = 5000
	maxProduceServings = 30
	maxBreathMin       = 120
	maxKcal            = 10000
	maxMacroGrams      = 5000
	maxMealName        = 80
	maxNote            = 200
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
	// Minutes and Intensity are for type "other": a free-named activity that counts toward
	// exercise minutes. Moderate and hard count fully, easy counts half.
	Minutes   int     `json:"minutes"`
	Intensity string  `json:"intensity"`
	Kcal      int     `json:"kcal"`
	Protein   float64 `json:"protein"`
	Carbs     float64 `json:"carbs"`
	Fat       float64 `json:"fat"`
	Fiber     float64 `json:"fiber"`
}

// logJSON is the tagged union of an activity or a meal entry; fields of the other kind are
// left out.
type logJSON struct {
	ID        int64      `json:"id"`
	Kind      string     `json:"kind"`
	LocalDate score.Date `json:"localDate"`
	LoggedAt  string     `json:"loggedAt"`

	Type      string `json:"type,omitempty"`
	Quantity  int    `json:"quantity,omitempty"`
	Unit      string `json:"unit,omitempty"`
	Intensity string `json:"intensity,omitempty"`

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
	db.ActivityOtherMinutes:   {"other", "minutes"},
	db.ActivityWaterML:        {"water", "ml"},
	db.ActivityProduce:        {"produce", "servings"},
	db.ActivityBreathing:      {"breathing", "minutes"},
}

// storedActivity resolves the wire's type and unit to a stored type. The stored names are
// accepted as types too, with the unit implied. A wire type may leave out its unit only when it
// has one; reading counts minutes or pages, so it must say which.
func storedActivity(typ, unit string) (string, bool) {
	if wire, ok := wireActivity[typ]; ok {
		return typ, unit == "" || unit == wire[1]
	}
	found, matches := "", 0
	for stored, wire := range wireActivity {
		if wire[0] != typ {
			continue
		}
		matches++
		if unit == wire[1] {
			return stored, true
		}
		found = stored
	}
	return found, unit == "" && matches == 1
}

func activityCap(stored string) int {
	switch stored {
	case db.ActivityPushups:
		return maxReps
	case db.ActivityReadingPages:
		return maxPages
	case db.ActivityWaterML:
		return maxWaterML
	case db.ActivityProduce:
		return maxProduceServings
	case db.ActivityBreathing:
		return maxBreathMin
	}
	return maxMinutes
}

func toActivityJSON(l db.ActivityLog) logJSON {
	wire := wireActivity[l.Type]
	return logJSON{ID: l.ID, Kind: db.KindActivity, LocalDate: l.LocalDate, LoggedAt: wireTime(l.LoggedAt),
		Type: wire[0], Quantity: l.Quantity, Unit: wire[1], Name: l.Name, Intensity: l.Intensity}
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
			return v, invalid("type must be pushups, reading (with unit minutes or pages), yoga, water (unit ml), produce (unit servings), breathing or other")
		}
		activity := db.NewActivityLog{Type: stored, Quantity: req.Quantity, ClientOpID: v.opID}
		if stored == db.ActivityOtherMinutes {
			var herr *httpError
			if activity, herr = otherActivity(req, v.opID); herr != nil {
				return v, herr
			}
		} else if req.Intensity != "" || req.Name != "" || req.Minutes != 0 {
			return v, invalid("name, minutes and intensity are only for type other")
		}
		if activity.Quantity < 1 || activity.Quantity > activityCap(stored) {
			return v, invalid("quantity is out of range for " + req.Type)
		}
		v.activity = &activity
	case db.KindMeal:
		name, herr := validMealName(req.Name)
		if herr != nil {
			return v, herr
		}
		if herr := validKcal(req.Kcal); herr != nil {
			return v, herr
		}
		if herr := validMacros(req.Protein, req.Carbs, req.Fat, req.Fiber); herr != nil {
			return v, herr
		}
		v.meal = &db.NewMealLog{Name: name, Kcal: req.Kcal, ProteinG: req.Protein, CarbsG: req.Carbs,
			FatG: req.Fat, FiberG: req.Fiber, ClientOpID: v.opID}
	default:
		return v, invalid("kind must be activity or meal")
	}
	return v, nil
}

func validMealName(raw string) (string, *httpError) {
	name := strings.TrimSpace(raw)
	if n := utf8.RuneCountInString(name); n < 1 || n > maxMealName || hasControlChars(name) {
		return "", invalid("name must be 1 to 80 characters without control characters")
	}
	return name, nil
}

func validKcal(kcal int) *httpError {
	if kcal < 1 || kcal > maxKcal {
		return invalid("kcal must be between 1 and 10000")
	}
	return nil
}

func validMacros(grams ...float64) *httpError {
	for _, g := range grams {
		if g < 0 || g > maxMacroGrams {
			return invalid("macros must be between 0 and 5000 grams")
		}
	}
	return nil
}

// intensities are the effort levels of a manual activity.
var intensities = []string{"easy", "moderate", "hard"}

// maxActivityName mirrors the table check.
const maxActivityName = 60

// otherActivity validates a generic manual activity: a free name, its minutes (sent as minutes
// or quantity) and how hard it was.
func otherActivity(req createLogRequest, opID string) (db.NewActivityLog, *httpError) {
	name := strings.TrimSpace(req.Name)
	if n := utf8.RuneCountInString(name); n < 1 || n > maxActivityName || hasControlChars(name) {
		return db.NewActivityLog{}, invalid("name must be 1 to 60 characters without control characters")
	}
	if !slices.Contains(intensities, req.Intensity) {
		return db.NewActivityLog{}, invalid("intensity must be easy, moderate or hard")
	}
	minutes := req.Minutes
	if minutes == 0 {
		minutes = req.Quantity
	} else if req.Quantity != 0 && req.Quantity != minutes {
		return db.NewActivityLog{}, invalid("send minutes or quantity, not both")
	}
	return db.NewActivityLog{Type: db.ActivityOtherMinutes, Quantity: minutes, ClientOpID: opID,
		Name: name, Intensity: req.Intensity}, nil
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

// patchMealRequest carries only the fields to change. Absent fields keep their stored value.
type patchMealRequest struct {
	Name    *string  `json:"name"`
	Kcal    *int     `json:"kcal"`
	Protein *float64 `json:"protein"`
	Carbs   *float64 `json:"carbs"`
	Fat     *float64 `json:"fat"`
	Fiber   *float64 `json:"fiber"`

	// LoggedAt is an RFC 3339 moment; its day for the caller becomes the meal's day.
	LoggedAt *string `json:"loggedAt"`
}

func (req patchMealRequest) validate(now time.Time, loc *time.Location) (db.MealPatch, *httpError) {
	patch := db.MealPatch{Kcal: req.Kcal, ProteinG: req.Protein, CarbsG: req.Carbs, FatG: req.Fat, FiberG: req.Fiber}
	if req.Name == nil && req.Kcal == nil && req.Protein == nil && req.Carbs == nil && req.Fat == nil &&
		req.Fiber == nil && req.LoggedAt == nil {
		return patch, invalid("send at least one of name, kcal, protein, carbs, fat, fiber or loggedAt")
	}
	if req.LoggedAt != nil {
		at, err := time.Parse(time.RFC3339, *req.LoggedAt)
		if err != nil {
			return patch, invalid("loggedAt must be an RFC 3339 time")
		}
		if at.After(now.Add(time.Minute)) {
			return patch, invalid("loggedAt cannot be in the future")
		}
		at = at.UTC()
		date := score.LocalToday(at, loc)
		patch.LoggedAt, patch.LocalDate = &at, &date
	}
	if req.Name != nil {
		name, herr := validMealName(*req.Name)
		if herr != nil {
			return patch, herr
		}
		patch.Name = &name
	}
	if req.Kcal != nil {
		if herr := validKcal(*req.Kcal); herr != nil {
			return patch, herr
		}
	}
	for _, g := range []*float64{req.Protein, req.Carbs, req.Fat, req.Fiber} {
		if g == nil {
			continue
		}
		if herr := validMacros(*g); herr != nil {
			return patch, herr
		}
	}
	return patch, nil
}

// handlePatchLog corrects one of the caller's meals and rescores its day, under the same day
// window as creating it. Activities are not editable: they answer 422 rather than 404 because
// the entry exists and is the caller's, and the message tells the app what to do instead.
func (s *Server) handlePatchLog(w http.ResponseWriter, r *http.Request) {
	id, err := strconv.ParseInt(chi.URLParam(r, "id"), 10, 64)
	if err != nil || id < 1 {
		fail(w, r, newErr(http.StatusNotFound, codeNotFound, "no such log"))
		return
	}
	var req patchMealRequest
	if err := decodeJSON(r, &req); err != nil {
		fail(w, r, err)
		return
	}
	c := callerFrom(r)
	patch, herr := req.validate(s.now(), c.loc)
	if herr != nil {
		fail(w, r, herr)
		return
	}
	ctx := r.Context()
	var (
		entry  logJSON
		date   score.Date
		scored engine.Scored
	)
	err = s.db.WithTx(ctx, func(tx pgx.Tx) error {
		var from *score.Date
		if patch.LocalDate != nil {
			if old, err := db.MealLocalDate(ctx, tx, c.user.ID, id); err == nil {
				from = &old
			}
		}
		meal, err := db.UpdateMealLog(ctx, tx, c.user.ID, id, patch)
		if errors.Is(err, db.ErrNotFound) {
			isActivity, aerr := db.ActivityLogExists(ctx, tx, c.user.ID, id)
			if aerr != nil {
				return aerr
			}
			if isActivity {
				return invalid("only meals can be edited; delete the entry and log it again")
			}
			return newErr(http.StatusNotFound, codeNotFound, "no such log")
		}
		if err != nil {
			return err
		}
		date = meal.LocalDate
		if !s.writable(c.user, c.loc, date) {
			return errDateClosed
		}
		entry = toMealJSON(meal)
		if from != nil && *from != date {
			if !s.writable(c.user, c.loc, *from) {
				return errDateClosed
			}
			if _, err := s.scoreDay(ctx, tx, c, *from); err != nil {
				return err
			}
		}
		scored, err = s.scoreDay(ctx, tx, c, date)
		return err
	})
	if err != nil {
		fail(w, r, err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"log": entry, "day": toDayDetailJSON(date, scored)})
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
