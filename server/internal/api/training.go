package api

import (
	"errors"
	"fmt"
	"log"
	"net/http"
	"slices"
	"strconv"
	"strings"
	"time"
	"unicode/utf8"

	"github.com/go-chi/chi/v5"
	"github.com/jackc/pgx/v5"

	"github.com/nc1107/new-me/server/internal/db"
	"github.com/nc1107/new-me/server/internal/engine"
	"github.com/nc1107/new-me/server/internal/planner"
	"github.com/nc1107/new-me/server/internal/readiness"
	"github.com/nc1107/new-me/server/internal/score"
	"github.com/nc1107/new-me/server/internal/training"
)

// plansPerDay caps plan generation and changes per person, since each costs up to three Claude
// calls.
const plansPerDay = 10

// Error codes of the training endpoints.
const (
	codeTrainingDisabled  = "training_disabled"
	codeNoTrainingProfile = "no_training_profile"
	codeNoPlan            = "no_plan"
	codePlanInvalid       = "plan_invalid"
	codePlannerFailed     = "planner_unavailable"
)

var (
	errTrainingDisabled  = newErr(http.StatusNotFound, codeTrainingDisabled, "plan design needs NEWME_ANTHROPIC_API_KEY on the server")
	errNoTrainingProfile = newErr(http.StatusUnprocessableEntity, codeNoTrainingProfile, "save a training profile first")
	errNoPlan            = newErr(http.StatusNotFound, codeNoPlan, "there is no active plan")
)

// lowerBody marks exercises whose load steps use the larger ACSM range.
var lowerBody = []string{"quads", "hamstrings", "glutes", "calves"}

type trainingProfileJSON struct {
	Equipment      []string `json:"equipment"`
	DumbbellMaxKg  *float64 `json:"dumbbellMaxKg"`
	DaysPerWeek    int      `json:"daysPerWeek"`
	SessionMinutes int      `json:"sessionMinutes"`
	Experience     string   `json:"experience"`
	Focus          string   `json:"focus"`
}

func toTrainingProfileJSON(p db.TrainingProfile) trainingProfileJSON {
	return trainingProfileJSON{Equipment: nonNil(p.Equipment), DumbbellMaxKg: p.DumbbellMaxKg, DaysPerWeek: p.DaysPerWeek,
		SessionMinutes: p.SessionMinutes, Experience: p.Experience, Focus: p.Focus}
}

func (s *Server) handleGetTrainingProfile(w http.ResponseWriter, r *http.Request) {
	p, err := db.GetTrainingProfile(r.Context(), s.db.Pool, callerFrom(r).user.ID)
	if errors.Is(err, db.ErrNotFound) {
		writeJSON(w, http.StatusOK, map[string]any{"profile": nil})
		return
	}
	if err != nil {
		fail(w, r, err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"profile": toTrainingProfileJSON(p)})
}

func (s *Server) handlePutTrainingProfile(w http.ResponseWriter, r *http.Request) {
	var req trainingProfileJSON
	if err := decodeJSON(r, &req); err != nil {
		fail(w, r, err)
		return
	}
	for _, e := range req.Equipment {
		if !slices.Contains(db.Equipment, e) {
			fail(w, r, invalid("unknown equipment "+strconv.Quote(e)))
			return
		}
	}
	switch {
	case req.DaysPerWeek < 2 || req.DaysPerWeek > 6:
		fail(w, r, invalid("daysPerWeek must be between 2 and 6"))
		return
	case req.SessionMinutes < 20 || req.SessionMinutes > 90:
		fail(w, r, invalid("sessionMinutes must be between 20 and 90"))
		return
	case !slices.Contains([]string{training.ExperienceNew, training.ExperienceSome, training.ExperienceExperienced}, req.Experience):
		fail(w, r, invalid("experience must be new, some or experienced"))
		return
	case req.DumbbellMaxKg != nil && (*req.DumbbellMaxKg <= 0 || *req.DumbbellMaxKg > 200):
		fail(w, r, invalid("dumbbellMaxKg must be above 0 and at most 200"))
		return
	}
	focus := strings.TrimSpace(req.Focus)
	if utf8.RuneCountInString(focus) > 300 || hasControlChars(focus) {
		fail(w, r, invalid("focus must be at most 300 characters without control characters"))
		return
	}
	p, err := db.PutTrainingProfile(r.Context(), s.db.Pool, callerFrom(r).user.ID, db.TrainingProfile{
		Equipment: nonNil(req.Equipment), DumbbellMaxKg: req.DumbbellMaxKg, DaysPerWeek: req.DaysPerWeek,
		SessionMinutes: req.SessionMinutes, Experience: req.Experience, Focus: focus})
	if err != nil {
		fail(w, r, err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"profile": toTrainingProfileJSON(p)})
}

