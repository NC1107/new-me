package db

import (
	"context"
	"errors"
	"time"

	"github.com/jackc/pgx/v5"

	"github.com/nc1107/new-me/server/internal/gems"
	"github.com/nc1107/new-me/server/internal/score"
	"github.com/nc1107/new-me/server/internal/tasks"
)

// Task is a chore worth gems. See docs/design-v21-tasks.md.
type Task struct {
	ID         int64
	Title      string
	CreatorID  int64
	AssigneeID int64
	Stake      int
	// LoseIfMissed is the assignee's explicit choice to put the gems on the line.
	LoseIfMissed bool
	// Lost is what a miss took: set once, at settlement, never above the stake.
	Lost      int
	Deadline  score.Date
	Status    string
	CreatedAt time.Time
	AgreedAt  *time.Time
	SettledAt *time.Time
}

const taskColumns = `id, title, creator_id, assignee_id, stake, lose_if_missed, lost, deadline::text, status, created_at, agreed_at, settled_at`

func scanTask(row interface{ Scan(...any) error }) (Task, error) {
	var t Task
	var deadline string
	err := row.Scan(&t.ID, &t.Title, &t.CreatorID, &t.AssigneeID, &t.Stake, &t.LoseIfMissed, &t.Lost, &deadline, &t.Status,
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
		INSERT INTO tasks (title, creator_id, assignee_id, stake, lose_if_missed, deadline, status, agreed_at)
		VALUES ($1, $2, $3, $4, $5, $6::date, $7, CASE WHEN $7 = 'agreed' THEN now() END)
		RETURNING `+taskColumns, t.Title, t.CreatorID, t.AssigneeID, t.Stake, t.LoseIfMissed, string(t.Deadline), t.Status))
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
		UPDATE tasks SET title = $2, assignee_id = $3, stake = $4, lose_if_missed = $5, deadline = $6::date,
		    status = $7, agreed_at = CASE WHEN $7 = 'agreed' THEN now() END, updated_at = now()
		WHERE id = $1 RETURNING `+taskColumns, t.ID, t.Title, t.AssigneeID, t.Stake, t.LoseIfMissed, string(t.Deadline), t.Status))
}

// CounterTask answers a proposal with a different amount. The counter-offer becomes the proposal:
// the person who made it is now its creator, so the original proposer is the one asked to agree.
func CounterTask(ctx context.Context, tx pgx.Tx, id, by int64, stake int) (Task, error) {
	return scanTask(tx.QueryRow(ctx, `
		UPDATE tasks SET stake = $2, creator_id = $3, updated_at = now()
		WHERE id = $1 RETURNING `+taskColumns, id, stake, by))
}

// SetTaskStatus moves a locked task to a new status. Done and missed stamp settled_at, which is
// the moment the gems move; lost is what a miss takes and is zero for any other status.
func SetTaskStatus(ctx context.Context, tx pgx.Tx, id int64, status string, lost int) (Task, error) {
	return scanTask(tx.QueryRow(ctx, `
		UPDATE tasks SET status = $2, updated_at = now(),
		    agreed_at = CASE WHEN $2 = 'agreed' THEN now() ELSE agreed_at END,
		    settled_at = CASE WHEN $2 IN ('done', 'missed') THEN now() END,
		    lost = $3
		WHERE id = $1 RETURNING `+taskColumns, id, status, lost))
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
		WHERE creator_id = $1 AND assignee_id = $2 AND title = $3 AND stake = $4 AND lose_if_missed = $5
		  AND deadline = $6::date AND status = 'proposed' ORDER BY id LIMIT 1`,
		t.CreatorID, t.AssigneeID, t.Title, t.Stake, t.LoseIfMissed, string(t.Deadline)))
}

// SettleTask applies a settlement verdict to one task under the wishlist lock, which orders it
// with every other balance change, and the task's row lock. It reports whether this call moved
// the task: one already settled by a concurrent pass, a finish or a withdrawal is left alone, so
// a loss is charged once. The verdict is judged on the locked row, not the one the caller listed.
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
		people, err := ReadPersonGems(ctx, tx)
		if err != nil {
			return Task{}, false, err
		}
		holder, _ := people.Find(t.AssigneeID)
		t, err = SetTaskStatus(ctx, tx, id, tasks.Missed, gems.TaskLoss(t.LoseIfMissed, t.Stake, holder.Balance()))
		return t, err == nil, err
	case tasks.Lapse:
		t, err = SetTaskStatus(ctx, tx, id, tasks.Withdrawn, 0)
		return t, err == nil, err
	}
	return t, false, nil
}
