package estimate

import (
	"context"
	"errors"
	"net/http"
	"net/http/httptest"
	"sync/atomic"
	"testing"
)

func TestPerMinuteHoldsASlidingMinute(t *testing.T) {
	now := timeNow()
	p := newPerMinute(2, now.get)
	if !p.allow() || !p.allow() || p.allow() {
		t.Fatal("the third call within a minute must wait")
	}
	now.advance(59)
	if p.allow() {
		t.Fatal("the window is a full minute")
	}
	now.advance(1)
	if !p.allow() {
		t.Fatal("calls older than a minute no longer count")
	}
}

func TestOpenFoodFactsStaysInsideItsSearchLimit(t *testing.T) {
	var hits atomic.Int32
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		hits.Add(1)
		_, _ = w.Write([]byte(`{"products":[]}`))
	}))
	defer srv.Close()
	o := NewOpenFoodFacts("test")
	o.BaseURL = srv.URL
	for range 10 {
		if _, err := o.Search(context.Background(), "huel"); err != nil {
			t.Fatal(err)
		}
	}
	if _, err := o.Search(context.Background(), "huel"); !errors.Is(err, ErrLookup) {
		t.Fatalf("eleventh search = %v, want a skipped lookup", err)
	}
	if hits.Load() != 10 {
		t.Fatalf("Open Food Facts saw %d searches, want 10", hits.Load())
	}
}
