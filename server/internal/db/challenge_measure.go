package db

import (
	"context"
	"fmt"

	"github.com/nc1107/new-me/server/internal/score"
)

// Challenge kinds measured from stored data. They mirror the together package's constants; the
// db package cannot import it.
const (
	ChallengeSleepNights = "sleep_nights"
	ChallengeMealDays    = "meal_days"
	ChallengeProteinDays = "protein_days"
	ChallengePushupReps  = "pushup_reps"
	ChallengeYogaMinutes = "yoga_minutes"
	ChallengeHabitMarks  = "habit_marks"
	ChallengeActiveDays  = "active_days"
)

// defaultSleepTargetMin applies to a night on a day that had no sleep quest.
const defaultSleepTargetMin = 420

// Measure is one person's amount of a challenge kind over a range of local dates.
type Measure struct {
	// Total is the amount: nights, days, reps or minutes, depending on the kind.
	Total int
	// Days is how many distinct days had any data of the kind.
	Days int
	// Asked is what the person's own quest targets asked for over the range, for kinds that
	// have a per-day target (push-ups, yoga); zero otherwise.
	Asked int
}

// ChallengeMeasure measures the kind for the person on local dates from..to inclusive. Day-count
// kinds hold each day to the target that was frozen into that day's quests, so a person is
// always measured against their own bar.
func ChallengeMeasure(ctx context.Context, q Querier, userID int64, kind string, from, to score.Date) (Measure, error) {
	var sql string
	var args []any
	switch kind {
	case ChallengeSleepNights:
		sql = `
			SELECT count(*) FILTER (WHERE n.asleep_min >= COALESCE(d.target, $4))::int, count(*)::int, 0
			FROM sleep_nights n
			LEFT JOIN day_quests d ON d.user_id = n.user_id AND d.local_date = n.local_date AND d.key = 'sleep'
			WHERE n.user_id = $1 AND n.local_date BETWEEN $2::date AND $3::date`
		args = []any{defaultSleepTargetMin}
	case ChallengeMealDays:
		sql = `
			SELECT count(DISTINCT local_date)::int, count(DISTINCT local_date)::int, 0 FROM meal_logs
			WHERE user_id = $1 AND deleted_at IS NULL AND local_date BETWEEN $2::date AND $3::date`
	case ChallengeProteinDays:
		sql = `
			SELECT count(*) FILTER (WHERE m.protein >= COALESCE(d.target, u.protein_target, $4))::int, count(*)::int, 0
			FROM (SELECT user_id, local_date, sum(protein_g) AS protein FROM meal_logs
			      WHERE user_id = $1 AND deleted_at IS NULL AND local_date BETWEEN $2::date AND $3::date
			      GROUP BY user_id, local_date) m
			JOIN users u ON u.id = m.user_id
			LEFT JOIN day_quests d ON d.user_id = m.user_id AND d.local_date = m.local_date AND d.key = 'protein'`
		args = []any{DefaultProteinTarget}
	case ChallengePushupReps:
		sql = activitySQL(`type = 'pushups' AND exercise = 'push_up'`, "pushups")
	case ChallengeYogaMinutes:
		sql = activitySQL(`type = 'yoga_minutes'`, "yoga")
	case ChallengeHabitMarks:
		sql = `
			SELECT count(*)::int, count(DISTINCT m.local_date)::int, 0
			FROM habit_marks m JOIN habits h ON h.id = m.habit_id
			WHERE h.user_id = $1 AND h.deleted_at IS NULL AND m.local_date BETWEEN $2::date AND $3::date`
	case ChallengeActiveDays:
		sql = `
			SELECT count(*)::int, count(*)::int, 0 FROM (
			  SELECT local_date FROM workouts
			  WHERE user_id = $1 AND local_date BETWEEN $2::date AND $3::date
			  UNION
			  SELECT local_date FROM activity_logs
			  WHERE user_id = $1 AND deleted_at IS NULL AND type IN ('pushups', 'yoga_minutes', 'other_minutes')
			    AND local_date BETWEEN $2::date AND $3::date) active`
	default:
		return Measure{}, fmt.Errorf("challenge kind %q is not measured from stored data", kind)
	}
	var m Measure
	err := q.QueryRow(ctx, sql, append([]any{userID, from, to}, args...)...).Scan(&m.Total, &m.Days, &m.Asked)
	return m, err
}

// activitySQL sums an activity type's quantity and sums the quest target of the same days.
func activitySQL(where, questKey string) string {
	return `
		SELECT COALESCE(sum(quantity), 0)::int, count(DISTINCT local_date)::int,
		       (SELECT COALESCE(sum(target), 0)::int FROM day_quests
		        WHERE user_id = $1 AND key = '` + questKey + `' AND local_date BETWEEN $2::date AND $3::date)
		FROM activity_logs
		WHERE user_id = $1 AND deleted_at IS NULL AND ` + where + ` AND local_date BETWEEN $2::date AND $3::date`
}

// ChallengeKindsBetween lists the kinds of the challenges that started on weeks from..to.
func ChallengeKindsBetween(ctx context.Context, q Querier, from, to score.Date) ([]string, error) {
	rows, err := q.Query(ctx, `
		SELECT kind FROM challenges WHERE week_start BETWEEN $1::date AND $2::date ORDER BY week_start`, from, to)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var out []string
	for rows.Next() {
		var kind string
		if err := rows.Scan(&kind); err != nil {
			return nil, err
		}
		out = append(out, kind)
	}
	return out, rows.Err()
}

// CloseMissedChallenges marks every unfinished challenge of the two weeks before the given Monday
// as missed, once, and returns how many it closed. Older weeks are left alone so the pass stays
// cheap. There is no penalty: nothing else reads it except the recap and the Us screen.
func CloseMissedChallenges(ctx context.Context, q Querier, currentWeek score.Date) (int, error) {
	tag, err := q.Exec(ctx, `
		UPDATE challenges SET missed_at = now()
		WHERE completed_at IS NULL AND missed_at IS NULL
		  AND week_start < $1::date AND week_start >= $1::date - 14`, currentWeek)
	return int(tag.RowsAffected()), err
}
