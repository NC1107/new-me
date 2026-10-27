package db

import (
	"context"
	"time"

	"github.com/nc1107/new-me/server/internal/score"
)

// Workout is one Apple Health workout. The optional measurements are nil when Health had none.
type Workout struct {
	HealthID    string
	Type        string
	LocalDate   score.Date
	StartedAt   time.Time
	EndedAt     time.Time
	DurationMin float64
	Kcal        *float64
	DistanceM   *float64
	AvgHR       *float64
	Source      string
}

// UpsertWorkout stores a workout by its HealthKit id, replacing an earlier copy so a re-sent
// or edited sample never duplicates.
func UpsertWorkout(ctx context.Context, q Querier, userID int64, w Workout) error {
	_, err := q.Exec(ctx, `
		INSERT INTO workouts (user_id, health_id, type, local_date, started_at, ended_at,
		                      duration_min, kcal, distance_m, avg_hr, source)
		VALUES ($1, $2, $3, $4::date, $5, $6, $7, $8, $9, $10, $11)
		ON CONFLICT (user_id, health_id) DO UPDATE
		SET type = EXCLUDED.type, local_date = EXCLUDED.local_date, started_at = EXCLUDED.started_at,
		    ended_at = EXCLUDED.ended_at, duration_min = EXCLUDED.duration_min, kcal = EXCLUDED.kcal,
		    distance_m = EXCLUDED.distance_m, avg_hr = EXCLUDED.avg_hr, source = EXCLUDED.source,
		    updated_at = now()`,
		userID, w.HealthID, w.Type, w.LocalDate, w.StartedAt, w.EndedAt,
		w.DurationMin, w.Kcal, w.DistanceM, w.AvgHR, w.Source)
	return err
}

// ListWorkouts returns the user's workouts that fall on local dates from..to inclusive, newest
// first.
func ListWorkouts(ctx context.Context, q Querier, userID int64, from, to score.Date) ([]Workout, error) {
	rows, err := q.Query(ctx, `
		SELECT health_id, type, to_char(local_date, 'YYYY-MM-DD'), started_at, ended_at,
		       duration_min::float8, kcal::float8, distance_m::float8, avg_hr::float8, source
		FROM workouts
		WHERE user_id = $1 AND local_date BETWEEN $2::date AND $3::date
		ORDER BY started_at DESC, id DESC`, userID, from, to)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := []Workout{}
	for rows.Next() {
		var w Workout
		if err := rows.Scan(&w.HealthID, &w.Type, &w.LocalDate, &w.StartedAt, &w.EndedAt,
			&w.DurationMin, &w.Kcal, &w.DistanceM, &w.AvgHR, &w.Source); err != nil {
			return nil, err
		}
		out = append(out, w)
	}
	return out, rows.Err()
}

// CountWorkouts is how many workouts the user has on local dates from..to inclusive.
func CountWorkouts(ctx context.Context, q Querier, userID int64, from, to score.Date) (int, error) {
	var n int
	err := q.QueryRow(ctx, `
		SELECT count(*)::int FROM workouts
		WHERE user_id = $1 AND local_date BETWEEN $2::date AND $3::date`, userID, from, to).Scan(&n)
	return n, err
}

// WorkoutSpans lists the type and length of the workouts that fall on one local date.
func WorkoutSpans(ctx context.Context, q Querier, userID int64, date score.Date) ([]score.WorkoutSpan, error) {
	rows, err := q.Query(ctx, `
		SELECT type, duration_min::float8, avg_hr::float8 FROM workouts
		WHERE user_id = $1 AND local_date = $2::date ORDER BY started_at, id`, userID, date)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var out []score.WorkoutSpan
	for rows.Next() {
		var w score.WorkoutSpan
		if err := rows.Scan(&w.Type, &w.DurationMin, &w.AvgHR); err != nil {
			return nil, err
		}
		out = append(out, w)
	}
	return out, rows.Err()
}

// WorkoutDates returns the local dates the given workouts are currently stored on, so a
// workout that moves to another day can rescore the day it left.
func WorkoutDates(ctx context.Context, q Querier, userID int64, healthIDs []string) ([]score.Date, error) {
	rows, err := q.Query(ctx, `
		SELECT DISTINCT local_date::text FROM workouts WHERE user_id = $1 AND health_id = ANY($2)`,
		userID, healthIDs)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var out []score.Date
	for rows.Next() {
		var d score.Date
		if err := rows.Scan(&d); err != nil {
			return nil, err
		}
		out = append(out, d)
	}
	return out, rows.Err()
}
