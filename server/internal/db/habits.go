package db

import (
	"context"
	"encoding/json"
	"time"

	"github.com/jackc/pgx/v5"

	"github.com/nc1107/new-me/server/internal/score"
)

// Habit kinds.
const (
	HabitCheck = "check"
	HabitCount = "count"
)

// MaxHabits is how many live habits one person may have.
const MaxHabits = 30

// HabitSlot is one time of day a check habit is done. Time is "HH:MM" or nil.
type HabitSlot struct {
	Label string  `json:"label"`
	Time  *string `json:"time"`
}

// Habit is a person's habit with its schedule. Weekdays is the mask from score.WeekdayBit.
type Habit struct {
	ID       int64
	UserID   int64
	Name     string
	Icon     string
	Kind     string
	Weekdays int
	Slots    []HabitSlot
	Target   *int
	Position int
	Paused   bool
	// Points is the habit's worth toward the daily goal.
	Points int
	// Minutes is how long the habit takes; nil when it is only tracked or predates v11.
	Minutes *int
	// ProposedPoints is non-nil while the partner has a change to approve. ProposedMinutes is
	// the minutes it came from, nil when it proposes only tracking.
	ProposedPoints  *int
	ProposedMinutes *int
	ProposedAt      *time.Time
	CreatedAt       time.Time
}

const habitColumns = `id, user_id, name, icon, kind, weekdays, slots, target, position, paused, points, minutes, proposed_points, proposed_minutes, proposed_at, created_at`

func scanHabit(row pgx.Row) (Habit, error) {
	var h Habit
	var slots []byte
	err := row.Scan(&h.ID, &h.UserID, &h.Name, &h.Icon, &h.Kind, &h.Weekdays, &slots, &h.Target,
		&h.Position, &h.Paused, &h.Points, &h.Minutes, &h.ProposedPoints, &h.ProposedMinutes, &h.ProposedAt, &h.CreatedAt)
	if err != nil {
		return h, err
	}
	if err := json.Unmarshal(slots, &h.Slots); err != nil {
		return h, err
	}
	if h.Slots == nil {
		h.Slots = []HabitSlot{}
	}
	return h, nil
}

// LockHabits serializes the writers of one person's habit list, so the habit cap holds when
// two creates race.
func LockHabits(ctx context.Context, tx pgx.Tx, userID int64) error {
	_, err := tx.Exec(ctx, `SELECT 1 FROM users WHERE id = $1 FOR UPDATE`, userID)
	return err
}

// CountHabits is how many live habits the person has.
func CountHabits(ctx context.Context, q Querier, userID int64) (int, error) {
	var n int
	err := q.QueryRow(ctx,
		`SELECT count(*)::int FROM habits WHERE user_id = $1 AND deleted_at IS NULL`, userID).Scan(&n)
	return n, err
}

// CreateHabit appends a habit after the person's last one.
func CreateHabit(ctx context.Context, q Querier, h Habit) (Habit, error) {
	slots, err := json.Marshal(h.Slots)
	if err != nil {
		return Habit{}, err
	}
	return scanHabit(q.QueryRow(ctx, `
		INSERT INTO habits (user_id, name, icon, kind, weekdays, slots, target, points, minutes,
		                    proposed_points, proposed_minutes, proposed_at, position)
		VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12,
		        COALESCE((SELECT max(position) + 1 FROM habits WHERE user_id = $1 AND deleted_at IS NULL), 0))
		RETURNING `+habitColumns, h.UserID, h.Name, h.Icon, h.Kind, h.Weekdays, slots, h.Target, h.Points,
		h.Minutes, h.ProposedPoints, h.ProposedMinutes, h.ProposedAt))
}

// GetHabit reads one live habit of the person.
func GetHabit(ctx context.Context, q Querier, userID, id int64) (Habit, error) {
	h, err := scanHabit(q.QueryRow(ctx,
		`SELECT `+habitColumns+` FROM habits WHERE id = $1 AND user_id = $2 AND deleted_at IS NULL`, id, userID))
	return h, notFound(err)
}

