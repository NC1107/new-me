package db

import (
	"context"
	"time"
)

// HeldPush is a push waiting for its recipient's next allowed time.
type HeldPush struct {
	ID           int64
	UserID       int64
	Kind         string
	Title, Body  string
	CreatedAt    time.Time
	DeliverAfter time.Time
}

// InsertHeldPush stores a push to be delivered at or after DeliverAfter.
func InsertHeldPush(ctx context.Context, q Querier, h HeldPush) error {
	_, err := q.Exec(ctx, `
		INSERT INTO held_pushes (user_id, kind, title, body, created_at, deliver_after)
		VALUES ($1, $2, $3, $4, $5, $6)`, h.UserID, h.Kind, h.Title, h.Body, h.CreatedAt, h.DeliverAfter)
	return err
}

// ExpireHeldPushes removes undelivered pushes created before the cutoff and delivered ones
// stamped before it, so the table stays small.
func ExpireHeldPushes(ctx context.Context, q Querier, cutoff time.Time) error {
	_, err := q.Exec(ctx, `
		DELETE FROM held_pushes
		WHERE (delivered_at IS NULL AND created_at < $1) OR delivered_at < $1`, cutoff)
	return err
}

// DueHeldPushes lists the undelivered pushes whose time has come, oldest first.
func DueHeldPushes(ctx context.Context, q Querier, now time.Time) ([]HeldPush, error) {
	rows, err := q.Query(ctx, `
		SELECT id, user_id, kind, title, body, created_at, deliver_after
		FROM held_pushes WHERE delivered_at IS NULL AND deliver_after <= $1 ORDER BY created_at, id`, now)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var out []HeldPush
	for rows.Next() {
		var h HeldPush
		if err := rows.Scan(&h.ID, &h.UserID, &h.Kind, &h.Title, &h.Body, &h.CreatedAt, &h.DeliverAfter); err != nil {
			return nil, err
		}
		out = append(out, h)
	}
	return out, rows.Err()
}

// MarkHeldDelivered stamps the pushes as delivered.
func MarkHeldDelivered(ctx context.Context, q Querier, ids []int64, at time.Time) error {
	_, err := q.Exec(ctx, `UPDATE held_pushes SET delivered_at = $2 WHERE id = ANY($1)`, ids, at)
	return err
}

// DeleteHeldPushes drops the pushes without delivering them.
func DeleteHeldPushes(ctx context.Context, q Querier, ids []int64) error {
	_, err := q.Exec(ctx, `DELETE FROM held_pushes WHERE id = ANY($1)`, ids)
	return err
}

// DeferHeldPushes moves the pushes to a later delivery time.
func DeferHeldPushes(ctx context.Context, q Querier, ids []int64, after time.Time) error {
	_, err := q.Exec(ctx, `UPDATE held_pushes SET deliver_after = $2 WHERE id = ANY($1)`, ids, after)
	return err
}
