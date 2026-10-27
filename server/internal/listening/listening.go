// Package listening keeps each linked person's Audiobookshelf listening time current and
// folds it into the days it belongs to.
package listening

import (
	"context"
	"errors"
	"fmt"
	"math"
	"sync"
	"time"

	"github.com/jackc/pgx/v5"

	"github.com/nc1107/new-me/server/internal/abs"
	"github.com/nc1107/new-me/server/internal/db"
	"github.com/nc1107/new-me/server/internal/engine"
	"github.com/nc1107/new-me/server/internal/score"
)

// refreshLead is how long before an access token expires it is refreshed, so a poll never
// starts with a token about to die.
const refreshLead = 2 * time.Minute

// maxDayMinutes matches the listening_daily bound, so an odd server clock or bad data cannot
// violate the constraint.
const maxDayMinutes = 24 * 60

// Syncer polls Audiobookshelf for linked accounts.
type Syncer struct {
	DB  *db.DB
	ABS *abs.Client
	Now func() time.Time
}

// New builds a syncer on the wall clock for the Audiobookshelf at baseURL.
func New(database *db.DB, baseURL string) *Syncer {
	return &Syncer{DB: database, ABS: abs.New(baseURL), Now: time.Now}
}

// userLocks serializes syncs of one account. Audiobookshelf rotates the refresh token on each
// refresh, so two overlapping syncs would race to store the newer one.
var userLocks sync.Map

func lockUser(id int64) func() {
	m, _ := userLocks.LoadOrStore(id, &sync.Mutex{})
	mu := m.(*sync.Mutex)
	mu.Lock()
	return mu.Unlock
}

// SyncAll syncs every linked account. One failing account does not stop the others.
func (s *Syncer) SyncAll(ctx context.Context) error {
	accounts, err := db.ListABSAccounts(ctx, s.DB.Pool)
	if err != nil {
		return fmt.Errorf("list audiobookshelf accounts: %w", err)
	}
	var errs []error
	for _, a := range accounts {
		if err := s.SyncUser(ctx, a.UserID); err != nil {
			errs = append(errs, fmt.Errorf("user %d: %w", a.UserID, err))
		}
	}
	return errors.Join(errs...)
}

// SyncUser reads the user's recent listening and rescores the open days it changed. Failures
// are recorded on the account, which stays linked. A rejected sign-in is recorded and not
// returned, because only the person can fix it; anything else is returned for the log.
func (s *Syncer) SyncUser(ctx context.Context, userID int64) error {
	defer lockUser(userID)()
	acct, err := db.GetABSAccount(ctx, s.DB.Pool, userID)
	if errors.Is(err, db.ErrNotFound) {
		return nil
	}
	if err != nil {
		return err
	}
	days, err := s.fetch(ctx, acct)
	switch {
	case errors.Is(err, abs.ErrAuth):
		return s.record(ctx, userID, db.ABSErrorAuth, nil)
	case err != nil:
		return s.record(ctx, userID, db.ABSErrorUnreachable, err)
	}
	if err := s.apply(ctx, userID, days); err != nil {
		return err
	}
	return db.MarkABSSynced(ctx, s.DB.Pool, userID, s.Now())
}

func (s *Syncer) record(ctx context.Context, userID int64, code string, cause error) error {
	if err := db.MarkABSError(ctx, s.DB.Pool, userID, code); err != nil {
		return err
	}
	return cause
}

// fetch reads listening seconds per date, refreshing the session first when it is about to
// expire and once more if Audiobookshelf still rejects the access token.
func (s *Syncer) fetch(ctx context.Context, acct db.ABSAccount) (map[string]float64, error) {
	sess := abs.Session{
		UserID: acct.ABSUserID, Username: acct.Username, AccessToken: acct.AccessToken,
		RefreshToken: acct.RefreshToken, AccessExpires: acct.AccessExpiresAt,
	}
	refreshed := false
	refresh := func() error {
		next, err := s.ABS.Refresh(ctx, sess)
		if err != nil {
			return err
		}
		sess = next
		refreshed = true
		return db.SaveABSTokens(ctx, s.DB.Pool, acct.UserID, sess.AccessToken, sess.RefreshToken, sess.AccessExpires)
	}
	if !s.Now().Add(refreshLead).Before(sess.AccessExpires) {
		if err := refresh(); err != nil {
			return nil, err
		}
	}
	days, err := s.ABS.ListeningSeconds(ctx, sess.AccessToken)
	if errors.Is(err, abs.ErrAuth) && !refreshed {
		if err := refresh(); err != nil {
			return nil, err
		}
		days, err = s.ABS.ListeningSeconds(ctx, sess.AccessToken)
	}
	return days, err
}

