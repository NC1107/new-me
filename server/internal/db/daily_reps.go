package db

import (
	"context"
	"slices"

	"github.com/nc1107/new-me/server/internal/score"
)

// DefaultRepsExercise is the exercise of the pushups quest until the person picks another, and
// of every row written before v18.
const DefaultRepsExercise = "push_up"

// RepsExercise is one bodyweight exercise the daily-reps quest can count.
type RepsExercise struct {
	Key string
	// Name is the plural the quest is titled with, Noun the same in running text, Singular the
	// name of one rep.
	Name     string
	Noun     string
	Singular string
	// Needs is the equipment tag the exercise cannot be done without, or empty.
	Needs string
	// Hint is one line on how to do it or when to pick it.
	Hint string
	// Counts lists the catalog exercises whose logged sets count toward the quest.
	Counts []string
}

// RepsExercises are the choices, easiest push-up variations first. Everything but the pull-up
// needs no equipment, and each push-up variation is a step on the way to the next.
var RepsExercises = []RepsExercise{
	{Key: "knee_push_up", Name: "Knee push-ups", Noun: "knee push-ups", Singular: "knee push-up",
		Hint: "A push-up from the knees. The easiest place to start."},
	{Key: "incline_push_up", Name: "Incline push-ups", Noun: "incline push-ups", Singular: "incline push-up",
		Hint: "Hands on a counter or sturdy table. The higher the surface, the easier."},
	{Key: "push_up", Name: "Push-ups", Noun: "push-ups", Singular: "push-up",
		Hint:   "On the floor, body in one line from head to heels.",
		Counts: []string{"incline_push_up", "push_up", "decline_push_up"}},
	{Key: "air_squat", Name: "Squats", Noun: "squats", Singular: "squat",
		Hint: "Feet shoulder width apart, sit back and down, then stand."},
	{Key: "lunge", Name: "Lunges", Noun: "lunges", Singular: "lunge",
		Hint: "Step forward and lower the back knee. Count each step."},
	{Key: "glute_bridge", Name: "Glute bridges", Noun: "glute bridges", Singular: "glute bridge",
		Hint: "On your back, knees bent, lift your hips. Gentle on the knees."},
	{Key: "crunch", Name: "Crunches", Noun: "crunches", Singular: "crunch",
		Hint: "On your back, curl your shoulders off the floor."},
	{Key: "pull_up", Name: "Pull-ups", Noun: "pull-ups", Singular: "pull-up", Needs: "pullup_bar",
		Hint: "Needs a pull-up bar. Chin over the bar from a full hang."},
}

// RepsExerciseByKey finds a daily-reps choice.
func RepsExerciseByKey(key string) (RepsExercise, bool) {
	i := slices.IndexFunc(RepsExercises, func(e RepsExercise) bool { return e.Key == key })
	if i < 0 {
		return RepsExercise{}, false
	}
	return RepsExercises[i], true
}

// RepsNoun words an amount of the exercise's reps: "1 squat", "30 push-ups". An unknown
// exercise reads as plain reps.
func RepsNoun(key string, n int) string {
	if key == "" {
		key = DefaultRepsExercise
	}
	e, ok := RepsExerciseByKey(key)
	switch {
	case !ok && n == 1:
		return "rep"
	case !ok:
		return "reps"
	case n == 1:
		return e.Singular
	}
	return e.Noun
}

// countedKeys are the catalog exercises whose logged sets count toward a daily-reps exercise.
func countedKeys(exercise string) []string {
	if e, ok := RepsExerciseByKey(exercise); ok && len(e.Counts) > 0 {
		return e.Counts
	}
	return []string{exercise}
}

// RepsExerciseOf is the exercise the pushups quest counts on a date: the day's snapshot, else
// the standing template, else push-ups.
func RepsExerciseOf(ctx context.Context, q Querier, userID int64, date score.Date) (string, error) {
	var exercise string
	err := q.QueryRow(ctx, `
		SELECT COALESCE(
			(SELECT exercise FROM day_quests WHERE user_id = $1 AND local_date = $2::date AND key = 'pushups'),
			(SELECT exercise FROM quest_templates WHERE user_id = $1 AND key = 'pushups'),
			$3)`, userID, date, DefaultRepsExercise).Scan(&exercise)
	return exercise, err
}

// RepsMax is a recorded max test of one exercise: one set to near failure.
type RepsMax struct {
	Date score.Date
	Reps int
}

// LatestRepsMax is the newest rep max test of the exercise, or ErrNotFound. Push-up maxes
// recorded through the v8 endpoint live in their own table and compete with the general one.
func LatestRepsMax(ctx context.Context, q Querier, userID int64, exercise string) (RepsMax, error) {
	var m RepsMax
	err := q.QueryRow(ctx, `
		SELECT local_date::text, reps FROM (
			SELECT t.local_date, t.reps, t.created_at FROM exercise_max_tests t
			JOIN exercises e ON e.id = t.exercise_id
			WHERE t.user_id = $1 AND e.key = $2 AND t.reps IS NOT NULL
			UNION ALL
			SELECT local_date, reps, created_at FROM pushup_max_tests WHERE user_id = $1 AND $2 = 'push_up'
		) m ORDER BY local_date DESC, created_at DESC LIMIT 1`, userID, exercise).Scan(&m.Date, &m.Reps)
	return m, notFound(err)
}

// RepsSets lists each day's logged sets of the exercise (one log entry is one set), oldest
// first, for the progression rule.
func RepsSets(ctx context.Context, q Querier, userID int64, exercise string, from, to score.Date) (map[score.Date][]int, error) {
	rows, err := q.Query(ctx, `
		SELECT local_date::text, quantity FROM activity_logs
		WHERE user_id = $1 AND type = 'pushups' AND exercise = $4 AND deleted_at IS NULL
		  AND local_date BETWEEN $2::date AND $3::date
		ORDER BY local_date, id`, userID, from, to, exercise)
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

// RepsSetReps is the reps of the day's live catalog sets that count toward the exercise, next
// to its activity logs.
func RepsSetReps(ctx context.Context, q Querier, userID int64, date score.Date, exercise string) (int, error) {
	var reps int
	err := q.QueryRow(ctx, `SELECT COALESCE(sum(s.reps), 0)::int
		FROM exercise_sets s JOIN exercises e ON e.id = s.exercise_id
		WHERE s.user_id = $1 AND s.local_date = $2::date AND s.deleted_at IS NULL AND e.key = ANY($3)`,
		userID, date, countedKeys(exercise)).Scan(&reps)
	return reps, err
}
