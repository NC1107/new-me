package api

import (
	"errors"
	"net/http"
	"slices"
	"strconv"
	"strings"
	"unicode/utf8"

	"github.com/go-chi/chi/v5"
	"github.com/jackc/pgx/v5"

	"github.com/nc1107/new-me/server/internal/db"
	"github.com/nc1107/new-me/server/internal/engine"
	"github.com/nc1107/new-me/server/internal/score"
	"github.com/nc1107/new-me/server/internal/training"
)

// Bounds for a set and for custom exercises; they mirror the table checks.
const (
	maxSetReps         = 500
	maxSetSeconds      = 3600
	maxSetLoadKg       = 1000
	maxSetRIR          = 10
	maxExerciseName    = 60
	maxMaxTestReps     = 1000
	defaultSetsDays    = 30
	maxSetsDays        = 365
	maxCustomExercises = 100
)

var errNoExercise = newErr(http.StatusNotFound, codeNotFound, "no such exercise")

type bestJSON struct {
	Date    score.Date `json:"date"`
	Reps    *int       `json:"reps"`
	Seconds *int       `json:"seconds"`
	LoadKg  *float64   `json:"loadKg"`
	// E1RMKg is the Epley estimate of a one-rep max, only for loaded exercises.
	E1RMKg *float64 `json:"e1rmKg"`
}

type maxTestJSON struct {
	Date    score.Date `json:"date"`
	Reps    *int       `json:"reps"`
	Seconds *int       `json:"seconds"`
}

type exerciseJSON struct {
	Key              string       `json:"key"`
	Name             string       `json:"name"`
	PrimaryMuscles   []string     `json:"primaryMuscles"`
	SecondaryMuscles []string     `json:"secondaryMuscles"`
	Measure          string       `json:"measure"`
	Load             string       `json:"load"`
	Equipment        []string     `json:"equipment"`
	EasierKey        *string      `json:"easierKey"`
	HarderKey        *string      `json:"harderKey"`
	Custom           bool         `json:"custom"`
	Kind             string       `json:"kind"`
	PerSide          bool         `json:"perSide"`
	Steps            []string     `json:"steps"`
	Cues             []string     `json:"cues"`
	ImageURLs        []string     `json:"imageUrls"`
	Best             *bestJSON    `json:"best"`
	MaxTest          *maxTestJSON `json:"maxTest"`
}

func toExerciseJSON(e db.Exercise) exerciseJSON {
	return exerciseJSON{Key: e.Key, Name: e.Name, PrimaryMuscles: nonNil(e.PrimaryMuscles),
		SecondaryMuscles: nonNil(e.SecondaryMuscles), Measure: e.Measure, Load: e.Load,
		Equipment: nonNil(e.Equipment), EasierKey: optString(e.EasierKey), HarderKey: optString(e.HarderKey),
		Custom: e.Custom(), Kind: e.Kind, PerSide: e.PerSide, Steps: nonNil(e.Steps), Cues: nonNil(e.Cues), ImageURLs: exerciseImageURLs(e)}
}

func nonNil(s []string) []string {
	if s == nil {
		return []string{}
	}
	return s
}

func optString(s string) *string {
	if s == "" {
		return nil
	}
	return &s
}

func toBestJSON(b training.Best, loaded bool) *bestJSON {
	out := &bestJSON{Date: score.Date(b.Date)}
	if b.Seconds > 0 {
		out.Seconds = &b.Seconds
	} else {
		out.Reps = &b.Reps
	}
	if loaded && b.LoadKg > 0 {
		load, e1rm := b.LoadKg, b.E1RMKg
		out.LoadKg, out.E1RMKg = &load, &e1rm
	}
	return out
}

func trainingSet(s db.ExerciseSet) training.Set {
	out := training.Set{Date: string(s.LocalDate)}
	if s.Reps != nil {
		out.Reps = *s.Reps
	}
	if s.Seconds != nil {
		out.Seconds = *s.Seconds
	}
	if s.LoadKg != nil {
		out.LoadKg = *s.LoadKg
	}
	return out
}

