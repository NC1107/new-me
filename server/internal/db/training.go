package db

import (
	"context"
	"encoding/json"
	"time"

	"github.com/nc1107/new-me/server/internal/score"
	"github.com/nc1107/new-me/server/internal/training"
)

// TrainingProfile is what a person's plans are built for.
type TrainingProfile struct {
	Equipment      []string
	DumbbellMaxKg  *float64
	DaysPerWeek    int
	SessionMinutes int
	Experience     string
	Focus          string
	UpdatedAt      time.Time
}

// GetTrainingProfile returns the person's profile, or ErrNotFound before the first save.
func GetTrainingProfile(ctx context.Context, q Querier, userID int64) (TrainingProfile, error) {
	var p TrainingProfile
	err := q.QueryRow(ctx, `SELECT equipment, dumbbell_max_kg::float8, days_per_week, session_minutes,
		experience, focus, updated_at FROM training_profiles WHERE user_id = $1`, userID).Scan(
		&p.Equipment, &p.DumbbellMaxKg, &p.DaysPerWeek, &p.SessionMinutes, &p.Experience, &p.Focus, &p.UpdatedAt)
	return p, notFound(err)
}

// PutTrainingProfile replaces the person's profile.
func PutTrainingProfile(ctx context.Context, q Querier, userID int64, p TrainingProfile) (TrainingProfile, error) {
	var out TrainingProfile
	err := q.QueryRow(ctx, `
		INSERT INTO training_profiles (user_id, equipment, dumbbell_max_kg, days_per_week, session_minutes, experience, focus)
		VALUES ($1, $2, $3, $4, $5, $6, $7)
		ON CONFLICT (user_id) DO UPDATE SET equipment = EXCLUDED.equipment, dumbbell_max_kg = EXCLUDED.dumbbell_max_kg,
			days_per_week = EXCLUDED.days_per_week, session_minutes = EXCLUDED.session_minutes,
			experience = EXCLUDED.experience, focus = EXCLUDED.focus, updated_at = now()
		RETURNING equipment, dumbbell_max_kg::float8, days_per_week, session_minutes, experience, focus, updated_at`,
		userID, p.Equipment, p.DumbbellMaxKg, p.DaysPerWeek, p.SessionMinutes, p.Experience, p.Focus).Scan(
		&out.Equipment, &out.DumbbellMaxKg, &out.DaysPerWeek, &out.SessionMinutes, &out.Experience, &out.Focus, &out.UpdatedAt)
	return out, err
}

// StoredPlan is a saved plan.
type StoredPlan struct {
	ID       int64
	StartsOn score.Date
	Weeks    int
	Days     []training.PlanDay
	Notes    string
}

// EndsOn is the last day of the block.
func (p StoredPlan) EndsOn() score.Date { return p.StartsOn.AddDays(p.Weeks*7 - 1) }

// ActivePlan returns the person's active plan, or ErrNotFound.
func ActivePlan(ctx context.Context, q Querier, userID int64) (StoredPlan, error) {
	var (
		p    StoredPlan
		days []byte
	)
	err := q.QueryRow(ctx, `SELECT id, starts_on::text, weeks, days, notes FROM training_plans
		WHERE user_id = $1 AND ended_at IS NULL`, userID).Scan(&p.ID, &p.StartsOn, &p.Weeks, &days, &p.Notes)
	if err = notFound(err); err != nil {
		return p, err
	}
	return p, json.Unmarshal(days, &p.Days)
}

// ReplacePlan ends any active plan and saves the new one as active.
func ReplacePlan(ctx context.Context, q Querier, userID int64, startsOn score.Date, plan training.Plan) (StoredPlan, error) {
	if err := EndActivePlan(ctx, q, userID); err != nil {
		return StoredPlan{}, err
	}
	days, err := json.Marshal(plan.Days)
	if err != nil {
		return StoredPlan{}, err
	}
	out := StoredPlan{StartsOn: startsOn, Weeks: plan.Weeks, Days: plan.Days, Notes: plan.Notes}
	err = q.QueryRow(ctx, `INSERT INTO training_plans (user_id, starts_on, weeks, days, notes)
		VALUES ($1, $2::date, $3, $4, $5) RETURNING id`, userID, startsOn, plan.Weeks, days, plan.Notes).Scan(&out.ID)
	return out, err
}

// EndActivePlan ends the person's active plan, if any, and removes its sessions that were
// never started so a new plan can schedule those dates.
func EndActivePlan(ctx context.Context, q Querier, userID int64) error {
	if _, err := q.Exec(ctx, `DELETE FROM training_sessions s USING training_plans p
		WHERE s.plan_id = p.id AND p.user_id = $1 AND p.ended_at IS NULL AND s.completed_at IS NULL
		  AND NOT EXISTS (SELECT 1 FROM exercise_sets x WHERE x.session_id = s.id AND x.deleted_at IS NULL)`, userID); err != nil {
		return err
	}
	_, err := q.Exec(ctx, `UPDATE training_plans SET ended_at = now() WHERE user_id = $1 AND ended_at IS NULL`, userID)
	return err
}

