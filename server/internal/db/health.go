package db

import (
	"context"
	"strconv"
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
	// Metrics holds the day's Health readings by metric key, only for keys that have one.
	Metrics map[string]float64
	// Synced marks every metric with a reading on or before the day, which is what lets a
	// Health-fed quest appear.
	Synced map[string]bool

	Pushups        int
	ReadingMinutes int
	ReadingPages   int
	YogaMinutes    int
	// OtherFullMinutes and OtherEasyMinutes are manual activity minutes by intensity: moderate
	// and hard count fully toward exercise, easy counts half.
	OtherFullMinutes int
	OtherEasyMinutes int
	// ListeningMinutes is Audiobookshelf listening for the day, which counts as reading time.
	ListeningMinutes int

	// Workouts are the day's Health workouts, which complete the push-ups quest and add to yoga.
	Workouts []score.WorkoutSpan
	// HIITMinHR is the average heart rate a HIIT workout needs to count, nil when the person's
	// age or resting heart rate is unknown.
	HIITMinHR *float64

	Meals    int
	Kcal     int
	ProteinG float64
	CarbsG   float64
	FatG     float64
	FiberG   float64
}

// ManualExerciseMinutes is what manual activity adds to the day's exercise minutes.
func (in DayInputs) ManualExerciseMinutes() int { return in.OtherFullMinutes + in.OtherEasyMinutes/2 }

// Metric is the day's reading for a metric, or 0 when there is none.
func (in DayInputs) Metric(key string) float64 { return in.Metrics[key] }

// Connected reports whether the metric has ever been synced on or before the day.
func (in DayInputs) Connected(key string) bool { return in.Synced[key] }

// LoadDayInputs aggregates the day's live logs and Health readings in two queries.
// A metric is Synced once any reading of it exists on or before the date.
func LoadDayInputs(ctx context.Context, q Querier, userID int64, date score.Date) (DayInputs, error) {
	var in DayInputs
	err := q.QueryRow(ctx, `
		SELECT a.pushups, a.reading_minutes, a.reading_pages, a.yoga_minutes, a.other_full, a.other_easy,
		       m.meals, m.kcal, m.protein, m.carbs, m.fat, m.fiber
		FROM (
			SELECT COALESCE(sum(quantity) FILTER (WHERE type = 'pushups'), 0)::int AS pushups,
			       COALESCE(sum(quantity) FILTER (WHERE type = 'reading_minutes'), 0)::int AS reading_minutes,
			       COALESCE(sum(quantity) FILTER (WHERE type = 'reading_pages'), 0)::int AS reading_pages,
			       COALESCE(sum(quantity) FILTER (WHERE type = 'yoga_minutes'), 0)::int AS yoga_minutes,
			       COALESCE(sum(quantity) FILTER (WHERE type = 'other_minutes' AND intensity <> 'easy'), 0)::int AS other_full,
			       COALESCE(sum(quantity) FILTER (WHERE type = 'other_minutes' AND intensity = 'easy'), 0)::int AS other_easy
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
		&in.Pushups, &in.ReadingMinutes, &in.ReadingPages, &in.YogaMinutes, &in.OtherFullMinutes, &in.OtherEasyMinutes,
		&in.Meals, &in.Kcal, &in.ProteinG, &in.CarbsG, &in.FatG, &in.FiberG)
	if err != nil {
		return in, err
	}
	if in.ListeningMinutes, err = ListeningMinutes(ctx, q, userID, date); err != nil {
		return in, err
	}
	if in.Workouts, err = WorkoutSpans(ctx, q, userID, date); err != nil {
		return in, err
	}
	in.Metrics, in.Synced, err = loadHealthDay(ctx, q, userID, date)
	if err != nil {
		return in, err
	}
	in.HIITMinHR, err = hiitThreshold(ctx, q, userID, date)
	return in, err
}

func loadHealthDay(ctx context.Context, q Querier, userID int64, date score.Date) (map[string]float64, map[string]bool, error) {
	rows, err := q.Query(ctx, `
		SELECT metric,
		       max(value) FILTER (WHERE local_date = $2::date)::float8,
		       true
		FROM health_daily WHERE user_id = $1 AND local_date <= $2::date
		GROUP BY metric`, userID, date)
	if err != nil {
		return nil, nil, err
	}
	defer rows.Close()
	metrics, synced := map[string]float64{}, map[string]bool{}
	for rows.Next() {
		var key string
		var value *float64
		var seen bool
		if err := rows.Scan(&key, &value, &seen); err != nil {
			return nil, nil, err
		}
		synced[key] = seen
		if value != nil {
			metrics[key] = *value
		}
	}
	return metrics, synced, rows.Err()
}

// HealthDay returns the date's readings by metric key.
func HealthDay(ctx context.Context, q Querier, userID int64, date score.Date) (map[string]float64, error) {
	metrics, _, err := loadHealthDay(ctx, q, userID, date)
	return metrics, err
}

// LatestMeasurement is the newest reading of a metric on or before a date.
type LatestMeasurement struct {
	Value float64
	Date  score.Date
}

// LatestHealth returns, for each requested metric that has one, the newest reading on or
// before the date.
func LatestHealth(ctx context.Context, q Querier, userID int64, date score.Date, metrics []string) (map[string]LatestMeasurement, error) {
	rows, err := q.Query(ctx, `
		SELECT DISTINCT ON (metric) metric, value, to_char(local_date, 'YYYY-MM-DD')
		FROM health_daily
		WHERE user_id = $1 AND local_date <= $2::date AND metric = ANY($3)
		ORDER BY metric, local_date DESC`, userID, date, metrics)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := map[string]LatestMeasurement{}
	for rows.Next() {
		var key string
		var m LatestMeasurement
		if err := rows.Scan(&key, &m.Value, &m.Date); err != nil {
			return nil, err
		}
		out[key] = m
	}
	return out, rows.Err()
}

// HealthPoint is one day of a metric.
type HealthPoint struct {
	Date  score.Date
	Value float64
}

// HealthSeries lists a metric's readings from..to inclusive, oldest first.
func HealthSeries(ctx context.Context, q Querier, userID int64, metric string, from, to score.Date) ([]HealthPoint, error) {
	rows, err := q.Query(ctx, `
		SELECT to_char(local_date, 'YYYY-MM-DD'), value FROM health_daily
		WHERE user_id = $1 AND metric = $2 AND local_date BETWEEN $3::date AND $4::date
		ORDER BY local_date`, userID, metric, from, to)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := []HealthPoint{}
	for rows.Next() {
		var p HealthPoint
		if err := rows.Scan(&p.Date, &p.Value); err != nil {
			return nil, err
		}
		out = append(out, p)
	}
	return out, rows.Err()
}

// hiitThreshold derives the HIIT heart-rate threshold from the birth year and the newest
// resting heart rate on or before the date.
func hiitThreshold(ctx context.Context, q Querier, userID int64, date score.Date) (*float64, error) {
	var birthYear *int
	if err := q.QueryRow(ctx, `SELECT birth_year FROM users WHERE id = $1`, userID).Scan(&birthYear); err != nil {
		return nil, err
	}
	if birthYear == nil {
		return nil, nil
	}
	resting, err := LatestHealth(ctx, q, userID, date, []string{"resting_hr"})
	if err != nil {
		return nil, err
	}
	rest, ok := resting["resting_hr"]
	if !ok {
		return nil, nil
	}
	year, err := strconv.Atoi(string(date)[:4])
	if err != nil {
		return nil, nil
	}
	age := year - *birthYear
	return score.HIITMinHR(&age, &rest.Value), nil
}
