package db

import (
	"context"
	"time"

	"github.com/nc1107/new-me/server/internal/score"
)

// Cheer kinds.
var CheerKinds = []string{"clap", "fire", "flex", "heart"}

// Cheer is one reaction sent to a partner.
type Cheer struct {
	ID        int64
	From      int64
	FromName  string
	To        int64
	Kind      string
	LocalDate score.Date
	At        time.Time
}

const cheerColumns = `c.id, c.from_user, u.name, c.to_user, c.kind, c.local_date::text, c.created_at`

func scanCheer(row interface{ Scan(...any) error }) (Cheer, error) {
	var c Cheer
	err := row.Scan(&c.ID, &c.From, &c.FromName, &c.To, &c.Kind, &c.LocalDate, &c.At)
	return c, err
}

// InsertCheer stores a cheer at the given instant, once per sender, recipient, kind and sender-local day. On a repeat
// it returns the stored cheer with created=false.
func InsertCheer(ctx context.Context, q Querier, from, to int64, kind string, date score.Date, at time.Time) (Cheer, bool, error) {
	var id int64
	err := q.QueryRow(ctx, `
		INSERT INTO cheers (from_user, to_user, kind, local_date, created_at) VALUES ($1, $2, $3, $4::date, $5)
		ON CONFLICT (from_user, to_user, kind, local_date) DO NOTHING
		RETURNING id`, from, to, kind, date, at).Scan(&id)
	created := err == nil
	if err != nil && notFound(err) != ErrNotFound {
		return Cheer{}, false, err
	}
	c, err := scanCheer(q.QueryRow(ctx, `
		SELECT `+cheerColumns+` FROM cheers c JOIN users u ON u.id = c.from_user
		WHERE c.from_user = $1 AND c.to_user = $2 AND c.kind = $3 AND c.local_date = $4::date`,
		from, to, kind, date))
	return c, created, err
}

// CheersReceived lists cheers sent to the person between two instants, newest first.
func CheersReceived(ctx context.Context, q Querier, to int64, from, until time.Time) ([]Cheer, error) {
	rows, err := q.Query(ctx, `
		SELECT `+cheerColumns+` FROM cheers c JOIN users u ON u.id = c.from_user
		WHERE c.to_user = $1 AND c.created_at >= $2 AND c.created_at < $3
		ORDER BY c.created_at DESC, c.id DESC`, to, from, until)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := []Cheer{}
	for rows.Next() {
		c, err := scanCheer(rows)
		if err != nil {
			return nil, err
		}
		out = append(out, c)
	}
	return out, rows.Err()
}

// Challenge is one week's shared challenge.
type Challenge struct {
	ID          int64
	WeekStart   score.Date
	Kind        string
	Title       string
	Target      int
	CompletedAt *time.Time
	// PickReason is why the kind was chosen; empty for challenges from before v13.
	PickReason string
	// MissedAt is set at week end on a challenge that was not finished.
	MissedAt *time.Time
}

// EndsOn is the Sunday of the challenge's week.
func (c Challenge) EndsOn() score.Date { return c.WeekStart.AddDays(6) }

const challengeColumns = `id, week_start::text, kind, title, target, completed_at, COALESCE(pick_reason, ''), missed_at`

func scanChallenge(row interface{ Scan(...any) error }) (Challenge, error) {
	var c Challenge
	err := row.Scan(&c.ID, &c.WeekStart, &c.Kind, &c.Title, &c.Target, &c.CompletedAt, &c.PickReason, &c.MissedAt)
	return c, err
}

// GetChallenge reads the challenge of the week starting on the Monday.
func GetChallenge(ctx context.Context, q Querier, weekStart score.Date) (Challenge, error) {
	c, err := scanChallenge(q.QueryRow(ctx,
		`SELECT `+challengeColumns+` FROM challenges WHERE week_start = $1::date`, weekStart))
	return c, notFound(err)
}

// InsertChallenge stores a week's challenge unless one already exists, and returns the stored
// one either way, so two racing creators agree on the target.
func InsertChallenge(ctx context.Context, q Querier, c Challenge) (Challenge, error) {
	if _, err := q.Exec(ctx, `
		INSERT INTO challenges (week_start, kind, title, target, pick_reason) VALUES ($1::date, $2, $3, $4, NULLIF($5, ''))
		ON CONFLICT (week_start) DO NOTHING`, c.WeekStart, c.Kind, c.Title, c.Target, c.PickReason); err != nil {
		return Challenge{}, err
	}
	return GetChallenge(ctx, q, c.WeekStart)
}

// CompleteChallenge stamps the completion once. It reports false when someone else already did,
// which is what keeps the award from being paid twice.
func CompleteChallenge(ctx context.Context, q Querier, id int64) (bool, error) {
	tag, err := q.Exec(ctx,
		`UPDATE challenges SET completed_at = now() WHERE id = $1 AND completed_at IS NULL`, id)
	return tag.RowsAffected() == 1, err
}

