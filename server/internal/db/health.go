package db

import (
	"context"
	"time"

	"github.com/nc1107/new-me/server/internal/score"
)

// UpsertHealthDaily stores a day's reading for one metric unless a newer one is already there,
// so a stale retry or a second device can never lower a count. applied is false when the
// stored reading was newer and nothing changed.
func UpsertHealthDaily(ctx context.Context, q Querier, userID int64, date score.Date, metric string,
	value float64, source string, measuredAt time.Time) (applied bool, err error) {
	var one int
	err = q.QueryRow(ctx, `
		INSERT INTO health_daily AS h (user_id, local_date, metric, value, source, measured_at)
		VALUES ($1, $2::date, $3, $4, $5, $6)
		ON CONFLICT (user_id, local_date, metric) DO UPDATE
		SET value = EXCLUDED.value, source = EXCLUDED.source,
		    measured_at = EXCLUDED.measured_at, updated_at = now()
		WHERE h.measured_at <= EXCLUDED.measured_at
		RETURNING 1`, userID, date, metric, value, source, measuredAt).Scan(&one)
	if err != nil {
		if notFound(err) == ErrNotFound {
			return false, nil
		}
		return false, err
	}
	return true, nil
}

// LastHealthSync is when the user's Health data last changed, or nil if it never arrived.
func LastHealthSync(ctx context.Context, q Querier, userID int64) (*time.Time, error) {
	var t *time.Time
	err := q.QueryRow(ctx, `SELECT max(updated_at) FROM health_daily WHERE user_id = $1`, userID).Scan(&t)
	return t, err
}

// DayInputs is everything scoring and the Today screen read for one user-day.
type DayInputs struct {
	Steps          float64
	ActiveEnergy   float64
	StepsConnected bool

	Pushups        int
	ReadingMinutes int
	ReadingPages   int
	YogaMinutes    int

	Meals    int
	Kcal     int
	ProteinG float64
	CarbsG   float64
	FatG     float64
	FiberG   float64
}

// LoadDayInputs aggregates the day's live logs and Health readings in one round trip.
// StepsConnected is true once any steps reading exists on or before the date.
func LoadDayInputs(ctx context.Context, q Querier, userID int64, date score.Date) (DayInputs, error) {
	var in DayInputs
	err := q.QueryRow(ctx, `
		SELECT h.steps, h.active_energy, h.steps_connected,
		       a.pushups, a.reading_minutes, a.reading_pages, a.yoga_minutes,
		       m.meals, m.kcal, m.protein, m.carbs, m.fat, m.fiber
		FROM (
			SELECT COALESCE(max(value) FILTER (WHERE metric = 'steps' AND local_date = $2::date), 0)::float8 AS steps,
			       COALESCE(max(value) FILTER (WHERE metric = 'active_energy' AND local_date = $2::date), 0)::float8 AS active_energy,
			       COALESCE(bool_or(metric = 'steps' AND local_date <= $2::date), false) AS steps_connected
			FROM health_daily WHERE user_id = $1
		) h, (
			SELECT COALESCE(sum(quantity) FILTER (WHERE type = 'pushups'), 0)::int AS pushups,
			       COALESCE(sum(quantity) FILTER (WHERE type = 'reading_minutes'), 0)::int AS reading_minutes,
			       COALESCE(sum(quantity) FILTER (WHERE type = 'reading_pages'), 0)::int AS reading_pages,
			       COALESCE(sum(quantity) FILTER (WHERE type = 'yoga_minutes'), 0)::int AS yoga_minutes
			FROM activity_logs WHERE user_id = $1 AND local_date = $2::date AND deleted_at IS NULL
		) a, (
			SELECT (count(*) FILTER (WHERE kcal > 0))::int AS meals,
			       COALESCE(sum(kcal), 0)::int AS kcal,
			       COALESCE(sum(protein_g), 0)::float8 AS protein,
			       COALESCE(sum(carbs_g), 0)::float8 AS carbs,
			       COALESCE(sum(fat_g), 0)::float8 AS fat,
			       COALESCE(sum(fiber_g), 0)::float8 AS fiber
			FROM meal_logs WHERE user_id = $1 AND local_date = $2::date AND deleted_at IS NULL
		) m`, userID, date).Scan(
		&in.Steps, &in.ActiveEnergy, &in.StepsConnected,
		&in.Pushups, &in.ReadingMinutes, &in.ReadingPages, &in.YogaMinutes,
		&in.Meals, &in.Kcal, &in.ProteinG, &in.CarbsG, &in.FatG, &in.FiberG)
	return in, err
}
