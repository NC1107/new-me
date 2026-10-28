package coach

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/nc1107/new-me/server/internal/anthropic"
)

func claudeSays(t *testing.T, text string) *Polisher {
	t.Helper()
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		_ = json.NewEncoder(w).Encode(map[string]any{
			"content": []map[string]string{{"type": "text", "text": text}}})
	}))
	t.Cleanup(srv.Close)
	return &Polisher{Client: anthropic.New("test-key", srv.URL)}
}

func fitsNinety(s string) bool { return len([]rune(s)) < 90 }

func TestVaryAcceptsWordingThatAddsNoFacts(t *testing.T) {
	p := claudeSays(t, "Sam did 10,432 steps today. Cheer them on?")
	got := p.Vary(context.Background(), "Sam did 10,432 steps today. A cheer is one tap away.", fitsNinety)
	if got != "Sam did 10,432 steps today. Cheer them on?" {
		t.Fatalf("got %q", got)
	}
}

func TestVaryRejectsAnInventedNumber(t *testing.T) {
	original := "You hold 2 freezes. One could keep Sam's streak going."
	p := claudeSays(t, "You hold 3 freezes. One could keep Sam's streak going.")
	if got := p.Vary(context.Background(), original, fitsNinety); got != original {
		t.Fatalf("an invented figure got through: %q", got)
	}
}

func TestVaryRejectsTextThatBreaksTheCallersRules(t *testing.T) {
	original := "6,000 steps left on your share, with 4 days to go."
	for name, reply := range map[string]string{
		"too long":  "6,000 steps left on your share, with 4 days to go, so a walk tonight would help a lot.",
		"two lines": "6,000 steps left.\nWith 4 days to go.",
	} {
		p := claudeSays(t, reply)
		if got := p.Vary(context.Background(), original, func(s string) bool { return len(s) < 60 }); got != original {
			t.Errorf("%s: got %q", name, got)
		}
	}
}

func TestVaryKeepsTheOriginalWithoutAKeyAndOnFailure(t *testing.T) {
	original := "Sam did 30 push-ups today. A cheer is one tap away."
	var none *Polisher
	if got := none.Vary(context.Background(), original, fitsNinety); got != original {
		t.Errorf("nil polisher changed the text: %q", got)
	}
	if got := (&Polisher{}).Vary(context.Background(), original, fitsNinety); got != original {
		t.Errorf("polisher without a client changed the text: %q", got)
	}
	down := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		http.Error(w, strings.Repeat("x", 10), http.StatusInternalServerError)
	}))
	defer down.Close()
	failing := &Polisher{Client: anthropic.New("test-key", down.URL)}
	if got := failing.Vary(context.Background(), original, fitsNinety); got != original {
		t.Errorf("a failed call changed the text: %q", got)
	}
}
