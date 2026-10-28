package db

import (
	"context"

	"github.com/nc1107/new-me/server/internal/score"
)

// PlanPolish is the cached Claude wording of a day's plan. Text is nil while the day's single
// call is in flight or after it failed.
type PlanPolish struct {
	FactsKey string
	Text     *string
}

// ClaimPlanPolish reserves the day's one Claude call. It is true only for the caller that
// created the row, which is the one that should make the call.
func ClaimPlanPolish(ctx context.Context, q Querier, userID int64, date score.Date, factsKey string) (bool, error) {
	tag, err := q.Exec(ctx, `
		INSERT INTO plan_polish (user_id, local_date, facts_key) VALUES ($1, $2::date, $3)
		ON CONFLICT DO NOTHING`, userID, date, factsKey)
	return tag.RowsAffected() == 1, err
}

// SavePlanPolish stores the wording the claimed call produced.
func SavePlanPolish(ctx context.Context, q Querier, userID int64, date score.Date, text string) error {
	_, err := q.Exec(ctx, `UPDATE plan_polish SET text = $3 WHERE user_id = $1 AND local_date = $2::date`,
		userID, date, text)
	return err
}

// ReleasePlanPolish gives the day's claim back when the call produced nothing, so a later pass
// may try again. A row that already holds wording is left alone.
func ReleasePlanPolish(ctx context.Context, q Querier, userID int64, date score.Date, factsKey string) error {
	_, err := q.Exec(ctx, `DELETE FROM plan_polish
		WHERE user_id = $1 AND local_date = $2::date AND facts_key = $3 AND text IS NULL`,
		userID, date, factsKey)
	return err
}

// GetPlanPolish reads the day's row, or ErrNotFound when no call was ever claimed.
func GetPlanPolish(ctx context.Context, q Querier, userID int64, date score.Date) (PlanPolish, error) {
	var p PlanPolish
	err := q.QueryRow(ctx, `SELECT facts_key, text FROM plan_polish WHERE user_id = $1 AND local_date = $2::date`,
		userID, date).Scan(&p.FactsKey, &p.Text)
	return p, notFound(err)
}
