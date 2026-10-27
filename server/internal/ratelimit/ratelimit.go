// Package ratelimit is a small in-memory token bucket keyed by an arbitrary string. It is
// enough for one server process; a multi-instance deployment would need a shared store.
package ratelimit

import (
	"math"
	"sync"
	"time"
)

// evictInterval is how often idle buckets are swept. Driven by elapsed time rather than a call
// counter so an idle server still releases memory.
const evictInterval = 5 * time.Minute

// idleAfter is how long a bucket may go untouched before the sweep drops it.
const idleAfter = 10 * time.Minute

// Limiter hands out tokens per key at a steady rate up to a burst.
type Limiter struct {
	mu        sync.Mutex
	buckets   map[string]*bucket
	rate      float64 // tokens per second
	burst     float64
	lastEvict time.Time
	now       func() time.Time
}

type bucket struct {
	tokens float64
	last   time.Time
}

// New builds a limiter that refills perMinute tokens a minute and holds at most burst.
func New(perMinute, burst int) *Limiter {
	return &Limiter{
		buckets:   make(map[string]*bucket),
		rate:      float64(perMinute) / 60.0,
		burst:     float64(burst),
		lastEvict: time.Now(),
		now:       time.Now,
	}
}

// Allow consumes one token for key. When none is left it reports how long until one is.
func (l *Limiter) Allow(key string) (ok bool, retryAfter time.Duration) {
	l.mu.Lock()
	defer l.mu.Unlock()
	now := l.now()
	if now.Sub(l.lastEvict) > evictInterval {
		l.evictIdle(now)
		l.lastEvict = now
	}
	b, found := l.buckets[key]
	if !found {
		l.buckets[key] = &bucket{tokens: l.burst - 1, last: now}
		return true, 0
	}
	b.tokens = math.Min(l.burst, b.tokens+now.Sub(b.last).Seconds()*l.rate)
	b.last = now
	if b.tokens >= 1 {
		b.tokens--
		return true, 0
	}
	missing := 1 - b.tokens
	return false, time.Duration(missing / l.rate * float64(time.Second))
}

// evictIdle drops buckets nobody has touched for a while. Callers hold l.mu.
func (l *Limiter) evictIdle(now time.Time) {
	cutoff := now.Add(-idleAfter)
	for k, b := range l.buckets {
		if b.last.Before(cutoff) {
			delete(l.buckets, k)
		}
	}
}

// Window allows at most limit events per key within a sliding window. Unlike the token bucket
// it never forgets a spent allowance early, which is what a per-hour spending cap needs.
type Window struct {
	mu     sync.Mutex
	events map[string][]time.Time
	limit  int
	window time.Duration
	now    func() time.Time
}

// NewWindow builds a sliding-window limiter.
func NewWindow(limit int, window time.Duration) *Window {
	return &Window{events: make(map[string][]time.Time), limit: limit, window: window, now: time.Now}
}

// Allow records an event for key unless the window is full, in which case it reports when the
// oldest event leaves the window.
func (w *Window) Allow(key string) (ok bool, retryAfter time.Duration) {
	w.mu.Lock()
	defer w.mu.Unlock()
	now := w.now()
	cutoff := now.Add(-w.window)
	kept := w.events[key][:0]
	for _, t := range w.events[key] {
		if t.After(cutoff) {
			kept = append(kept, t)
		}
	}
	if len(kept) >= w.limit {
		w.events[key] = kept
		return false, kept[0].Add(w.window).Sub(now)
	}
	w.events[key] = append(kept, now)
	return true, 0
}
