package db

import (
	"context"
	"time"
)

// lastSeenThrottle bounds how often an authenticated request writes devices.last_seen_at.
const lastSeenThrottle = 5 * time.Minute

// CreateDevice registers a paired install by the hash of its bearer token.
func CreateDevice(ctx context.Context, q Querier, userID int64, tokenHash, name string) (int64, error) {
	var id int64
	err := q.QueryRow(ctx,
		`INSERT INTO devices (user_id, token_hash, name) VALUES ($1, $2, $3) RETURNING id`,
		userID, tokenHash, name).Scan(&id)
	return id, err
}

// UserByTokenHash resolves a bearer token to its live user and device, refreshing last_seen_at
// at most once per throttle window in the same round trip.
func UserByTokenHash(ctx context.Context, q Querier, tokenHash string) (User, int64, error) {
	var deviceID int64
	u, err := scanUser(q.QueryRow(ctx, `
		WITH touched AS (
			UPDATE devices SET last_seen_at = now()
			WHERE token_hash = $1 AND last_seen_at < now() - make_interval(secs => $2)
		)
		SELECT d.id, `+userColumns+`
		FROM devices d JOIN users u ON u.id = d.user_id
		WHERE d.token_hash = $1 AND u.deleted_at IS NULL`, tokenHash, lastSeenThrottle.Seconds()), &deviceID)
	return u, deviceID, notFound(err)
}

// DeleteDevice removes one device, which signs that install out.
func DeleteDevice(ctx context.Context, q Querier, deviceID int64) error {
	tag, err := q.Exec(ctx, `DELETE FROM devices WHERE id = $1`, deviceID)
	if err != nil {
		return err
	}
	if tag.RowsAffected() == 0 {
		return ErrNotFound
	}
	return nil
}

// DeleteUserDevices signs out every install of the user. A re-pair uses it because a valid code
// proves control of the account, so whatever held it before is no longer trusted.
func DeleteUserDevices(ctx context.Context, q Querier, userID int64) error {
	_, err := q.Exec(ctx, `DELETE FROM devices WHERE user_id = $1`, userID)
	return err
}