// handleListExercises returns the catalog and the caller's custom exercises, each with its best
// set and latest max test.
func (s *Server) handleListExercises(w http.ResponseWriter, r *http.Request) {
	c := callerFrom(r)
	ctx := r.Context()
	exercises, err := db.ListExercises(ctx, s.db.Pool, c.user.ID)
	if err != nil {
		fail(w, r, err)
		return
	}
	today := score.LocalToday(s.now(), c.loc)
	sets, err := db.ListExerciseSets(ctx, s.db.Pool, c.user.ID, "2000-01-01", today, 0)
	if err != nil {
		fail(w, r, err)
		return
	}
	maxTests, err := db.LatestMaxTests(ctx, s.db.Pool, c.user.ID)
	if err != nil {
		fail(w, r, err)
		return
	}
	byExercise := map[int64][]training.Set{}
	for _, set := range sets {
		byExercise[set.ExerciseID] = append(byExercise[set.ExerciseID], trainingSet(set))
	}
	pushupMax, err := db.LatestPushupMax(ctx, s.db.Pool, c.user.ID)
	if err != nil && !errors.Is(err, db.ErrNotFound) {
		fail(w, r, err)
		return
	}
	out := make([]exerciseJSON, 0, len(exercises))
	for _, e := range exercises {
		j := toExerciseJSON(e)
		loaded := e.Load == db.LoadExternal
		if best, ok := training.BestSet(byExercise[e.ID], loaded); ok {
			j.Best = toBestJSON(best, loaded)
		}
		if t, ok := maxTests[e.ID]; ok {
			j.MaxTest = &maxTestJSON{Date: t.LocalDate, Reps: t.Reps, Seconds: t.Seconds}
		} else if e.Key == "push_up" && err == nil && pushupMax.Reps > 0 {
			// Push-up maxes recorded through the v8 endpoint live in their own table.
			reps := pushupMax.Reps
			j.MaxTest = &maxTestJSON{Date: pushupMax.Date, Reps: &reps}
		}
		out = append(out, j)
	}
	writeJSON(w, http.StatusOK, map[string]any{"exercises": out, "muscles": db.Muscles, "equipment": db.Equipment})
}

type exerciseRequest struct {
	Name             string   `json:"name"`
	PrimaryMuscles   []string `json:"primaryMuscles"`
	SecondaryMuscles []string `json:"secondaryMuscles"`
	Measure          string   `json:"measure"`
	Load             string   `json:"load"`
	Equipment        []string `json:"equipment"`
}

func validateExercise(req exerciseRequest) (db.NewExercise, *httpError) {
	name := strings.TrimSpace(req.Name)
	if n := utf8.RuneCountInString(name); n < 1 || n > maxExerciseName || hasControlChars(name) {
		return db.NewExercise{}, invalid("name must be 1 to 60 characters without control characters")
	}
	if len(req.PrimaryMuscles) < 1 || len(req.PrimaryMuscles) > 4 {
		return db.NewExercise{}, invalid("primaryMuscles must list 1 to 4 muscles")
	}
	for _, m := range append(slices.Clone(req.PrimaryMuscles), req.SecondaryMuscles...) {
		if !slices.Contains(db.Muscles, m) {
			return db.NewExercise{}, invalid("unknown muscle " + strconv.Quote(m))
		}
	}
	if req.Measure != db.MeasureReps && req.Measure != db.MeasureSeconds {
		return db.NewExercise{}, invalid("measure must be reps or seconds")
	}
	if req.Load != db.LoadBodyweight && req.Load != db.LoadExternal {
		return db.NewExercise{}, invalid("load must be bodyweight or external")
	}
	for _, e := range req.Equipment {
		if !slices.Contains(db.Equipment, e) {
			return db.NewExercise{}, invalid("unknown equipment " + strconv.Quote(e))
		}
	}
	return db.NewExercise{Name: name, PrimaryMuscles: req.PrimaryMuscles, SecondaryMuscles: nonNil(req.SecondaryMuscles),
		Measure: req.Measure, Load: req.Load, Equipment: nonNil(req.Equipment)}, nil
}

