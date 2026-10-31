package db

import (
	"context"
	"time"

	"github.com/jackc/pgx/v5"

	"github.com/nc1107/new-me/server/internal/score"
)

// ActivityLog is one manual activity entry. Quantity is reps, minutes or pages by Type.
type ActivityLog struct {
	ID         int64
	UserID     int64
	LocalDate  score.Date
	Type       string
	Quantity   int
	ClientOpID string
	LoggedAt   time.Time
	UpdatedAt  time.Time
	DeletedAt  *time.Time
	// Name and Intensity describe an "other" activity and are empty for every other type.
	Name      string
	Intensity string
}

// MealLog is one meal entry with its macros in grams.
type MealLog struct {
	ID         int64
	UserID     int64
	LocalDate  score.Date
	Name       string
	Kcal       int
	ProteinG   float64
	CarbsG     float64
	FatG       float64
	FiberG     float64
	ClientOpID string
	LoggedAt   time.Time
	UpdatedAt  time.Time
	DeletedAt  *time.Time
}

const activityColumns = `id, user_id, local_date::text, type, quantity, client_op_id::text,
	logged_at, updated_at, deleted_at, COALESCE(name, ''), COALESCE(intensity, '')`

const mealColumns = `id, user_id, local_date::text, name, kcal, protein_g::float8, carbs_g::float8,
	fat_g::float8, fiber_g::float8, client_op_id::text, logged_at, updated_at, deleted_at`

func scanActivity(row pgx.Row) (ActivityLog, error) {
	var l ActivityLog
	err := row.Scan(&l.ID, &l.UserID, &l.LocalDate, &l.Type, &l.Quantity, &l.ClientOpID,
		&l.LoggedAt, &l.UpdatedAt, &l.DeletedAt, &l.Name, &l.Intensity)
	return l, err
}

func scanMeal(row pgx.Row) (MealLog, error) {
	var l MealLog
	err := row.Scan(&l.ID, &l.UserID, &l.LocalDate, &l.Name, &l.Kcal, &l.ProteinG, &l.CarbsG,
		&l.FatG, &l.FiberG, &l.ClientOpID, &l.LoggedAt, &l.UpdatedAt, &l.DeletedAt)
	return l, err
}

// NewActivityLog is the input of InsertActivityLog.
type NewActivityLog struct {
	UserID     int64
	LocalDate  score.Date
	Type       string
	Quantity   int
	ClientOpID string
	// Name and Intensity are set for the "other" type only.
	Name      string
	Intensity string
}

// InsertActivityLog stores an entry exactly once per (user, clientOpId). On a replay it
// returns the stored row with created=false, including one that has since been deleted, so a
// retry can never undelete.
func InsertActivityLog(ctx context.Context, q Querier, n NewActivityLog) (log ActivityLog, created bool, err error) {
	log, err = scanActivity(q.QueryRow(ctx, `
		INSERT INTO activity_logs (user_id, local_date, type, quantity, client_op_id, name, intensity)
		VALUES ($1, $2::date, $3, $4, $5::uuid, NULLIF($6, ''), NULLIF($7, ''))
		ON CONFLICT (user_id, client_op_id) DO NOTHING
		RETURNING `+activityColumns, n.UserID, n.LocalDate, n.Type, n.Quantity, n.ClientOpID, n.Name, n.Intensity))
	if err == nil {
		return log, true, nil
	}
	if notFound(err) != ErrNotFound {
		return log, false, err
	}
	log, err = scanActivity(q.QueryRow(ctx,
		`SELECT `+activityColumns+` FROM activity_logs WHERE user_id = $1 AND client_op_id = $2::uuid`,
		n.UserID, n.ClientOpID))
	return log, false, err
}

// NewMealLog is the input of InsertMealLog.
type NewMealLog struct {
	UserID     int64
	LocalDate  score.Date
	Name       string
	Kcal       int
	ProteinG   float64
	CarbsG     float64
	FatG       float64
	FiberG     float64
	ClientOpID string
}

// InsertMealLog stores a meal exactly once per (user, clientOpId), replaying like
// InsertActivityLog.
func InsertMealLog(ctx context.Context, q Querier, n NewMealLog) (log MealLog, created bool, err error) {
	log, err = scanMeal(q.QueryRow(ctx, `
		INSERT INTO meal_logs (user_id, local_date, name, kcal, protein_g, carbs_g, fat_g, fiber_g, client_op_id)
		VALUES ($1, $2::date, $3, $4, $5, $6, $7, $8, $9::uuid)
		ON CONFLICT (user_id, client_op_id) DO NOTHING
		RETURNING `+mealColumns,
		n.UserID, n.LocalDate, n.Name, n.Kcal, n.ProteinG, n.CarbsG, n.FatG, n.FiberG, n.ClientOpID))
	if err == nil {
		return log, true, nil
	}
	if notFound(err) != ErrNotFound {
		return log, false, err
	}
	log, err = scanMeal(q.QueryRow(ctx,
		`SELECT `+mealColumns+` FROM meal_logs WHERE user_id = $1 AND client_op_id = $2::uuid`,
		n.UserID, n.ClientOpID))
	return log, false, err
}

// MealPatch lists the fields of a meal to change; nil leaves a field as it is.
type MealPatch struct {
	Name     *string
	Kcal     *int
	ProteinG *float64
	CarbsG   *float64
	FatG     *float64
	FiberG   *float64

	// LoggedAt moves the meal to another moment, and LocalDate is that moment's day for the user.
	LoggedAt  *time.Time
	LocalDate *score.Date
}

