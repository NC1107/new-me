package db

import (
	"context"
	"encoding/json"

	"github.com/nc1107/new-me/server/internal/score"
)

// PushupMax is a recorded max test: one set of push-ups to near failure.
type PushupMax struct {
	Date score.Date
	Reps int
}

// SetPushupMax records the test of a day, replacing an earlier test the same day.
func SetPushupMax(ctx context.Context, q Querier, userID int64, date score.Date, reps int) error {
	_, err := q.Exec(ctx, `
		INSERT INTO pushup_max_tests (user_id, local_date, reps) VALUES ($1, $2::date, $3)
		ON CONFLICT (user_id, local_date) DO UPDATE SET reps = EXCLUDED.reps, created_at = now()`,
		userID, date, reps)
	return err
}

// LatestPushupMax is the newest max test, or ErrNotFound.
func LatestPushupMax(ctx context.Context, q Querier, userID int64) (PushupMax, error) {
	var m PushupMax
	err := q.QueryRow(ctx, `
		SELECT local_date::text, reps FROM pushup_max_tests
		WHERE user_id = $1 ORDER BY local_date DESC LIMIT 1`, userID).Scan(&m.Date, &m.Reps)
	return m, notFound(err)
}

// PushupSets lists each day's push-up log entries (one entry is one set), oldest first.
func PushupSets(ctx context.Context, q Querier, userID int64, from, to score.Date) (map[score.Date][]int, error) {
	rows, err := q.Query(ctx, `
		SELECT local_date::text, quantity FROM activity_logs
		WHERE user_id = $1 AND type = 'pushups' AND deleted_at IS NULL
		  AND local_date BETWEEN $2::date AND $3::date
		ORDER BY local_date, id`, userID, from, to)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := map[score.Date][]int{}
	for rows.Next() {
		var d score.Date
		var reps int
		if err := rows.Scan(&d, &reps); err != nil {
			return nil, err
		}
		out[d] = append(out[d], reps)
	}
	return out, rows.Err()
}

// DailyKcal sums the logged energy of each day from..to that has any.
func DailyKcal(ctx context.Context, q Querier, userID int64, from, to score.Date) (map[score.Date]float64, error) {
	rows, err := q.Query(ctx, `
		SELECT local_date::text, sum(kcal)::float8 FROM meal_logs
		WHERE user_id = $1 AND deleted_at IS NULL AND local_date BETWEEN $2::date AND $3::date
		GROUP BY local_date HAVING sum(kcal) > 0`, userID, from, to)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := map[score.Date]float64{}
	for rows.Next() {
		var d score.Date
		var kcal float64
		if err := rows.Scan(&d, &kcal); err != nil {
			return nil, err
		}
		out[d] = kcal
	}
	return out, rows.Err()
}

// TargetBaseline is a target's formula value when it was last applied, decided on or first seen,
// with the inputs that gave it.
type TargetBaseline struct {
	Value  float64
	Inputs map[string]any
	SetOn  score.Date
}

// GetTargetBaseline returns the stored baseline of a target key, or ErrNotFound.
func GetTargetBaseline(ctx context.Context, q Querier, userID int64, key string) (TargetBaseline, error) {
	var b TargetBaseline
	var raw []byte
	err := q.QueryRow(ctx, `
		SELECT value, inputs, set_on::text FROM target_baselines WHERE user_id = $1 AND key = $2`,
		userID, key).Scan(&b.Value, &raw, &b.SetOn)
	if err != nil {
		return b, notFound(err)
	}
	return b, json.Unmarshal(raw, &b.Inputs)
}

// SetTargetBaseline stores the baseline of a target key.
func SetTargetBaseline(ctx context.Context, q Querier, userID int64, key string, value float64,
	inputs map[string]any, on score.Date) error {
	raw, err := json.Marshal(inputs)
	if err != nil {
		return err
	}
	_, err = q.Exec(ctx, `
		INSERT INTO target_baselines (user_id, key, value, inputs, set_on) VALUES ($1, $2, $3, $4, $5::date)
		ON CONFLICT (user_id, key) DO UPDATE SET value = EXCLUDED.value, inputs = EXCLUDED.inputs, set_on = EXCLUDED.set_on`,
		userID, key, value, raw, on)
	return err
}