// apply stores minutes for the user's still-open days and rescores the ones that changed.
// Finalized days are never touched, so history cannot move after the grace window.
func (s *Syncer) apply(ctx context.Context, userID int64, seconds map[string]float64) error {
	now := s.Now()
	user, err := db.GetUser(ctx, s.DB.Pool, userID)
	if err != nil {
		return err
	}
	if user, err = db.SwitchTimezoneIfDue(ctx, s.DB.Pool, user, now); err != nil {
		return err
	}
	loc, err := user.Location()
	if err != nil {
		return err
	}
	for _, date := range OpenDates(user.JoinedOn, now, loc) {
		minutes := MinutesFromSeconds(seconds[string(date)])
		err := s.DB.WithTx(ctx, func(tx pgx.Tx) error {
			if err := db.LockUserDay(ctx, tx, userID, date); err != nil {
				return err
			}
			if have, err := db.ListeningMinutes(ctx, tx, userID, date); err != nil || have == minutes {
				return err
			}
			if err := db.UpsertListening(ctx, tx, userID, date, minutes, now); err != nil {
				return err
			}
			_, err := engine.RecomputeDayAt(ctx, tx, userID, date, loc, now)
			return err
		})
		if err != nil {
			return fmt.Errorf("store %s: %w", date, err)
		}
	}
	return nil
}

// OpenDates are the local dates that can still change: today, and yesterday until its grace
// window ends. Dates before the person joined are left out.
func OpenDates(joined score.Date, now time.Time, loc *time.Location) []score.Date {
	today := score.LocalToday(now, loc)
	var out []score.Date
	for _, d := range []score.Date{today.AddDays(-1), today} {
		if !d.Before(joined) && now.Before(score.FinalizeAt(d, loc)) {
			out = append(out, d)
		}
	}
	return out
}

// MinutesFromSeconds rounds listening down to whole minutes, like Health values, and keeps it
// inside what a day can hold.
func MinutesFromSeconds(seconds float64) int {
	if seconds <= 0 || math.IsNaN(seconds) {
		return 0
	}
	return int(math.Min(math.Floor(seconds/60), maxDayMinutes))
}

// Link stores a fresh sign-in for the user and reads their listening right away, so the first
// answer already reflects today. The sync outcome lands on the account, so its failure does
// not fail the link.
func (s *Syncer) Link(ctx context.Context, userID int64, sess abs.Session) (db.ABSAccount, error) {
	unlock := lockUser(userID)
	_, err := db.LinkABSAccount(ctx, s.DB.Pool, db.ABSAccount{
		UserID: userID, ABSUserID: sess.UserID, Username: sess.Username, AccessToken: sess.AccessToken,
		RefreshToken: sess.RefreshToken, AccessExpiresAt: sess.AccessExpires,
	})
	unlock()
	if err != nil {
		return db.ABSAccount{}, err
	}
	// A failed first poll is already recorded as last_error, which the app shows.
	_ = s.SyncUser(ctx, userID)
	return db.GetABSAccount(ctx, s.DB.Pool, userID)
}

// Unlink removes the link and the minutes of the still-open days, then rescores those days so
// they no longer count them. Finalized days keep theirs. It reports whether there was a link.
func (s *Syncer) Unlink(ctx context.Context, user db.User, loc *time.Location) (bool, error) {
	defer lockUser(user.ID)()
	var had bool
	err := s.DB.WithTx(ctx, func(tx pgx.Tx) error {
		var err error
		if had, err = db.DeleteABSAccount(ctx, tx, user.ID); err != nil {
			return err
		}
		now := s.Now()
		for _, date := range OpenDates(user.JoinedOn, now, loc) {
			if err := db.LockUserDay(ctx, tx, user.ID, date); err != nil {
				return err
			}
			if err := db.DeleteListening(ctx, tx, user.ID, date); err != nil {
				return err
			}
			if _, err := engine.RecomputeDayAt(ctx, tx, user.ID, date, loc, now); err != nil {
				return err
			}
		}
		return nil
	})
	return had, err
}
