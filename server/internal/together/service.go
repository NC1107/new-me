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

	// The v7 events. The look-back is the first notification of the 1st and shares the daily
	// budget; a milestone is a celebration of something that just happened and does not.
	EventLookback  = "lookback"
	EventMilestone = "milestone"
	EventCover     = "cover"

	// EventHabitProposal asks the partner to approve a habit's gems (v11).
	EventHabitProposal = "habit_proposal"

	// EventRewardProposal asks the partner to approve a reward or its new price (v13).
	EventRewardProposal = "reward_proposal"
)

// AutoKinds are the automatic pushes that count toward a person's daily budget. Cheers,
// challenge, reward and partner-done are between the two people and do not.
var AutoKinds = []string{EventBehindPaceAfternoon, EventBehindPaceEvening, EventCloseToDone, EventWindDown,
	EventMorningPlan, EventWeeklyRecap, EventLookback}

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
	case EventLookback:
		return n.Lookback
	case EventMilestone:
		return n.Milestones
	case EventCover, EventHabitProposal, EventRewardProposal:
		return n.Cheers
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
// week on first use, and gives every person without one a share sized from their own history.
// Sizing never looks at the week itself, so when it is created does not change what it asks for.
// A person who joins mid-week gets a share and the combined target grows by it.
func (s *Service) EnsureChallenge(ctx context.Context, week score.Date) (db.Challenge, error) {
	users, err := db.ListUsers(ctx, s.DB.Pool)
	if err != nil {
		return db.Challenge{}, err
	}
	ch, err := db.GetChallenge(ctx, s.DB.Pool, week)
	if errors.Is(err, db.ErrNotFound) {
		ch, err = db.InsertChallenge(ctx, s.DB.Pool, db.Challenge{WeekStart: week, Kind: KindFor(week),
			Title: Title(KindFor(week), 0), Target: 1})
	}
	if err != nil {
		return db.Challenge{}, err
	}
	if ch.CompletedAt != nil {
		return ch, nil
	}
	shares, err := db.ChallengeShares(ctx, s.DB.Pool, ch.ID)
	if err != nil {
		return db.Challenge{}, err
	}
	added := false
	for _, u := range users {
		if _, ok := shares[u.ID]; ok {
			continue
		}
		sizing, err := s.sizing(ctx, u.ID, week)
		if err != nil {
			return db.Challenge{}, err
		}
		share := Share(ch.Kind, sizing)
		if err := db.InsertChallengeShare(ctx, s.DB.Pool, ch.ID, u.ID, share); err != nil {
			return db.Challenge{}, err
		}
		shares[u.ID] = share
		added = true
	}
	if !added {
		return ch, nil
	}
	total := 0
	for _, share := range shares {
		total += share
	}
	if err := db.SetChallengeTarget(ctx, s.DB.Pool, ch.ID, total, Title(ch.Kind, total)); err != nil {
		return db.Challenge{}, err
	}
	return db.GetChallenge(ctx, s.DB.Pool, week)
}

func (s *Service) sizing(ctx context.Context, userID int64, week score.Date) (Sizing, error) {
	q := s.DB.Pool
	var in Sizing
	total, days, err := db.StepsByUserID(ctx, q, userID, week.AddDays(-weeksOfHistory*daysInWeek), week.AddDays(-1))
	if err != nil {
		return in, err
	}
	if days > 0 {
		in.StepsDailyAverage = total / float64(days)
	}
	if in.WorkoutsLastWeek, err = db.CountWorkouts(ctx, q, userID, week.AddDays(-daysInWeek), week.AddDays(-1)); err != nil {
		return in, err
	}
	in.ReadingLastTwoWeeks, err = db.ReadingMinutesUser(ctx, q, userID, week.AddDays(-weeksOfHistory*daysInWeek), week.AddDays(-1))
	return in, err
}

// PersonStanding is one person's progress on their share, with who they are.
type PersonStanding struct {
	Standing
	Name  string
	Color string
}

// ChallengeStatus is how far the pair has got on a challenge.
type ChallengeStatus struct {
	// Progress adds each person's progress capped at their own share; Target is the sum of the
	// shares. The challenge is complete when every person has reached their own share.
	Progress int
	Target   int
	Complete bool
	People   []PersonStanding
}

