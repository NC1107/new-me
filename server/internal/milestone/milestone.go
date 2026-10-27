// Package milestone records the moments worth celebrating once: streaks of 7, 14, 30, 50, 100,
// 200 and 365 days for each person and for the couple, and a few firsts.
package milestone

import (
	"context"
	"errors"
	"fmt"
	"log"
	"strconv"
	"time"

	"github.com/nc1107/new-me/server/internal/db"
	"github.com/nc1107/new-me/server/internal/engine"
	"github.com/nc1107/new-me/server/internal/push"
	"github.com/nc1107/new-me/server/internal/score"
	"github.com/nc1107/new-me/server/internal/together"
)

// pushWindowDays is how long after being recorded a milestone may still be pushed, so a restart
// or a night in quiet hours does not lose it but an old one is never announced late.
const pushWindowDays = 1

// Title is the plain words for a milestone.
func Title(m db.Milestone) string {
	switch m.Kind {
	case db.MilestoneStreak:
		return fmt.Sprintf("%d-day streak", m.Value)
	case db.MilestoneSharedStreak:
		return fmt.Sprintf("%d days together", m.Value)
	case db.MilestoneFirst10K:
		return "First 10,000-step day"
	case db.MilestoneFirstAll:
		return "First day with every quest done"
	case db.MilestoneFirstWeek:
		return "First fully counted week"
	}
	return m.Kind
}

func body(m db.Milestone) string {
	switch m.Kind {
	case db.MilestoneStreak:
		return fmt.Sprintf("%d days in a row. That is real consistency.", m.Value)
	case db.MilestoneSharedStreak:
		return fmt.Sprintf("You have both counted for %d days running.", m.Value)
	}
	return "A first, and now it is yours."
}

// Service records milestones and announces them.
type Service struct {
	DB       *db.DB
	Together *together.Service
	Now      func() time.Time
}

// Run records every milestone that has been reached and pushes the ones that are due. Each is
// recorded once, so it is safe to call after any write and from the scheduler.
func (s *Service) Run(ctx context.Context) error {
	users, err := db.ListUsers(ctx, s.DB.Pool)
	if err != nil {
		return err
	}
	now := s.Now()
	results := make(map[int64]score.StreakResult, len(users))
	var errs []error
	for _, u := range users {
		loc, err := u.Location()
		if err != nil {
			errs = append(errs, err)
			continue
		}
		res, err := engine.StreakFor(ctx, s.DB.Pool, u, now, loc)
		if err != nil {
			errs = append(errs, err)
			continue
		}
		results[u.ID] = res
		if err := s.recordPersonal(ctx, u, loc, res, now); err != nil {
			errs = append(errs, err)
		}
	}
	if err := s.recordShared(ctx, users, results, now); err != nil {
		errs = append(errs, err)
	}
	errs = append(errs, s.pushDue(ctx, users, now))
	return errors.Join(errs...)
}

// RunQuietly is Run for request handlers: a failure is logged, never shown.
func (s *Service) RunQuietly(ctx context.Context) {
	defer func() {
		if r := recover(); r != nil {
			log.Printf("[NEWME] milestones panic: %v", r)
		}
	}()
	if err := s.Run(ctx); err != nil && ctx.Err() == nil {
		log.Printf("[NEWME] milestones: %v", err)
	}
}

func key(kind string, value int) string { return kind + ":" + strconv.Itoa(value) }

