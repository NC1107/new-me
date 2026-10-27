package db

import (
	"context"

	"github.com/nc1107/new-me/server/internal/score"
)

// Quest keys and the activity types and health metrics that feed them.
const (
	QuestSteps       = "steps"
	QuestPushups     = "pushups"
	QuestReading     = "reading"
	QuestMealsLogged = "meals_logged"
	QuestProtein     = "protein"
	QuestYoga        = "yoga"
	QuestExercise    = "exercise"
	QuestSleep       = "sleep"

	ActivityPushups        = "pushups"
	ActivityReadingMinutes = "reading_minutes"
	ActivityReadingPages   = "reading_pages"
	ActivityYogaMinutes    = "yoga_minutes"
	ActivityOtherMinutes   = "other_minutes"

	MetricSteps        = "steps"
	MetricActiveEnergy = "active_energy"
	MetricExercise     = "exercise_minutes"
	MetricSleep        = "sleep_minutes"
	MetricWeight       = "weight_kg"
)

// DefaultProteinTarget is the protein goal snapshotted until the user sets their own.
const DefaultProteinTarget = 100

// QuestTemplate is a user's standing definition of one quest. Points are fixed at creation.
// TargetAlt and UnitAlt are the second target of the reading quest, in pages.
type QuestTemplate struct {
	Key       string
	Target    int
	Unit      string
	TargetAlt *int
	UnitAlt   *string
	Points    int
	Enabled   bool
	Position  int
}

// DayQuest is one quest as snapshotted for a local day.
type DayQuest struct {
	Key       string
	Target    int
	Unit      string
	TargetAlt *int
	UnitAlt   *string
	Points    int
	Position  int
}

func intPtr(n int) *int { return &n }

func strPtr(s string) *string { return &s }

// DefaultTemplates are the quests every new user starts with. Yoga ships disabled; exercise and
// sleep are on because Health-fed quests stay out of the day until their data arrives.
func DefaultTemplates() []QuestTemplate {
	return []QuestTemplate{
		{Key: QuestSteps, Target: 8000, Unit: "steps", Points: 100, Enabled: true, Position: 0},
		{Key: QuestPushups, Target: 30, Unit: "reps", Points: 100, Enabled: true, Position: 1},
		{Key: QuestReading, Target: 20, Unit: "minutes", TargetAlt: intPtr(15), UnitAlt: strPtr("pages"),
			Points: 100, Enabled: true, Position: 2},
		{Key: QuestMealsLogged, Target: 2, Unit: "meals", Points: 50, Enabled: true, Position: 3},
		{Key: QuestProtein, Target: DefaultProteinTarget, Unit: "g", Points: 50, Enabled: true, Position: 4},
		{Key: QuestYoga, Target: 20, Unit: "minutes", Points: 50, Enabled: false, Position: 5},
		{Key: QuestExercise, Target: 30, Unit: "min", Points: 100, Enabled: true, Position: 6},
		{Key: QuestSleep, Target: 420, Unit: "min", Points: 50, Enabled: true, Position: 7},
	}
}

// SeedDefaultTemplates gives a new user the default quests, leaving existing rows alone.
func SeedDefaultTemplates(ctx context.Context, q Querier, userID int64) error {
	for _, t := range DefaultTemplates() {
		if _, err := q.Exec(ctx, `
			INSERT INTO quest_templates (user_id, key, target, unit, target_alt, unit_alt, points, enabled, position)
			VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)
			ON CONFLICT (user_id, key) DO NOTHING`,
			userID, t.Key, t.Target, t.Unit, t.TargetAlt, t.UnitAlt, t.Points, t.Enabled, t.Position); err != nil {
			return err
		}
	}
	return nil
}