type prescriptionJSON struct {
	Exercise string `json:"exercise"`
	Sets     int    `json:"sets"`
	Min      int    `json:"min"`
	Max      int    `json:"max"`
	RIR      int    `json:"rir"`
	RestSec  int    `json:"restSec"`
}

type trainingDayJSON struct {
	Label     string             `json:"label"`
	Weekday   int                `json:"weekday"`
	Exercises []prescriptionJSON `json:"exercises"`
}

type trainingPlanJSON struct {
	ID       int64             `json:"id"`
	StartsOn score.Date        `json:"startsOn"`
	EndsOn   score.Date        `json:"endsOn"`
	Weeks    int               `json:"weeks"`
	Notes    string            `json:"notes"`
	Days     []trainingDayJSON `json:"days"`
}

func toPlanJSON(p db.StoredPlan) trainingPlanJSON {
	out := trainingPlanJSON{ID: p.ID, StartsOn: p.StartsOn, EndsOn: p.EndsOn(), Weeks: p.Weeks, Notes: p.Notes, Days: []trainingDayJSON{}}
	for _, d := range p.Days {
		day := trainingDayJSON{Label: d.Label, Weekday: d.Weekday, Exercises: []prescriptionJSON{}}
		for _, e := range d.Exercises {
			day.Exercises = append(day.Exercises, prescriptionJSON{Exercise: e.Exercise, Sets: e.Sets, Min: e.Min,
				Max: e.Max, RIR: e.RIR, RestSec: e.RestSec})
		}
		out.Days = append(out.Days, day)
	}
	return out
}

func (s *Server) handleGetPlan(w http.ResponseWriter, r *http.Request) {
	p, err := db.ActivePlan(r.Context(), s.db.Pool, callerFrom(r).user.ID)
	if errors.Is(err, db.ErrNotFound) {
		writeJSON(w, http.StatusOK, map[string]any{"plan": nil})
		return
	}
	if err != nil {
		fail(w, r, err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"plan": toPlanJSON(p)})
}

type generatePlanRequest struct {
	Weeks int `json:"weeks"`
}

func (s *Server) handleGeneratePlan(w http.ResponseWriter, r *http.Request) {
	var req generatePlanRequest
	if err := decodeJSON(r, &req); err != nil {
		fail(w, r, err)
		return
	}
	if req.Weeks != 0 && (req.Weeks < training.MinWeeks || req.Weeks > training.MaxWeeks) {
		fail(w, r, invalid("weeks must be between 4 and 6"))
		return
	}
	s.planAndSave(w, r, req.Weeks, nil, "")
}

// Plan change kinds a person can ask for, each turned into one plain instruction for the model.
var changeKinds = map[string]string{
	"swap":       "Swap the exercise named in the detail for a suitable alternative that trains the same muscles.",
	"bodyweight": "Use bodyweight exercises only for now; keep the same days.",
	"shorter":    "Make every session shorter while keeping the weekly volume limits.",
	"pain":       "Something hurts (see detail): avoid exercises that load that area and keep the rest.",
	"new_block":  "Design a fresh block that progresses from the current one.",
}

type changePlanRequest struct {
	Kind   string `json:"kind"`
	Detail string `json:"detail"`
}

