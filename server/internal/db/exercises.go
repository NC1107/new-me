package db

import (
	"context"
	"strconv"
	"time"

	"github.com/jackc/pgx/v5"

	"github.com/nc1107/new-me/server/internal/score"
	"github.com/nc1107/new-me/server/internal/training"
)

// Exercise measures and load types, mirroring the table checks.
const (
	MeasureReps    = "reps"
	MeasureSeconds = "seconds"
	LoadBodyweight = "bodyweight"
	LoadExternal   = "external"
)

// Exercise kinds. Stretches belong to mobility sessions and never to strength plans or counts.
const (
	KindStrength = "strength"
	KindStretch  = "stretch"
)

// Muscles and Equipment are the fixed vocabularies the exercises table accepts.
var (
	Muscles = []string{"chest", "back", "shoulders", "biceps", "triceps", "forearms",
		"quads", "hamstrings", "glutes", "calves", "core"}
	Equipment = []string{"pullup_bar", "dumbbells", "barbell", "bench", "bands", "dip_bars", "hangboard", "low_bar", "gym"}
)

// PushupKeys are the catalog exercises whose reps count toward the push-ups quest, so logging a
// set of incline push-ups moves the same quest as the original push-up log.
var PushupKeys = []string{"incline_push_up", "push_up", "decline_push_up"}

// Exercise is a catalog exercise (UserID nil) or one person's custom exercise.
type Exercise struct {
	ID               int64
	Key              string
	UserID           *int64
	Name             string
	PrimaryMuscles   []string
	SecondaryMuscles []string
	Measure          string
	Load             string
	Equipment        []string
	EasierKey        string
	HarderKey        string
	Position         int
	// Steps, Cues and Images are the how-to; Images holds embedded photo file names in order.
	Steps  []string
	Cues   []string
	Images []string
	// Kind is KindStrength or KindStretch; PerSide marks a stretch done once on each side.
	Kind    string
	PerSide bool
}

// Stretch reports whether the exercise is a stretch rather than a strength exercise.
func (e Exercise) Stretch() bool { return e.Kind == KindStretch }

// Custom reports whether the exercise belongs to a person rather than the catalog.
func (e Exercise) Custom() bool { return e.UserID != nil }

const exerciseColumns = `id, key, user_id, name, primary_muscles, secondary_muscles, measure, load,
	equipment, COALESCE(easier_key, ''), COALESCE(harder_key, ''), position, steps, cues, images, kind, per_side`

func scanExercise(row pgx.Row) (Exercise, error) {
	var e Exercise
	err := row.Scan(&e.ID, &e.Key, &e.UserID, &e.Name, &e.PrimaryMuscles, &e.SecondaryMuscles, &e.Measure,
		&e.Load, &e.Equipment, &e.EasierKey, &e.HarderKey, &e.Position, &e.Steps, &e.Cues, &e.Images, &e.Kind, &e.PerSide)
	return e, err
}

