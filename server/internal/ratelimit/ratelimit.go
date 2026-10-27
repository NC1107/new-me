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
