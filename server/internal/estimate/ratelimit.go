package estimate

import (
	"sync"
	"time"
)

// sliding allows at most max calls in any sliding window. It is not the ratelimit package's
// token bucket because a bucket lets a full burst and its refill through within one window,
// which breaks a hard cap set by someone else.
type sliding struct {
	mu     sync.Mutex
	max    int
	window time.Duration
	now    func() time.Time
	calls  []time.Time
}

func newSliding(max int, window time.Duration, now func() time.Time) *sliding {
	return &sliding{max: max, window: window, now: now}
}

// allow records a call and reports true, or reports false without recording when the last
// window already holds max calls. A nil limiter allows everything.
func (p *sliding) allow() bool {
	if p == nil {
		return true
	}
	p.mu.Lock()
	defer p.mu.Unlock()
	now := p.now()
	kept := p.calls[:0]
	for _, t := range p.calls {
		if now.Sub(t) < p.window {
			kept = append(kept, t)
		}
	}
	p.calls = kept
	if len(p.calls) >= p.max {
		return false
	}
	p.calls = append(p.calls, now)
	return true
}
