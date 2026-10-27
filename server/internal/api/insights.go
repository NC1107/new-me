package api

import (
	"net/http"

	"github.com/nc1107/new-me/server/internal/db"
	"github.com/nc1107/new-me/server/internal/insights"
	"github.com/nc1107/new-me/server/internal/score"
)

// defaultSleepTargetMin is the sleep target shown while the sleep quest is off.
const defaultSleepTargetMin = 420

// handleInsights answers the caller's step, sleep and workout insights, computed from the
// stored data by the pure functions in the insights package.
func (s *Server) handleInsights(w http.ResponseWriter, r *http.Request) {
	c := callerFrom(r)
	ctx := r.Context()
	today := score.LocalToday(s.now(), c.loc)
	from := today.AddDays(-29)

	templates, err := db.GetQuestTemplates(ctx, s.db.Pool, c.user.ID)
	if err != nil {
		fail(w, r, err)
		return
	}
	stepGoal, sleepTarget := 0, defaultSleepTargetMin
	for _, t := range templates {
		switch {
		case t.Key == db.QuestSteps:
			stepGoal = t.Target
		case t.Key == db.QuestSleep && t.Enabled:
			sleepTarget = t.Target
		}
	}

	points, err := db.HealthSeries(ctx, s.db.Pool, c.user.ID, db.MetricSteps, from, today)
	if err != nil {
		fail(w, r, err)
		return
	}
	days := make([]insights.StepDay, len(points))
	for i, p := range points {
		days[i] = insights.StepDay{Date: p.Date, Steps: p.Value}
	}

	stored, err := db.ListSleepNights(ctx, s.db.Pool, c.user.ID, from, today)
	if err != nil {
		fail(w, r, err)
		return
	}
	nights := make([]insights.Night, len(stored))
	for i, n := range stored {
		nights[i] = insights.Night{
			Date: n.Date, BedAt: n.BedAt, WakeAt: n.WakeAt, AsleepMin: n.AsleepMin,
			DeepMin: n.DeepMin, REMMin: n.REMMin, CoreMin: n.CoreMin, AwakeMin: n.AwakeMin,
		}
	}

	rows, err := db.ListWorkouts(ctx, s.db.Pool, c.user.ID, from, today)
	if err != nil {
		fail(w, r, err)
		return
	}
	workouts := make([]insights.Workout, len(rows))
	for i, row := range rows {
		workouts[i] = insights.Workout{Type: row.Type, Date: row.LocalDate, DurationMin: row.DurationMin}
	}

	writeJSON(w, http.StatusOK, map[string]any{
		"steps": insights.ComputeSteps(insights.StepInput{
			Days: days, Today: today, Goal: stepGoal, BirthYear: c.user.BirthYear,
		}),
		"sleep": insights.ComputeSleep(insights.SleepInput{
			Nights: nights, Today: today, TargetMin: sleepTarget, Loc: c.loc,
		}),
		"workouts": insights.ComputeWorkouts(workouts, today),
	})
}
