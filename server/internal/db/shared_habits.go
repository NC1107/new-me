package db

import (
	"context"
	"time"

	"github.com/jackc/pgx/v5"

	"github.com/nc1107/new-me/server/internal/score"
)

// MaxSharedHabits is how many live shared habits the pair may have.
const MaxSharedHabits = 40

// SharedHabit is a household chore both people see. Weekdays is the mask from score.WeekdayBit
// and is meaningful for the weekdays kind only; EveryDays for every_n only.
type SharedHabit struct {
	ID        int64
	Name      string
	Icon      string
	Kind      string
	Weekdays  int
	EveryDays *int
	StartOn   score.Date
	CreatedBy int64
	CreatedAt time.Time
}

// Schedule is the habit's schedule for the due-date rules.
func (h SharedHabit) Schedule() score.SharedSchedule {
	s := score.SharedSchedule{Kind: h.Kind, Weekdays: h.Weekdays}
	if h.EveryDays != nil {
		s.EveryDays = *h.EveryDays
	}
	return s
}

// SharedMark is one time a chore was done. LocalDate is the doer's own day.
type SharedMark struct {
	ID            int64
	SharedHabitID int64
	UserID        int64
	LocalDate     score.Date
	DoneAt        time.Time
	Points        int
}

const sharedHabitColumns = `id, name, icon, schedule_kind, weekdays, every_days, start_on::text, created_by, created_at`

func scanSharedHabit(row pgx.Row) (SharedHabit, error) {
	var h SharedHabit
	err := row.Scan(&h.ID, &h.Name, &h.Icon, &h.Kind, &h.Weekdays, &h.EveryDays, &h.StartOn, &h.CreatedBy, &h.CreatedAt)
	return h, err
}

const sharedMarkColumns = `id, shared_habit_id, user_id, local_date::text, done_at, points`

func scanSharedMark(row pgx.Row) (SharedMark, error) {
	var m SharedMark
	err := row.Scan(&m.ID, &m.SharedHabitID, &m.UserID, &m.LocalDate, &m.DoneAt, &m.Points)
	return m, err
}

// LockSharedHabits serializes the writers of the shared list, so the cap holds when two creates
// race. The lock is shared by both people on purpose.
func LockSharedHabits(ctx context.Context, tx pgx.Tx) error {
	_, err := tx.Exec(ctx, `SELECT pg_advisory_xact_lock(hashtext('shared_habits'))`)
	return err
}

// CountSharedHabits is how many live shared habits exist.
func CountSharedHabits(ctx context.Context, q Querier) (int, error) {
	var n int
	err := q.QueryRow(ctx, `SELECT count(*)::int FROM shared_habits WHERE deleted_at IS NULL`).Scan(&n)
	return n, err
}

// CreateSharedHabit adds a shared habit.
func CreateSharedHabit(ctx context.Context, q Querier, h SharedHabit) (SharedHabit, error) {
	return scanSharedHabit(q.QueryRow(ctx, `
		INSERT INTO shared_habits (name, icon, schedule_kind, weekdays, every_days, start_on, created_by)
		VALUES ($1, $2, $3, $4, $5, $6::date, $7)
		RETURNING `+sharedHabitColumns, h.Name, h.Icon, h.Kind, h.Weekdays, h.EveryDays, h.StartOn, h.CreatedBy))
}

// GetSharedHabit reads one live shared habit. With lock it holds the row until the transaction
// ends, which is what makes "done once a day" hold when both people tap at once.
func GetSharedHabit(ctx context.Context, q Querier, id int64, lock bool) (SharedHabit, error) {
	sql := `SELECT ` + sharedHabitColumns + ` FROM shared_habits WHERE id = $1 AND deleted_at IS NULL`
	if lock {
		sql += ` FOR UPDATE`
	}
	h, err := scanSharedHabit(q.QueryRow(ctx, sql, id))
	return h, notFound(err)
}

