package db

import (
	"context"

	"github.com/nc1107/new-me/server/internal/score"
)

// DailySeries reads dated numbers for a person from a query that returns (date, value) rows.
func dailySeries(ctx context.Context, q Querier, sql string, args ...any) (map[score.Date]float64, error) {
	rows, err := q.Query(ctx, sql, args...)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := map[score.Date]float64{}
	for rows.Next() {
		var d score.Date
		var v float64
		if err := rows.Scan(&d, &v); err != nil {
			return nil, err
		}
		out[d] = v
	}
	return out, rows.Err()
}

// ReadingByDay is the logged reading minutes plus Audiobookshelf listening of each day.
func ReadingByDay(ctx context.Context, q Querier, userID int64, from, to score.Date) (map[score.Date]float64, error) {
	return dailySeries(ctx, q, `
		SELECT d::text, sum(v)::float8 FROM (
			SELECT local_date AS d, quantity AS v FROM activity_logs
			WHERE user_id = $1 AND type = 'reading_minutes' AND deleted_at IS NULL
			  AND local_date BETWEEN $2::date AND $3::date
			UNION ALL
			SELECT local_date, minutes FROM listening_daily
			WHERE user_id = $1 AND local_date BETWEEN $2::date AND $3::date
		) r GROUP BY d`, userID, from, to)
}

// PushupsByDay is the logged push-up reps of each day, from push-up logs and push-up sets.
func PushupsByDay(ctx context.Context, q Querier, userID int64, from, to score.Date) (map[score.Date]float64, error) {
	return dailySeries(ctx, q, `
		SELECT d, sum(n)::float8 FROM (
			SELECT local_date::text AS d, quantity AS n FROM activity_logs
			WHERE user_id = $1 AND type = 'pushups' AND exercise = 'push_up' AND deleted_at IS NULL
			  AND local_date BETWEEN $2::date AND $3::date
			UNION ALL
			SELECT s.local_date::text, s.reps FROM exercise_sets s JOIN exercises e ON e.id = s.exercise_id
			WHERE s.user_id = $1 AND s.deleted_at IS NULL AND s.reps IS NOT NULL
			  AND e.key IN ('incline_push_up', 'push_up', 'decline_push_up')
			  AND s.local_date BETWEEN $2::date AND $3::date
		) p GROUP BY d`, userID, from, to)
}

// ProteinByDay is the grams of protein of each day that has a meal.
func ProteinByDay(ctx context.Context, q Querier, userID int64, from, to score.Date) (map[score.Date]float64, error) {
	return dailySeries(ctx, q, `
		SELECT local_date::text, sum(protein_g)::float8 FROM meal_logs
		WHERE user_id = $1 AND deleted_at IS NULL AND local_date BETWEEN $2::date AND $3::date
		GROUP BY local_date`, userID, from, to)
}

// WorkoutsByDay is the number of workouts of each day.
func WorkoutsByDay(ctx context.Context, q Querier, userID int64, from, to score.Date) (map[score.Date]float64, error) {
	return dailySeries(ctx, q, `
		SELECT local_date::text, count(*)::float8 FROM workouts
		WHERE user_id = $1 AND local_date BETWEEN $2::date AND $3::date GROUP BY local_date`, userID, from, to)
}

// SleepByDay is the minutes asleep of each night, from the sleep records and, for a morning
// that has none, from the daily sleep total.
func SleepByDay(ctx context.Context, q Querier, userID int64, from, to score.Date) (map[score.Date]float64, error) {
	return dailySeries(ctx, q, `
		SELECT d::text, v::float8 FROM (
			SELECT DISTINCT ON (d) d, v FROM (
				SELECT local_date AS d, asleep_min AS v, 0 AS rank FROM sleep_nights
				WHERE user_id = $1 AND asleep_min > 0 AND local_date BETWEEN $2::date AND $3::date
				UNION ALL
				SELECT local_date, value, 1 FROM health_daily
				WHERE user_id = $1 AND metric = 'sleep_minutes' AND value > 0
				  AND local_date BETWEEN $2::date AND $3::date
			) s ORDER BY d, rank
		) best`, userID, from, to)
}

// HabitsKeptByDay is how many habit completions each day has: a done slot of a check habit, or a
// count habit at its target.
func HabitsKeptByDay(ctx context.Context, q Querier, userID int64, from, to score.Date) (map[score.Date]float64, error) {
	return dailySeries(ctx, q, `
		SELECT m.local_date::text,
		       (count(*) FILTER (WHERE h.kind = 'check')
		        + count(*) FILTER (WHERE h.kind = 'count' AND m.count >= h.target))::float8
		FROM habit_marks m JOIN habits h ON h.id = m.habit_id
		WHERE h.user_id = $1 AND h.deleted_at IS NULL AND m.local_date BETWEEN $2::date AND $3::date
		GROUP BY m.local_date`, userID, from, to)
}

// ProteinDay is a day's protein target snapshot and the grams eaten.
type ProteinDay struct {
	Date    score.Date
	TargetG int
	Grams   float64
}

// ProteinDays lists the days from..to that have a protein quest, with what was eaten.
func ProteinDays(ctx context.Context, q Querier, userID int64, from, to score.Date) ([]ProteinDay, error) {
	rows, err := q.Query(ctx, `
		SELECT d.local_date::text, d.target,
		       COALESCE((SELECT sum(m.protein_g)::float8 FROM meal_logs m
		                 WHERE m.user_id = d.user_id AND m.local_date = d.local_date AND m.deleted_at IS NULL), 0)
		FROM day_quests d
		WHERE d.user_id = $1 AND d.key = 'protein' AND d.local_date BETWEEN $2::date AND $3::date
		ORDER BY d.local_date`, userID, from, to)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var out []ProteinDay
	for rows.Next() {
		var p ProteinDay
		if err := rows.Scan(&p.Date, &p.TargetG, &p.Grams); err != nil {
			return nil, err
		}
		out = append(out, p)
	}
	return out, rows.Err()
}

// CountedDaysIn is how many days of from..to the person's day counted.
func CountedDaysIn(ctx context.Context, q Querier, userID int64, from, to score.Date) (int, error) {
	var n int
	err := q.QueryRow(ctx, `
		SELECT count(*)::int FROM day_scores
		WHERE user_id = $1 AND counted AND local_date BETWEEN $2::date AND $3::date`, userID, from, to).Scan(&n)
	return n, err
}
