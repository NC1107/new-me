package together

import (
	"context"
	"errors"
	"fmt"

	"github.com/jackc/pgx/v5"

	"github.com/nc1107/new-me/server/internal/db"
	"github.com/nc1107/new-me/server/internal/push"
	"github.com/nc1107/new-me/server/internal/score"
	"github.com/nc1107/new-me/server/internal/tasks"
)

// SettleTasks charges the stake of every agreed task whose deadline day has ended on its
// assignee's calendar, and withdraws proposals nobody answered in time. It runs from Settle, so
// the scheduler does it with nobody in the app, and every task list read does it first. Each
// task moves under its own lock and only from its open status, so a stake is charged once no
// matter how many passes or requests race.
func (s *Service) SettleTasks(ctx context.Context) error {
	users, err := db.ListUsers(ctx, s.DB.Pool)
	if err != nil {
		return err
	}
	byID := make(map[int64]db.User, len(users))
	for _, u := range users {
		byID[u.ID] = u
	}
	now := s.Now()
	// No zone is more than a day ahead of UTC, so this reaches every task that might be overdue.
	candidates, err := db.ListTasksDueBy(ctx, s.DB.Pool, score.DateOf(now.UTC()).AddDays(1))
	if err != nil {
		return err
	}
	var errs []error
	for _, c := range candidates {
		assignee, ok := byID[c.AssigneeID]
		if !ok {
			continue
		}
		loc, err := assignee.Location()
		if err != nil {
			errs = append(errs, err)
			continue
		}
		today := score.LocalToday(now, loc)
		var settled db.Task
		var moved bool
		err = s.DB.WithTx(ctx, func(tx pgx.Tx) error {
			var err error
			settled, moved, err = db.SettleTask(ctx, tx, c.ID, func(t db.Task) tasks.Verdict {
				return tasks.Judge(t.Status, t.Deadline, today)
			})
			return err
		})
		if err != nil {
			errs = append(errs, fmt.Errorf("task %d: %w", c.ID, err))
			continue
		}
		if moved && settled.Status == tasks.Missed {
			s.announceMissed(settled, byID)
		}
	}
	return errors.Join(errs...)
}

// announceMissed tells both people a stake was lost. The gems have already moved, so a push that
// cannot be queued is only a missed notification and never retried into a second charge.
func (s *Service) announceMissed(t db.Task, users map[int64]db.User) {
	assignee := users[t.AssigneeID]
	for _, u := range users {
		body := fmt.Sprintf("%s missed %s, -%d gems", assignee.Name, t.Title, t.Stake)
		if u.ID == t.AssigneeID {
			body = fmt.Sprintf("You missed %s, -%d gems", t.Title, t.Stake)
		}
		s.Notify(u, push.Message{Kind: EventTask, Title: "Task missed", Body: body})
	}
}
