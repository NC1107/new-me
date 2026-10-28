package estimate

import (
	"sync"
	"time"
)

// perMinute allows at most max calls in any sliding minute. It is not the ratelimit package's
// token bucket because a bucket lets a full burst and its refill through within one minute,
// which breaks a hard per-minute cap set by someone else.
type perMinute struct {
	mu    sync.Mutex
	max   int
	now   func() time.Time
	calls []time.Time
}

func newPerMinute(max int, now func() time.Time) *perMinute {
	return &perMinute{max: max, now: now}
}

// allow records a call and reports true, or reports false without recording when the last
// minute already holds max calls. A nil limiter allows everything.
func (p *perMinute) allow() bool {
	if p == nil {
		return true
	}
	p.mu.Lock()
	defer p.mu.Unlock()
	now := p.now()
	kept := p.calls[:0]
	for _, t := range p.calls {
		if now.Sub(t) < time.Minute {
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
