package api

import (
	"context"
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
	stepGoal, sleepTarget, proteinTemplate := 0, defaultSleepTargetMin, db.DefaultProteinTarget
	for _, t := range templates {
		switch {
		case t.Key == db.QuestSteps:
			stepGoal = t.Target
		case t.Key == db.QuestSleep && t.Enabled:
			sleepTarget = t.Target
		case t.Key == db.QuestProtein:
			proteinTemplate = t.Target
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

	weight, err := s.weightInsight(ctx, c.user.ID, today)
	if err != nil {
		fail(w, r, err)
		return
	}
	activity, err := s.activityInsight(ctx, c, today)
	if err != nil {
		fail(w, r, err)
		return
	}
	protein, err := s.proteinInsight(ctx, c, today, proteinTemplate)
	if err != nil {
		fail(w, r, err)
		return
	}

	writeJSON(w, http.StatusOK, map[string]any{
		"weight":   weight,
		"activity": activity,
		"protein":  protein,
		"steps": insights.ComputeSteps(insights.StepInput{
			Days: days, Today: today, Goal: stepGoal, BirthYear: c.user.BirthYear,
		}),
		"sleep": insights.ComputeSleep(insights.SleepInput{
			Nights: nights, Today: today, TargetMin: sleepTarget, Loc: c.loc,
		}),
		"workouts": insights.ComputeWorkouts(workouts, today),
	})
}

// weightInsight smooths every weigh-in into a trend and its weekly rate; nil without a weigh-in.
func (s *Server) weightInsight(ctx context.Context, userID int64, today score.Date) (*insights.Weight, error) {
	points, err := db.HealthSeries(ctx, s.db.Pool, userID, db.MetricWeight, "0001-01-01", today)
	if err != nil {
		return nil, err
	}
	readings := make([]insights.Reading, len(points))
	for i, p := range points {
		readings[i] = insights.Reading{Date: p.Date, Value: p.Value}
	}
	return insights.ComputeWeight(readings), nil
}

// activityInsight totals the last seven days of workouts against the WHO 2020 guideline.
func (s *Server) activityInsight(ctx context.Context, c caller, today score.Date) (insights.Activity, error) {
	rows, err := db.ListWorkouts(ctx, s.db.Pool, c.user.ID, today.AddDays(-6), today)
	if err != nil {
		return insights.Activity{}, err
	}
	sessions := make([]insights.Session, len(rows))
	for i, row := range rows {
		sessions[i] = insights.Session{Date: row.LocalDate, Type: row.Type, DurationMin: row.DurationMin, AvgHR: row.AvgHR}
	}
	in := insights.ActivityInput{Sessions: sessions, Today: today}
	latest, err := db.LatestHealth(ctx, s.db.Pool, c.user.ID, today, []string{"resting_hr"})
	if err != nil {
		return insights.Activity{}, err
	}
	if rest, ok := latest["resting_hr"]; ok && c.user.BirthYear != nil {
		in.RestingHR = rest.Value
		in.MaxHR = float64(220 - (s.now().In(c.loc).Year() - *c.user.BirthYear))
	}
	return insights.ComputeActivity(in), nil
}

// proteinInsight reports the protein target, the per-kilogram value it follows, and how many of
// the last seven completed days reached it.
func (s *Server) proteinInsight(ctx context.Context, c caller, today score.Date, templateTarget int) (insights.Protein, error) {
	protein, err := proteinFor(ctx, s.db.Pool, c.user, today, templateTarget)
	if err != nil {
		return insights.Protein{}, err
	}
	rows, err := db.ProteinDays(ctx, s.db.Pool, c.user.ID, today.AddDays(-7), today.AddDays(-1))
	if err != nil {
		return insights.Protein{}, err
	}
	days := make([]insights.ProteinDay, len(rows))
	for i, r := range rows {
		days[i] = insights.ProteinDay{Date: r.Date, TargetG: r.TargetG, Grams: r.Grams}
	}
	return insights.ComputeProtein(protein.Effective, protein.WeightKg, days), nil
}
