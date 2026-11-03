package db

import (
	"context"
	"encoding/json"
	"errors"
	"time"

	"github.com/jackc/pgx/v5"
)

// CoachFact is one short thing a person told the coach about themselves.
type CoachFact struct {
	ID        int64
	Category  string
	Text      string
	CreatedAt time.Time
}

// CoachFactCategories are the kinds of fact the coach can keep.
var CoachFactCategories = []string{"injury", "schedule", "preference", "equipment", "diet", "other"}

// MaxCoachFacts bounds what the coach keeps per person, which also bounds the system prompt.
const MaxCoachFacts = 40

// ErrCoachFactsFull means the person is at MaxCoachFacts.
var ErrCoachFactsFull = errors.New("coach facts are full")

// ListCoachFacts returns the person's facts, oldest first.
func ListCoachFacts(ctx context.Context, q Querier, userID int64) ([]CoachFact, error) {
	rows, err := q.Query(ctx, `
		SELECT id, category, text, created_at FROM coach_facts WHERE user_id = $1 ORDER BY id`, userID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var out []CoachFact
	for rows.Next() {
		var f CoachFact
		if err := rows.Scan(&f.ID, &f.Category, &f.Text, &f.CreatedAt); err != nil {
			return nil, err
		}
		out = append(out, f)
	}
	return out, rows.Err()
}

// AddCoachFact stores a fact. Saying the same thing twice returns the existing fact, and a
// person at the cap gets ErrCoachFactsFull.
func AddCoachFact(ctx context.Context, q Querier, userID int64, category, text string) (CoachFact, error) {
	var f CoachFact
	err := q.QueryRow(ctx, `
		SELECT id, category, text, created_at FROM coach_facts
		WHERE user_id = $1 AND lower(text) = lower($2)`, userID, text).
		Scan(&f.ID, &f.Category, &f.Text, &f.CreatedAt)
	if err == nil {
		return f, nil
	}
	if !errors.Is(err, pgx.ErrNoRows) {
		return f, err
	}
	err = q.QueryRow(ctx, `
		INSERT INTO coach_facts (user_id, category, text)
		SELECT $1, $2, $3 WHERE (SELECT count(*) FROM coach_facts WHERE user_id = $1) < $4
		RETURNING id, category, text, created_at`, userID, category, text, MaxCoachFacts).
		Scan(&f.ID, &f.Category, &f.Text, &f.CreatedAt)
	if errors.Is(err, pgx.ErrNoRows) {
		return f, ErrCoachFactsFull
	}
	return f, err
}

// DeleteCoachFact removes one of the person's own facts.
func DeleteCoachFact(ctx context.Context, q Querier, userID, id int64) error {
	tag, err := q.Exec(ctx, `DELETE FROM coach_facts WHERE id = $1 AND user_id = $2`, id, userID)
	if err != nil {
		return err
	}
	if tag.RowsAffected() == 0 {
		return ErrNotFound
	}
	return nil
}

// Coach proposal statuses.
const (
	ProposalPendingStatus   = "pending"
	ProposalAppliedStatus   = "applied"
	ProposalDismissedStatus = "dismissed"
	ProposalUndoneStatus    = "undone"
)

// CoachProposal is a change the coach proposed, stored until the person decides.
type CoachProposal struct {
	ID        int64
	UserID    int64
	Kind      string
	Summary   string
	Reason    string
	After     json.RawMessage
	Before    json.RawMessage
	Status    string
	CreatedAt time.Time
	ExpiresAt time.Time
	DecidedAt *time.Time
}

const proposalColumns = `id, user_id, kind, summary, reason, after_state, before_state, status, created_at, expires_at, decided_at`

func scanProposal(row pgx.Row) (CoachProposal, error) {
	var p CoachProposal
	err := row.Scan(&p.ID, &p.UserID, &p.Kind, &p.Summary, &p.Reason, &p.After, &p.Before, &p.Status,
		&p.CreatedAt, &p.ExpiresAt, &p.DecidedAt)
	if errors.Is(err, pgx.ErrNoRows) {
		return p, ErrNotFound
	}
	return p, err
}

// CreateCoachProposal stores a pending proposal.
func CreateCoachProposal(ctx context.Context, q Querier, p CoachProposal) (CoachProposal, error) {
	return scanProposal(q.QueryRow(ctx, `
		INSERT INTO coach_proposals (user_id, kind, summary, reason, after_state, expires_at)
		VALUES ($1, $2, $3, $4, $5, $6) RETURNING `+proposalColumns,
		p.UserID, p.Kind, p.Summary, p.Reason, p.After, p.ExpiresAt))
}

// GetCoachProposal loads one of the person's proposals; another person's id is ErrNotFound.
func GetCoachProposal(ctx context.Context, q Querier, userID, id int64) (CoachProposal, error) {
	return scanProposal(q.QueryRow(ctx, `SELECT `+proposalColumns+` FROM coach_proposals WHERE id = $1 AND user_id = $2`, id, userID))
}

// MoveCoachProposal changes the status of a proposal that is in from, storing before (when
// given) for undo. It reports false when the proposal was not in from, which is how two taps on
// the same card are told apart: only one of them wins.
func MoveCoachProposal(ctx context.Context, q Querier, userID, id int64, from, to string, before json.RawMessage, at time.Time) (bool, error) {
	tag, err := q.Exec(ctx, `
		UPDATE coach_proposals SET status = $4, before_state = COALESCE($5, before_state), decided_at = $6
		WHERE id = $1 AND user_id = $2 AND status = $3`, id, userID, from, to, before, at)
	return tag.RowsAffected() == 1, err
}
