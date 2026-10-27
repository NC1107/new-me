// Package score holds the pure scoring rules: points, day scores, streaks, seasons and the
// local-date window logic. It touches no database and no clock, so every rule is table-tested.
package score

import (
	"fmt"
	"time"
)

// GraceHours is how long after local midnight yesterday stays open for backdated entries,
// and also when a finished day is finalized.
const GraceHours = 10

// Date is a calendar day as "YYYY-MM-DD" with no time zone. Strings compare in date order and
// all arithmetic happens on UTC calendar days, so DST can never shift a day.
type Date string

// ParseDate validates an ISO calendar date.
func ParseDate(s string) (Date, error) {
	t, err := time.Parse(time.DateOnly, s)
	if err != nil {
		return "", fmt.Errorf("invalid date %q: %w", s, err)
	}
	return Date(t.Format(time.DateOnly)), nil
}

// MustDate parses a literal known to be valid and panics otherwise.
func MustDate(s string) Date {
	d, err := ParseDate(s)
	if err != nil {
		panic(err)
	}
	return d
}

// DateOf is the calendar date t shows on the wall clock of its own location.
func DateOf(t time.Time) Date {
	return Date(t.Format(time.DateOnly))
}

// Time is midnight UTC on the date; the zero time if the date is malformed.
func (d Date) Time() time.Time {
	t, err := time.Parse(time.DateOnly, string(d))
	if err != nil {
		return time.Time{}
	}
	return t
}

// AddDays moves the date by n calendar days.
func (d Date) AddDays(n int) Date {
	return DateOf(d.Time().AddDate(0, 0, n))
}

// Before reports whether d is an earlier day than other.
func (d Date) Before(other Date) bool { return d < other }

// After reports whether d is a later day than other.
func (d Date) After(other Date) bool { return d > other }

// Weekday is the day of the week of the calendar date.
func (d Date) Weekday() time.Weekday { return d.Time().Weekday() }

// WeekStart is the Monday on or before the date, the key of its ISO week.
func WeekStart(d Date) Date {
	offset := (int(d.Weekday()) + 6) % 7
	return d.AddDays(-offset)
}

// LocalToday is the user's current calendar day.
func LocalToday(now time.Time, loc *time.Location) Date {
	return DateOf(now.In(loc))
}

// BackdateUntil returns the instant yesterday stops accepting entries, or false when that
// window has already closed for the local day.
func BackdateUntil(now time.Time, loc *time.Location) (time.Time, bool) {
	local := now.In(loc)
	if local.Hour() >= GraceHours {
		return time.Time{}, false
	}
	y, m, d := local.Date()
	return time.Date(y, m, d, GraceHours, 0, 0, 0, loc), true
}

// FinalizeAt is the instant a day becomes immutable: the grace hour on the following day.
func FinalizeAt(date Date, loc *time.Location) time.Time {
	t := date.Time()
	return time.Date(t.Year(), t.Month(), t.Day()+1, GraceHours, 0, 0, 0, loc)
}

// DateAccess says whether a date may still be written.
type DateAccess int

const (
	// DateClosed covers the future and any day past its grace window.
	DateClosed DateAccess = iota
	// DateToday is the user's current local day.
	DateToday
	// DateYesterday is yesterday while the grace window is open.
	DateYesterday
)

// Open reports whether entries may be written to the date.
func (a DateAccess) Open() bool { return a != DateClosed }

// DateAllowed classifies date against the user's local clock.
func DateAllowed(date Date, now time.Time, loc *time.Location) DateAccess {
	today := LocalToday(now, loc)
	switch {
	case date == today:
		return DateToday
	case date == today.AddDays(-1):
		if _, open := BackdateUntil(now, loc); open {
			return DateYesterday
		}
	}
	return DateClosed
}
