package coach

import (
	"context"
	"testing"
	"time"
)

func TestFailuresPastTheRetryWindowArePruned(t *testing.T) {
	now := time.Date(2026, 11, 2, 12, 0, 0, 0, time.UTC)
	p := &Polisher{Now: func() time.Time { return now }, failedAt: map[string]time.Time{
		"old":    now.Add(-polishRetryAfter - time.Second),
		"recent": now.Add(-time.Minute),
	}}
	p.pruneFailures()
	if _, ok := p.failedAt["old"]; ok || len(p.failedAt) != 1 {
		t.Fatalf("failedAt = %v, want only the recent failure", p.failedAt)
	}
}

func TestWaitContextGivesUpAtTheDeadline(t *testing.T) {
	p := &Polisher{}
	p.wg.Add(1)
	ctx, cancel := context.WithTimeout(context.Background(), 20*time.Millisecond)
	defer cancel()
	if err := p.WaitContext(ctx); err == nil {
		t.Fatal("WaitContext returned nil with a call still running")
	}
	p.wg.Done()
	if err := p.WaitContext(context.Background()); err != nil {
		t.Fatal(err)
	}
}