// ChallengeProgress measures the challenge. A completed challenge reads as at least its target
// for everyone, since completion is final even if a log is deleted afterwards.
func (s *Service) ChallengeProgress(ctx context.Context, ch db.Challenge) (ChallengeStatus, error) {
	q := s.DB.Pool
	shares, err := db.ChallengeShares(ctx, q, ch.ID)
	if err != nil {
		return ChallengeStatus{}, err
	}
	users, err := db.ListUsers(ctx, q)
	if err != nil {
		return ChallengeStatus{}, err
	}
	var counted []db.CountedDay
	if ch.Kind == KindCountedDays {
		if counted, err = db.CountedDays(ctx, q, ch.WeekStart, ch.EndsOn()); err != nil {
			return ChallengeStatus{}, err
		}
	}
	status := ChallengeStatus{}
	var standings []Standing
	for _, u := range users {
		target, ok := shares[u.ID]
		if !ok {
			continue
		}
		progress, err := s.personProgress(ctx, ch, u.ID, counted)
		if err != nil {
			return ChallengeStatus{}, err
		}
		if ch.CompletedAt != nil {
			progress = max(progress, target)
		}
		st := Standing{UserID: u.ID, Target: target, Progress: progress}
		standings = append(standings, st)
		status.People = append(status.People, PersonStanding{Standing: st, Name: u.Name, Color: u.Color})
	}
	status.Progress, status.Target, status.Complete = Combined(standings)
	if len(standings) == 0 {
		return s.legacyStatus(ctx, ch, users, counted)
	}
	return status, nil
}

// legacyStatus measures a challenge from before personal shares, which only knows its combined
// target: the pair's total, or for counted days the days everyone counted on.
func (s *Service) legacyStatus(ctx context.Context, ch db.Challenge, users []db.User, counted []db.CountedDay) (ChallengeStatus, error) {
	status := ChallengeStatus{Target: ch.Target, Complete: ch.CompletedAt != nil}
	if ch.Kind == KindCountedDays {
		pairs := make([]Counted, len(counted))
		for i, c := range counted {
			pairs[i] = Counted{UserID: c.UserID, Date: c.Date}
		}
		members := make([]int64, len(users))
		for i, u := range users {
			members[i] = u.ID
		}
		status.Progress = BothCountedDays(pairs, members)
	} else {
		for _, u := range users {
			n, err := s.personProgress(ctx, ch, u.ID, counted)
			if err != nil {
				return status, err
			}
			status.Progress += n
		}
	}
	if status.Complete {
		status.Progress = max(status.Progress, ch.Target)
	}
	return status, nil
}

func (s *Service) personProgress(ctx context.Context, ch db.Challenge, userID int64, counted []db.CountedDay) (int, error) {
	q := s.DB.Pool
	from, to := ch.WeekStart, ch.EndsOn()
	switch ch.Kind {
	case KindSteps:
		total, _, err := db.StepsByUserID(ctx, q, userID, from, to)
		return int(total), err
	case KindWorkouts:
		return db.CountWorkouts(ctx, q, userID, from, to)
	case KindReading:
		return db.ReadingMinutesUser(ctx, q, userID, from, to)
	}
	n := 0
	for _, d := range counted {
		if d.UserID == userID {
			n++
		}
	}
	return n, nil
}

func (s *Service) settleChallenge(ctx context.Context, week score.Date, users []db.User) error {
	ch, err := s.EnsureChallenge(ctx, week)
	if err != nil || ch.CompletedAt != nil {
		return err
	}
	status, err := s.ChallengeProgress(ctx, ch)
	if err != nil || !status.Complete {
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

// Bank reads the pair's spendable gems.
func (s *Service) Bank(ctx context.Context) (int, error) {
	total, err := db.TotalPoints(ctx, s.DB.Pool)
	if err != nil {
		return 0, err
	}
	spent, err := db.SpentGems(ctx, s.DB.Pool)
	return Bank(total, spent), err
}

// settleReward announces, once each, the approved rewards the bank now covers.
func (s *Service) settleReward(ctx context.Context, users []db.User) error {
	bank, err := s.Bank(ctx)
	if err != nil {
		return err
	}
	ready, err := db.MarkRewardsReady(ctx, s.DB.Pool, bank)
	if err != nil {
		return err
	}
	for _, r := range ready {
		for _, u := range users {
			s.Notify(u, push.Message{Kind: EventReward, Title: "Reward ready", Body: r.Name})
		}
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