// handleCreateExercise adds a custom exercise for the caller.
func (s *Server) handleCreateExercise(w http.ResponseWriter, r *http.Request) {
	var req exerciseRequest
	if err := decodeJSON(r, &req); err != nil {
		fail(w, r, err)
		return
	}
	n, herr := validateExercise(req)
	if herr != nil {
		fail(w, r, herr)
		return
	}
	c := callerFrom(r)
	ctx := r.Context()
	existing, err := db.ListExercises(ctx, s.db.Pool, c.user.ID)
	if err != nil {
		fail(w, r, err)
		return
	}
	custom := 0
	for _, e := range existing {
		if e.Custom() {
			custom++
		}
	}
	if custom >= maxCustomExercises {
		fail(w, r, invalid("at most 100 custom exercises"))
		return
	}
	e, err := db.InsertCustomExercise(ctx, s.db.Pool, c.user.ID, n)
	if err != nil {
		fail(w, r, err)
		return
	}
	writeJSON(w, http.StatusCreated, map[string]any{"exercise": toExerciseJSON(e)})
}

// handlePatchExercise replaces a custom exercise's fields; catalog exercises cannot change.
func (s *Server) handlePatchExercise(w http.ResponseWriter, r *http.Request) {
	var req exerciseRequest
	if err := decodeJSON(r, &req); err != nil {
		fail(w, r, err)
		return
	}
	n, herr := validateExercise(req)
	if herr != nil {
		fail(w, r, herr)
		return
	}
	e, err := db.UpdateCustomExercise(r.Context(), s.db.Pool, callerFrom(r).user.ID, chi.URLParam(r, "key"), n)
	if errors.Is(err, db.ErrNotFound) {
		fail(w, r, errNoExercise)
		return
	}
	if err != nil {
		fail(w, r, err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"exercise": toExerciseJSON(e)})
}

