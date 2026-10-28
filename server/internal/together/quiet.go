package together

import (
	"context"
	"log"
	"time"

	"github.com/nc1107/new-me/server/internal/db"
	"github.com/nc1107/new-me/server/internal/score"
)

// safetyKinds are the pushes that ignore quiet hours and away days. No push today is about
// safety, so the set is empty; a kind added here is delivered at any hour.
var safetyKinds = map[string]bool{}

const (
	heldLookupTimeout = 3 * time.Second
	// nextAllowedHorizon bounds the search for the end of quiet hours. Away spans longer than
	// this are re-checked by the scheduler when a held push comes due.
	nextAllowedHorizon = 48 * time.Hour
)

// Quiet reports whether a push should wait for the person at the instant: outside the window
// between their first notification of the day and their bedtime, or on a day inside an away span.
// Both are read in the person's own zone and schedule.
func Quiet(schedule score.Schedule, loc *time.Location, away []db.AwaySpan, now time.Time) bool {
	local := now.In(loc)
	today := score.LocalToday(now, loc)
	for _, sp := range away {
		if sp.Contains(today) {
			return true
		}
	}
	return schedule.Quiet(today, local.Hour()*60+local.Minute())
}

// Held reports whether a push of the kind must not reach the person right now. This is the one
// quiet-hours and away-day rule for every push sent through Deliver. A failed away lookup does
// not hold the push back.
func (s *Service) Held(to db.User, kind string) bool {
	held, _ := s.holdUntil(to, kind)
	return held
}

// holdUntil reports whether a push of the kind is held for the person right now and, if so, the
// next instant it may be delivered.
func (s *Service) holdUntil(to db.User, kind string) (bool, time.Time) {
	if safetyKinds[kind] {
		return false, time.Time{}
	}
	loc, err := to.Location()
	if err != nil {
		return false, time.Time{}
	}
	now := s.now()
	var spans []db.AwaySpan
	if s.DB != nil {
		ctx, cancel := context.WithTimeout(context.Background(), heldLookupTimeout)
		defer cancel()
		if spans, err = db.AwaySpansFrom(ctx, s.DB.Pool, to.ID, score.LocalToday(now, loc)); err != nil {
			log.Printf("[NEWME] away lookup for user %d: %v", to.ID, err)
			spans = nil
		}
	}
	if !Quiet(to.Schedule, loc, spans, now) {
		return false, time.Time{}
	}
	return true, nextAllowed(to.Schedule, loc, spans, now)
}

// nextAllowed is the first minute after now that is outside quiet hours and away days. When none
// is found within the search horizon (a very long away span) it is the horizon's end, and the
// scheduler asks again then.
func nextAllowed(schedule score.Schedule, loc *time.Location, spans []db.AwaySpan, now time.Time) time.Time {
	at := now.Truncate(time.Minute).Add(time.Minute)
	for end := at.Add(nextAllowedHorizon); at.Before(end); at = at.Add(time.Minute) {
		if !Quiet(schedule, loc, spans, at) {
			return at
		}
	}
	return at
}

func (s *Service) now() time.Time {
	if s.Now != nil {
		return s.Now()
	}
	return time.Now()
}
