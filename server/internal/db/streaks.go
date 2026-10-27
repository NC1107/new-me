package db

import (
	"context"
	"time"

	"github.com/jackc/pgx/v5"

	"github.com/nc1107/new-me/server/internal/score"
)

// MaxAwayDays is the longest away span, and how far ahead one may start.
const MaxAwayDays = 14

// AwaySpan is a stretch of days a person marked as away.
type AwaySpan struct {
	ID     int64
	UserID int64
	From   score.Date
	To     score.Date
	Note   string
}

// Contains reports whether the date falls inside the span.
func (a AwaySpan) Contains(d score.Date) bool { return !d.Before(a.From) && !d.After(a.To) }

const awayColumns = `id, user_id, from_date::text, to_date::text, note`

func scanAway(row pgx.Row) (AwaySpan, error) {
	var a AwaySpan
	err := row.Scan(&a.ID, &a.UserID, &a.From, &a.To, &a.Note)
	return a, err
}

// LockUserRows serializes the writers of one person's spans.
func LockUserRows(ctx context.Context, tx pgx.Tx, userID int64) error {
	_, err := tx.Exec(ctx, `SELECT 1 FROM users WHERE id = $1 FOR UPDATE`, userID)
	return err
}

// OverlappingAway reports whether the person already has a span touching from..to.
func OverlappingAway(ctx context.Context, q Querier, userID int64, from, to score.Date) (bool, error) {
	var n int
	err := q.QueryRow(ctx, `
		SELECT count(*)::int FROM away_spans
		WHERE user_id = $1 AND from_date <= $3::date AND to_date >= $2::date`, userID, from, to).Scan(&n)
	return n > 0, err
}

// CreateAway stores a span.
func CreateAway(ctx context.Context, q Querier, userID int64, from, to score.Date, note string) (AwaySpan, error) {
	return scanAway(q.QueryRow(ctx, `
		INSERT INTO away_spans (user_id, from_date, to_date, note) VALUES ($1, $2::date, $3::date, $4)
		RETURNING `+awayColumns, userID, from, to, note))
}

// DeleteAway removes one of the person's spans and returns it.
func DeleteAway(ctx context.Context, q Querier, userID, id int64) (AwaySpan, error) {
	a, err := scanAway(q.QueryRow(ctx,
		`DELETE FROM away_spans WHERE id = $1 AND user_id = $2 RETURNING `+awayColumns, id, userID))
	return a, notFound(err)
}

// AwaySpansFrom lists the person's spans that end on or after the date, oldest first.
func AwaySpansFrom(ctx context.Context, q Querier, userID int64, date score.Date) ([]AwaySpan, error) {
	return queryAway(ctx, q, `SELECT `+awayColumns+` FROM away_spans
		WHERE user_id = $1 AND to_date >= $2::date ORDER BY from_date, id`, userID, date)
}

// AwaySpansBetween lists the spans touching from..to, oldest first.
func AwaySpansBetween(ctx context.Context, q Querier, userID int64, from, to score.Date) ([]AwaySpan, error) {
	return queryAway(ctx, q, `SELECT `+awayColumns+` FROM away_spans
		WHERE user_id = $1 AND from_date <= $3::date AND to_date >= $2::date ORDER BY from_date, id`, userID, from, to)
}

func queryAway(ctx context.Context, q Querier, sql string, args ...any) ([]AwaySpan, error) {
	rows, err := q.Query(ctx, sql, args...)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := []AwaySpan{}
	for rows.Next() {
		a, err := scanAway(rows)
		if err != nil {
			return nil, err
		}
		out = append(out, a)
	}
	return out, rows.Err()
}

// Cover is a freeze one person spent on the other's missed day.
type Cover struct {
	CoveredUser int64
	Date        score.Date
	ByUser      int64
}

// CreateCover records a cover. It reports false when the day is already covered.
func CreateCover(ctx context.Context, q Querier, covered, by int64, date score.Date) (bool, error) {
	tag, err := q.Exec(ctx, `
		INSERT INTO streak_covers (covered_user, local_date, by_user) VALUES ($1, $2::date, $3)
		ON CONFLICT DO NOTHING`, covered, date, by)
	return tag.RowsAffected() == 1, err
}

// DeleteCover removes a cover, which refunds the freeze to the person who spent it.
func DeleteCover(ctx context.Context, q Querier, covered int64, date score.Date) error {
	_, err := q.Exec(ctx, `DELETE FROM streak_covers WHERE covered_user = $1 AND local_date = $2::date`, covered, date)
	return err
}

// CoversFor lists the covers on the person's days (Covered) and the ones they paid for (Spent).
func CoversFor(ctx context.Context, q Querier, userID int64) (covered, spent []Cover, err error) {
	rows, err := q.Query(ctx, `
		SELECT covered_user, local_date::text, by_user FROM streak_covers
		WHERE covered_user = $1 OR by_user = $1 ORDER BY local_date`, userID)
	if err != nil {
		return nil, nil, err
	}
	defer rows.Close()
	for rows.Next() {
		var c Cover
		if err := rows.Scan(&c.CoveredUser, &c.Date, &c.ByUser); err != nil {
			return nil, nil, err
		}
		if c.CoveredUser == userID {
			covered = append(covered, c)
		} else {
			spent = append(spent, c)
		}
	}
	return covered, spent, rows.Err()
}

