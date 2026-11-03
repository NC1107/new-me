package db

import (
	"context"
	"errors"
	"time"

	"github.com/jackc/pgx/v5"

	"github.com/nc1107/new-me/server/internal/gems"
)

// PersonGem is one live person's gems.
type PersonGem struct {
	UserID int64
	Name   string
	gems.Person
}

// PersonGems lists every live person's gems, by user id.
type PersonGems []PersonGem

// Gems is the arithmetic view of the list, in the same order.
func (p PersonGems) Gems() []gems.Person {
	out := make([]gems.Person, len(p))
	for i, g := range p {
		out[i] = g.Person
	}
	return out
}

// Find returns the person with the given id.
func (p PersonGems) Find(userID int64) (PersonGem, bool) {
	for _, g := range p {
		if g.UserID == userID {
			return g, true
		}
	}
	return PersonGem{}, false
}

// ReadPersonGems reads each live person's earned and paid gems: paid is their treat redemptions
// plus their payments toward claimed shared rewards. Tasks is the net of their settled tasks.
func ReadPersonGems(ctx context.Context, q Querier) (PersonGems, error) {
	rows, err := q.Query(ctx, `
		SELECT u.id, u.name,
		       COALESCE((SELECT sum(s.base_points + s.bonus_points) FROM day_scores s WHERE s.user_id = u.id), 0)::int,
		       (COALESCE((SELECT sum(p.amount) FROM reward_payments p WHERE p.user_id = u.id), 0)
		      + COALESCE((SELECT sum(t.price) FROM treat_redemptions t WHERE t.user_id = u.id), 0))::int,
		       COALESCE((SELECT sum(CASE k.status WHEN 'done' THEN k.stake ELSE -k.lost END) FROM tasks k
		                 WHERE k.assignee_id = u.id AND k.status IN ('done', 'missed')), 0)::int
		FROM users u WHERE u.deleted_at IS NULL ORDER BY u.id`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := PersonGems{}
	for rows.Next() {
		var g PersonGem
		if err := rows.Scan(&g.UserID, &g.Name, &g.Earned, &g.Paid, &g.Tasks); err != nil {
			return nil, err
		}
		out = append(out, g)
	}
	return out, rows.Err()
}

// ListTreats is every open treat of both people: pending, declined and approved.
func ListTreats(ctx context.Context, q Querier) ([]Reward, error) {
	return queryRewards(ctx, q, `
		SELECT `+rewardColumns+` FROM rewards
		WHERE status IN ('pending', 'declined', 'approved') AND owner_id IS NOT NULL
		ORDER BY owner_id, id`)
}

// CountOpenTreats is how many open treats the person owns.
func CountOpenTreats(ctx context.Context, q Querier, owner int64) (int, error) {
	var n int
	err := q.QueryRow(ctx, `SELECT count(*)::int FROM rewards
		WHERE status IN ('pending', 'declined', 'approved') AND owner_id = $1`, owner).Scan(&n)
	return n, err
}

// Redemption is one treat bought with its owner's gems.
type Redemption struct {
	ID        int64
	TreatID   *int64
	UserID    int64
	Name      string
	Price     int
	CreatedAt time.Time
}

const redemptionColumns = `id, treat_id, user_id, name, price, created_at`

func scanRedemption(row interface{ Scan(...any) error }) (Redemption, error) {
	var r Redemption
	err := row.Scan(&r.ID, &r.TreatID, &r.UserID, &r.Name, &r.Price, &r.CreatedAt)
	return r, err
}

// ListRedemptions is the treat history of both people, newest first.
func ListRedemptions(ctx context.Context, q Querier) ([]Redemption, error) {
	rows, err := q.Query(ctx, `SELECT `+redemptionColumns+` FROM treat_redemptions
		ORDER BY created_at DESC, id DESC LIMIT 100`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := []Redemption{}
	for rows.Next() {
		r, err := scanRedemption(rows)
		if err != nil {
			return nil, err
		}
		out = append(out, r)
	}
	return out, rows.Err()
}

// RedeemTreat spends the treat's price from its owner's own balance. The wishlist lock serializes
// it with every other spend, so a balance is read and spent with nothing in between. A repeat of
// a request id returns the redemption it already made (created is false) and spends nothing.
func RedeemTreat(ctx context.Context, tx pgx.Tx, userID, treatID int64, requestID string) (red Redemption, created bool, err error) {
	if err := LockRewards(ctx, tx); err != nil {
		return Redemption{}, false, err
	}
	existing, err := scanRedemption(tx.QueryRow(ctx, `SELECT `+redemptionColumns+` FROM treat_redemptions
		WHERE user_id = $1 AND request_id = $2`, userID, requestID))
	if err == nil {
		return existing, false, nil
	}
	if !errors.Is(err, pgx.ErrNoRows) {
		return Redemption{}, false, err
	}
	treat, err := GetReward(ctx, tx, treatID)
	if err != nil {
		return Redemption{}, false, err
	}
	if treat.OwnerID == nil {
		return Redemption{}, false, ErrRewardState
	}
	if *treat.OwnerID != userID {
		return Redemption{}, false, ErrNotTreatOwner
	}
	if treat.Status != RewardApproved {
		return Redemption{}, false, ErrRewardState
	}
	people, err := ReadPersonGems(ctx, tx)
	if err != nil {
		return Redemption{}, false, err
	}
	me, ok := people.Find(userID)
	if !ok || !gems.TreatReady(me.Balance(), treat.Price) {
		return Redemption{}, false, ErrInsufficientGems
	}
	red, err = scanRedemption(tx.QueryRow(ctx, `
		INSERT INTO treat_redemptions (treat_id, user_id, name, price, request_id)
		VALUES ($1, $2, $3, $4, $5) RETURNING `+redemptionColumns, treatID, userID, treat.Name, treat.Price, requestID))
	return red, err == nil, err
}