// MealLocalDate is the day of the user's live meal, or ErrNotFound.
func MealLocalDate(ctx context.Context, q Querier, userID, id int64) (score.Date, error) {
	var d score.Date
	err := q.QueryRow(ctx, `
		SELECT local_date::text FROM meal_logs WHERE id = $1 AND user_id = $2 AND deleted_at IS NULL`,
		id, userID).Scan(&d)
	return d, notFound(err)
}

// UpdateMealLog changes the user's live meal and returns it. A meal that is deleted, missing or
// someone else's is ErrNotFound.
func UpdateMealLog(ctx context.Context, q Querier, userID, id int64, p MealPatch) (MealLog, error) {
	l, err := scanMeal(q.QueryRow(ctx, `
		UPDATE meal_logs SET
			name = COALESCE($3, name),
			kcal = COALESCE($4, kcal),
			protein_g = COALESCE($5, protein_g),
			carbs_g = COALESCE($6, carbs_g),
			fat_g = COALESCE($7, fat_g),
			fiber_g = COALESCE($8, fiber_g),
			logged_at = COALESCE($9, logged_at),
			local_date = COALESCE($10::date, local_date),
			updated_at = now()
		WHERE id = $1 AND user_id = $2 AND deleted_at IS NULL
		RETURNING `+mealColumns, id, userID, p.Name, p.Kcal, p.ProteinG, p.CarbsG, p.FatG, p.FiberG, p.LoggedAt, p.LocalDate))
	return l, notFound(err)
}

// ActivityLogExists reports whether the user has a live activity entry with this id.
func ActivityLogExists(ctx context.Context, q Querier, userID, id int64) (bool, error) {
	var exists bool
	err := q.QueryRow(ctx, `
		SELECT EXISTS (SELECT 1 FROM activity_logs WHERE id = $1 AND user_id = $2 AND deleted_at IS NULL)`,
		id, userID).Scan(&exists)
	return exists, err
}

// ListActivityLogs returns the user's live activity entries for a date, oldest first.
func ListActivityLogs(ctx context.Context, q Querier, userID int64, date score.Date) ([]ActivityLog, error) {
	rows, err := q.Query(ctx, `
		SELECT `+activityColumns+` FROM activity_logs
		WHERE user_id = $1 AND local_date = $2::date AND deleted_at IS NULL
		ORDER BY logged_at, id`, userID, date)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var out []ActivityLog
	for rows.Next() {
		l, err := scanActivity(rows)
		if err != nil {
			return nil, err
		}
		out = append(out, l)
	}
	return out, rows.Err()
}

// ListMealLogs returns the user's live meals for a date, oldest first.
func ListMealLogs(ctx context.Context, q Querier, userID int64, date score.Date) ([]MealLog, error) {
	rows, err := q.Query(ctx, `
		SELECT `+mealColumns+` FROM meal_logs
		WHERE user_id = $1 AND local_date = $2::date AND deleted_at IS NULL
		ORDER BY logged_at, id`, userID, date)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var out []MealLog
	for rows.Next() {
		l, err := scanMeal(rows)
		if err != nil {
			return nil, err
		}
		out = append(out, l)
	}
	return out, rows.Err()
}

// DeletedLog says which day a soft delete touched, so the caller can rescore it.
type DeletedLog struct {
	Kind      string
	LocalDate score.Date
}

// Log kinds as they appear in DeletedLog and on the wire.
const (
	KindActivity = "activity"
	KindMeal     = "meal"
)

// SoftDeleteLog hides the user's live entry with this id, whichever table holds it. Activity
// and meal ids come from one sequence, so the id alone is unambiguous.
func SoftDeleteLog(ctx context.Context, q Querier, userID, id int64) (DeletedLog, error) {
	for _, table := range []struct{ name, kind string }{
		{"activity_logs", KindActivity},
		{"meal_logs", KindMeal},
	} {
		var date score.Date
		err := q.QueryRow(ctx, `
			UPDATE `+table.name+` SET deleted_at = now(), updated_at = now()
			WHERE id = $1 AND user_id = $2 AND deleted_at IS NULL
			RETURNING local_date::text`, id, userID).Scan(&date)
		if err == nil {
			return DeletedLog{Kind: table.kind, LocalDate: date}, nil
		}
		if notFound(err) != ErrNotFound {
			return DeletedLog{}, err
		}
	}
	return DeletedLog{}, ErrNotFound
}

// RecentMeals returns the newest distinct meals logged by anyone, so one person can repeat what
// the other entered. Distinct means the same name (ignoring case) and the same numbers.
func RecentMeals(ctx context.Context, q Querier, limit int) ([]MealLog, error) {
	rows, err := q.Query(ctx, `
		SELECT `+mealColumns+` FROM (
			SELECT DISTINCT ON (lower(name), kcal, protein_g, carbs_g, fat_g) *
			FROM meal_logs WHERE deleted_at IS NULL
			ORDER BY lower(name), kcal, protein_g, carbs_g, fat_g, logged_at DESC, id DESC
		) m ORDER BY logged_at DESC, id DESC LIMIT $1`, limit)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var out []MealLog
	for rows.Next() {
		l, err := scanMeal(rows)
		if err != nil {
			return nil, err
		}
		out = append(out, l)
	}
	return out, rows.Err()
}
