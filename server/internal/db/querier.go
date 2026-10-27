package db

import (
	"context"
	"errors"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgconn"

	"github.com/nc1107/new-me/server/internal/score"
)

// Querier is the slice of pgx shared by the pool and a transaction, so every query function
// runs standalone or inside a caller's transaction unchanged.
type Querier interface {
	Exec(ctx context.Context, sql string, args ...any) (pgconn.CommandTag, error)
	Query(ctx context.Context, sql string, args ...any) (pgx.Rows, error)
	QueryRow(ctx context.Context, sql string, args ...any) pgx.Row
}

// ErrNotFound is returned when a row does not exist.
var ErrNotFound = errors.New("not found")

// WithTx runs fn in a transaction, committing when it returns nil and rolling back otherwise.
func (d *DB) WithTx(ctx context.Context, fn func(tx pgx.Tx) error) error {
	tx, err := d.Pool.Begin(ctx)
	if err != nil {
		return err
	}
	if err := fn(tx); err != nil {
		_ = tx.Rollback(context.Background())
		return err
	}
	return tx.Commit(ctx)
}

// notFound maps pgx's empty-result error onto ErrNotFound and passes anything else through.
func notFound(err error) error {
	if errors.Is(err, pgx.ErrNoRows) {
		return ErrNotFound
	}
	return err
}

// violatedConstraint names the constraint behind a unique or exclusion violation, or "".
func violatedConstraint(err error) string {
	var pgErr *pgconn.PgError
	if errors.As(err, &pgErr) && (pgErr.Code == "23505" || pgErr.Code == "23P01") {
		return pgErr.ConstraintName
	}
	return ""
}

// LockUserDay serializes every writer of one user's day for the rest of the transaction, so a
// health upsert and a log insert can never score from stale inputs. Locks are re-entrant
// within a transaction, so layered callers may each take it.
func LockUserDay(ctx context.Context, tx pgx.Tx, userID int64, date score.Date) error {
	_, err := tx.Exec(ctx,
		`SELECT pg_advisory_xact_lock($1::int4, ($2::date - DATE '2000-01-01'))`, userID, date)
	return err
}
