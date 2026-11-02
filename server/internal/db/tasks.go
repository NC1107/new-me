package db

import (
	"context"
	"errors"
	"time"

	"github.com/jackc/pgx/v5"

	"github.com/nc1107/new-me/server/internal/score"
	"github.com/nc1107/new-me/server/internal/tasks"
)

// Task is a chore with a stake in gems. See docs/design-v21-tasks.md.
type Task struct {
	ID         int64
	Title      string
	CreatorID  int64
	AssigneeID int64
	Stake      int
	Deadline   score.Date
	Status     string
	CreatedAt  time.Time
	AgreedAt   *time.Time
	SettledAt  *time.Time
}

const taskColumns = `id, title, creator_id, assignee_id, stake, deadline::text, status, created_at, agreed_at, settled_at`

func scanTask(row interface{ Scan(...any) error }) (Task, error) {
	var t Task
	var deadline string
	err := row.Scan(&t.ID, &t.Title, &t.CreatorID, &t.AssigneeID, &t.Stake, &deadline, &t.Status,
		&t.CreatedAt, &t.AgreedAt, &t.SettledAt)
	t.Deadline = score.Date(deadline)
	if errors.Is(err, pgx.ErrNoRows) {
		return Task{}, ErrNotFound
	}
	return t, err
}

func queryTasks(ctx context.Context, q Querier, sql string, args ...any) ([]Task, error) {
	rows, err := q.Query(ctx, sql, args...)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := []Task{}
	for rows.Next() {
		t, err := scanTask(rows)
		if err != nil {
			return nil, err
		}
		out = append(out, t)
	}
	return out, rows.Err()
}

// InsertTask adds a task with the given status.
func InsertTask(ctx context.Context, q Querier, t Task) (Task, error) {
	return scanTask(q.QueryRow(ctx, `
		INSERT INTO tasks (title, creator_id, assignee_id, stake, deadline, status, agreed_at)
		VALUES ($1, $2, $3, $4, $5::date, $6, CASE WHEN $6 = 'agreed' THEN now() END)
		RETURNING `+taskColumns, t.Title, t.CreatorID, t.AssigneeID, t.Stake, string(t.Deadline), t.Status))
}

// GetTask reads one task.
func GetTask(ctx context.Context, q Querier, id int64) (Task, error) {
	return scanTask(q.QueryRow(ctx, `SELECT `+taskColumns+` FROM tasks WHERE id = $1`, id))
}

// LockTask reads one task and holds its row until the transaction ends, so a finish and a
// settlement of the same task cannot both win.
func LockTask(ctx context.Context, tx pgx.Tx, id int64) (Task, error) {
	return scanTask(tx.QueryRow(ctx, `SELECT `+taskColumns+` FROM tasks WHERE id = $1 FOR UPDATE`, id))
}

// SaveTaskTerms rewrites what a proposal asks for and its status.
func SaveTaskTerms(ctx context.Context, tx pgx.Tx, t Task) (Task, error) {
	return scanTask(tx.QueryRow(ctx, `
		UPDATE tasks SET title = $2, assignee_id = $3, stake = $4, deadline = $5::date, status = $6,
		    agreed_at = CASE WHEN $6 = 'agreed' THEN now() END, updated_at = now()
		WHERE id = $1 RETURNING `+taskColumns, t.ID, t.Title, t.AssigneeID, t.Stake, string(t.Deadline), t.Status))
}

// SetTaskStatus moves a locked task to a new status. Done and missed stamp settled_at, which is
// the moment the stake moves.
func SetTaskStatus(ctx context.Context, tx pgx.Tx, id int64, status string) (Task, error) {
	return scanTask(tx.QueryRow(ctx, `
		UPDATE tasks SET status = $2, updated_at = now(),
		    agreed_at = CASE WHEN $2 = 'agreed' THEN now() ELSE agreed_at END,
		    settled_at = CASE WHEN $2 IN ('done', 'missed') THEN now() END
		WHERE id = $1 RETURNING `+taskColumns, id, status))
}

// ListOpenTasks is every proposed, declined and agreed task of both people, soonest deadline first.
func ListOpenTasks(ctx context.Context, q Querier) ([]Task, error) {
	return queryTasks(ctx, q, `SELECT `+taskColumns+` FROM tasks
		WHERE status IN ('proposed', 'declined', 'agreed') ORDER BY deadline, id`)
}

// ListTaskHistory is the newest done and missed tasks of both people.
func ListTaskHistory(ctx context.Context, q Querier) ([]Task, error) {
	return queryTasks(ctx, q, `SELECT `+taskColumns+` FROM tasks
		WHERE status IN ('done', 'missed') ORDER BY settled_at DESC, id DESC LIMIT $1`, tasks.HistoryLimit)
}

// ListTasksDueBy is the open tasks whose deadline is on or before the date. Callers pass a date a
// day beyond UTC today, since no zone is ahead of that, and judge each task on its assignee's day.
func ListTasksDueBy(ctx context.Context, q Querier, date score.Date) ([]Task, error) {
	return queryTasks(ctx, q, `SELECT `+taskColumns+` FROM tasks
		WHERE status IN ('proposed', 'declined', 'agreed') AND deadline <= $1::date ORDER BY id`, string(date))
}

// CountOpenTasks is how many open tasks the person created.
func CountOpenTasks(ctx context.Context, q Querier, creator int64) (int, error) {
	var n int
	err := q.QueryRow(ctx, `SELECT count(*)::int FROM tasks
		WHERE creator_id = $1 AND status IN ('proposed', 'declined', 'agreed')`, creator).Scan(&n)
	return n, err
}

// FindProposedTask returns the creator's proposal that asks for exactly these terms, so a retried
// or double-tapped request proposes once.
func FindProposedTask(ctx context.Context, q Querier, t Task) (Task, error) {
	return scanTask(q.QueryRow(ctx, `SELECT `+taskColumns+` FROM tasks
		WHERE creator_id = $1 AND assignee_id = $2 AND title = $3 AND stake = $4 AND deadline = $5::date
		  AND status = 'proposed' ORDER BY id LIMIT 1`, t.CreatorID, t.AssigneeID, t.Title, t.Stake, string(t.Deadline)))
}

// SettleTask applies a settlement verdict to one task under the wishlist lock, which orders it
// with every other balance change, and the task's row lock. It reports whether this call moved
// the task: one already settled by a concurrent pass, a finish or a withdrawal is left alone, so
// a stake is charged once. The verdict is judged on the locked row, not the one the caller listed.
func SettleTask(ctx context.Context, tx pgx.Tx, id int64, judge func(Task) tasks.Verdict) (Task, bool, error) {
	if err := LockRewards(ctx, tx); err != nil {
		return Task{}, false, err
	}
	t, err := LockTask(ctx, tx, id)
	if errors.Is(err, ErrNotFound) {
		return Task{}, false, nil
	}
	if err != nil {
		return Task{}, false, err
	}
	switch judge(t) {
	case tasks.MarkMissed:
		t, err = SetTaskStatus(ctx, tx, id, tasks.Missed)
		return t, err == nil, err
	case tasks.Lapse:
		t, err = SetTaskStatus(ctx, tx, id, tasks.Withdrawn)
		return t, err == nil, err
	}
	return t, false, nil
}
