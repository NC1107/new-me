package db

import (
	"context"

	"github.com/nc1107/new-me/server/internal/score"
)

// FoodDay is one day's logged food.
type FoodDay struct {
	Meals    int
	Kcal     float64
	ProteinG float64
}

// DailyFood sums the person's meal logs per local day from..to inclusive; days without a
// calorie-bearing meal are left out.
func DailyFood(ctx context.Context, q Querier, userID int64, from, to score.Date) (map[score.Date]FoodDay, error) {
	rows, err := q.Query(ctx, `
		SELECT local_date::text, (count(*) FILTER (WHERE kcal > 0))::int,
		       COALESCE(sum(kcal), 0)::float8, COALESCE(sum(protein_g), 0)::float8
		FROM meal_logs
		WHERE user_id = $1 AND deleted_at IS NULL AND local_date BETWEEN $2::date AND $3::date
		GROUP BY local_date HAVING sum(kcal) > 0`, userID, from, to)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := map[score.Date]FoodDay{}
	for rows.Next() {
		var d score.Date
		var day FoodDay
		if err := rows.Scan(&d, &day.Meals, &day.Kcal, &day.ProteinG); err != nil {
			return nil, err
		}
		out[d] = day
	}
	return out, rows.Err()
}

// HabitMarkedDays counts, per habit, the distinct days from..to inclusive on which the person
// marked something: a slot for a check habit, a positive count for a count habit.
func HabitMarkedDays(ctx context.Context, q Querier, userID int64, from, to score.Date) (map[int64]int, error) {
	rows, err := q.Query(ctx, `
		SELECT m.habit_id, count(DISTINCT m.local_date)::int
		FROM habit_marks m JOIN habits h ON h.id = m.habit_id
		WHERE h.user_id = $1 AND h.deleted_at IS NULL AND m.local_date BETWEEN $2::date AND $3::date
		  AND (h.kind = 'check' OR m.count > 0)
		GROUP BY m.habit_id`, userID, from, to)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := map[int64]int{}
	for rows.Next() {
		var id int64
		var n int
		if err := rows.Scan(&id, &n); err != nil {
			return nil, err
		}
		out[id] = n
	}
	return out, rows.Err()
}