// ListSharedHabits returns the live shared habits, oldest first.
func ListSharedHabits(ctx context.Context, q Querier) ([]SharedHabit, error) {
	rows, err := q.Query(ctx, `SELECT `+sharedHabitColumns+` FROM shared_habits WHERE deleted_at IS NULL ORDER BY id`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := []SharedHabit{}
	for rows.Next() {
		h, err := scanSharedHabit(rows)
		if err != nil {
			return nil, err
		}
		out = append(out, h)
	}
	return out, rows.Err()
}

// UpdateSharedHabit writes back the editable parts of a shared habit.
func UpdateSharedHabit(ctx context.Context, q Querier, h SharedHabit) (SharedHabit, error) {
	updated, err := scanSharedHabit(q.QueryRow(ctx, `
		UPDATE shared_habits SET name = $2, icon = $3, schedule_kind = $4, weekdays = $5, every_days = $6
		WHERE id = $1 AND deleted_at IS NULL
		RETURNING `+sharedHabitColumns, h.ID, h.Name, h.Icon, h.Kind, h.Weekdays, h.EveryDays))
	return updated, notFound(err)
}

// SoftDeleteSharedHabit hides a shared habit and keeps its marks, and so the gems already earned.
func SoftDeleteSharedHabit(ctx context.Context, q Querier, id int64) error {
	tag, err := q.Exec(ctx, `UPDATE shared_habits SET deleted_at = now() WHERE id = $1 AND deleted_at IS NULL`, id)
	if err != nil {
		return err
	}
	if tag.RowsAffected() == 0 {
		return ErrNotFound
	}
	return nil
}

// LastSharedMarks is the most recent mark of every live shared habit, by habit id.
func LastSharedMarks(ctx context.Context, q Querier) (map[int64]SharedMark, error) {
	rows, err := q.Query(ctx, `
		SELECT DISTINCT ON (m.shared_habit_id) m.id, m.shared_habit_id, m.user_id, m.local_date::text, m.done_at, m.points
		FROM shared_habit_marks m JOIN shared_habits h ON h.id = m.shared_habit_id AND h.deleted_at IS NULL
		ORDER BY m.shared_habit_id, m.done_at DESC, m.id DESC`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := map[int64]SharedMark{}
	for rows.Next() {
		m, err := scanSharedMark(rows)
		if err != nil {
			return nil, err
		}
		out[m.SharedHabitID] = m
	}
	return out, rows.Err()
}

// InsertSharedMark records that a person did a chore.
func InsertSharedMark(ctx context.Context, q Querier, m SharedMark) (SharedMark, error) {
	return scanSharedMark(q.QueryRow(ctx, `
		INSERT INTO shared_habit_marks (shared_habit_id, user_id, local_date, done_at, points)
		VALUES ($1, $2, $3::date, $4, $5) RETURNING `+sharedMarkColumns,
		m.SharedHabitID, m.UserID, m.LocalDate, m.DoneAt, m.Points))
}

// DeleteSharedMark removes one mark, and the gems it earned with it.
func DeleteSharedMark(ctx context.Context, q Querier, id int64) error {
	_, err := q.Exec(ctx, `DELETE FROM shared_habit_marks WHERE id = $1`, id)
	return err
}

// PeekLastSharedMark reads the chore's latest mark without removing it.
func PeekLastSharedMark(ctx context.Context, q Querier, habitID int64) (SharedMark, error) {
	m, err := scanSharedMark(q.QueryRow(ctx, `
		SELECT `+sharedMarkColumns+` FROM shared_habit_marks WHERE shared_habit_id = $1
		ORDER BY done_at DESC, id DESC LIMIT 1`, habitID))
	return m, notFound(err)
}

// SharedBonus is the gems the person earned from shared habits on a local day.
func SharedBonus(ctx context.Context, q Querier, userID int64, date score.Date) (int, error) {
	var points int
	err := q.QueryRow(ctx, `
		SELECT COALESCE(sum(points), 0)::int FROM shared_habit_marks WHERE user_id = $1 AND local_date = $2::date`,
		userID, date).Scan(&points)
	return points, err
}
