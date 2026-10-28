package api

import (
	"errors"
	"net/http"
	"strconv"
	"time"

	"github.com/go-chi/chi/v5"

	"github.com/nc1107/new-me/server/internal/db"
	"github.com/nc1107/new-me/server/internal/score"
	"github.com/nc1107/new-me/server/internal/training"
)

const (
	defaultExerciseHistoryDays = 180
	maxExerciseHistoryDays     = 730
)

type historySetJSON struct {
	Exercise string   `json:"exercise"`
	Name     string   `json:"name"`
	Reps     *int     `json:"reps"`
	Seconds  *int     `json:"seconds"`
	LoadKg   *float64 `json:"loadKg"`
}

type historyDayJSON struct {
	Date             score.Date       `json:"date"`
	Sets             int              `json:"sets"`
	SessionCompleted bool             `json:"sessionCompleted"`
	YogaMinutes      int              `json:"yogaMinutes"`
	WorkoutTypes     []string         `json:"workoutTypes"`
	Logged           []historySetJSON `json:"logged"`
}

// handleTrainingHistory returns the caller's training days of one month: sets, whether the
// planned session was completed, yoga and mobility minutes, and the Health workout types.
func (s *Server) handleTrainingHistory(w http.ResponseWriter, r *http.Request) {
	c := callerFrom(r)
	first, err := time.Parse("2006-01", r.URL.Query().Get("month"))
	if err != nil {
		fail(w, r, invalid("month must be YYYY-MM"))
		return
	}
	from := score.DateOf(first)
	to := from.AddDays(first.AddDate(0, 1, -1).Day() - 1)
	days, err := db.TrainingHistory(r.Context(), s.db.Pool, c.user.ID, from, to)
	if err != nil {
		fail(w, r, err)
		return
	}
	out := make([]historyDayJSON, 0, len(days))
	for _, d := range days {
		logged := make([]historySetJSON, 0, len(d.Sets))
		for _, set := range d.Sets {
			logged = append(logged, historySetJSON(set))
		}
		out = append(out, historyDayJSON{Date: d.Date, Sets: d.SetCount, SessionCompleted: d.SessionCompleted,
			YogaMinutes: d.YogaMinutes, WorkoutTypes: d.WorkoutTypes, Logged: logged})
	}
	writeJSON(w, http.StatusOK, map[string]any{"month": first.Format("2006-01"), "days": out})
}

type chartPointJSON struct {
	Date  score.Date `json:"date"`
	Value float64    `json:"value"`
}

// handleExerciseHistory returns the per-day bests of one exercise in the chart metric, and the
// exercise's max tests separately so the chart can mark them.
func (s *Server) handleExerciseHistory(w http.ResponseWriter, r *http.Request) {
	c := callerFrom(r)
	ctx := r.Context()
	days := defaultExerciseHistoryDays
	if raw := r.URL.Query().Get("days"); raw != "" {
		n, err := strconv.Atoi(raw)
		if err != nil || n < 1 || n > maxExerciseHistoryDays {
			fail(w, r, invalid("days must be between 1 and 730"))
			return
		}
		days = n
	}
	exercise, err := db.ExerciseByKey(ctx, s.db.Pool, c.user.ID, chi.URLParam(r, "key"))
	if errors.Is(err, db.ErrNotFound) {
		fail(w, r, errNoExercise)
		return
	}
	if err != nil {
		fail(w, r, err)
		return
	}
	today := score.LocalToday(s.now(), c.loc)
	from := today.AddDays(1 - days)
	sets, err := db.ListExerciseSets(ctx, s.db.Pool, c.user.ID, from, today, exercise.ID)
	if err != nil {
		fail(w, r, err)
		return
	}
	tests, err := db.ListMaxTests(ctx, s.db.Pool, c.user.ID, exercise.ID, from, today)
	if err != nil {
		fail(w, r, err)
		return
	}
	rules := make([]training.Set, 0, len(sets))
	for _, set := range sets {
		rules = append(rules, trainingSet(set))
	}
	series := training.ChartSeries(exercise.Measure == db.MeasureSeconds, exercise.Load == db.LoadExternal, rules)
	points := make([]chartPointJSON, 0, len(series.Points))
	for _, p := range series.Points {
		points = append(points, chartPointJSON{Date: score.Date(p.Date), Value: p.Value})
	}
	maxTests := make([]maxTestJSON, 0, len(tests))
	for _, t := range tests {
		maxTests = append(maxTests, maxTestJSON{Date: t.LocalDate, Reps: t.Reps, Seconds: t.Seconds})
	}
	writeJSON(w, http.StatusOK, map[string]any{
		"exercise": exercise.Key, "measure": exercise.Measure, "load": exercise.Load,
		"metric": series.Metric, "estimated": series.Metric.Estimated(), "days": days,
		"points": points, "maxTests": maxTests,
	})
}