// GetQuestTemplates lists a user's templates in display order.
func GetQuestTemplates(ctx context.Context, q Querier, userID int64) ([]QuestTemplate, error) {
	rows, err := q.Query(ctx, `
		SELECT key, target, unit, target_alt, unit_alt, points, enabled, position
		FROM quest_templates WHERE user_id = $1 ORDER BY position, id`, userID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var out []QuestTemplate
	for rows.Next() {
		var t QuestTemplate
		if err := rows.Scan(&t.Key, &t.Target, &t.Unit, &t.TargetAlt, &t.UnitAlt, &t.Points,
			&t.Enabled, &t.Position); err != nil {
			return nil, err
		}
		out = append(out, t)
	}
	return out, rows.Err()
}

// UpsertQuestTemplate changes the editable parts of a template (enabled and the targets),
// creating it if missing. Points and units never change after creation.
func UpsertQuestTemplate(ctx context.Context, q Querier, userID int64, t QuestTemplate) error {
	_, err := q.Exec(ctx, `
		INSERT INTO quest_templates (user_id, key, target, unit, target_alt, unit_alt, points, enabled, position)
		VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)
		ON CONFLICT (user_id, key) DO UPDATE
		SET target = EXCLUDED.target, target_alt = EXCLUDED.target_alt, enabled = EXCLUDED.enabled`,
		userID, t.Key, t.Target, t.Unit, t.TargetAlt, t.UnitAlt, t.Points, t.Enabled, t.Position)
	return err
}

// EnsureSnapshot freezes the user's enabled templates into day_quests for the date, once. A day
// that already has quests, or has been scored, is left exactly as it is, so a template that is
// enabled or edited later applies from the next day instead of joining a day in progress.
// Protein follows the profile target, and for a person who has not set one and was given the
// per-kilogram default, 1.6 g/kg of the latest weight on or before the date.
func EnsureSnapshot(ctx context.Context, q Querier, userID int64, date score.Date) error {
	_, err := q.Exec(ctx, `
		INSERT INTO day_quests (user_id, local_date, key, target, unit, target_alt, unit_alt, points, position)
		SELECT t.user_id, $2::date, t.key,
		       CASE WHEN t.key = 'protein' THEN COALESCE(u.protein_target,
		           CASE WHEN u.protein_auto THEN (
		               SELECT (round((h.value * $3 / 5)::numeric) * 5)::int FROM health_daily h
		               WHERE h.user_id = t.user_id AND h.metric = 'weight_kg' AND h.local_date <= $2::date
		               ORDER BY h.local_date DESC LIMIT 1) END,
		           t.target) ELSE t.target END,
		       t.unit, t.target_alt, t.unit_alt, t.points, t.position
		FROM quest_templates t JOIN users u ON u.id = t.user_id
		WHERE t.user_id = $1 AND t.enabled
		  AND NOT EXISTS (SELECT 1 FROM day_quests d WHERE d.user_id = $1 AND d.local_date = $2::date)
		  AND NOT EXISTS (SELECT 1 FROM day_scores s WHERE s.user_id = $1 AND s.local_date = $2::date)
		ON CONFLICT (user_id, local_date, key) DO NOTHING`, userID, date, score.ProteinPerKg)
	return err
}

// ResetDaySnapshot drops the date's frozen quests and stored score so the next scoring
// snapshots the templates afresh. The caller holds the day lock and rescores in the same
// transaction; logs and Health readings are keyed by date and are untouched.
func ResetDaySnapshot(ctx context.Context, q Querier, userID int64, date score.Date) error {
	if _, err := q.Exec(ctx, `DELETE FROM day_quests WHERE user_id = $1 AND local_date = $2::date`, userID, date); err != nil {
		return err
	}
	_, err := q.Exec(ctx, `DELETE FROM day_scores WHERE user_id = $1 AND local_date = $2::date`, userID, date)
	return err
}

// GetDayQuests returns the date's snapshot in display order.
func GetDayQuests(ctx context.Context, q Querier, userID int64, date score.Date) ([]DayQuest, error) {
	rows, err := q.Query(ctx, `
		SELECT key, target, unit, target_alt, unit_alt, points, position
		FROM day_quests WHERE user_id = $1 AND local_date = $2::date ORDER BY position, id`, userID, date)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var out []DayQuest
	for rows.Next() {
		var d DayQuest
		if err := rows.Scan(&d.Key, &d.Target, &d.Unit, &d.TargetAlt, &d.UnitAlt, &d.Points, &d.Position); err != nil {
			return nil, err
		}
		out = append(out, d)
	}
	return out, rows.Err()
}