// recordPersonal stores the person's reached streak milestones and firsts. Only the highest of
// a batch recorded together is announced, so the first run after an update does not send a
// push per milestone.
func (s *Service) recordPersonal(ctx context.Context, u db.User, loc *time.Location, res score.StreakResult, now time.Time) error {
	today := score.LocalToday(now, loc)
	have, err := db.MilestoneKinds(ctx, s.DB.Pool, &u.ID)
	if err != nil {
		return err
	}
	var fresh []db.Milestone
	record := func(kind string, value int, on score.Date) error {
		if have[key(kind, value)] {
			return nil
		}
		m, created, err := db.RecordMilestone(ctx, s.DB.Pool, &u.ID, kind, value, on)
		if err != nil || !created {
			return err
		}
		fresh = append(fresh, m)
		return nil
	}
	for _, m := range score.MilestonesReached(res.Count) {
		if err := record(db.MilestoneStreak, m, today); err != nil {
			return err
		}
	}
	firsts := []struct {
		kind string
		find func() (score.Date, error)
	}{
		{db.MilestoneFirst10K, func() (score.Date, error) {
			return db.FirstDayOver(ctx, s.DB.Pool, u.ID, db.MetricSteps, score.TenKSteps)
		}},
		{db.MilestoneFirstAll, func() (score.Date, error) { return db.FirstAllQuestsDay(ctx, s.DB.Pool, u.ID) }},
		{db.MilestoneFirstWeek, func() (score.Date, error) { return db.FirstFullWeek(ctx, s.DB.Pool, u.ID) }},
	}
	for _, f := range firsts {
		if have[key(f.kind, 0)] {
			continue
		}
		on, err := f.find()
		if err != nil {
			return err
		}
		if on == "" {
			continue
		}
		if err := record(f.kind, 0, on); err != nil {
			return err
		}
	}
	return s.silenceAllButBest(ctx, u.ID, fresh)
}

func (s *Service) recordShared(ctx context.Context, users []db.User, results map[int64]score.StreakResult, now time.Time) error {
	shared := engine.SharedStreakFor(users, results, now)
	if shared.Current == 0 {
		return nil
	}
	have, err := db.MilestoneKinds(ctx, s.DB.Pool, nil)
	if err != nil {
		return err
	}
	var today score.Date
	for _, u := range users {
		if loc, err := u.Location(); err == nil {
			today = max(today, score.LocalToday(now, loc))
		}
	}
	var fresh []db.Milestone
	for _, m := range score.MilestonesReached(shared.Current) {
		if have[key(db.MilestoneSharedStreak, m)] {
			continue
		}
		rec, created, err := db.RecordMilestone(ctx, s.DB.Pool, nil, db.MilestoneSharedStreak, m, today)
		if err != nil {
			return err
		}
		if created {
			fresh = append(fresh, rec)
		}
	}
	for _, u := range users {
		if err := s.silenceAllButBest(ctx, u.ID, fresh); err != nil {
			return err
		}
	}
	return nil
}

// silenceAllButBest claims the announcement of every milestone in the batch except the highest
// streak one (or the only one), so only that one is pushed.
func (s *Service) silenceAllButBest(ctx context.Context, userID int64, batch []db.Milestone) error {
	if len(batch) < 2 {
		return nil
	}
	rank := func(m db.Milestone) int {
		if m.Kind == db.MilestoneStreak || m.Kind == db.MilestoneSharedStreak {
			return 1000 + m.Value
		}
		return 0
	}
	best := 0
	for i, m := range batch {
		if rank(m) > rank(batch[best]) {
			best = i
		}
	}
	for i, m := range batch {
		if i == best {
			continue
		}
		if _, err := db.ClaimNotice(ctx, s.DB.Pool, noticeKind(m), userID, m.AchievedOn); err != nil {
			return err
		}
	}
	return nil
}

func noticeKind(m db.Milestone) string { return "milestone_" + strconv.FormatInt(m.ID, 10) }

// pushDue sends each unannounced, recent milestone to the people it belongs to, inside their
// notification window.
func (s *Service) pushDue(ctx context.Context, users []db.User, now time.Time) error {
	if s.Together == nil || s.Together.Notifier == nil {
		return nil
	}
	var errs []error
	for _, u := range users {
		loc, err := u.Location()
		if err != nil {
			errs = append(errs, err)
			continue
		}
		today := score.LocalToday(now, loc)
		local := now.In(loc)
		if u.Schedule.Quiet(today, local.Hour()*60+local.Minute()) {
			continue
		}
		recent, err := db.MilestonesSince(ctx, s.DB.Pool, u.ID, today.AddDays(-pushWindowDays))
		if err != nil {
			errs = append(errs, err)
			continue
		}
		for _, m := range recent {
			first, err := db.ClaimNotice(ctx, s.DB.Pool, noticeKind(m), u.ID, m.AchievedOn)
			if err != nil {
				errs = append(errs, err)
				continue
			}
			if first {
				s.Together.Notify(u, push.Message{Kind: together.EventMilestone, Title: Title(m), Body: body(m)})
			}
		}
	}
	return errors.Join(errs...)
}
