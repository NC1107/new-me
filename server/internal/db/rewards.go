package db

import (
	"context"
	"errors"
	"time"

	"github.com/jackc/pgx/v5"

	"github.com/nc1107/new-me/server/internal/score"
)

// Reward statuses. A reward is pending until the other person answers, approved while it waits
// on the wishlist, and claimed once its price was spent.
const (
	RewardPending   = "pending"
	RewardDeclined  = "declined"
	RewardApproved  = "approved"
	RewardClaimed   = "claimed"
	RewardCancelled = "cancelled"
)

var (
	// ErrRewardNotReady means the bank does not cover the price.
	ErrRewardNotReady = errors.New("the gem bank does not cover that reward")
	// ErrRewardState means the reward is not in a state the action applies to.
	ErrRewardState = errors.New("the reward is not in a state for that")
)

// Reward is one wishlist entry, priced in gems.
type Reward struct {
	ID     int64
	Name   string
	Price  int
	Status string
	Focus  bool
	Spent  int
	// ApprovedPrice and ApprovedFocus are the approved state a pending price change replaced;
	// ApprovedPrice is nil unless the reward is a pending change to an approved one.
	ApprovedPrice *int
	ApprovedFocus bool
	ProposedBy    *int64
	StartedAt     time.Time
	ReachedAt     *time.Time
	ClaimedAt     *time.Time
}

const rewardColumns = `id, name, target, status, is_focus, spent, approved_price, approved_focus, proposed_by, started_at, reached_at, claimed_at`

func scanReward(row interface{ Scan(...any) error }) (Reward, error) {
	var r Reward
	err := row.Scan(&r.ID, &r.Name, &r.Price, &r.Status, &r.Focus, &r.Spent, &r.ApprovedPrice, &r.ApprovedFocus, &r.ProposedBy,
		&r.StartedAt, &r.ReachedAt, &r.ClaimedAt)
	return r, err
}

func queryRewards(ctx context.Context, q Querier, sql string, args ...any) ([]Reward, error) {
	rows, err := q.Query(ctx, sql, args...)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := []Reward{}
	for rows.Next() {
		r, err := scanReward(rows)
		if err != nil {
			return nil, err
		}
		out = append(out, r)
	}
	return out, rows.Err()
}

// LockRewards serializes everything that changes the wishlist or spends gems for the rest of
// the transaction, so the single focus and the bank stay consistent between requests.
func LockRewards(ctx context.Context, tx pgx.Tx) error {
	_, err := tx.Exec(ctx, `SELECT pg_advisory_xact_lock(4915012028)`)
	return err
}

// InsertReward adds a reward with the given status. An approved one becomes the focus when
// there is none.
func InsertReward(ctx context.Context, tx pgx.Tx, name string, price int, by int64, status string) (Reward, error) {
	if err := LockRewards(ctx, tx); err != nil {
		return Reward{}, err
	}
	r, err := scanReward(tx.QueryRow(ctx, `
		INSERT INTO rewards (name, target, created_by, proposed_by, status)
		VALUES ($1, $2, $3, $3, $4) RETURNING `+rewardColumns, name, price, by, status))
	if err != nil {
		return Reward{}, err
	}
	if err := PromoteFocus(ctx, tx); err != nil {
		return Reward{}, err
	}
	return GetReward(ctx, tx, r.ID)
}

// PendingRewardByName finds a pending reward the person proposed under the same name, ignoring
// case, so a repeated create can be answered with it instead of adding a duplicate.
func PendingRewardByName(ctx context.Context, q Querier, by int64, name string) (Reward, error) {
	r, err := scanReward(q.QueryRow(ctx, `
		SELECT `+rewardColumns+` FROM rewards
		WHERE status = 'pending' AND proposed_by = $1 AND lower(name) = lower($2)
		ORDER BY id LIMIT 1`, by, name))
	return r, notFound(err)
}

// PromoteFocus fills an empty focus slot with the oldest approved reward.
func PromoteFocus(ctx context.Context, tx pgx.Tx) error {
	_, err := tx.Exec(ctx, `
		UPDATE rewards SET is_focus = true
		WHERE id = (SELECT id FROM rewards WHERE status = 'approved' ORDER BY id LIMIT 1)
		  AND NOT EXISTS (SELECT 1 FROM rewards WHERE is_focus)`)
	return err
}

// GetReward reads one reward.
func GetReward(ctx context.Context, q Querier, id int64) (Reward, error) {
	r, err := scanReward(q.QueryRow(ctx, `SELECT `+rewardColumns+` FROM rewards WHERE id = $1`, id))
	return r, notFound(err)
}

// FocusReward is the approved reward shown as the bar on Us.
func FocusReward(ctx context.Context, q Querier) (Reward, error) {
	r, err := scanReward(q.QueryRow(ctx, `SELECT `+rewardColumns+` FROM rewards WHERE is_focus`))
	return r, notFound(err)
}

// ListOpenRewards is the wishlist: pending, declined and approved, focus first.
func ListOpenRewards(ctx context.Context, q Querier) ([]Reward, error) {
	return queryRewards(ctx, q, `
		SELECT `+rewardColumns+` FROM rewards WHERE status IN ('pending', 'declined', 'approved')
		ORDER BY is_focus DESC, id`)
}

// ListClaimedRewards is the history, newest first.
func ListClaimedRewards(ctx context.Context, q Querier) ([]Reward, error) {
	return queryRewards(ctx, q, `
		SELECT `+rewardColumns+` FROM rewards WHERE status = 'claimed'
		ORDER BY claimed_at DESC, id DESC LIMIT 100`)
}

