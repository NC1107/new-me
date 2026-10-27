package engine

import (
	"context"

	"github.com/nc1107/new-me/server/internal/db"
	"github.com/nc1107/new-me/server/internal/readiness"
	"github.com/nc1107/new-me/server/internal/score"
)

const (
	// DefaultSleepTargetMin applies while the sleep quest is off.
	DefaultSleepTargetMin = 420
	// readinessBaselineDays is the history HRV and resting heart rate are compared against.
	readinessBaselineDays = 30
	metricHRV             = "hrv_ms"
	metricRestingHR       = "resting_hr"
)

// ReadinessFor turns a morning's readings into the readiness level. metrics are the date's Health
// readings; the baselines are read from the days before it.
func ReadinessFor(ctx context.Context, q db.Querier, userID int64, date score.Date, lastNightMin *int,
	sleepTargetMin int, metrics map[string]float64) (*readiness.Result, error) {
	in := readiness.Input{SleepMin: lastNightMin, SleepTargetMin: sleepTargetMin}
	if v, ok := metrics[metricHRV]; ok {
		in.HRV = &v
	}
	if v, ok := metrics[metricRestingHR]; ok {
		in.RestingHR = &v
	}
	var err error
	if in.HRVBase, err = readingsBefore(ctx, q, userID, metricHRV, date); err != nil {
		return nil, err
	}
	if in.RestingBase, err = readingsBefore(ctx, q, userID, metricRestingHR, date); err != nil {
		return nil, err
	}
	if res, ok := readiness.Compute(in); ok {
		return &res, nil
	}
	return nil, nil
}

func readingsBefore(ctx context.Context, q db.Querier, userID int64, metric string, date score.Date) ([]float64, error) {
	points, err := db.HealthSeries(ctx, q, userID, metric, date.AddDays(-readinessBaselineDays), date.AddDays(-1))
	if err != nil {
		return nil, err
	}
	out := make([]float64, len(points))
	for i, p := range points {
		out[i] = p.Value
	}
	return out, nil
}

// ReadinessOn is the readiness of a past or present morning, from what is stored for it.
func ReadinessOn(ctx context.Context, q db.Querier, userID int64, date score.Date) (*readiness.Result, error) {
	templates, err := db.GetQuestTemplates(ctx, q, userID)
	if err != nil {
		return nil, err
	}
	target := DefaultSleepTargetMin
	for _, t := range templates {
		if t.Key == db.QuestSleep && t.Enabled {
			target = t.Target
		}
	}
	metrics, err := db.HealthDay(ctx, q, userID, date)
	if err != nil {
		return nil, err
	}
	var lastNight *int
	nights, err := db.ListSleepNights(ctx, q, userID, date, date)
	if err != nil {
		return nil, err
	}
	for _, n := range nights {
		if n.AsleepMin > 0 {
			asleep := n.AsleepMin
			lastNight = &asleep
		}
	}
	if lastNight == nil {
		if m := int(metrics[db.MetricSleep]); m > 0 {
			lastNight = &m
		}
	}
	return ReadinessFor(ctx, q, userID, date, lastNight, target, metrics)
}
