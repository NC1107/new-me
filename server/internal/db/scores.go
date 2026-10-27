package db

import (
	"context"
	"time"

	"github.com/jackc/pgx/v5"

	"github.com/nc1107/new-me/server/internal/score"
)

// DayScoreRow is the stored outcome of one user-day. Detail is the per-quest JSON.
type DayScoreRow struct {
	UserID      int64
	LocalDate   score.Date
	BasePoints  int
	BonusPoints int
	MaxBase     int
	Percent     int
	Counted     bool
	Detail      []byte
	FinalizedAt *time.Time
	ComputedAt  time.Time
	// FrozenReason, Away and Settled are the streak outcome recorded when the day finalized.
	FrozenReason string
	Away         bool
	Settled      bool
}

// Points is what the Board adds up: base plus bonus.
func (r DayScoreRow) Points() int { return r.BasePoints + r.BonusPoints }

const dayScoreColumns = `user_id, local_date::text, base_points, bonus_points, max_base, percent,
	counted, detail, finalized_at, computed_at, COALESCE(frozen_reason, ''), away, settled`

func scanDayScore(row interface{ Scan(...any) error }) (DayScoreRow, error) {
	var r DayScoreRow
	err := row.Scan(&r.UserID, &r.LocalDate, &r.BasePoints, &r.BonusPoints, &r.MaxBase, &r.Percent,
		&r.Counted, &r.Detail, &r.FinalizedAt, &r.ComputedAt, &r.FrozenReason, &r.Away, &r.Settled)
	return r, err
}

// UpsertDayScore stores a day's score. A day that is already finalized stays finalized;
// finalize additionally stamps one that is not.
func UpsertDayScore(ctx context.Context, q Querier, r DayScoreRow, finalize bool) (DayScoreRow, error) {
	row, err := scanDayScore(q.QueryRow(ctx, `
		INSERT INTO day_scores AS s (user_id, local_date, base_points, bonus_points, max_base, percent,
			counted, detail, finalized_at)
		VALUES ($1, $2::date, $3, $4, $5, $6, $7, $8, CASE WHEN $9 THEN now() END)
		ON CONFLICT (user_id, local_date) DO UPDATE
		SET base_points = EXCLUDED.base_points, bonus_points = EXCLUDED.bonus_points,
		    max_base = EXCLUDED.max_base, percent = EXCLUDED.percent, counted = EXCLUDED.counted,
		    detail = EXCLUDED.detail, computed_at = now(),
		    finalized_at = COALESCE(s.finalized_at, EXCLUDED.finalized_at)
		RETURNING `+dayScoreColumns,
		r.UserID, r.LocalDate, r.BasePoints, r.BonusPoints, r.MaxBase, r.Percent, r.Counted, r.Detail, finalize))
	return row, err
}

// GetDayScore reads one stored day.
func GetDayScore(ctx context.Context, q Querier, userID int64, date score.Date) (DayScoreRow, error) {
	row, err := scanDayScore(q.QueryRow(ctx,
		`SELECT `+dayScoreColumns+` FROM day_scores WHERE user_id = $1 AND local_date = $2::date`, userID, date))
	return row, notFound(err)
}

// ListDayScores reads stored days from..to inclusive, oldest first.
func ListDayScores(ctx context.Context, q Querier, userID int64, from, to score.Date) ([]DayScoreRow, error) {
	rows, err := q.Query(ctx, `
		SELECT `+dayScoreColumns+` FROM day_scores
		WHERE user_id = $1 AND local_date BETWEEN $2::date AND $3::date
		ORDER BY local_date`, userID, from, to)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var out []DayScoreRow
	for rows.Next() {
		r, err := scanDayScore(rows)
		if err != nil {
			return nil, err
		}
		out = append(out, r)
	}
	return out, rows.Err()
}

// SumPoints adds base and bonus points over from..to inclusive.
func SumPoints(ctx context.Context, q Querier, userID int64, from, to score.Date) (int, error) {
	var total int
	err := q.QueryRow(ctx, `
		SELECT COALESCE(sum(base_points + bonus_points), 0)::int FROM day_scores
		WHERE user_id = $1 AND local_date BETWEEN $2::date AND $3::date`, userID, from, to).Scan(&total)
	return total, err
}

// UnfinalizedDates lists the dates from..through that still have no finalized score, oldest
// first. Dates with no row at all are included, so a restart never skips a day.
func UnfinalizedDates(ctx context.Context, q Querier, userID int64, from, through score.Date) ([]score.Date, error) {
	rows, err := q.Query(ctx, `
		SELECT ($2::date + g)::text FROM generate_series(0, $3::date - $2::date) g
		WHERE NOT EXISTS (
			SELECT 1 FROM day_scores s
			WHERE s.user_id = $1 AND s.local_date = $2::date + g AND s.finalized_at IS NOT NULL)
		ORDER BY g`, userID, from, through)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var out []score.Date
	for rows.Next() {
		var d score.Date
		if err := rows.Scan(&d); err != nil {
			return nil, err
		}
		out = append(out, d)
	}
	return out, rows.Err()
}

// SettleDay records the streak outcome of a finalized day, once. A day that is already settled
// keeps what it has, which is what makes the recorded history final.
func SettleDay(ctx context.Context, q Querier, userID int64, date score.Date, reason string, away bool) error {
	_, err := q.Exec(ctx, `
		UPDATE day_scores SET settled = true, frozen_reason = NULLIF($3, ''), away = $4
		WHERE user_id = $1 AND local_date = $2::date AND finalized_at IS NOT NULL AND NOT settled`,
		userID, date, reason, away)
	return err
}

// RepairDay turns a missed, unfrozen, settled day into a repaired one. It reports whether it
// changed the day.
func RepairDay(ctx context.Context, q Querier, userID int64, date score.Date) (bool, error) {
	tag, err := q.Exec(ctx, `
		UPDATE day_scores SET frozen_reason = 'repair'
		WHERE user_id = $1 AND local_date = $2::date AND settled AND NOT counted AND NOT away
		  AND frozen_reason IS NULL`, userID, date)
	return tag.RowsAffected() == 1, err
}

// LockUserStreak serializes the settling of one person's days. Everything that finalizes a day
// takes it before touching the day row, so two settlers can never wait on each other's rows.
func LockUserStreak(ctx context.Context, tx pgx.Tx, userID int64) error {
	return LockUserDay(ctx, tx, userID, "1999-12-31")
}
