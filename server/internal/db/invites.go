package db

import (
	"context"
	"errors"
	"strconv"
	"time"
)

// MaxInviteAttempts is how many wrong codes lock the outstanding invites.
const MaxInviteAttempts = 5

// ErrInviteInvalid covers an unknown, used, expired or locked invite alike, so a caller cannot
// tell which.
var ErrInviteInvalid = errors.New("invalid invite code")

// CreateInvite stores the hash of a fresh single-use code that expires after ttl.
// createdBy is nil for codes minted from the command line.
func CreateInvite(ctx context.Context, q Querier, codeHash string, createdBy *int64, ttl time.Duration) error {
	_, err := q.Exec(ctx, `
		INSERT INTO invites (code_hash, created_by, expires_at)
		VALUES ($1, $2, now() + make_interval(secs => $3))`,
		codeHash, createdBy, ttl.Seconds())
	return err
}

// liveInvite is the condition for a code that can still be redeemed.
var liveInvite = `used_at IS NULL AND expires_at > now() AND attempts < ` + strconv.Itoa(MaxInviteAttempts)

// CheckInvite reports whether the code could be redeemed right now, without spending it.
func CheckInvite(ctx context.Context, q Querier, codeHash string) error {
	var ok bool
	err := q.QueryRow(ctx,
		`SELECT EXISTS (SELECT 1 FROM invites WHERE code_hash = $1 AND `+liveInvite+`)`, codeHash).Scan(&ok)
	if err != nil {
		return err
	}
	if !ok {
		return ErrInviteInvalid
	}
	return nil
}

// ConsumeInvite spends a live code. Run it in the join transaction so a join that fails
// afterwards gives the code back.
func ConsumeInvite(ctx context.Context, q Querier, codeHash string) error {
	tag, err := q.Exec(ctx,
		`UPDATE invites SET used_at = now() WHERE code_hash = $1 AND `+liveInvite, codeHash)
	if err != nil {
		return err
	}
	if tag.RowsAffected() == 0 {
		return ErrInviteInvalid
	}
	return nil
}

// RecordInviteMiss charges a wrong code against every outstanding invite, since a wrong guess
// matches none of them. Call it on the pool, outside any transaction that is about to roll
// back, so the charge sticks.
func RecordInviteMiss(ctx context.Context, q Querier) error {
	_, err := q.Exec(ctx,
		`UPDATE invites SET attempts = attempts + 1 WHERE used_at IS NULL AND expires_at > now()`)
	return err
}