// ListHabits returns the person's live habits in their order, paused ones included.
func ListHabits(ctx context.Context, q Querier, userID int64) ([]Habit, error) {
	rows, err := q.Query(ctx, `
		SELECT `+habitColumns+` FROM habits
		WHERE user_id = $1 AND deleted_at IS NULL ORDER BY position, id`, userID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := []Habit{}
	for rows.Next() {
		h, err := scanHabit(rows)
		if err != nil {
			return nil, err
		}
		out = append(out, h)
	}
	return out, rows.Err()
}

// UpdateHabit writes back the editable parts of a habit. The kind never changes.
func UpdateHabit(ctx context.Context, q Querier, h Habit) (Habit, error) {
	slots, err := json.Marshal(h.Slots)
	if err != nil {
		return Habit{}, err
	}
	updated, err := scanHabit(q.QueryRow(ctx, `
		UPDATE habits SET name = $3, icon = $4, weekdays = $5, slots = $6, target = $7, paused = $8, points = $9, minutes = $10,
		                  proposed_points = $11, proposed_minutes = $12, proposed_at = $13
		WHERE id = $1 AND user_id = $2 AND deleted_at IS NULL
		RETURNING `+habitColumns, h.ID, h.UserID, h.Name, h.Icon, h.Weekdays, slots, h.Target, h.Paused, h.Points,
		h.Minutes, h.ProposedPoints, h.ProposedMinutes, h.ProposedAt))
	return updated, notFound(err)
}

// SoftDeleteHabit hides a habit and keeps its marks.
func SoftDeleteHabit(ctx context.Context, q Querier, userID, id int64) error {
	tag, err := q.Exec(ctx,
		`UPDATE habits SET deleted_at = now() WHERE id = $1 AND user_id = $2 AND deleted_at IS NULL`, id, userID)
	if err != nil {
		return err
	}
	if tag.RowsAffected() == 0 {
		return ErrNotFound
	}
	return nil
}

// SetHabitOrder numbers the given habit ids 0..n-1 in the order given.
func SetHabitOrder(ctx context.Context, q Querier, userID int64, ids []int64) error {
	_, err := q.Exec(ctx, `
		UPDATE habits h SET position = (o.pos - 1)::int
		FROM unnest($2::bigint[]) WITH ORDINALITY AS o(id, pos)
		WHERE h.id = o.id AND h.user_id = $1 AND h.deleted_at IS NULL`, userID, ids)
	return err
}

// HabitMark is what was recorded for one habit slot on a date. Count is 1 for a check slot.
type HabitMark struct {
	HabitID int64
	Slot    int
	Count   int
}

// MarkSlot records a check slot as done, once.
func MarkSlot(ctx context.Context, q Querier, habitID int64, date score.Date, slot int) error {
	_, err := q.Exec(ctx, `
		INSERT INTO habit_marks (habit_id, local_date, slot, count) VALUES ($1, $2::date, $3, 1)
		ON CONFLICT (habit_id, local_date, slot) DO NOTHING`, habitID, date, slot)
	return err
}

// UnmarkSlot removes a check slot's mark; removing one that is not there is fine.
func UnmarkSlot(ctx context.Context, q Querier, habitID int64, date score.Date, slot int) error {
	_, err := q.Exec(ctx,
		`DELETE FROM habit_marks WHERE habit_id = $1 AND local_date = $2::date AND slot = $3`, habitID, date, slot)
	return err
}

// SetHabitCount stores a count habit's total for the date, where zero clears it.
func SetHabitCount(ctx context.Context, q Querier, habitID int64, date score.Date, count int) error {
	if count <= 0 {
		return UnmarkSlot(ctx, q, habitID, date, 0)
	}
	_, err := q.Exec(ctx, `
		INSERT INTO habit_marks (habit_id, local_date, slot, count) VALUES ($1, $2::date, 0, $3)
		ON CONFLICT (habit_id, local_date, slot) DO UPDATE SET count = EXCLUDED.count, marked_at = now()`,
		habitID, date, count)
	return err
}

// HabitMarks lists the person's marks on a date, across all their live habits.
func HabitMarks(ctx context.Context, q Querier, userID int64, date score.Date) ([]HabitMark, error) {
	rows, err := q.Query(ctx, `
		SELECT m.habit_id, m.slot, m.count FROM habit_marks m JOIN habits h ON h.id = m.habit_id
		WHERE h.user_id = $1 AND h.deleted_at IS NULL AND m.local_date = $2::date
		ORDER BY m.habit_id, m.slot`, userID, date)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var out []HabitMark
	for rows.Next() {
		var m HabitMark
		if err := rows.Scan(&m.HabitID, &m.Slot, &m.Count); err != nil {
			return nil, err
		}
		out = append(out, m)
	}
	return out, rows.Err()
}

// HabitState is a habit that is due on a date with what was done on it.
type HabitState struct {
	Habit Habit
	// Done is true per slot index for a check habit.
	Done []bool
	// Count is a count habit's total for the day.
	Count int
}

// DueHabits returns the person's unpaused habits that apply on the date, in order, with the
// day's marks. A mark on a slot the habit no longer has is ignored.
func DueHabits(ctx context.Context, q Querier, userID int64, date score.Date) ([]HabitState, error) {
	habits, err := ListHabits(ctx, q, userID)
	if err != nil {
		return nil, err
	}
	marks, err := HabitMarks(ctx, q, userID, date)
	if err != nil {
		return nil, err
	}
	byHabit := map[int64][]HabitMark{}
	for _, m := range marks {
		byHabit[m.HabitID] = append(byHabit[m.HabitID], m)
	}
	out := make([]HabitState, 0, len(habits))
	for _, h := range habits {
		if h.Paused || !score.HabitDue(h.Weekdays, date) {
			continue
		}
		st := HabitState{Habit: h, Done: make([]bool, len(h.Slots))}
		for _, m := range byHabit[h.ID] {
			switch {
			case h.Kind == HabitCount:
				st.Count = m.Count
			case m.Slot < len(st.Done):
				st.Done[m.Slot] = true
			}
		}
		out = append(out, st)
	}
	return out, nil
}

// HabitDays reduces due habits to what scoring reads.
func HabitDays(states []HabitState) []score.HabitDay {
	out := make([]score.HabitDay, 0, len(states))
	for _, st := range states {
		day := score.HabitDay{Check: st.Habit.Kind == HabitCheck, Slots: len(st.Habit.Slots), Count: st.Count,
			Points: st.Habit.Points}
		if st.Habit.Target != nil {
			day.Target = *st.Habit.Target
		}
		for _, done := range st.Done {
			if done {
				day.SlotsDone++
			}
		}
		out = append(out, day)
	}
	return out
}

// PendingProposals lists the person's live habits that wait for their partner's answer.
func PendingProposals(ctx context.Context, q Querier, userID int64) ([]Habit, error) {
	habits, err := ListHabits(ctx, q, userID)
	if err != nil {
		return nil, err
	}
	out := []Habit{}
	for _, h := range habits {
		if h.ProposedAt != nil {
			out = append(out, h)
		}
	}
	return out, nil
}
