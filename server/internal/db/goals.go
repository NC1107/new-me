package db

import (
	"context"

	"github.com/nc1107/new-me/server/internal/score"
)

// Goal proposal states.
const (
	ProposalPending   = "pending"
	ProposalAccepted  = "accepted"
	ProposalDismissed = "dismissed"
)

// GoalProposal is one suggested target change for a week, frozen when first shown.
type GoalProposal struct {
	Key      string
	Current  int
	Proposed int
	Reason   string
	State    string
}

// ListGoalProposals returns the person's proposals of the week, in key order.
func ListGoalProposals(ctx context.Context, q Querier, userID int64, week score.Date) ([]GoalProposal, error) {
	rows, err := q.Query(ctx, `
		SELECT key, current, proposed, reason, state FROM goal_proposals
		WHERE user_id = $1 AND week_start = $2::date ORDER BY key`, userID, week)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var out []GoalProposal
	for rows.Next() {
		var p GoalProposal
		if err := rows.Scan(&p.Key, &p.Current, &p.Proposed, &p.Reason, &p.State); err != nil {
			return nil, err
		}
		out = append(out, p)
	}
	return out, rows.Err()
}

// SaveGoalProposal stores or refreshes a pending proposal. A decided one is never touched.
func SaveGoalProposal(ctx context.Context, q Querier, userID int64, week score.Date, p GoalProposal) error {
	_, err := q.Exec(ctx, `
		INSERT INTO goal_proposals (user_id, week_start, key, current, proposed, reason)
		VALUES ($1, $2::date, $3, $4, $5, $6)
		ON CONFLICT (user_id, week_start, key) DO UPDATE
		SET current = EXCLUDED.current, proposed = EXCLUDED.proposed, reason = EXCLUDED.reason
		WHERE goal_proposals.state = 'pending'`,
		userID, week, p.Key, p.Current, p.Proposed, p.Reason)
	return err
}

// DecideGoalProposal moves a pending proposal to accepted or dismissed and returns it. It
// reports ErrNotFound when there is no pending proposal, which makes a double tap harmless.
func DecideGoalProposal(ctx context.Context, q Querier, userID int64, week score.Date, key, state string) (GoalProposal, error) {
	var p GoalProposal
	err := q.QueryRow(ctx, `
		UPDATE goal_proposals SET state = $4, decided_at = now()
		WHERE user_id = $1 AND week_start = $2::date AND key = $3 AND state = 'pending'
		RETURNING key, current, proposed, reason, state`, userID, week, key, state).
		Scan(&p.Key, &p.Current, &p.Proposed, &p.Reason, &p.State)
	return p, notFound(err)
}