// handleDeleteExercise hides a custom exercise; its logged sets stay in history.
func (s *Server) handleDeleteExercise(w http.ResponseWriter, r *http.Request) {
	err := db.DeleteCustomExercise(r.Context(), s.db.Pool, callerFrom(r).user.ID, chi.URLParam(r, "key"))
	if errors.Is(err, db.ErrNotFound) {
		fail(w, r, errNoExercise)
		return
	}
	if err != nil {
		fail(w, r, err)
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

type setJSON struct {
	ID        int64      `json:"id"`
	Exercise  string     `json:"exercise"`
	LocalDate score.Date `json:"localDate"`
	LoggedAt  string     `json:"loggedAt"`
	Reps      *int       `json:"reps"`
	Seconds   *int       `json:"seconds"`
	LoadKg    *float64   `json:"loadKg"`
	RIR       *int       `json:"rir"`
	SessionID *int64     `json:"sessionId"`
}

func toSetJSON(s db.ExerciseSet) setJSON {
	return setJSON{ID: s.ID, Exercise: s.ExerciseKey, LocalDate: s.LocalDate, LoggedAt: wireTime(s.LoggedAt),
		Reps: s.Reps, Seconds: s.Seconds, LoadKg: s.LoadKg, RIR: s.RIR, SessionID: s.SessionID}
}

type createSetRequest struct {
	ClientOpID string   `json:"clientOpId"`
	Exercise   string   `json:"exercise"`
	Date       *string  `json:"date"`
	Reps       *int     `json:"reps"`
	Seconds    *int     `json:"seconds"`
	LoadKg     *float64 `json:"loadKg"`
	RIR        *int     `json:"rir"`
	SessionID  *int64   `json:"sessionId"`
}

// validateSetAmount checks a set's reps or seconds and load against the exercise.
func validateSetAmount(e db.Exercise, reps, seconds *int, loadKg *float64) *httpError {
	switch e.Measure {
	case db.MeasureReps:
		if seconds != nil || reps == nil {
			return invalid(e.Name + " is measured in reps")
		}
		if *reps < 1 || *reps > maxSetReps {
			return invalid("reps must be between 1 and 500")
		}
	case db.MeasureSeconds:
		if reps != nil || seconds == nil {
			return invalid(e.Name + " is measured in seconds")
		}
		if *seconds < 1 || *seconds > maxSetSeconds {
			return invalid("seconds must be between 1 and 3600")
		}
	}
	if loadKg != nil && (*loadKg <= 0 || *loadKg > maxSetLoadKg) {
		return invalid("loadKg must be above 0 and at most 1000")
	}
	return nil
}

// handleCreateSet logs one set exactly once per clientOpId and rescores the day, since push-up
// sets move the push-ups quest.
func (s *Server) handleCreateSet(w http.ResponseWriter, r *http.Request) {
	var req createSetRequest
	if err := decodeJSON(r, &req); err != nil {
		fail(w, r, err)
		return
	}
	if !uuidShape.MatchString(req.ClientOpID) {
		fail(w, r, invalid("clientOpId must be a UUID"))
		return
	}
	if req.RIR != nil && (*req.RIR < 0 || *req.RIR > maxSetRIR) {
		fail(w, r, invalid("rir must be between 0 and 10"))
		return
	}
	c := callerFrom(r)
	ctx := r.Context()
	exercise, err := db.ExerciseByKey(ctx, s.db.Pool, c.user.ID, req.Exercise)
	if errors.Is(err, db.ErrNotFound) {
		fail(w, r, errNoExercise)
		return
	}
	if err != nil {
		fail(w, r, err)
		return
	}
	if herr := validateSetAmount(exercise, req.Reps, req.Seconds, req.LoadKg); herr != nil {
		fail(w, r, herr)
		return
	}
	date, herr := parseDateParam(deref(req.Date), score.LocalToday(s.now(), c.loc))
	if herr != nil {
		fail(w, r, herr)
		return
	}
	requested := date
	var (
		set     db.ExerciseSet
		created bool
		scored  engine.Scored
	)
	err = s.db.WithTx(ctx, func(tx pgx.Tx) error {
		if err := db.LockUserDay(ctx, tx, c.user.ID, date); err != nil {
			return err
		}
		if req.SessionID != nil {
			if _, err := sessionByID(r, tx, *req.SessionID); err != nil {
				return err
			}
		}
		var err error
		set, created, err = db.InsertExerciseSet(ctx, tx, db.NewExerciseSet{UserID: c.user.ID, LocalDate: date,
			ExerciseID: exercise.ID, Reps: req.Reps, Seconds: req.Seconds, LoadKg: req.LoadKg, RIR: req.RIR,
			SessionID: req.SessionID, ClientOpID: strings.ToLower(req.ClientOpID)})
		if err != nil {
			return err
		}
		date = set.LocalDate
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
	writeJSON(w, status, map[string]any{"set": toSetJSON(set), "day": toDayDetailJSON(date, scored)})
}

// handleDeleteSet hides one of the caller's sets under the same day window as logging it.
func (s *Server) handleDeleteSet(w http.ResponseWriter, r *http.Request) {
	id, err := strconv.ParseInt(chi.URLParam(r, "id"), 10, 64)
	if err != nil || id < 1 {
		fail(w, r, newErr(http.StatusNotFound, codeNotFound, "no such set"))
		return
	}
	c := callerFrom(r)
	ctx := r.Context()
	var (
		date   score.Date
		scored engine.Scored
	)
	err = s.db.WithTx(ctx, func(tx pgx.Tx) error {
		deleted, err := db.SoftDeleteExerciseSet(ctx, tx, c.user.ID, id)
		if errors.Is(err, db.ErrNotFound) {
			return newErr(http.StatusNotFound, codeNotFound, "no such set")
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

// handleListSets returns the caller's sets of the last N days, optionally for one exercise.
func (s *Server) handleListSets(w http.ResponseWriter, r *http.Request) {
	c := callerFrom(r)
	ctx := r.Context()
	days := defaultSetsDays
	if raw := r.URL.Query().Get("days"); raw != "" {
		n, err := strconv.Atoi(raw)
		if err != nil || n < 1 || n > maxSetsDays {
			fail(w, r, invalid("days must be between 1 and 365"))
			return
		}
		days = n
	}
	var exerciseID int64
	if key := r.URL.Query().Get("exercise"); key != "" {
		e, err := db.ExerciseByKey(ctx, s.db.Pool, c.user.ID, key)
		if errors.Is(err, db.ErrNotFound) {
			fail(w, r, errNoExercise)
			return
		}
		if err != nil {
			fail(w, r, err)
			return
		}
		exerciseID = e.ID
	}
	today := score.LocalToday(s.now(), c.loc)
	sets, err := db.ListExerciseSets(ctx, s.db.Pool, c.user.ID, today.AddDays(1-days), today, exerciseID)
	if err != nil {
		fail(w, r, err)
		return
	}
	out := make([]setJSON, 0, len(sets))
	for _, set := range sets {
		out = append(out, toSetJSON(set))
	}
	writeJSON(w, http.StatusOK, map[string]any{"sets": out})
}

type maxTestRequest struct {
	Reps    *int    `json:"reps"`
	Seconds *int    `json:"seconds"`
	Date    *string `json:"date"`
}

// handleRecordMaxTest records one set to near failure for an exercise. A push-up max also goes
// to the v8 push-up table so the push-up target reads it.
func (s *Server) handleRecordMaxTest(w http.ResponseWriter, r *http.Request) {
	var req maxTestRequest
	if err := decodeJSON(r, &req); err != nil {
		fail(w, r, err)
		return
	}
	c := callerFrom(r)
	ctx := r.Context()
	exercise, err := db.ExerciseByKey(ctx, s.db.Pool, c.user.ID, chi.URLParam(r, "key"))
	if errors.Is(err, db.ErrNotFound) {
		fail(w, r, errNoExercise)
		return
	}
	if err != nil {
		fail(w, r, err)
		return
	}
	if req.Reps != nil && *req.Reps > maxMaxTestReps {
		fail(w, r, invalid("reps must be between 1 and 1000"))
		return
	}
	if herr := validateSetAmount(exercise, clampForCheck(req.Reps), req.Seconds, nil); herr != nil {
		fail(w, r, herr)
		return
	}
	today := score.LocalToday(s.now(), c.loc)
	date := today
	if req.Date != nil {
		var herr *httpError
		if date, herr = parseDateParam(*req.Date, today); herr != nil {
			fail(w, r, herr)
			return
		}
	}
	if date.After(today) || !s.writable(c.user, c.loc, date) {
		fail(w, r, errDateClosed)
		return
	}
	err = s.db.WithTx(ctx, func(tx pgx.Tx) error {
		if err := db.UpsertMaxTest(ctx, tx, c.user.ID, db.MaxTest{ExerciseID: exercise.ID, LocalDate: date,
			Reps: req.Reps, Seconds: req.Seconds}); err != nil {
			return err
		}
		if exercise.Key == "push_up" && req.Reps != nil {
			return db.SetPushupMax(ctx, tx, c.user.ID, date, *req.Reps)
		}
		return nil
	})
	if err != nil {
		fail(w, r, err)
		return
	}
	writeJSON(w, http.StatusCreated, map[string]any{"exercise": exercise.Key,
		"maxTest": maxTestJSON{Date: date, Reps: req.Reps, Seconds: req.Seconds}})
}

// clampForCheck lets a max test above the per-set cap through the amount check; the max test
// has its own, higher cap.
func clampForCheck(reps *int) *int {
	if reps == nil || *reps <= maxSetReps {
		return reps
	}
	capped := maxSetReps
	return &capped
}
