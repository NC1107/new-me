package score

import (
	"testing"
	"time"
)

func TestDateArithmetic(t *testing.T) {
	if got := MustDate("2026-12-31").AddDays(1); got != "2027-01-01" {
		t.Fatalf("year rollover = %s", got)
	}
	if got := MustDate("2026-03-01").AddDays(-1); got != "2026-02-28" {
		t.Fatalf("month rollover = %s", got)
	}
	if _, err := ParseDate("2026-13-01"); err == nil {
		t.Fatal("expected an error for month 13")
	}
	if _, err := ParseDate("26-1-1"); err == nil {
		t.Fatal("expected an error for a loose format")
	}
}

func TestWeekStart(t *testing.T) {
	tests := map[Date]Date{
		"2026-10-26": "2026-10-26",
		"2026-10-28": "2026-10-26",
		"2026-11-01": "2026-10-26",
		"2026-11-02": "2026-11-02",
		"2027-01-01": "2026-12-28",
	}
	for in, want := range tests {
		if got := WeekStart(in); got != want {
			t.Fatalf("WeekStart(%s) = %s, want %s", in, got, want)
		}
	}
}

func TestLocalTodayFollowsTheUsersClock(t *testing.T) {
	ny := mustLoc(t, "America/New_York")
	tokyo := mustLoc(t, "Asia/Tokyo")
	now := time.Date(2026, 10, 26, 2, 30, 0, 0, time.UTC)
	if got := LocalToday(now, ny); got != "2026-10-25" {
		t.Fatalf("New York = %s, want 2026-10-25", got)
	}
	if got := LocalToday(now, tokyo); got != "2026-10-26" {
		t.Fatalf("Tokyo = %s, want 2026-10-26", got)
	}
}

func TestBackdateUntil(t *testing.T) {
	ny := mustLoc(t, "America/New_York")
	tests := []struct {
		name     string
		now      time.Time
		wantOpen bool
	}{
		{"just after midnight", time.Date(2026, 10, 26, 0, 1, 0, 0, ny), true},
		{"one minute before the grace hour", time.Date(2026, 10, 26, 9, 59, 0, 0, ny), true},
		{"at the grace hour", time.Date(2026, 10, 26, 10, 0, 0, 0, ny), false},
		{"evening", time.Date(2026, 10, 26, 21, 0, 0, 0, ny), false},
	}
	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			until, open := BackdateUntil(tc.now, ny)
			if open != tc.wantOpen {
				t.Fatalf("open = %v, want %v", open, tc.wantOpen)
			}
			if open && !until.Equal(time.Date(2026, 10, 26, 10, 0, 0, 0, ny)) {
				t.Fatalf("until = %v", until)
			}
		})
	}
}

func TestDateAllowed(t *testing.T) {
	ny := mustLoc(t, "America/New_York")
	morning := time.Date(2026, 10, 26, 8, 0, 0, 0, ny)
	evening := time.Date(2026, 10, 26, 20, 0, 0, 0, ny)
	tests := []struct {
		name string
		date Date
		now  time.Time
		want DateAccess
	}{
		{"today in the morning", "2026-10-26", morning, DateToday},
		{"yesterday within grace", "2026-10-25", morning, DateYesterday},
		{"yesterday after grace", "2026-10-25", evening, DateClosed},
		{"two days ago", "2026-10-24", morning, DateClosed},
		{"tomorrow", "2026-10-27", morning, DateClosed},
	}
	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			if got := DateAllowed(tc.date, tc.now, ny); got != tc.want {
				t.Fatalf("got %d, want %d", got, tc.want)
			}
		})
	}
	if DateClosed.Open() || !DateToday.Open() || !DateYesterday.Open() {
		t.Fatal("Open() disagrees with the access values")
	}
}

func TestWindowAcrossDSTTransitions(t *testing.T) {
	ny := mustLoc(t, "America/New_York")
	// 2026-03-08 loses an hour at 02:00 and 2026-11-01 gains one; the grace hour is wall-clock.
	for _, day := range []time.Time{
		time.Date(2026, 3, 8, 9, 30, 0, 0, ny),
		time.Date(2026, 11, 1, 9, 30, 0, 0, ny),
	} {
		date := DateOf(day)
		if got := DateAllowed(date.AddDays(-1), day, ny); got != DateYesterday {
			t.Fatalf("%s 09:30: yesterday = %d, want open", date, got)
		}
		if got := DateAllowed(date.AddDays(-1), day.Add(time.Hour), ny); got != DateClosed {
			t.Fatalf("%s 10:30: yesterday = %d, want closed", date, got)
		}
	}
}

func TestFinalizeAt(t *testing.T) {
	ny := mustLoc(t, "America/New_York")
	want := time.Date(2026, 3, 9, 10, 0, 0, 0, ny)
	if got := FinalizeAt("2026-03-08", ny); !got.Equal(want) {
		t.Fatalf("FinalizeAt over spring forward = %v, want %v", got, want)
	}
	if got := FinalizeAt("2026-12-31", ny); !got.Equal(time.Date(2027, 1, 1, 10, 0, 0, 0, ny)) {
		t.Fatalf("FinalizeAt over new year = %v", got)
	}
}
