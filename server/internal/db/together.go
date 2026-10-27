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
}

// EndsOn is the Sunday of the challenge's week.
func (c Challenge) EndsOn() score.Date { return c.WeekStart.AddDays(6) }

const challengeColumns = `id, week_start::text, kind, title, target, completed_at`

func scanChallenge(row interface{ Scan(...any) error }) (Challenge, error) {
	var c Challenge
	err := row.Scan(&c.ID, &c.WeekStart, &c.Kind, &c.Title, &c.Target, &c.CompletedAt)
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
		INSERT INTO challenges (week_start, kind, title, target) VALUES ($1::date, $2, $3, $4)
		ON CONFLICT (week_start) DO NOTHING`, c.WeekStart, c.Kind, c.Title, c.Target); err != nil {
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

// StepsByUser is each live user's total and number of days with a steps reading from..to.
type StepsByUser struct {
	UserID int64
	Total  float64
	Days   int
}

// StepTotals aggregates Health steps per live user over from..to inclusive.
func StepTotals(ctx context.Context, q Querier, from, to score.Date) ([]StepsByUser, error) {
	rows, err := q.Query(ctx, `
		SELECT h.user_id, sum(h.value)::float8, count(*)::int
		FROM health_daily h JOIN users u ON u.id = h.user_id AND u.deleted_at IS NULL
		WHERE h.metric = $3 AND h.local_date BETWEEN $1::date AND $2::date
		GROUP BY h.user_id ORDER BY h.user_id`, from, to, MetricSteps)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var out []StepsByUser
	for rows.Next() {
		var s StepsByUser
		if err := rows.Scan(&s.UserID, &s.Total, &s.Days); err != nil {
			return nil, err
		}
		out = append(out, s)
	}
	return out, rows.Err()
}

// WorkoutsAll counts every live user's workouts on local dates from..to inclusive.
func WorkoutsAll(ctx context.Context, q Querier, from, to score.Date) (int, error) {
	var n int
	err := q.QueryRow(ctx, `
		SELECT count(*)::int FROM workouts w JOIN users u ON u.id = w.user_id AND u.deleted_at IS NULL
		WHERE w.local_date BETWEEN $1::date AND $2::date`, from, to).Scan(&n)
	return n, err
}

// ReadingMinutesAll adds every live user's logged reading minutes and Audiobookshelf listening
// on local dates from..to inclusive.
func ReadingMinutesAll(ctx context.Context, q Querier, from, to score.Date) (int, error) {
	var n int
	err := q.QueryRow(ctx, `
		SELECT (
		  SELECT COALESCE(sum(a.quantity), 0) FROM activity_logs a
		  JOIN users u ON u.id = a.user_id AND u.deleted_at IS NULL
		  WHERE a.type = 'reading_minutes' AND a.deleted_at IS NULL
		    AND a.local_date BETWEEN $1::date AND $2::date
		) + (
		  SELECT COALESCE(sum(l.minutes), 0) FROM listening_daily l
		  JOIN users u ON u.id = l.user_id AND u.deleted_at IS NULL
		  WHERE l.local_date BETWEEN $1::date AND $2::date
		)`, from, to).Scan(&n)
	return n, err
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

// Reward is a shared goal measured in combined points since it started.
type Reward struct {
	ID        int64
	Name      string
	Target    int
	Baseline  int
	CreatedBy *int64
	StartedAt time.Time
	ReachedAt *time.Time
	ClaimedAt *time.Time
}

const rewardColumns = `id, name, target, baseline, created_by, started_at, reached_at, claimed_at`

func scanReward(row interface{ Scan(...any) error }) (Reward, error) {
	var r Reward
	err := row.Scan(&r.ID, &r.Name, &r.Target, &r.Baseline, &r.CreatedBy, &r.StartedAt, &r.ReachedAt, &r.ClaimedAt)
	return r, err
}

// TotalPoints is the combined all-time points of every live user.
func TotalPoints(ctx context.Context, q Querier) (int, error) {
	var n int
	err := q.QueryRow(ctx, `
		SELECT COALESCE(sum(s.base_points + s.bonus_points), 0)::int FROM day_scores s
		JOIN users u ON u.id = s.user_id AND u.deleted_at IS NULL`).Scan(&n)
	return n, err
}

// CreateReward starts a reward from the given baseline. A second unreached reward violates
// rewards_one_active, which ErrRewardActive reports.
func CreateReward(ctx context.Context, q Querier, name string, target, baseline int, by int64) (Reward, error) {
	r, err := scanReward(q.QueryRow(ctx, `
		INSERT INTO rewards (name, target, baseline, created_by) VALUES ($1, $2, $3, $4)
		RETURNING `+rewardColumns, name, target, baseline, by))
	if violatedConstraint(err) == "rewards_one_active" {
		return Reward{}, ErrRewardActive
	}
	return r, err
}

// ActiveReward is the reward still being earned.
func ActiveReward(ctx context.Context, q Querier) (Reward, error) {
	r, err := scanReward(q.QueryRow(ctx,
		`SELECT `+rewardColumns+` FROM rewards WHERE reached_at IS NULL`))
	return r, notFound(err)
}

// LatestUnclaimedReward is the newest reached reward nobody has marked as enjoyed yet.
func LatestUnclaimedReward(ctx context.Context, q Querier) (Reward, error) {
	r, err := scanReward(q.QueryRow(ctx, `
		SELECT `+rewardColumns+` FROM rewards WHERE reached_at IS NOT NULL AND claimed_at IS NULL
		ORDER BY reached_at DESC, id DESC LIMIT 1`))
	return r, notFound(err)
}

// GetReward reads one reward.
func GetReward(ctx context.Context, q Querier, id int64) (Reward, error) {
	r, err := scanReward(q.QueryRow(ctx, `SELECT `+rewardColumns+` FROM rewards WHERE id = $1`, id))
	return r, notFound(err)
}

// ListReachedRewards is the history, newest first.
func ListReachedRewards(ctx context.Context, q Querier) ([]Reward, error) {
	rows, err := q.Query(ctx, `
		SELECT `+rewardColumns+` FROM rewards WHERE reached_at IS NOT NULL
		ORDER BY reached_at DESC, id DESC LIMIT 100`)
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

// MarkRewardReached stamps the moment once and reports whether this call did it.
func MarkRewardReached(ctx context.Context, q Querier, id int64) (bool, error) {
	tag, err := q.Exec(ctx, `UPDATE rewards SET reached_at = now() WHERE id = $1 AND reached_at IS NULL`, id)
	return tag.RowsAffected() == 1, err
}

// ClaimReward marks a reached reward as enjoyed. A repeat keeps the first time.
func ClaimReward(ctx context.Context, q Querier, id int64) (Reward, error) {
	r, err := scanReward(q.QueryRow(ctx, `
		UPDATE rewards SET claimed_at = COALESCE(claimed_at, now())
		WHERE id = $1 AND reached_at IS NOT NULL RETURNING `+rewardColumns, id))
	return r, notFound(err)
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