// ListExercises returns the catalog and the person's live custom exercises in catalog order,
// custom ones last.
func ListExercises(ctx context.Context, q Querier, userID int64) ([]Exercise, error) {
	rows, err := q.Query(ctx, `SELECT `+exerciseColumns+` FROM exercises
		WHERE deleted_at IS NULL AND (user_id IS NULL OR user_id = $1)
		ORDER BY (user_id IS NOT NULL), position, name`, userID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var out []Exercise
	for rows.Next() {
		e, err := scanExercise(rows)
		if err != nil {
			return nil, err
		}
		out = append(out, e)
	}
	return out, rows.Err()
}

// ExerciseByKey finds a live exercise the person may use: a catalog one or their own.
func ExerciseByKey(ctx context.Context, q Querier, userID int64, key string) (Exercise, error) {
	e, err := scanExercise(q.QueryRow(ctx, `SELECT `+exerciseColumns+` FROM exercises
		WHERE key = $1 AND deleted_at IS NULL AND (user_id IS NULL OR user_id = $2)`, key, userID))
	return e, notFound(err)
}

// ExerciseByID finds an exercise by id the person may see, including deleted custom ones, so
// sets logged before a delete still resolve.
func ExerciseByID(ctx context.Context, q Querier, userID, id int64) (Exercise, error) {
	e, err := scanExercise(q.QueryRow(ctx, `SELECT `+exerciseColumns+` FROM exercises
		WHERE id = $1 AND (user_id IS NULL OR user_id = $2)`, id, userID))
	return e, notFound(err)
}

// NewExercise is a custom exercise to create or the new values of one to update.
type NewExercise struct {
	Name             string
	PrimaryMuscles   []string
	SecondaryMuscles []string
	Measure          string
	Load             string
	Equipment        []string
}

// InsertCustomExercise creates a custom exercise under a generated key.
func InsertCustomExercise(ctx context.Context, q Querier, userID int64, n NewExercise) (Exercise, error) {
	return scanExercise(q.QueryRow(ctx, `
		INSERT INTO exercises (key, user_id, name, primary_muscles, secondary_muscles, measure, load, equipment, position)
		VALUES ('custom_' || $8::text || '_' || substr(md5(random()::text), 1, 10), $1, $2, $3, $4, $5, $6, $7, 1000)
		RETURNING `+exerciseColumns,
		userID, n.Name, n.PrimaryMuscles, n.SecondaryMuscles, n.Measure, n.Load, n.Equipment, strconv.FormatInt(userID, 10)))
}

// UpdateCustomExercise changes one of the person's live custom exercises.
func UpdateCustomExercise(ctx context.Context, q Querier, userID int64, key string, n NewExercise) (Exercise, error) {
	e, err := scanExercise(q.QueryRow(ctx, `
		UPDATE exercises SET name = $3, primary_muscles = $4, secondary_muscles = $5, measure = $6,
		       load = $7, equipment = $8
		WHERE key = $2 AND user_id = $1 AND deleted_at IS NULL
		RETURNING `+exerciseColumns,
		userID, key, n.Name, n.PrimaryMuscles, n.SecondaryMuscles, n.Measure, n.Load, n.Equipment))
	return e, notFound(err)
}

// DeleteCustomExercise hides one of the person's custom exercises; its sets stay.
func DeleteCustomExercise(ctx context.Context, q Querier, userID int64, key string) error {
	tag, err := q.Exec(ctx, `UPDATE exercises SET deleted_at = now()
		WHERE key = $2 AND user_id = $1 AND deleted_at IS NULL`, userID, key)
	if err != nil {
		return err
	}
	if tag.RowsAffected() == 0 {
		return ErrNotFound
	}
	return nil
}

// ExerciseSet is one logged set.
type ExerciseSet struct {
	ID          int64
	UserID      int64
	LocalDate   score.Date
	ExerciseID  int64
	ExerciseKey string
	Reps        *int
	Seconds     *int
	LoadKg      *float64
	RIR         *int
	SessionID   *int64
	ClientOpID  string
	LoggedAt    time.Time
	DeletedAt   *time.Time
}

const setColumns = `s.id, s.user_id, s.local_date::text, s.exercise_id, e.key, s.reps, s.seconds,
	s.load_kg::float8, s.rir, s.session_id, s.client_op_id::text, s.logged_at, s.deleted_at`

func scanSet(row pgx.Row) (ExerciseSet, error) {
	var s ExerciseSet
	err := row.Scan(&s.ID, &s.UserID, &s.LocalDate, &s.ExerciseID, &s.ExerciseKey, &s.Reps, &s.Seconds,
		&s.LoadKg, &s.RIR, &s.SessionID, &s.ClientOpID, &s.LoggedAt, &s.DeletedAt)
	return s, err
}

// NewExerciseSet is the input of InsertExerciseSet.
type NewExerciseSet struct {
	UserID     int64
	LocalDate  score.Date
	ExerciseID int64
	Reps       *int
	Seconds    *int
	LoadKg     *float64
	RIR        *int
	SessionID  *int64
	ClientOpID string
}

// InsertExerciseSet stores a set exactly once per (user, clientOpId); a replay returns the
// stored row with created=false, deleted or not, like InsertActivityLog.
func InsertExerciseSet(ctx context.Context, q Querier, n NewExerciseSet) (set ExerciseSet, created bool, err error) {
	var id int64
	err = q.QueryRow(ctx, `
		INSERT INTO exercise_sets (user_id, local_date, exercise_id, reps, seconds, load_kg, rir, session_id, client_op_id)
		VALUES ($1, $2::date, $3, $4, $5, $6, $7, $8, $9::uuid)
		ON CONFLICT (user_id, client_op_id) DO NOTHING
		RETURNING id`,
		n.UserID, n.LocalDate, n.ExerciseID, n.Reps, n.Seconds, n.LoadKg, n.RIR, n.SessionID, n.ClientOpID).Scan(&id)
	switch {
	case err == nil:
		created = true
	case notFound(err) == ErrNotFound:
		if err = q.QueryRow(ctx, `SELECT id FROM exercise_sets WHERE user_id = $1 AND client_op_id = $2::uuid`,
			n.UserID, n.ClientOpID).Scan(&id); err != nil {
			return set, false, err
		}
	default:
		return set, false, err
	}
	set, err = scanSet(q.QueryRow(ctx, `SELECT `+setColumns+`
		FROM exercise_sets s JOIN exercises e ON e.id = s.exercise_id WHERE s.id = $1`, id))
	return set, created, err
}

// SoftDeleteExerciseSet hides one of the person's sets and returns it.
func SoftDeleteExerciseSet(ctx context.Context, q Querier, userID, id int64) (ExerciseSet, error) {
	var setID int64
	err := q.QueryRow(ctx, `UPDATE exercise_sets SET deleted_at = now()
		WHERE id = $2 AND user_id = $1 AND deleted_at IS NULL RETURNING id`, userID, id).Scan(&setID)
	if err = notFound(err); err != nil {
		return ExerciseSet{}, err
	}
	return scanSet(q.QueryRow(ctx, `SELECT `+setColumns+`
		FROM exercise_sets s JOIN exercises e ON e.id = s.exercise_id WHERE s.id = $1`, setID))
}

// ListExerciseSets returns the person's live sets between two dates, oldest first, optionally
// for one exercise only (exerciseID 0 means all).
func ListExerciseSets(ctx context.Context, q Querier, userID int64, from, to score.Date, exerciseID int64) ([]ExerciseSet, error) {
	rows, err := q.Query(ctx, `SELECT `+setColumns+`
		FROM exercise_sets s JOIN exercises e ON e.id = s.exercise_id
		WHERE s.user_id = $1 AND s.deleted_at IS NULL AND s.local_date BETWEEN $2::date AND $3::date
		  AND ($4 = 0 OR s.exercise_id = $4)
		ORDER BY s.local_date, s.logged_at, s.id`, userID, from, to, exerciseID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var out []ExerciseSet
	for rows.Next() {
		s, err := scanSet(rows)
		if err != nil {
			return nil, err
		}
		out = append(out, s)
	}
	return out, rows.Err()
}

// PushupSetReps is the reps of the day's live sets of the push-up exercises, which count toward
// the push-ups quest alongside push-up activity logs.
func PushupSetReps(ctx context.Context, q Querier, userID int64, date score.Date) (int, error) {
	var reps int
	err := q.QueryRow(ctx, `SELECT COALESCE(sum(s.reps), 0)::int
		FROM exercise_sets s JOIN exercises e ON e.id = s.exercise_id
		WHERE s.user_id = $1 AND s.local_date = $2::date AND s.deleted_at IS NULL AND e.key = ANY($3)`,
		userID, date, PushupKeys).Scan(&reps)
	return reps, err
}

// MaxTest is one recorded max test.
type MaxTest struct {
	ExerciseID int64
	LocalDate  score.Date
	Reps       *int
	Seconds    *int
}

// UpsertMaxTest records a max test, replacing one already recorded that day for the exercise.
func UpsertMaxTest(ctx context.Context, q Querier, userID int64, t MaxTest) error {
	_, err := q.Exec(ctx, `
		INSERT INTO exercise_max_tests (user_id, exercise_id, local_date, reps, seconds)
		VALUES ($1, $2, $3::date, $4, $5)
		ON CONFLICT (user_id, exercise_id, local_date) DO UPDATE SET reps = EXCLUDED.reps,
			seconds = EXCLUDED.seconds, created_at = now()`,
		userID, t.ExerciseID, t.LocalDate, t.Reps, t.Seconds)
	return err
}

// LatestMaxTests returns the newest max test of each exercise the person has tested.
func LatestMaxTests(ctx context.Context, q Querier, userID int64) (map[int64]MaxTest, error) {
	rows, err := q.Query(ctx, `
		SELECT DISTINCT ON (exercise_id) exercise_id, local_date::text, reps, seconds
		FROM exercise_max_tests WHERE user_id = $1
		ORDER BY exercise_id, local_date DESC`, userID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := map[int64]MaxTest{}
	for rows.Next() {
		var t MaxTest
		if err := rows.Scan(&t.ExerciseID, &t.LocalDate, &t.Reps, &t.Seconds); err != nil {
			return nil, err
		}
		out[t.ExerciseID] = t
	}
	return out, rows.Err()
}

// LiftSet is a logged set with what a look-back needs about its exercise.
type LiftSet struct {
	Key    string
	Name   string
	Loaded bool
	training.Set
}

// LiftSetsThrough returns every live set of the person up to a date, oldest first, for the
// exercises logged between from and to. Look-backs compare a month's best with the best of the
// first month each exercise was logged.
func LiftSetsThrough(ctx context.Context, q Querier, userID int64, from, to score.Date) ([]LiftSet, error) {
	rows, err := q.Query(ctx, `
		SELECT e.key, e.name, e.load = 'external', s.local_date::text, COALESCE(s.reps, 0), COALESCE(s.seconds, 0),
		       COALESCE(s.load_kg::float8, 0)
		FROM exercise_sets s JOIN exercises e ON e.id = s.exercise_id
		WHERE s.user_id = $1 AND s.deleted_at IS NULL AND s.local_date <= $3::date
		  AND s.exercise_id IN (SELECT exercise_id FROM exercise_sets
		                        WHERE user_id = $1 AND deleted_at IS NULL AND local_date BETWEEN $2::date AND $3::date)
		ORDER BY s.local_date, s.id`, userID, from, to)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var out []LiftSet
	for rows.Next() {
		var l LiftSet
		if err := rows.Scan(&l.Key, &l.Name, &l.Loaded, &l.Date, &l.Reps, &l.Seconds, &l.LoadKg); err != nil {
			return nil, err
		}
		out = append(out, l)
	}
	return out, rows.Err()
}