// InsertChallengeAward records one person's completion bonus on a local day.
func InsertChallengeAward(ctx context.Context, q Querier, challengeID, userID int64, date score.Date, points int) error {
	_, err := q.Exec(ctx, `
		INSERT INTO challenge_awards (challenge_id, user_id, local_date, points) VALUES ($1, $2, $3::date, $4)
		ON CONFLICT (challenge_id, user_id) DO NOTHING`, challengeID, userID, date, points)
	return err
}

// ChallengeBonus is the challenge points the person earned on a local day.
func ChallengeBonus(ctx context.Context, q Querier, userID int64, date score.Date) (int, error) {
	var points int
	err := q.QueryRow(ctx, `
		SELECT COALESCE(sum(points), 0)::int FROM challenge_awards WHERE user_id = $1 AND local_date = $2::date`,
		userID, date).Scan(&points)
	return points, err
}

// CountedDay is a local day on which a person's day counted.
type CountedDay struct {
	UserID int64
	Date   score.Date
}

// CountedDays lists every live user's counted days from..to inclusive.
func CountedDays(ctx context.Context, q Querier, from, to score.Date) ([]CountedDay, error) {
	rows, err := q.Query(ctx, `
		SELECT s.user_id, s.local_date::text FROM day_scores s
		JOIN users u ON u.id = s.user_id AND u.deleted_at IS NULL
		WHERE s.counted AND s.local_date BETWEEN $1::date AND $2::date
		ORDER BY s.local_date, s.user_id`, from, to)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var out []CountedDay
	for rows.Next() {
		var d CountedDay
		if err := rows.Scan(&d.UserID, &d.Date); err != nil {
			return nil, err
		}
		out = append(out, d)
	}
	return out, rows.Err()
}

// TotalPoints is the combined all-time points (gems) of every live user.
func TotalPoints(ctx context.Context, q Querier) (int, error) {
	var n int
	err := q.QueryRow(ctx, `
		SELECT COALESCE(sum(s.base_points + s.bonus_points), 0)::int FROM day_scores s
		JOIN users u ON u.id = s.user_id AND u.deleted_at IS NULL`).Scan(&n)
	return n, err
}

// UpsertPushToken registers the APNs token of an install. The token is unique, so one that
// moves to another install leaves the old one.
func UpsertPushToken(ctx context.Context, q Querier, deviceID, userID int64, token string) error {
	if _, err := q.Exec(ctx, `DELETE FROM push_tokens WHERE token = $1 AND device_id <> $2`, token, deviceID); err != nil {
		return err
	}
	_, err := q.Exec(ctx, `
		INSERT INTO push_tokens (device_id, user_id, token) VALUES ($1, $2, $3)
		ON CONFLICT (device_id) DO UPDATE SET token = EXCLUDED.token, user_id = EXCLUDED.user_id, updated_at = now()`,
		deviceID, userID, token)
	return err
}

// DeletePushToken forgets the install's token.
func DeletePushToken(ctx context.Context, q Querier, deviceID int64) error {
	_, err := q.Exec(ctx, `DELETE FROM push_tokens WHERE device_id = $1`, deviceID)
	return err
}

// DeletePushTokenValue forgets a token Apple reported as dead.
func DeletePushTokenValue(ctx context.Context, q Querier, token string) error {
	_, err := q.Exec(ctx, `DELETE FROM push_tokens WHERE token = $1`, token)
	return err
}

