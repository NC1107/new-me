package api

import (
	"io"
	"net/http"
	"net/http/httptest"
	"strings"
	"sync/atomic"
	"testing"
	"time"

	"github.com/nc1107/new-me/server/internal/ratelimit"
	"github.com/nc1107/new-me/server/internal/voice"
)

func withVoice(t *testing.T, calls *atomic.Int32) func(*Server) {
	fake := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		calls.Add(1)
		_, _ = io.Copy(io.Discard, r.Body)
		_, _ = w.Write([]byte("ID3 fake audio"))
	}))
	t.Cleanup(fake.Close)
	return func(s *Server) { s.voice = voice.New(fake.URL, "af_heart", 0.8, t.TempDir()) }
}

func TestVoiceIsOffWithoutASidecar(t *testing.T) {
	h := newHarness(t)
	nick := h.joinAdmin("Nick", "green")
	h.post("/api/voice", nick.Token, obj{"text": "Breathe in"}).expect(http.StatusNotFound).code("voice_disabled")
	if h.get("/api/me", nick.Token).flag("features.voice") {
		t.Fatal("features.voice must be false without a sidecar")
	}
}

func TestVoiceNeedsADeviceToken(t *testing.T) {
	var calls atomic.Int32
	h := newHarness(t, withVoice(t, &calls))
	h.post("/api/voice", "", obj{"text": "Breathe in"}).expect(http.StatusUnauthorized)
	if calls.Load() != 0 {
		t.Fatal("the sidecar must not be reached without a token")
	}
}

func TestVoiceSpeaksOnceAndServesTheCachedLineAfter(t *testing.T) {
	var calls atomic.Int32
	h := newHarness(t, withVoice(t, &calls))
	nick := h.joinAdmin("Nick", "green")
	if !h.get("/api/me", nick.Token).flag("features.voice") {
		t.Fatal("features.voice must be true with a sidecar")
	}
	for range 3 {
		got := h.post("/api/voice", nick.Token, obj{"text": "  Breathe in... and out.  "}).expect(http.StatusOK)
		if got.Header.Get("Content-Type") != "audio/mpeg" || string(got.Body) != "ID3 fake audio" {
			t.Fatalf("response = %v %q", got.Header, got.Body)
		}
		if !strings.Contains(got.Header.Get("Cache-Control"), "immutable") {
			t.Fatalf("cache control = %q", got.Header.Get("Cache-Control"))
		}
	}
	if calls.Load() != 1 {
		t.Fatalf("sidecar calls = %d, want 1", calls.Load())
	}
}

func TestVoiceRejectsBadText(t *testing.T) {
	var calls atomic.Int32
	h := newHarness(t, withVoice(t, &calls))
	nick := h.joinAdmin("Nick", "green")
	for name, text := range map[string]string{
		"empty":    "   ",
		"too long": strings.Repeat("a", voice.MaxRunes+1),
		"control":  "Breathe\x07 in",
	} {
		t.Run(name, func(t *testing.T) {
			h.post("/api/voice", nick.Token, obj{"text": text}).expect(http.StatusUnprocessableEntity)
		})
	}
	if calls.Load() != 0 {
		t.Fatal("bad text must not reach the sidecar")
	}
}

func TestVoiceLimitsNewLinesButNotCachedOnes(t *testing.T) {
	var calls atomic.Int32
	h := newHarness(t, withVoice(t, &calls), func(s *Server) { s.voices = ratelimit.NewWindow(2, time.Hour) })
	nick := h.joinAdmin("Nick", "green")
	h.post("/api/voice", nick.Token, obj{"text": "one"}).expect(http.StatusOK)
	h.post("/api/voice", nick.Token, obj{"text": "two"}).expect(http.StatusOK)
	limited := h.post("/api/voice", nick.Token, obj{"text": "three"}).expect(http.StatusTooManyRequests)
	if limited.Header.Get("Retry-After") == "" {
		t.Fatal("want Retry-After")
	}
	h.post("/api/voice", nick.Token, obj{"text": "one"}).expect(http.StatusOK)
}

func TestVoiceReportsASidecarFailure(t *testing.T) {
	down := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		http.Error(w, "boom", http.StatusInternalServerError)
	}))
	t.Cleanup(down.Close)
	h := newHarness(t, func(s *Server) { s.voice = voice.New(down.URL, "af_heart", 0.8, t.TempDir()) })
	nick := h.joinAdmin("Nick", "green")
	h.post("/api/voice", nick.Token, obj{"text": "Breathe in"}).expect(http.StatusBadGateway).code("voice_unavailable")
}
