package db

import (
	"context"

	"github.com/nc1107/new-me/server/internal/score"
)

// HistorySet is one logged set on a history day.
type HistorySet struct {
	Exercise string   `json:"exercise"`
	Name     string   `json:"name"`
	Reps     *int     `json:"reps"`
	Seconds  *int     `json:"seconds"`
	LoadKg   *float64 `json:"loadKg"`
}

// HistoryDay is what one day of the training calendar shows.
type HistoryDay struct {
	Date             score.Date
	SetCount         int
	Sets             []HistorySet
	SessionCompleted bool
	// YogaMinutes is logged yoga (mobility sessions log here too) plus yoga workouts from Health.
	YogaMinutes  int
	WorkoutTypes []string
}

// TrainingHistory returns the days between two dates on which the person did something
// training related, oldest first, from one aggregate query over sets, sessions, yoga logs and
// workouts.
func TrainingHistory(ctx context.Context, q Querier, userID int64, from, to score.Date) ([]HistoryDay, error) {
	rows, err := q.Query(ctx, `
		WITH sets AS (
			SELECT s.local_date AS d, count(*)::int AS n,
			       jsonb_agg(jsonb_build_object('exercise', e.key, 'name', e.name, 'reps', s.reps,
			                 'seconds', s.seconds, 'loadKg', s.load_kg::float8) ORDER BY s.logged_at, s.id) AS sets
			FROM exercise_sets s JOIN exercises e ON e.id = s.exercise_id
			WHERE s.user_id = $1 AND s.deleted_at IS NULL AND s.local_date BETWEEN $2::date AND $3::date
			GROUP BY s.local_date
		), sessions AS (
			SELECT local_date AS d FROM training_sessions
			WHERE user_id = $1 AND completed_at IS NOT NULL AND local_date BETWEEN $2::date AND $3::date
		), yoga AS (
			SELECT local_date AS d, sum(quantity)::int AS minutes FROM activity_logs
			WHERE user_id = $1 AND type = 'yoga_minutes' AND deleted_at IS NULL
			  AND local_date BETWEEN $2::date AND $3::date
			GROUP BY local_date
		), workouts_by_day AS (
			SELECT local_date AS d, array_agg(DISTINCT type ORDER BY type) AS types,
			       COALESCE(round(sum(duration_min) FILTER (WHERE type = 'yoga')), 0)::int AS yoga_minutes
			FROM workouts
			WHERE user_id = $1 AND local_date BETWEEN $2::date AND $3::date
			GROUP BY local_date
		), days AS (
			SELECT d FROM sets UNION SELECT d FROM sessions UNION SELECT d FROM yoga UNION SELECT d FROM workouts_by_day
		)
		SELECT days.d::text, COALESCE(sets.n, 0), COALESCE(sets.sets, '[]'::jsonb),
		       EXISTS (SELECT 1 FROM sessions WHERE sessions.d = days.d),
		       COALESCE(yoga.minutes, 0) + COALESCE(workouts_by_day.yoga_minutes, 0),
		       COALESCE(workouts_by_day.types, '{}')
		FROM days
		LEFT JOIN sets ON sets.d = days.d
		LEFT JOIN yoga ON yoga.d = days.d
		LEFT JOIN workouts_by_day ON workouts_by_day.d = days.d
		ORDER BY days.d`, userID, from, to)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var out []HistoryDay
	for rows.Next() {
		var day HistoryDay
		if err := rows.Scan(&day.Date, &day.SetCount, &day.Sets, &day.SessionCompleted, &day.YogaMinutes,
			&day.WorkoutTypes); err != nil {
			return nil, err
		}
		out = append(out, day)
	}
	return out, rows.Err()
}

// ListMaxTests returns the person's max tests of one exercise between two dates, oldest first.
func ListMaxTests(ctx context.Context, q Querier, userID, exerciseID int64, from, to score.Date) ([]MaxTest, error) {
	rows, err := q.Query(ctx, `
		SELECT exercise_id, local_date::text, reps, seconds FROM exercise_max_tests
		WHERE user_id = $1 AND exercise_id = $2 AND local_date BETWEEN $3::date AND $4::date
		ORDER BY local_date`, userID, exerciseID, from, to)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var out []MaxTest
	for rows.Next() {
		var t MaxTest
		if err := rows.Scan(&t.ExerciseID, &t.LocalDate, &t.Reps, &t.Seconds); err != nil {
			return nil, err
		}
		out = append(out, t)
	}
	return out, rows.Err()
}
