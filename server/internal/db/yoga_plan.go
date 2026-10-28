package db

import (
	"context"
	"time"

	"github.com/nc1107/new-me/server/internal/score"
)

// YogaPlan is a person's weekly yoga plan.
type YogaPlan struct {
	DaysPerWeek int
	FlowMinutes int
	// Weekdays are ISO weekdays, 1 is Monday, sorted.
	Weekdays []int
	// LevelSince is when the current flow length began.
	LevelSince score.Date
	UpdatedAt  time.Time
}

// GetYogaPlan returns the person's plan, or ErrNotFound.
func GetYogaPlan(ctx context.Context, q Querier, userID int64) (YogaPlan, error) {
	var (
		p        YogaPlan
		weekdays []int16
	)
	err := q.QueryRow(ctx, `SELECT days_per_week, flow_minutes, weekdays, level_since::text, updated_at
		FROM yoga_plans WHERE user_id = $1`, userID).Scan(&p.DaysPerWeek, &p.FlowMinutes, &weekdays, &p.LevelSince, &p.UpdatedAt)
	if err = notFound(err); err != nil {
		return p, err
	}
	for _, d := range weekdays {
		p.Weekdays = append(p.Weekdays, int(d))
	}
	return p, nil
}

// PutYogaPlan replaces the person's plan.
func PutYogaPlan(ctx context.Context, q Querier, userID int64, p YogaPlan) error {
	weekdays := make([]int16, 0, len(p.Weekdays))
	for _, d := range p.Weekdays {
		weekdays = append(weekdays, int16(d))
	}
	_, err := q.Exec(ctx, `
		INSERT INTO yoga_plans (user_id, days_per_week, flow_minutes, weekdays, level_since)
		VALUES ($1, $2, $3, $4, $5::date)
		ON CONFLICT (user_id) DO UPDATE SET days_per_week = EXCLUDED.days_per_week,
			flow_minutes = EXCLUDED.flow_minutes, weekdays = EXCLUDED.weekdays,
			level_since = EXCLUDED.level_since, updated_at = now()`,
		userID, p.DaysPerWeek, p.FlowMinutes, weekdays, p.LevelSince)
	return err
}