func (s *Server) handleChangePlan(w http.ResponseWriter, r *http.Request) {
	var req changePlanRequest
	if err := decodeJSON(r, &req); err != nil {
		fail(w, r, err)
		return
	}
	instruction, ok := changeKinds[req.Kind]
	if !ok {
		fail(w, r, invalid("kind must be swap, bodyweight, shorter, pain or new_block"))
		return
	}
	detail := strings.TrimSpace(req.Detail)
	if utf8.RuneCountInString(detail) > 200 || hasControlChars(detail) {
		fail(w, r, invalid("detail must be at most 200 characters without control characters"))
		return
	}
	current, err := db.ActivePlan(r.Context(), s.db.Pool, callerFrom(r).user.ID)
	if errors.Is(err, db.ErrNotFound) {
		fail(w, r, errNoPlan)
		return
	}
	if err != nil {
		fail(w, r, err)
		return
	}
	change := instruction
	if detail != "" {
		change += " Detail: " + detail
	}
	plan := training.Plan{Weeks: current.Weeks, Days: current.Days, Notes: current.Notes}
	s.planAndSave(w, r, current.Weeks, &plan, change)
}

// planAndSave runs the planner for the caller and saves the result as the active plan starting
// today.
func (s *Server) planAndSave(w http.ResponseWriter, r *http.Request, weeks int, current *training.Plan, change string) {
	if s.planner == nil {
		fail(w, r, errTrainingDisabled)
		return
	}
	c := callerFrom(r)
	ctx := r.Context()
	profile, err := db.GetTrainingProfile(ctx, s.db.Pool, c.user.ID)
	if errors.Is(err, db.ErrNotFound) {
		fail(w, r, errNoTrainingProfile)
		return
	}
	if err != nil {
		fail(w, r, err)
		return
	}
	if ok, retry := s.plans.Allow(strconv.FormatInt(c.user.ID, 10)); !ok {
		w.Header().Set("Retry-After", strconv.Itoa(int(retry.Seconds())+1))
		writeErr(w, http.StatusTooManyRequests, codeRateLimited, "too many plan requests today, try again tomorrow")
		return
	}
	exercises, err := db.ListExercises(ctx, s.db.Pool, c.user.ID)
	if err != nil {
		fail(w, r, err)
		return
	}
	in := planner.Input{
		Profile: training.Profile{DaysPerWeek: profile.DaysPerWeek, SessionMinutes: profile.SessionMinutes,
			Experience: profile.Experience, Equipment: profile.Equipment},
		Focus: profile.Focus, Goal: c.user.GoalKind, Workdays: isoWeekdays(c.user.Schedule.Workdays), Weeks: weeks,
		Current: current, Change: change,
	}
	for _, e := range exercises {
		if e.Stretch() || !equipped(profile.Equipment, e.Equipment) {
			continue
		}
		in.Catalog = append(in.Catalog, planner.Exercise{Key: e.Key, Name: e.Name, PrimaryMuscles: e.PrimaryMuscles,
			Timed: e.Measure == db.MeasureSeconds, Loaded: e.Load == db.LoadExternal, Equipment: e.Equipment})
	}
	plan, err := s.planner.Generate(ctx, in)
	var invalidPlan *planner.InvalidPlan
	if errors.As(err, &invalidPlan) {
		writeJSON(w, http.StatusUnprocessableEntity, map[string]any{"code": codePlanInvalid,
			"error":      "the designed plan still broke the training rules after repair; try again or change the profile",
			"violations": invalidPlan.Violations})
		return
	}
	if err != nil {
		if ctx.Err() == nil {
			log.Printf("[NEWME] training plan for user %d: %v", c.user.ID, err)
		}
		fail(w, r, newErr(http.StatusBadGateway, codePlannerFailed, "the plan designer is unavailable, try again later"))
		return
	}
	today := score.LocalToday(s.now(), c.loc)
	var saved db.StoredPlan
	err = s.db.WithTx(ctx, func(tx pgx.Tx) error {
		var err error
		saved, err = db.ReplacePlan(ctx, tx, c.user.ID, today, plan)
		return err
	})
	if err != nil {
		fail(w, r, err)
		return
	}
	writeJSON(w, http.StatusCreated, map[string]any{"plan": toPlanJSON(saved)})
}