// CountOpenRewards is how many wishlist entries exist.
func CountOpenRewards(ctx context.Context, q Querier) (int, error) {
	var n int
	err := q.QueryRow(ctx, `SELECT count(*)::int FROM rewards WHERE status IN ('pending', 'declined', 'approved')`).Scan(&n)
	return n, err
}

// LockReward takes the wishlist lock and reads the reward under it.
func LockReward(ctx context.Context, tx pgx.Tx, id int64) (Reward, error) {
	if err := LockRewards(ctx, tx); err != nil {
		return Reward{}, err
	}
	return GetReward(ctx, tx, id)
}

// SaveReward writes the changeable fields of r. A reward that is no longer approved loses the
// focus and the slot is refilled (a focus is only kept or restored while the slot is free); a changed price clears the ready mark so it is announced
// again once the new price is covered.
func SaveReward(ctx context.Context, tx pgx.Tx, r Reward, priceChanged bool) (Reward, error) {
	focus := r.Focus && r.Status == RewardApproved
	if _, err := scanReward(tx.QueryRow(ctx, `
		UPDATE rewards SET name = $2, target = $3, status = $4, proposed_by = $5,
		    is_focus = $6 AND NOT EXISTS (SELECT 1 FROM rewards o WHERE o.is_focus AND o.id <> $1),
		    approved_price = $8, approved_focus = $9,
		    reached_at = CASE WHEN $7 THEN NULL ELSE reached_at END, updated_at = now()
		WHERE id = $1 RETURNING `+rewardColumns, r.ID, r.Name, r.Price, r.Status, r.ProposedBy, focus, priceChanged,
		r.ApprovedPrice, r.ApprovedFocus)); err != nil {
		return Reward{}, notFound(err)
	}
	if err := PromoteFocus(ctx, tx); err != nil {
		return Reward{}, err
	}
	return GetReward(ctx, tx, r.ID)
}

// DeleteReward removes a reward that was never approved. A pending price change to an approved
// reward is not one: it is reverted instead.
func DeleteReward(ctx context.Context, tx pgx.Tx, id int64) error {
	_, err := tx.Exec(ctx, `DELETE FROM rewards WHERE id = $1 AND approved_price IS NULL`, id)
	return err
}

// SetFocus makes an approved reward the focus.
func SetFocus(ctx context.Context, tx pgx.Tx, id int64) (Reward, error) {
	if _, err := tx.Exec(ctx, `UPDATE rewards SET is_focus = false WHERE is_focus AND id <> $1`, id); err != nil {
		return Reward{}, err
	}
	r, err := scanReward(tx.QueryRow(ctx, `
		UPDATE rewards SET is_focus = true, updated_at = now() WHERE id = $1 AND status = 'approved'
		RETURNING `+rewardColumns, id))
	return r, notFound(err)
}

// SpentGems is what claimed rewards have cost so far.
func SpentGems(ctx context.Context, q Querier) (int, error) {
	var n int
	err := q.QueryRow(ctx, `SELECT COALESCE(sum(spent), 0)::int FROM rewards WHERE status = 'claimed'`).Scan(&n)
	return n, err
}

// MarkRewardsReady stamps every approved reward the bank now covers and returns those this
// call stamped, so each is announced once.
func MarkRewardsReady(ctx context.Context, q Querier, bank int) ([]Reward, error) {
	return queryRewards(ctx, q, `
		UPDATE rewards SET reached_at = now()
		WHERE status = 'approved' AND reached_at IS NULL AND target <= $1
		RETURNING `+rewardColumns, bank)
}

// ClaimReward spends the price of an approved reward in one transaction. The wishlist lock
// serializes claims, so the bank is read and spent without another claim in between and can
// never go negative. A repeat of a finished claim returns it unchanged.
func ClaimReward(ctx context.Context, tx pgx.Tx, id int64) (Reward, error) {
	r, err := LockReward(ctx, tx, id)
	if err != nil {
		return Reward{}, err
	}
	if r.Status == RewardClaimed {
		return r, nil
	}
	if r.Status != RewardApproved {
		return Reward{}, ErrRewardState
	}
	total, err := TotalPoints(ctx, tx)
	if err != nil {
		return Reward{}, err
	}
	spent, err := SpentGems(ctx, tx)
	if err != nil {
		return Reward{}, err
	}
	if total-spent < r.Price {
		return Reward{}, ErrRewardNotReady
	}
	claimed, err := scanReward(tx.QueryRow(ctx, `
		UPDATE rewards SET status = 'claimed', is_focus = false, spent = target,
		    reached_at = COALESCE(reached_at, now()), claimed_at = now(), updated_at = now()
		WHERE id = $1 RETURNING `+rewardColumns, id))
	if err != nil {
		return Reward{}, err
	}
	return claimed, PromoteFocus(ctx, tx)
}

// DailyGems is the pair's combined gems for each local day from..to inclusive, oldest first.
// Days before anyone's first score are left out rather than counted as zero.
func DailyGems(ctx context.Context, q Querier, from, to score.Date) ([]int, error) {
	rows, err := q.Query(ctx, `
		WITH first AS (
		  SELECT min(s.local_date) AS d FROM day_scores s
		  JOIN users u ON u.id = s.user_id AND u.deleted_at IS NULL
		)
		SELECT COALESCE(sum(s.base_points + s.bonus_points), 0)::int
		FROM first, generate_series(GREATEST($1::date, first.d), $2::date, interval '1 day') AS g(day)
		LEFT JOIN (day_scores s JOIN users u ON u.id = s.user_id AND u.deleted_at IS NULL)
		  ON s.local_date = g.day::date
		GROUP BY g.day ORDER BY g.day`, from, to)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := []int{}
	for rows.Next() {
		var n int
		if err := rows.Scan(&n); err != nil {
			return nil, err
		}
		out = append(out, n)
	}
	return out, rows.Err()
}
