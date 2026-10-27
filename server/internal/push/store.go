package push

import (
	"context"

	"github.com/nc1107/new-me/server/internal/db"
)

// DBStore keeps device tokens in the push_tokens table.
type DBStore struct{ DB *db.DB }

// Tokens lists the person's registered device tokens.
func (s DBStore) Tokens(ctx context.Context, userID int64) ([]string, error) {
	return db.PushTokens(ctx, s.DB.Pool, userID)
}

// Remove forgets a token Apple rejected.
func (s DBStore) Remove(ctx context.Context, token string) error {
	return db.DeletePushTokenValue(ctx, s.DB.Pool, token)
}