// Milestone kinds.
const (
	MilestoneStreak       = "streak"
	MilestoneSharedStreak = "shared_streak"
	MilestoneFirst10K     = "first_10k_steps"
	MilestoneFirstAll     = "first_all_quests"
	MilestoneFirstWeek    = "first_full_week"
)

// Milestone is something worth celebrating, recorded once. UserID is nil for the couple's.
type Milestone struct {
	ID         int64
	UserID     *int64
	Kind       string
	Value      int
	AchievedOn score.Date
	CreatedAt  time.Time
}

const milestoneColumns = `id, user_id, kind, value, achieved_on::text, created_at`

func scanMilestone(row pgx.Row) (Milestone, error) {
	var m Milestone
	err := row.Scan(&m.ID, &m.UserID, &m.Kind, &m.Value, &m.AchievedOn, &m.CreatedAt)
	return m, err
}

// RecordMilestone stores a milestone unless it exists already. The second result is true only
// for the call that recorded it.
func RecordMilestone(ctx context.Context, q Querier, userID *int64, kind string, value int, on score.Date) (Milestone, bool, error) {
	m, err := scanMilestone(q.QueryRow(ctx, `
		INSERT INTO milestones (user_id, kind, value, achieved_on) VALUES ($1, $2, $3, $4::date)
		ON CONFLICT DO NOTHING RETURNING `+milestoneColumns, userID, kind, value, on))
	if err == nil {
		return m, true, nil
	}
	return Milestone{}, false, notFound(err)
}

// ListMilestones returns the person's milestones and the couple's, newest first.
func ListMilestones(ctx context.Context, q Querier, userID int64) ([]Milestone, error) {
	return queryMilestones(ctx, q, `SELECT `+milestoneColumns+` FROM milestones
		WHERE user_id = $1 OR user_id IS NULL ORDER BY achieved_on DESC, id DESC`, userID)
}

// MilestonesSince returns the person's and the couple's milestones achieved on or after the date.
func MilestonesSince(ctx context.Context, q Querier, userID int64, since score.Date) ([]Milestone, error) {
	return queryMilestones(ctx, q, `SELECT `+milestoneColumns+` FROM milestones
		WHERE (user_id = $1 OR user_id IS NULL) AND achieved_on >= $2::date
		ORDER BY achieved_on DESC, id DESC`, userID, since)
}

// MilestoneKinds lists which (kind, value) pairs are already recorded for a person, or for the
// couple when userID is nil.
func MilestoneKinds(ctx context.Context, q Querier, userID *int64) (map[string]bool, error) {
	rows, err := q.Query(ctx, `
		SELECT kind || ':' || value FROM milestones WHERE user_id IS NOT DISTINCT FROM $1`, userID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := map[string]bool{}
	for rows.Next() {
		var k string
		if err := rows.Scan(&k); err != nil {
			return nil, err
		}
		out[k] = true
	}
	return out, rows.Err()
}

func queryMilestones(ctx context.Context, q Querier, sql string, args ...any) ([]Milestone, error) {
	rows, err := q.Query(ctx, sql, args...)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := []Milestone{}
	for rows.Next() {
		m, err := scanMilestone(rows)
		if err != nil {
			return nil, err
		}
		out = append(out, m)
	}
	return out, rows.Err()
}

// FirstDayOver is the earliest date the person's metric reached the value, or "" if never.
func FirstDayOver(ctx context.Context, q Querier, userID int64, metric string, value float64) (score.Date, error) {
	var d *score.Date
	err := q.QueryRow(ctx, `
		SELECT min(local_date)::text FROM health_daily WHERE user_id = $1 AND metric = $2 AND value >= $3`,
		userID, metric, value).Scan(&d)
	if err != nil || d == nil {
		return "", err
	}
	return *d, nil
}

// FirstAllQuestsDay is the earliest date on which the person finished every quest that day had.
func FirstAllQuestsDay(ctx context.Context, q Querier, userID int64) (score.Date, error) {
	var d *score.Date
	err := q.QueryRow(ctx, `
		SELECT min(local_date)::text FROM day_scores
		WHERE user_id = $1 AND jsonb_array_length(detail) > 0
		  AND NOT EXISTS (SELECT 1 FROM jsonb_array_elements(detail) e WHERE (e->>'complete')::boolean IS NOT TRUE)`,
		userID).Scan(&d)
	if err != nil || d == nil {
		return "", err
	}
	return *d, nil
}

// FirstFullWeek is the Sunday of the earliest Monday-to-Sunday week in which all seven days
// counted, or "" if there is none.
func FirstFullWeek(ctx context.Context, q Querier, userID int64) (score.Date, error) {
	var d *score.Date
	err := q.QueryRow(ctx, `
		SELECT (min(wk) + 6)::text FROM (
			SELECT date_trunc('week', local_date)::date AS wk FROM day_scores
			WHERE user_id = $1 AND counted GROUP BY 1 HAVING count(*) = 7
		) w`, userID).Scan(&d)
	if err != nil || d == nil {
		return "", err
	}
	return *d, nil
}
