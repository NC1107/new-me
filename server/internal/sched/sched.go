// Package sched finalizes finished days in the background, so a streak never depends on the
// app being opened or the server having stayed up.
package sched

import (
	"context"
	"errors"
	"fmt"
	"log"
	"time"

	"github.com/jackc/pgx/v5"

	"github.com/nc1107/new-me/server/internal/db"
	"github.com/nc1107/new-me/server/internal/engine"
	"github.com/nc1107/new-me/server/internal/listening"
	"github.com/nc1107/new-me/server/internal/score"
)

const (
	// Interval is how often the scheduler looks for days to finalize.
	Interval = 5 * time.Minute
	// ListeningInterval is how often linked Audiobookshelf accounts are polled.
	ListeningInterval = 15 * time.Minute
	// runTimeout bounds one pass, so a stuck query cannot pile up passes behind it.
	runTimeout = 2 * time.Minute
)

// Scheduler finalizes every day whose grace window has ended and, when Audiobookshelf is set
// up, keeps listening time current.
type Scheduler struct {
	DB  *db.DB
	Now func() time.Time
	// Listening is nil while the Audiobookshelf feature is off.
	Listening *listening.Syncer
}

// New builds a scheduler on the wall clock.
func New(database *db.DB) *Scheduler {
	return &Scheduler{DB: database, Now: time.Now}
}

// Run does one pass immediately, which catches up after a restart, then repeats every Interval
// until ctx ends. Listening polls run on their own, slower ticker so a slow Audiobookshelf
// never delays finalizing.
func (s *Scheduler) Run(ctx context.Context) {
	if s.Listening != nil {
		go s.runListening(ctx)
	}
	s.runGuarded(ctx, s.FinalizeDue)
	ticker := time.NewTicker(Interval)
	defer ticker.Stop()
	for {
		select {
		case <-ctx.Done():
			return
		case <-ticker.C:
			s.runGuarded(ctx, s.FinalizeDue)
		}
	}
}

func (s *Scheduler) runListening(ctx context.Context) {
	s.runGuarded(ctx, s.PollListening)
	ticker := time.NewTicker(ListeningInterval)
	defer ticker.Stop()
	for {
		select {
		case <-ctx.Done():
			return
		case <-ticker.C:
			s.runGuarded(ctx, s.PollListening)
		}
	}
}

// PollListening reads every linked Audiobookshelf account once.
func (s *Scheduler) PollListening(ctx context.Context) error {
	if s.Listening == nil {
		return nil
	}
	return s.Listening.SyncAll(ctx)
}

// runGuarded keeps a panic or a slow pass from taking the scheduler down.
func (s *Scheduler) runGuarded(ctx context.Context, pass func(context.Context) error) {
	defer func() {
		if r := recover(); r != nil {
			log.Printf("[NEWME] scheduler panic: %v", r)
		}
	}()
	passCtx, cancel := context.WithTimeout(ctx, runTimeout)
	defer cancel()
	// A pass cut short by shutdown is expected; one cut short by its own timeout is not.
	if err := pass(passCtx); err != nil && ctx.Err() == nil {
		log.Printf("[NEWME] scheduler: %v", err)
	}
}

// FinalizeDue scores and finalizes every local date that has passed its grace window and has no
// finalized score yet, from each user's first date on. One failing user or date does not stop
// the others; the errors come back together.
func (s *Scheduler) FinalizeDue(ctx context.Context) error {
	now := s.Now()
	users, err := db.ListUsers(ctx, s.DB.Pool)
	if err != nil {
		return fmt.Errorf("list users: %w", err)
	}
	var errs []error
	for _, u := range users {
		if err := s.finalizeUser(ctx, u, now); err != nil {
			errs = append(errs, fmt.Errorf("user %d: %w", u.ID, err))
		}
	}
	return errors.Join(errs...)
}

func (s *Scheduler) finalizeUser(ctx context.Context, u db.User, now time.Time) error {
	u, err := db.SwitchTimezoneIfDue(ctx, s.DB.Pool, u, now)
	if err != nil {
		return err
	}
	loc, err := u.Location()
	if err != nil {
		return err
	}
	dates, err := db.UnfinalizedDates(ctx, s.DB.Pool, u.ID, u.JoinedOn, lastFinalizable(now, loc))
	if err != nil {
		return err
	}
	for _, date := range dates {
		err := s.DB.WithTx(ctx, func(tx pgx.Tx) error {
			_, err := engine.RecomputeDayAt(ctx, tx, u.ID, date, loc, now)
			return err
		})
		if err != nil {
			return fmt.Errorf("finalize %s: %w", date, err)
		}
	}
	return nil
}

// lastFinalizable is the newest local date whose grace window has ended: yesterday once it is
// past the grace hour, the day before otherwise.
func lastFinalizable(now time.Time, loc *time.Location) score.Date {
	yesterday := score.LocalToday(now, loc).AddDays(-1)
	if now.Before(score.FinalizeAt(yesterday, loc)) {
		return yesterday.AddDays(-1)
	}
	return yesterday
}
