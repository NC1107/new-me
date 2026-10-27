package together

import (
	"context"
	"errors"
	"fmt"
	"log"
	"slices"
	"time"

	"github.com/jackc/pgx/v5"

	"github.com/nc1107/new-me/server/internal/db"
	"github.com/nc1107/new-me/server/internal/engine"
	"github.com/nc1107/new-me/server/internal/push"
	"github.com/nc1107/new-me/server/internal/score"
)

// Push event kinds. They double as the notice_log kinds and the keys the app routes taps on.
const (
	EventPartnerDone = "partner_done"
	EventCheer       = "cheer"
	EventChallenge   = "challenge"
	EventReward      = "reward"

	// The v6 autopilot events. Each behind-pace window is its own kind so it is sent at most
	// once, and the app routes all of them to Today.
	EventBehindPaceAfternoon = "nudge_behind_14"
	EventBehindPaceEvening   = "nudge_behind_1830"
	EventCloseToDone         = "nudge_close_to_done"
	EventWindDown            = "nudge_wind_down"
	EventMorningPlan         = "nudge_morning_plan"
	EventWeeklyRecap         = "weekly_recap"
)

// AutoKinds are the automatic pushes that count toward a person's daily budget. Cheers,
// challenge, reward and partner-done are between the two people and do not.
var AutoKinds = []string{EventBehindPaceAfternoon, EventBehindPaceEvening, EventCloseToDone, EventWindDown,
	EventMorningPlan, EventWeeklyRecap}

// Notifier accepts a message without waiting for its delivery.
type Notifier interface {
	Enqueue(push.Message) bool
}

// Service is the shared state of the pair: it creates each week's challenge, notices when a
// challenge or reward is complete, and sends the push events about them.
type Service struct {
	DB  *db.DB
	Now func() time.Time
	// Notifier is nil while push is off.
	Notifier Notifier
}

// Notify queues a message unless the person turned that event off. It never fails the caller.
func (s *Service) Notify(to db.User, m push.Message) {
	if s.Notifier == nil || !wants(to.Notify, m.Kind) {
		return
	}
	m.UserID = to.ID
	s.Notifier.Enqueue(m)
}

func wants(n db.Notifications, kind string) bool {
	switch kind {
	case EventPartnerDone:
		return n.PartnerDone
	case EventCheer:
		return n.Cheers
	case EventChallenge:
		return n.Challenge
	case EventReward:
		return n.Reward
	case EventBehindPaceAfternoon, EventBehindPaceEvening:
		return n.BehindPace
	case EventCloseToDone:
		return n.CloseToDone
	case EventWindDown:
		return n.WindDown
	case EventMorningPlan:
		return n.MorningPlan
	case EventWeeklyRecap:
		return n.WeeklyRecap
	}
	return false
}

// Settle brings everything shared up to date: this week's challenge exists and is checked for
// completion, the active reward is checked, and a partner whose day just counted is announced.
// It is safe to call after any write and from the scheduler, because every effect happens once.
func (s *Service) Settle(ctx context.Context) error {
	users, err := db.ListUsers(ctx, s.DB.Pool)
	if err != nil {
		return err
	}
	var errs []error
	now := s.Now()
	var weeks []score.Date
	for _, u := range users {
		loc, err := u.Location()
		if err != nil {
			errs = append(errs, err)
			continue
		}
		if week := score.WeekStart(score.LocalToday(now, loc)); !slices.Contains(weeks, week) {
			weeks = append(weeks, week)
		}
	}
	for _, week := range weeks {
		if err := s.settleChallenge(ctx, week, users); err != nil {
			errs = append(errs, fmt.Errorf("challenge %s: %w", week, err))
		}
	}
	if err := s.settleReward(ctx, users); err != nil {
		errs = append(errs, fmt.Errorf("reward: %w", err))
	}
	if err := s.announcePartnersDone(ctx, users, now); err != nil {
		errs = append(errs, fmt.Errorf("partner done: %w", err))
	}
	return errors.Join(errs...)
}

// SettleQuietly is Settle for request handlers: a failure is logged, never shown, because the
// write that triggered it has already been committed and answered.
func (s *Service) SettleQuietly(ctx context.Context) {
	defer func() {
		if r := recover(); r != nil {
			log.Printf("[NEWME] settle panic: %v", r)
		}
	}()
	if err := s.Settle(ctx); err != nil && ctx.Err() == nil {
		log.Printf("[NEWME] settle: %v", err)
	}
}

// EnsureChallenge returns the challenge of the week, creating it from the history before the
// week on first use. Sizing never looks at the week itself, so when it is created does not
// change what it asks for.
func (s *Service) EnsureChallenge(ctx context.Context, week score.Date) (db.Challenge, error) {
	ch, err := db.GetChallenge(ctx, s.DB.Pool, week)
	if err == nil || !errors.Is(err, db.ErrNotFound) {
		return ch, err
	}
	sizing, err := s.sizing(ctx, week)
	if err != nil {
		return db.Challenge{}, err
	}
	spec := Generate(week, sizing)
	return db.InsertChallenge(ctx, s.DB.Pool, db.Challenge{
		WeekStart: week, Kind: spec.Kind, Title: spec.Title, Target: spec.Target})
}