// isoWeekdays turns a Monday-first weekday bitmask into ISO weekday numbers.
func isoWeekdays(mask int) []int {
	var out []int
	for i := range 7 {
		if mask&(1<<i) != 0 {
			out = append(out, i+1)
		}
	}
	return out
}

func equipped(have, need []string) bool {
	if slices.Contains(have, "gym") {
		return true
	}
	for _, n := range need {
		if !slices.Contains(have, n) {
			return false
		}
	}
	return true
}

func (s *Server) handleDeletePlan(w http.ResponseWriter, r *http.Request) {
	if err := db.EndActivePlan(r.Context(), s.db.Pool, callerFrom(r).user.ID); err != nil {
		fail(w, r, err)
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

type sessionTargetJSON struct {
	Exercise string   `json:"exercise"`
	Sets     int      `json:"sets"`
	Amount   int      `json:"amount"`
	LoadKg   *float64 `json:"loadKg"`
}

type sessionExerciseJSON struct {
	Exercise string           `json:"exercise"`
	Name     string           `json:"name"`
	Measure  string           `json:"measure"`
	Load     string           `json:"load"`
	Plan     prescriptionJSON `json:"plan"`
	// PlanName names the planned exercise when progression moved to a variation.
	PlanName string            `json:"planName"`
	Target   sessionTargetJSON `json:"target"`
	Reason   string            `json:"reason"`
	Logged   []setJSON         `json:"logged"`
}

type sessionJSON struct {
	ID        int64                 `json:"id"`
	Date      score.Date            `json:"date"`
	Label     string                `json:"label"`
	Completed bool                  `json:"completed"`
	Exercises []sessionExerciseJSON `json:"exercises"`
	// Eased is true when an Easy readiness morning lightened the session, and EasedReason says why
	// in one line.
	Eased       bool   `json:"eased"`
	EasedReason string `json:"easedReason"`
}

// handleTrainingToday returns today's planned session with each exercise's target from the
// progression rules, or says it is a rest day.
func (s *Server) handleTrainingToday(w http.ResponseWriter, r *http.Request) {
	s.trainingToday(w, r, false)
}

// handleTakeFullSession answers today's session as handleTrainingToday does, after choosing the
// full session for the day. A session that already has sets logged keeps what it was shown.
func (s *Server) handleTakeFullSession(w http.ResponseWriter, r *http.Request) {
	s.trainingToday(w, r, true)
}

func (s *Server) trainingToday(w http.ResponseWriter, r *http.Request, takeFull bool) {
	c := callerFrom(r)
	ctx := r.Context()
	today := score.LocalToday(s.now(), c.loc)
	plan, err := db.ActivePlan(ctx, s.db.Pool, c.user.ID)
	if errors.Is(err, db.ErrNotFound) {
		writeJSON(w, http.StatusOK, map[string]any{"date": today, "plan": nil, "session": nil, "restDay": false, "blockEnded": false})
		return
	}
	if err != nil {
		fail(w, r, err)
		return
	}
	body := map[string]any{"date": today, "plan": toPlanJSON(plan), "session": nil, "restDay": false, "blockEnded": false}
	if today.After(plan.EndsOn()) {
		body["blockEnded"] = true
		writeJSON(w, http.StatusOK, body)
		return
	}
	dayIndex := planDayFor(plan, today)
	if dayIndex < 0 {
		body["restDay"] = true
		writeJSON(w, http.StatusOK, body)
		return
	}
	session, err := db.EnsureSession(ctx, s.db.Pool, c.user.ID, plan.ID, today, dayIndex)
	if err != nil {
		fail(w, r, err)
		return
	}
	// A session that already had sets survives a plan change, and keeps the day of the plan it
	// was scheduled from.
	sessionPlan := plan
	if session.PlanID != plan.ID {
		if sessionPlan, err = db.PlanByID(ctx, s.db.Pool, c.user.ID, session.PlanID); err != nil {
			fail(w, r, err)
			return
		}
	}
	if session.DayIndex >= len(sessionPlan.Days) {
		fail(w, r, fmt.Errorf("session %d points past its plan's days", session.ID))
		return
	}
	if takeFull {
		if err := s.takeFullSession(r, session); err != nil {
			fail(w, r, err)
			return
		}
	}
	out, err := s.sessionDetail(r, sessionPlan, session, today)
	if err != nil {
		fail(w, r, err)
		return
	}
	body["session"] = out
	writeJSON(w, http.StatusOK, body)
}

// planDayFor is the index of the plan day on a date's weekday, or -1 for a rest day.
func planDayFor(plan db.StoredPlan, date score.Date) int {
	t, err := time.Parse(time.DateOnly, string(date))
	if err != nil {
		return -1
	}
	weekday := int(t.Weekday())
	if weekday == 0 {
		weekday = 7
	}
	for i, d := range plan.Days {
		if d.Weekday == weekday {
			return i
		}
	}
	return -1
}

// takeFullSession stores the choice for a session that has not started.
func (s *Server) takeFullSession(r *http.Request, session db.TrainingSession) error {
	c := callerFrom(r)
	ctx := r.Context()
	logged, err := db.ListExerciseSets(ctx, s.db.Pool, c.user.ID, session.LocalDate, session.LocalDate, 0)
	if err != nil {
		return err
	}
	if len(logged) > 0 || session.CompletedAt != nil {
		return nil
	}
	return db.TakeFullSession(ctx, s.db.Pool, session.ID)
}

// sessionEased decides whether the session is shown eased. An unstarted session of today follows
// the morning's readiness, which can still change as readings sync; once sets are logged the
// stored decision stands so the session never changes under the person.
func (s *Server) sessionEased(r *http.Request, session db.TrainingSession, today score.Date, started bool) (bool, string, error) {
	c := callerFrom(r)
	ctx := r.Context()
	eased, full, err := db.SessionEase(ctx, s.db.Pool, session.ID)
	if err != nil || full {
		return false, "", err
	}
	live := !started && session.LocalDate == today
	if !eased && !live {
		return false, "", nil
	}
	ready, err := engine.ReadinessOn(ctx, s.db.Pool, c.user.ID, session.LocalDate)
	if err != nil {
		return false, "", err
	}
	if live {
		now := ready != nil && ready.Level == readiness.LevelEasy
		if now != eased {
			if err := db.SetSessionEased(ctx, s.db.Pool, session.ID, now); err != nil {
				return false, "", err
			}
		}
		eased = now
	}
	if !eased {
		return false, "", nil
	}
	var strain []string
	if ready != nil {
		for _, reason := range ready.Reasons {
			if reason.Strain {
				strain = append(strain, reason.Kind)
			}
		}
	}
	return true, training.EasedReason(strain), nil
}

func (s *Server) sessionDetail(r *http.Request, plan db.StoredPlan, session db.TrainingSession, today score.Date) (sessionJSON, error) {
	c := callerFrom(r)
	ctx := r.Context()
	day := plan.Days[session.DayIndex]
	out := sessionJSON{ID: session.ID, Date: session.LocalDate, Label: day.Label, Completed: session.CompletedAt != nil,
		Exercises: []sessionExerciseJSON{}}
	profile, err := db.GetTrainingProfile(ctx, s.db.Pool, c.user.ID)
	if err != nil && !errors.Is(err, db.ErrNotFound) {
		return out, err
	}
	eq := training.Equipment{Barbell: slices.Contains(profile.Equipment, "barbell") || slices.Contains(profile.Equipment, "gym"),
		Imperial: c.user.Imperial()}
	if profile.DumbbellMaxKg != nil {
		eq.DumbbellMaxKg = *profile.DumbbellMaxKg
	}
	keys := make([]string, 0, len(day.Exercises)*2)
	infos := map[string]db.Exercise{}
	for _, p := range day.Exercises {
		e, err := db.ExerciseByKey(ctx, s.db.Pool, c.user.ID, p.Exercise)
		if errors.Is(err, db.ErrNotFound) {
			continue
		}
		if err != nil {
			return out, err
		}
		infos[p.Exercise] = e
		keys = append(keys, e.Key)
		for _, v := range []string{e.EasierKey, e.HarderKey} {
			if v != "" {
				keys = append(keys, v)
			}
		}
	}
	history, err := db.ExerciseHistory(ctx, s.db.Pool, c.user.ID, keys, session.LocalDate, 2)
	if err != nil {
		return out, err
	}
	logged, err := db.ListExerciseSets(ctx, s.db.Pool, c.user.ID, session.LocalDate, session.LocalDate, 0)
	if err != nil {
		return out, err
	}
	out.Eased, out.EasedReason, err = s.sessionEased(r, session, today, len(logged) > 0 || out.Completed)
	if err != nil {
		return out, err
	}
	for _, p := range day.Exercises {
		planned := p.Exercise
		e, ok := infos[p.Exercise]
		if !ok {
			continue
		}
		plannedName := e.Name
		// After moving to a variation, progression continues from that variation's own sets.
		if key := latestVariation(e, history); key != e.Key {
			if v, err := db.ExerciseByKey(ctx, s.db.Pool, c.user.ID, key); err == nil {
				e = v
			}
		}
		p.Exercise = e.Key
		var target training.Target
		if out.Eased {
			target = training.Ease(p, history[e.Key])
		} else {
			target = training.Next(p, exerciseInfo(e), history[e.Key], eq)
		}
		targetInfo := e
		if target.Exercise != e.Key {
			if v, err := db.ExerciseByKey(ctx, s.db.Pool, c.user.ID, target.Exercise); err == nil {
				targetInfo = v
			}
		}
		item := sessionExerciseJSON{Exercise: targetInfo.Key, Name: targetInfo.Name, Measure: targetInfo.Measure,
			Load: targetInfo.Load, PlanName: plannedName, Plan: prescriptionJSON{Exercise: planned, Sets: p.Sets, Min: p.Min, Max: p.Max,
				RIR: p.RIR, RestSec: p.RestSec},
			Target: sessionTargetJSON{Exercise: target.Exercise, Sets: target.Sets, Amount: target.Amount},
			Reason: target.Reason, Logged: []setJSON{}}
		if target.LoadKg > 0 {
			load := target.LoadKg
			item.Target.LoadKg = &load
		}
		for _, set := range logged {
			if set.ExerciseKey == targetInfo.Key {
				item.Logged = append(item.Logged, toSetJSON(set))
			}
		}
		out.Exercises = append(out.Exercises, item)
	}
	return out, nil
}

// latestVariation is the key, among an exercise and its easier and harder variations, whose
// sets are the most recent; the exercise itself when none has history.
func latestVariation(e db.Exercise, history map[string][]training.SessionResult) string {
	best, bestDate := e.Key, ""
	for _, k := range []string{e.Key, e.EasierKey, e.HarderKey} {
		if h := history[k]; k != "" && len(h) > 0 && len(h[0].Sets) > 0 && h[0].Sets[0].Date > bestDate {
			best, bestDate = k, h[0].Sets[0].Date
		}
	}
	return best
}

func exerciseInfo(e db.Exercise) training.ExerciseInfo {
	info := training.ExerciseInfo{Key: e.Key, Name: e.Name, Timed: e.Measure == db.MeasureSeconds,
		Loaded: e.Load == db.LoadExternal, EasierKey: e.EasierKey, HarderKey: e.HarderKey}
	for _, m := range e.PrimaryMuscles {
		if slices.Contains(lowerBody, m) {
			info.Lower = true
		}
	}
	return info
}

// handleCompleteSession marks a session done and rescores its day, which completes the
// strength quest.
func (s *Server) handleCompleteSession(w http.ResponseWriter, r *http.Request) {
	id, err := strconv.ParseInt(chi.URLParam(r, "id"), 10, 64)
	if err != nil || id < 1 {
		fail(w, r, newErr(http.StatusNotFound, codeNotFound, "no such session"))
		return
	}
	c := callerFrom(r)
	ctx := r.Context()
	var (
		session db.TrainingSession
		scored  engine.Scored
	)
	err = s.db.WithTx(ctx, func(tx pgx.Tx) error {
		existing, err := sessionByID(r, tx, id)
		if err != nil {
			return err
		}
		if err := db.LockUserDay(ctx, tx, c.user.ID, existing.LocalDate); err != nil {
			return err
		}
		if !s.writable(c.user, c.loc, existing.LocalDate) {
			return errDateClosed
		}
		if session, err = db.CompleteSession(ctx, tx, c.user.ID, id); err != nil {
			return err
		}
		scored, err = s.scoreDay(ctx, tx, c, session.LocalDate)
		return err
	})
	if err != nil {
		fail(w, r, err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"session": map[string]any{"id": session.ID, "date": session.LocalDate,
		"completed": true}, "day": toDayDetailJSON(session.LocalDate, scored)})
}

func sessionByID(r *http.Request, q db.Querier, id int64) (db.TrainingSession, error) {
	c := callerFrom(r)
	var s db.TrainingSession
	err := q.QueryRow(r.Context(), `SELECT id, plan_id, local_date::text, day_index, completed_at FROM training_sessions
		WHERE id = $1 AND user_id = $2`, id, c.user.ID).Scan(&s.ID, &s.PlanID, &s.LocalDate, &s.DayIndex, &s.CompletedAt)
	if err != nil && errors.Is(err, pgx.ErrNoRows) {
		return s, newErr(http.StatusNotFound, codeNotFound, "no such session")
	}
	return s, err
}

type muscleVolumeJSON struct {
	Muscle string `json:"muscle"`
	// Weeks are hard sets per ISO week, oldest first, ending with this week.
	Weeks []int `json:"weeks"`
}

// handleTrainingProgress returns the weekly sets per muscle for the last four weeks against the
// evidence range for the person's experience.
func (s *Server) handleTrainingProgress(w http.ResponseWriter, r *http.Request) {
	c := callerFrom(r)
	ctx := r.Context()
	today := score.LocalToday(s.now(), c.loc)
	start := score.WeekStart(today).AddDays(-21)
	sets, err := db.ListExerciseSets(ctx, s.db.Pool, c.user.ID, start, today, 0)
	if err != nil {
		fail(w, r, err)
		return
	}
	exercises, err := db.ListExercises(ctx, s.db.Pool, c.user.ID)
	if err != nil {
		fail(w, r, err)
		return
	}
	muscles := map[int64][]string{}
	for _, e := range exercises {
		if !e.Stretch() {
			muscles[e.ID] = e.PrimaryMuscles
		}
	}
	weekly := map[string][]int{}
	for _, m := range db.Muscles {
		weekly[m] = make([]int, 4)
	}
	for _, set := range sets {
		week := int(score.WeekStart(set.LocalDate).Time().Sub(start.Time()).Hours()+12) / (24 * 7)
		if week < 0 || week > 3 {
			continue
		}
		for _, m := range muscles[set.ExerciseID] {
			weekly[m][week]++
		}
	}
	experience := training.ExperienceNew
	if p, err := db.GetTrainingProfile(ctx, s.db.Pool, c.user.ID); err == nil {
		experience = p.Experience
	}
	rng := training.WeeklySetRange(experience)
	out := make([]muscleVolumeJSON, 0, len(db.Muscles))
	for _, m := range db.Muscles {
		out = append(out, muscleVolumeJSON{Muscle: m, Weeks: weekly[m]})
	}
	writeJSON(w, http.StatusOK, map[string]any{"weeksStart": start, "muscles": out,
		"range": map[string]any{"min": rng.Min, "max": rng.Max, "label": rng.Label,
			"source": "Schoenfeld, Ogborn and Krieger, J Sports Sci 2017;35:1073"}})
}
