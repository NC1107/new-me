package nudge

import (
	"context"
	"errors"
	"fmt"
	"time"

	"github.com/jackc/pgx/v5"

	"github.com/nc1107/new-me/server/internal/coach"
	"github.com/nc1107/new-me/server/internal/db"
	"github.com/nc1107/new-me/server/internal/engine"
	"github.com/nc1107/new-me/server/internal/plan"
	"github.com/nc1107/new-me/server/internal/push"
	"github.com/nc1107/new-me/server/internal/readiness"
	"github.com/nc1107/new-me/server/internal/score"
	"github.com/nc1107/new-me/server/internal/together"
)

// Service runs Decide for every person on each pass of the scheduler.
type Service struct {
	DB *db.DB
	// Together sends the pushes and holds the Notifier; with no Notifier the pass does nothing.
	Together *together.Service
	Polisher *coach.Polisher
	Now      func() time.Time
}

// Run decides and sends the nudges due for every person. One failing person does not stop the
// others.
func (s *Service) Run(ctx context.Context) error {
	if s.Together == nil || s.Together.Notifier == nil {
		return nil
	}
	users, err := db.ListUsers(ctx, s.DB.Pool)
	if err != nil {
		return fmt.Errorf("list users: %w", err)
	}
	now := s.Now()
	var errs []error
	for _, u := range users {
		if err := s.runUser(ctx, u, now); err != nil {
			errs = append(errs, fmt.Errorf("user %d: %w", u.ID, err))
		}
	}
	return errors.Join(errs...)
}

func (s *Service) runUser(ctx context.Context, u db.User, now time.Time) error {
	u, err := db.SwitchTimezoneIfDue(ctx, s.DB.Pool, u, now)
	if err != nil {
		return err
	}
	loc, err := u.Location()
	if err != nil {
		return err
	}
	today := score.LocalToday(now, loc)
	if today.Before(u.JoinedOn) {
		return nil
	}
	if !wantsAny(u.Notify) {
		return nil
	}
	spans, err := db.AwaySpansFrom(ctx, s.DB.Pool, u.ID, today)
	if err != nil {
		return err
	}
	for _, sp := range spans {
		// An away day is skipped before anything is loaded or claimed.
		if sp.Contains(today) {
			return nil
		}
	}
	sent, err := db.NoticesSent(ctx, s.DB.Pool, u.ID, today)
	if err != nil {
		return err
	}
	sentCount, err := db.CountNotices(ctx, s.DB.Pool, u.ID, today, together.AutoKinds)
	if err != nil {
		return err
	}
	var day coach.Day
	err = s.DB.WithTx(ctx, func(tx pgx.Tx) error {
		scored, err := engine.ScoreAt(ctx, tx, u.ID, today, loc, now)
		if err != nil {
			return err
		}
		habits, err := db.DueHabits(ctx, tx, u.ID, today)
		if err != nil {
			return err
		}
		day, err = coach.Load(ctx, tx, u, loc, scored, habits, now)
		return err
	})
	if err != nil {
		return err
	}

	facts := factsFrom(day, u, now.In(loc), today, sent)
	facts.SentCount = sentCount
	facts.ReadinessEasy = day.Readiness != nil && day.Readiness.Level == readiness.LevelEasy
	facts.Morning = func() (string, string) { return s.morningText(ctx, u, today, day) }
	var errs []error
	for _, n := range Decide(facts) {
		first, err := db.ClaimNotice(ctx, s.DB.Pool, n.Kind, u.ID, today)
		if err != nil {
			errs = append(errs, err)
			continue
		}
		if first {
			s.Together.Notify(u, push.Message{Kind: n.Kind, Title: n.Title, Body: n.Body})
		}
	}
	return errors.Join(errs...)
}

func wantsAny(n db.Notifications) bool {
	return n.BehindPace || n.CloseToDone || n.WindDown || n.MorningPlan
}

// morningText is the headline and body of the morning plan push: the readiness level, its
// first reason, then the plan summary.
func (s *Service) morningText(ctx context.Context, u db.User, today score.Date, day coach.Day) (string, string) {
	title := "Today's plan"
	body := s.Polisher.Summary(ctx, u, today, day)
	if r := day.Readiness; r != nil {
		title = coach.ReadinessTitle(r.Level)
		if len(r.Reasons) > 0 {
			body = r.Reasons[0].Text + ". " + body
		}
	}
	return title, body
}

// factsFrom turns the loaded day into the plain facts Decide reads.
func factsFrom(day coach.Day, u db.User, local time.Time, today score.Date, sent map[string]bool) Facts {
	first, end := u.Schedule.Window(today)
	f := Facts{
		Now: local, Sent: sent, FirstMin: first, EndMin: end, BedMin: u.Schedule.On(today).BedMin,
		Prefs: Prefs{BehindPace: u.Notify.BehindPace, CloseToDone: u.Notify.CloseToDone,
			WindDown: u.Notify.WindDown, MorningPlan: u.Notify.MorningPlan},
		StepsTracked: day.StepsTracked, StepsGoal: day.StepsGoal, Steps: day.Steps, StepsUsual: day.StepsUsual,
		Counted: day.Counted, BasePts: day.Base, MaxBase: day.Max,
		SleepTargetMin: day.SleepTargetMin, LastNightMin: day.LastNightMin,
		SleepTracked: day.SleepTracked, SleepQuest: day.SleepQuest,
	}
	for _, row := range day.QuestRows {
		if row.Quest.Key == "steps" {
			f.StepsDone = row.Quest.Done
		}
		if row.Quest.Done {
			continue
		}
		if finish, ok := plan.FinishText(row.Quest); ok {
			f.OpenQuests = append(f.OpenQuests, OpenQuest{Key: row.Quest.Key, Finish: finish, Missing: row.Points - row.Base})
		}
	}
	return f
}