// PushTokens lists the person's registered tokens.
func PushTokens(ctx context.Context, q Querier, userID int64) ([]string, error) {
	rows, err := q.Query(ctx, `SELECT token FROM push_tokens WHERE user_id = $1 ORDER BY device_id`, userID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var out []string
	for rows.Next() {
		var t string
		if err := rows.Scan(&t); err != nil {
			return nil, err
		}
		out = append(out, t)
	}
	return out, rows.Err()
}

// ClaimNotice records that an event was sent for a person and day. It is true only for the
// first caller, which is the one that should send.
func ClaimNotice(ctx context.Context, q Querier, kind string, userID int64, date score.Date) (bool, error) {
	tag, err := q.Exec(ctx, `
		INSERT INTO notice_log (kind, user_id, local_date) VALUES ($1, $2, $3::date)
		ON CONFLICT DO NOTHING`, kind, userID, date)
	return tag.RowsAffected() == 1, err
}

// ReleaseNotice withdraws a claim whose push could not be queued, so the next pass sends it.
func ReleaseNotice(ctx context.Context, q Querier, kind string, userID int64, date score.Date) error {
	_, err := q.Exec(ctx, `DELETE FROM notice_log WHERE kind = $1 AND user_id = $2 AND local_date = $3::date`,
		kind, userID, date)
	return err
}

// CountNoticesOfKinds is how many notices a person was sent on a local date whose kind is one
// of the exact kinds or starts with one of the prefixes.
func CountNoticesOfKinds(ctx context.Context, q Querier, userID int64, date score.Date, kinds, prefixes []string) (int, error) {
	var n int
	err := q.QueryRow(ctx, `
		SELECT count(*)::int FROM notice_log
		WHERE user_id = $1 AND local_date = $2::date
		  AND (kind = ANY($3::text[]) OR EXISTS (SELECT 1 FROM unnest($4::text[]) p WHERE starts_with(kind, p)))`,
		userID, date, kinds, prefixes).Scan(&n)
	return n, err
}

// NoticeEverSent reports whether a person has a notice of the kind on any date.
func NoticeEverSent(ctx context.Context, q Querier, userID int64, kind string) (bool, error) {
	var ok bool
	err := q.QueryRow(ctx, `SELECT EXISTS (SELECT 1 FROM notice_log WHERE user_id = $1 AND kind = $2)`,
		userID, kind).Scan(&ok)
	return ok, err
}

// CheeredToday reports whether the sender has cheered the recipient on their local date.
func CheeredToday(ctx context.Context, q Querier, from, to int64, date score.Date) (bool, error) {
	var ok bool
	err := q.QueryRow(ctx, `
		SELECT EXISTS (SELECT 1 FROM cheers WHERE from_user = $1 AND to_user = $2 AND local_date = $3::date)`,
		from, to, date).Scan(&ok)
	return ok, err
}

// ReadingMinutesUser is one person's logged reading minutes plus Audiobookshelf listening on
// local dates from..to inclusive.
func ReadingMinutesUser(ctx context.Context, q Querier, userID int64, from, to score.Date) (int, error) {
	var n int
	err := q.QueryRow(ctx, `
		SELECT (
		  SELECT COALESCE(sum(quantity), 0) FROM activity_logs
		  WHERE user_id = $1 AND type = 'reading_minutes' AND deleted_at IS NULL
		    AND local_date BETWEEN $2::date AND $3::date
		) + (
		  SELECT COALESCE(sum(minutes), 0) FROM listening_daily
		  WHERE user_id = $1 AND local_date BETWEEN $2::date AND $3::date
		)`, userID, from, to).Scan(&n)
	return n, err
}

// NoticesSent lists the notice kinds already sent to a person for a local date.
func NoticesSent(ctx context.Context, q Querier, userID int64, date score.Date) (map[string]bool, error) {
	rows, err := q.Query(ctx, `SELECT kind FROM notice_log WHERE user_id = $1 AND local_date = $2::date`, userID, date)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := map[string]bool{}
	for rows.Next() {
		var kind string
		if err := rows.Scan(&kind); err != nil {
			return nil, err
		}
		out[kind] = true
	}
	return out, rows.Err()
}

// CountNotices is how many of the kinds were sent to a person for a local date.
func CountNotices(ctx context.Context, q Querier, userID int64, date score.Date, kinds []string) (int, error) {
	var n int
	err := q.QueryRow(ctx, `
		SELECT count(*)::int FROM notice_log WHERE user_id = $1 AND local_date = $2::date AND kind = ANY($3)`,
		userID, date, kinds).Scan(&n)
	return n, err
}

// ChallengeShares lists each person's share of a challenge by user id.
func ChallengeShares(ctx context.Context, q Querier, challengeID int64) (map[int64]int, error) {
	rows, err := q.Query(ctx, `SELECT user_id, target FROM challenge_shares WHERE challenge_id = $1`, challengeID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := map[int64]int{}
	for rows.Next() {
		var user int64
		var target int
		if err := rows.Scan(&user, &target); err != nil {
			return nil, err
		}
		out[user] = target
	}
	return out, rows.Err()
}

// InsertChallengeShare stores one person's share unless they already have one.
func InsertChallengeShare(ctx context.Context, q Querier, challengeID, userID int64, target int) error {
	_, err := q.Exec(ctx, `
		INSERT INTO challenge_shares (challenge_id, user_id, target) VALUES ($1, $2, $3)
		ON CONFLICT DO NOTHING`, challengeID, userID, target)
	return err
}

// SetChallengeTarget sets the combined target and title of a challenge that is not complete.
func SetChallengeTarget(ctx context.Context, q Querier, id int64, target int, title string) error {
	_, err := q.Exec(ctx, `
		UPDATE challenges SET target = $2, title = $3 WHERE id = $1 AND completed_at IS NULL`, id, target, title)
	return err
}

// StepsByUserID is the person's step total and days with a reading from..to.
func StepsByUserID(ctx context.Context, q Querier, userID int64, from, to score.Date) (total float64, days int, err error) {
	err = q.QueryRow(ctx, `
		SELECT COALESCE(sum(value), 0)::float8, count(*)::int FROM health_daily
		WHERE user_id = $1 AND metric = $4 AND local_date BETWEEN $2::date AND $3::date`,
		userID, from, to, MetricSteps).Scan(&total, &days)
	return total, days, err
}