func (s *Service) sizing(ctx context.Context, week score.Date) (Sizing, error) {
	q := s.DB.Pool
	var in Sizing
	steps, err := db.StepTotals(ctx, q, week.AddDays(-weeksOfHistory*daysInWeek), week.AddDays(-1))
	if err != nil {
		return in, err
	}
	for _, u := range steps {
		if u.Days > 0 {
			in.StepsDailyAverage += u.Total / float64(u.Days)
		}
	}
	if in.WorkoutsLastWeek, err = db.WorkoutsAll(ctx, q, week.AddDays(-daysInWeek), week.AddDays(-1)); err != nil {
		return in, err
	}
	in.ReadingLastTwoWeeks, err = db.ReadingMinutesAll(ctx, q, week.AddDays(-weeksOfHistory*daysInWeek), week.AddDays(-1))
	return in, err
}

// ChallengeProgress is how far the pair has got on a challenge. A completed challenge reads as
// at least its target, since completion is final even if a log is deleted afterwards.
func (s *Service) ChallengeProgress(ctx context.Context, ch db.Challenge) (int, error) {
	q := s.DB.Pool
	from, to := ch.WeekStart, ch.EndsOn()
	var progress int
	switch ch.Kind {
	case KindSteps:
		steps, err := db.StepTotals(ctx, q, from, to)
		if err != nil {
			return 0, err
		}
		total := 0.0
		for _, u := range steps {
			total += u.Total
		}
		progress = int(total)
	case KindWorkouts:
		n, err := db.WorkoutsAll(ctx, q, from, to)
		if err != nil {
			return 0, err
		}
		progress = n
	case KindReading:
		n, err := db.ReadingMinutesAll(ctx, q, from, to)
		if err != nil {
			return 0, err
		}
		progress = n
	case KindCountedDays:
		days, err := db.CountedDays(ctx, q, from, to)
		if err != nil {
			return 0, err
		}
		users, err := db.ListUsers(ctx, q)
		if err != nil {
			return 0, err
		}
		counted := make([]Counted, len(days))
		for i, d := range days {
			counted[i] = Counted{UserID: d.UserID, Date: d.Date}
		}
		members := make([]int64, len(users))
		for i, u := range users {
			members[i] = u.ID
		}
		progress = BothCountedDays(counted, members)
	}
	if ch.CompletedAt != nil {
		progress = max(progress, ch.Target)
	}
	return progress, nil
}

func (s *Service) settleChallenge(ctx context.Context, week score.Date, users []db.User) error {
	ch, err := s.EnsureChallenge(ctx, week)
	if err != nil || ch.CompletedAt != nil {
		return err
	}
	progress, err := s.ChallengeProgress(ctx, ch)
	if err != nil || progress < ch.Target {
		return err
	}
	now := s.Now()
	completed := false
	err = s.DB.WithTx(ctx, func(tx pgx.Tx) error {
		var err error
		if completed, err = db.CompleteChallenge(ctx, tx, ch.ID); err != nil || !completed {
			return err
		}
		for _, u := range users {
			loc, err := u.Location()
			if err != nil {
				return err
			}
			date := score.LocalToday(now, loc)
			if err := db.InsertChallengeAward(ctx, tx, ch.ID, u.ID, date, score.ChallengeBonusPoints); err != nil {
				return err
			}
			if _, err := engine.ScoreAt(ctx, tx, u.ID, date, loc, now); err != nil {
				return err
			}
		}
		return nil
	})
	if err != nil || !completed {
		return err
	}
	for _, u := range users {
		s.Notify(u, push.Message{Kind: EventChallenge, Title: "Challenge complete", Body: ch.Title})
	}
	return nil
}

// RewardTotals reads the combined points a reward measures against.
func (s *Service) RewardTotals(ctx context.Context) (int, error) {
	return db.TotalPoints(ctx, s.DB.Pool)
}

func (s *Service) settleReward(ctx context.Context, users []db.User) error {
	r, err := db.ActiveReward(ctx, s.DB.Pool)
	if errors.Is(err, db.ErrNotFound) {
		return nil
	}
	if err != nil {
		return err
	}
	total, err := s.RewardTotals(ctx)
	if err != nil || !RewardReached(total, r.Baseline, r.Target) {
		return err
	}
	marked, err := db.MarkRewardReached(ctx, s.DB.Pool, r.ID)
	if err != nil || !marked {
		return err
	}
	for _, u := range users {
		s.Notify(u, push.Message{Kind: EventReward, Title: "Reward reached", Body: r.Name})
	}
	return nil
}

func (s *Service) announcePartnersDone(ctx context.Context, users []db.User, now time.Time) error {
	if s.Notifier == nil {
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
		row, err := db.GetDayScore(ctx, s.DB.Pool, u.ID, today)
		if errors.Is(err, db.ErrNotFound) || (err == nil && !row.Counted) {
			continue
		}
		if err != nil {
			errs = append(errs, err)
			continue
		}
		first, err := db.ClaimNotice(ctx, s.DB.Pool, EventPartnerDone, u.ID, today)
		if err != nil || !first {
			errs = append(errs, err)
			continue
		}
		for _, partner := range users {
			if partner.ID != u.ID {
				s.Notify(partner, push.Message{Kind: EventPartnerDone,
					Title: u.Name + " finished the day", Body: "Their day counted. Your move."})
			}
		}
	}
	return errors.Join(errs...)
}
