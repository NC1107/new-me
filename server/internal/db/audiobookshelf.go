package db

import (
	"context"
	"time"

	"github.com/nc1107/new-me/server/internal/score"
)

// Last-error codes stored on a linked account and reported to the app.
const (
	ABSErrorAuth        = "auth_failed"
	ABSErrorUnreachable = "unreachable"
)

// ABSAccount is a user's linked Audiobookshelf sign-in. It holds tokens, never the password.
type ABSAccount struct {
	UserID          int64
	ABSUserID       string
	Username        string
	AccessToken     string
	RefreshToken    string
	AccessExpiresAt time.Time
	LinkedAt        time.Time
	SyncedAt        *time.Time
	LastError       *string
}

const absColumns = `user_id, abs_user_id, username, access_token, refresh_token, access_expires_at,
	linked_at, synced_at, last_error`

func scanABS(row interface{ Scan(...any) error }) (ABSAccount, error) {
	var a ABSAccount
	err := row.Scan(&a.UserID, &a.ABSUserID, &a.Username, &a.AccessToken, &a.RefreshToken,
		&a.AccessExpiresAt, &a.LinkedAt, &a.SyncedAt, &a.LastError)
	return a, err
}

// LinkABSAccount stores a fresh sign-in, replacing any earlier link and clearing its error and
// last sync so the new link starts clean.
func LinkABSAccount(ctx context.Context, q Querier, a ABSAccount) (ABSAccount, error) {
	return scanABS(q.QueryRow(ctx, `
		INSERT INTO audiobookshelf_accounts (user_id, abs_user_id, username, access_token, refresh_token,
			access_expires_at)
		VALUES ($1, $2, $3, $4, $5, $6)
		ON CONFLICT (user_id) DO UPDATE
		SET abs_user_id = EXCLUDED.abs_user_id, username = EXCLUDED.username,
		    access_token = EXCLUDED.access_token, refresh_token = EXCLUDED.refresh_token,
		    access_expires_at = EXCLUDED.access_expires_at, linked_at = now(),
		    synced_at = NULL, last_error = NULL
		RETURNING `+absColumns,
		a.UserID, a.ABSUserID, a.Username, a.AccessToken, a.RefreshToken, a.AccessExpiresAt))
}

// GetABSAccount reads a user's link, or ErrNotFound when there is none.
func GetABSAccount(ctx context.Context, q Querier, userID int64) (ABSAccount, error) {
	a, err := scanABS(q.QueryRow(ctx,
		`SELECT `+absColumns+` FROM audiobookshelf_accounts WHERE user_id = $1`, userID))
	return a, notFound(err)
}

// ListABSAccounts reads every link of a live user.
func ListABSAccounts(ctx context.Context, q Querier) ([]ABSAccount, error) {
	rows, err := q.Query(ctx, `
		SELECT `+absColumns+` FROM audiobookshelf_accounts a
		WHERE EXISTS (SELECT 1 FROM users u WHERE u.id = a.user_id AND u.deleted_at IS NULL)
		ORDER BY user_id`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var out []ABSAccount
	for rows.Next() {
		a, err := scanABS(rows)
		if err != nil {
			return nil, err
		}
		out = append(out, a)
	}
	return out, rows.Err()
}

// DeleteABSAccount unlinks the user and reports whether there was a link. Stored minutes stay,
// because finalized days must keep scoring from what they were scored with.
func DeleteABSAccount(ctx context.Context, q Querier, userID int64) (bool, error) {
	tag, err := q.Exec(ctx, `DELETE FROM audiobookshelf_accounts WHERE user_id = $1`, userID)
	return tag.RowsAffected() > 0, err
}

// DeleteListening drops one day's stored minutes.
func DeleteListening(ctx context.Context, q Querier, userID int64, date score.Date) error {
	_, err := q.Exec(ctx, `DELETE FROM listening_daily WHERE user_id = $1 AND local_date = $2::date`, userID, date)
	return err
}

// SaveABSTokens stores a refreshed session. The rotated refresh token must be saved before the
// new access token is used, or a crash would strand the link.
func SaveABSTokens(ctx context.Context, q Querier, userID int64, access, refresh string, expires time.Time) error {
	_, err := q.Exec(ctx, `
		UPDATE audiobookshelf_accounts SET access_token = $2, refresh_token = $3, access_expires_at = $4
		WHERE user_id = $1`, userID, access, refresh, expires)
	return err
}

// MarkABSSynced records a poll that worked.
func MarkABSSynced(ctx context.Context, q Querier, userID int64, at time.Time) error {
	_, err := q.Exec(ctx,
		`UPDATE audiobookshelf_accounts SET synced_at = $2, last_error = NULL WHERE user_id = $1`, userID, at)
	return err
}

// MarkABSError records a poll that failed, keeping the link and the last good sync time.
func MarkABSError(ctx context.Context, q Querier, userID int64, code string) error {
	_, err := q.Exec(ctx, `UPDATE audiobookshelf_accounts SET last_error = $2 WHERE user_id = $1`, userID, code)
	return err
}

// UpsertListening stores a day's listening minutes.
func UpsertListening(ctx context.Context, q Querier, userID int64, date score.Date, minutes int, at time.Time) error {
	_, err := q.Exec(ctx, `
		INSERT INTO listening_daily (user_id, local_date, minutes, synced_at)
		VALUES ($1, $2::date, $3, $4)
		ON CONFLICT (user_id, local_date) DO UPDATE SET minutes = EXCLUDED.minutes, synced_at = EXCLUDED.synced_at`,
		userID, date, minutes, at)
	return err
}

// ListeningMinutes is the day's stored listening minutes, 0 when there are none.
func ListeningMinutes(ctx context.Context, q Querier, userID int64, date score.Date) (int, error) {
	var minutes int
	err := q.QueryRow(ctx, `
		SELECT COALESCE(max(minutes), 0) FROM listening_daily WHERE user_id = $1 AND local_date = $2::date`,
		userID, date).Scan(&minutes)
	return minutes, err
}
