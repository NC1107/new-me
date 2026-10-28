package estimate

import (
	"context"
	"errors"
	"net/http"
	"net/http/httptest"
	"runtime"
	"slices"
	"sync"
	"sync/atomic"
	"testing"
	"time"
)

func TestSlidingHoldsAFullWindow(t *testing.T) {
	now := timeNow()
	p := newSliding(2, time.Minute, now.get)
	if got := []bool{p.allow(), p.allow(), p.allow()}; !slices.Equal(got, []bool{true, true, false}) {
		t.Fatalf("three calls in a minute = %v, the third must wait", got)
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

func TestUSDAStaysInsideItsHourlyLimit(t *testing.T) {
	var hits atomic.Int32
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		hits.Add(1)
		_, _ = w.Write([]byte(`{"foods":[]}`))
	}))
	defer srv.Close()
	now := timeNow()
	u := NewUSDA("test-key")
	u.BaseURL = srv.URL
	u.calls = newSliding(3, time.Hour, now.get)
	for range 3 {
		if _, err := u.Search(context.Background(), "apple", typeSRLegacy); err != nil {
			t.Fatal(err)
		}
	}
	if _, err := u.Search(context.Background(), "apple", typeSRLegacy); !errors.Is(err, ErrLookup) || hits.Load() != 3 {
		t.Fatalf("fourth search = %v after %d calls, want it skipped", err, hits.Load())
	}
	now.advance(3600)
	if _, err := u.Search(context.Background(), "apple", typeSRLegacy); err != nil {
		t.Fatalf("an hour later = %v", err)
	}
}

func TestConcurrentLookupsShareOneSearch(t *testing.T) {
	c := newTTLCache(timeNow().get)
	var calls atomic.Int32
	release := make(chan struct{})
	var wg sync.WaitGroup
	for range 5 {
		wg.Add(1)
		go func() {
			defer wg.Done()
			got, err := cached(c, "usda|generic|milk", func() ([]Food, error) {
				calls.Add(1)
				<-release
				return []Food{{ID: "1"}}, nil
			})
			if err != nil || len(got) != 1 {
				t.Errorf("got %v %v", got, err)
			}
		}()
	}
	// Whether a later lookup joins the one in flight or finds its cached answer, the search runs
	// once; no lookup may start its own.
	for calls.Load() == 0 {
		runtime.Gosched()
	}
	close(release)
	wg.Wait()
	if calls.Load() != 1 {
		t.Fatalf("five lookups made %d searches, want 1", calls.Load())
	}
}
