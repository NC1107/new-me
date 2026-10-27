package db

import (
	"context"
	"time"

	"github.com/nc1107/new-me/server/internal/score"
)

// SleepNight is one night of sleep, keyed by the morning it ends.
type SleepNight struct {
	Date      score.Date
	BedAt     time.Time
	WakeAt    time.Time
	AsleepMin int
	DeepMin   int
	REMMin    int
	CoreMin   int
	AwakeMin  int
	Source    string
}

// UpsertSleepNight stores a night, replacing an earlier copy of the same morning.
func UpsertSleepNight(ctx context.Context, q Querier, userID int64, n SleepNight) error {
	_, err := q.Exec(ctx, `
		INSERT INTO sleep_nights (user_id, local_date, bed_at, wake_at, asleep_min, deep_min,
		                          rem_min, core_min, awake_min, source)
		VALUES ($1, $2::date, $3, $4, $5, $6, $7, $8, $9, $10)
		ON CONFLICT (user_id, local_date) DO UPDATE
		SET bed_at = EXCLUDED.bed_at, wake_at = EXCLUDED.wake_at, asleep_min = EXCLUDED.asleep_min,
		    deep_min = EXCLUDED.deep_min, rem_min = EXCLUDED.rem_min, core_min = EXCLUDED.core_min,
		    awake_min = EXCLUDED.awake_min, source = EXCLUDED.source, updated_at = now()`,
		userID, n.Date, n.BedAt, n.WakeAt, n.AsleepMin, n.DeepMin, n.REMMin, n.CoreMin, n.AwakeMin, n.Source)
	return err
}

// ListSleepNights returns the nights ending on dates from..to inclusive, oldest first.
func ListSleepNights(ctx context.Context, q Querier, userID int64, from, to score.Date) ([]SleepNight, error) {
	rows, err := q.Query(ctx, `
		SELECT to_char(local_date, 'YYYY-MM-DD'), bed_at, wake_at, asleep_min, deep_min, rem_min,
		       core_min, awake_min, source
		FROM sleep_nights
		WHERE user_id = $1 AND local_date BETWEEN $2::date AND $3::date
		ORDER BY local_date`, userID, from, to)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := []SleepNight{}
	for rows.Next() {
		var n SleepNight
		if err := rows.Scan(&n.Date, &n.BedAt, &n.WakeAt, &n.AsleepMin, &n.DeepMin, &n.REMMin,
			&n.CoreMin, &n.AwakeMin, &n.Source); err != nil {
			return nil, err
		}
		out = append(out, n)
	}
	return out, rows.Err()
}
