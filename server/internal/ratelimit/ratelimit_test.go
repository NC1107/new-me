package ratelimit

import (
	"testing"
	"time"
)

func fakeClock(start time.Time) (*time.Time, func() time.Time) {
	t := start
	return &t, func() time.Time { return t }
}

func TestBurstThenDeny(t *testing.T) {
	l := New(60, 3)
	for i := range 3 {
		if ok, _ := l.Allow("ip"); !ok {
			t.Fatalf("burst token %d should be allowed", i)
		}
	}
	if ok, _ := l.Allow("ip"); ok {
		t.Fatal("expected a denial once the burst is spent")
	}
	if ok, _ := l.Allow("other"); !ok {
		t.Fatal("a different key must have its own bucket")
	}
}

func TestRefillAndRetryAfter(t *testing.T) {
	l := New(60, 2)
	now, clock := fakeClock(time.Date(2026, 10, 26, 8, 0, 0, 0, time.UTC))
	l.now = clock
	l.Allow("ip")
	l.Allow("ip")
	ok, retry := l.Allow("ip")
	if ok || retry != time.Second {
		t.Fatalf("empty bucket = (%v, %v), want (false, 1s)", ok, retry)
	}
	*now = now.Add(1500 * time.Millisecond)
	if ok, _ := l.Allow("ip"); !ok {
		t.Fatal("a token should have refilled after 1.5s")
	}
	if ok, _ := l.Allow("ip"); ok {
		t.Fatal("only one token should have refilled")
	}
}

func TestIdleBucketsAreEvicted(t *testing.T) {
	l := New(60, 2)
	now, clock := fakeClock(time.Date(2026, 10, 26, 8, 0, 0, 0, time.UTC))
	l.now = clock
	l.lastEvict = *now
	l.Allow("old")
	*now = now.Add(11 * time.Minute)
	l.Allow("new")
	if _, kept := l.buckets["old"]; kept {
		t.Fatal("the idle bucket should have been swept")
	}
}

func TestWindowCapsEventsPerKeyAndReleasesThemWhenTheyAgeOut(t *testing.T) {
	now := time.Date(2026, 11, 2, 12, 0, 0, 0, time.UTC)
	w := NewWindow(3, time.Hour)
	w.now = func() time.Time { return now }
	for i := range 3 {
		if ok, _ := w.Allow("a"); !ok {
			t.Fatalf("event %d refused", i)
		}
		now = now.Add(10 * time.Minute)
	}
	ok, retry := w.Allow("a")
	if ok || retry != 30*time.Minute {
		t.Fatalf("fourth = %v retry %v, want refused with 30m", ok, retry)
	}
	if ok, _ := w.Allow("b"); !ok {
		t.Fatal("another key must have its own allowance")
	}
	now = now.Add(31 * time.Minute)
	if ok, _ := w.Allow("a"); !ok {
		t.Fatal("the oldest event should have left the window")
	}
}