// TrainingSession is one scheduled session.
type TrainingSession struct {
	ID          int64
	PlanID      int64
	LocalDate   score.Date
	DayIndex    int
	CompletedAt *time.Time
}

// SessionOn returns the person's session on a date, or ErrNotFound.
func SessionOn(ctx context.Context, q Querier, userID int64, date score.Date) (TrainingSession, error) {
	var s TrainingSession
	err := q.QueryRow(ctx, `SELECT id, plan_id, local_date::text, day_index, completed_at FROM training_sessions
		WHERE user_id = $1 AND local_date = $2::date`, userID, date).Scan(
		&s.ID, &s.PlanID, &s.LocalDate, &s.DayIndex, &s.CompletedAt)
	return s, notFound(err)
}

// EnsureSession creates the session of a date for a plan day, or returns the existing one.
func EnsureSession(ctx context.Context, q Querier, userID, planID int64, date score.Date, dayIndex int) (TrainingSession, error) {
	if _, err := q.Exec(ctx, `INSERT INTO training_sessions (user_id, plan_id, local_date, day_index)
		VALUES ($1, $2, $3::date, $4) ON CONFLICT (user_id, local_date) DO NOTHING`,
		userID, planID, date, dayIndex); err != nil {
		return TrainingSession{}, err
	}
	return SessionOn(ctx, q, userID, date)
}

// CompleteSession marks one of the person's sessions done and returns it.
func CompleteSession(ctx context.Context, q Querier, userID, id int64) (TrainingSession, error) {
	var s TrainingSession
	err := q.QueryRow(ctx, `UPDATE training_sessions SET completed_at = COALESCE(completed_at, now())
		WHERE id = $2 AND user_id = $1
		RETURNING id, plan_id, local_date::text, day_index, completed_at`, userID, id).Scan(
		&s.ID, &s.PlanID, &s.LocalDate, &s.DayIndex, &s.CompletedAt)
	return s, notFound(err)
}

// CompletedSessionLabel is the plan-day label of the day's completed session, or "" when the
// day has none. It feeds the strength quest.
func CompletedSessionLabel(ctx context.Context, q Querier, userID int64, date score.Date) (string, error) {
	var label string
	err := q.QueryRow(ctx, `SELECT COALESCE(p.days -> s.day_index ->> 'Label', 'Training')
		FROM training_sessions s JOIN training_plans p ON p.id = s.plan_id
		WHERE s.user_id = $1 AND s.local_date = $2::date AND s.completed_at IS NOT NULL`, userID, date).Scan(&label)
	if notFound(err) == ErrNotFound {
		return "", nil
	}
	return label, err
}

// ExerciseHistory returns, for each exercise key, the person's sets on the latest days before a
// date that logged it, newest day first, at most `days` days each. Days rather than sessions,
// so sets logged outside a plan still count toward progression.
func ExerciseHistory(ctx context.Context, q Querier, userID int64, keys []string, before score.Date, days int) (map[string][]training.SessionResult, error) {
	rows, err := q.Query(ctx, `
		WITH ranked AS (
			SELECT e.key, s.local_date, s.reps, s.seconds, s.load_kg::float8 AS load_kg, s.rir, s.logged_at, s.id,
			       dense_rank() OVER (PARTITION BY e.key ORDER BY s.local_date DESC) AS day_rank
			FROM exercise_sets s JOIN exercises e ON e.id = s.exercise_id
			WHERE s.user_id = $1 AND s.deleted_at IS NULL AND s.local_date < $2::date AND e.key = ANY($3)
		)
		SELECT key, local_date::text, reps, seconds, load_kg, rir FROM ranked
		WHERE day_rank <= $4 ORDER BY key, local_date DESC, logged_at, id`, userID, before, keys, days)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := map[string][]training.SessionResult{}
	var lastKey, lastDate string
	for rows.Next() {
		var (
			key, date    string
			repsN, secsN *int
			load         *float64
			rir          *int
		)
		if err := rows.Scan(&key, &date, &repsN, &secsN, &load, &rir); err != nil {
			return nil, err
		}
		if key != lastKey || date != lastDate {
			out[key] = append(out[key], training.SessionResult{Exercise: key})
			lastKey, lastDate = key, date
		}
		r := &out[key][len(out[key])-1]
		set := training.Set{Date: date}
		if repsN != nil {
			set.Reps = *repsN
		}
		if secsN != nil {
			set.Seconds = *secsN
		}
		if load != nil {
			set.LoadKg = *load
		}
		r.Sets = append(r.Sets, set)
		if rir != nil {
			r.RIRs = append(r.RIRs, *rir)
		} else {
			r.RIRs = append(r.RIRs, -1)
		}
	}
	return out, rows.Err()
}
