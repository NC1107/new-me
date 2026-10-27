package api

import (
	"net/http"
	"strings"
	"testing"

	"github.com/nc1107/new-me/server/internal/ratelimit"
)

func noAppKey(r *http.Request) { r.Header.Del("X-App-Key") }

func clientVersion(v string) func(*http.Request) {
	return func(r *http.Request) { r.Header.Set("X-Client-Version", v) }
}

func TestHealthReportsVersionWithoutAppKey(t *testing.T) {
	h := newHarness(t)
	got := h.get("/api/health", "", noAppKey).expect(http.StatusOK)
	if got.str("status") != "ok" || got.str("version") != "9.9.9-test" {
		t.Fatalf("health = %s", got.Body)
	}
}

func TestHealthIsCachedAndExemptFromTheClientVersion(t *testing.T) {
	h := newHarness(t)
	h.get("/api/health", "", noAppKey, clientVersion("0.0.1")).expect(http.StatusOK)
	h.srv.health.mu.Lock()
	first := h.srv.health.checked
	h.srv.health.mu.Unlock()
	h.get("/api/health", "").expect(http.StatusOK)
	h.srv.health.mu.Lock()
	second := h.srv.health.checked
	h.srv.health.mu.Unlock()
	if !first.Equal(second) {
		t.Fatal("a second probe inside the TTL must reuse the cached ping")
	}
}

func TestAppKeyMissingOrWrongIs403WithCode(t *testing.T) {
	h := newHarness(t)
	for name, edit := range map[string]func(*http.Request){
		"missing": noAppKey,
		"wrong":   func(r *http.Request) { r.Header.Set("X-App-Key", "nope") },
	} {
		got := h.get("/api/server-info", "", edit).expect(http.StatusForbidden).code("bad_app_key")
		if got.str("error") == "" {
			t.Fatalf("%s: the envelope needs a message", name)
		}
	}
}

func TestAppKeyIsCheckedBeforeTheToken(t *testing.T) {
	h := newHarness(t)
	nick := h.joinAdmin("Nick", "green")
	h.get("/api/me", nick.Token, noAppKey).expect(http.StatusForbidden).code("bad_app_key")
}

func TestServerInfo(t *testing.T) {
	h := newHarness(t)
	got := h.get("/api/server-info", "").expect(http.StatusOK)
	if got.str("name") != testServerName || got.flag("initialized") || !got.flag("joinOpen") ||
		got.str("minClientVersion") != "1.0.0" {
		t.Fatalf("server-info = %s", got.Body)
	}

	nick, _ := h.pair()
	_ = nick
	got = h.get("/api/server-info", "").expect(http.StatusOK)
	if !got.flag("initialized") || got.flag("joinOpen") {
		t.Fatalf("a full server must be initialized and closed: %s", got.Body)
	}
	if strings.Contains(string(got.Body), "Nick") {
		t.Fatal("server-info must never list users")
	}
}

func TestUnknownRoutesUseTheEnvelope(t *testing.T) {
	h := newHarness(t)
	h.get("/api/nope", "").expect(http.StatusNotFound).code("not_found")
	h.do(http.MethodPatch, "/api/health", "", nil).expect(http.StatusMethodNotAllowed).code("method_not_allowed")
}

func TestResponsesCarryRequestIDAndSecurityHeaders(t *testing.T) {
	h := newHarness(t)
	r := h.get("/api/server-info", "")
	if r.Header.Get("X-Request-Id") == "" || r.Header.Get("X-Content-Type-Options") != "nosniff" {
		t.Fatalf("headers = %v", r.Header)
	}
}

func TestOldClientGets426ButNewOrUnversionedPass(t *testing.T) {
	h := newHarness(t)
	nick := h.joinAdmin("Nick", "green")

	got := h.get("/api/me", nick.Token, clientVersion("0.9.9")).expect(http.StatusUpgradeRequired).code("update_required")
	if got.str("minClientVersion") != "1.0.0" {
		t.Fatalf("426 body = %s", got.Body)
	}
	h.get("/api/me", nick.Token, clientVersion("garbage")).expect(http.StatusUpgradeRequired)
	h.get("/api/me", nick.Token, clientVersion("1.0.0")).expect(http.StatusOK)
	h.get("/api/me", nick.Token, clientVersion("1.2.0+7")).expect(http.StatusOK)
	h.get("/api/me", nick.Token).expect(http.StatusOK)
	// The app must still be able to read the minimum and show its update screen.
	h.get("/api/server-info", "", clientVersion("0.0.1")).expect(http.StatusOK)
}

func TestBadOrRevokedTokenIs401AndNothingElseIs(t *testing.T) {
	h := newHarness(t)
	nick := h.joinAdmin("Nick", "green")
	h.get("/api/me", "").expect(http.StatusUnauthorized).code("unauthorized")
	h.get("/api/me", "not-a-token").expect(http.StatusUnauthorized).code("unauthorized")
	h.get("/api/me", nick.Token, func(r *http.Request) { r.Header.Set("Authorization", "Basic abc") }).
		expect(http.StatusUnauthorized)

	h.delete("/api/devices/me", nick.Token).expect(http.StatusNoContent)
	h.get("/api/me", nick.Token).expect(http.StatusUnauthorized)
}

func TestJoinRateLimitIs429WithRetryAfter(t *testing.T) {
	h := newHarness(t, func(s *Server) { s.limits.join = ratelimit.New(5, 5) })
	for i := range 5 {
		h.post("/api/invites/check", "", obj{"code": "AAAA-AAAA-AAAA-AAAA"}).expect(http.StatusOK)
		_ = i
	}
	got := h.post("/api/invites/check", "", obj{"code": "AAAA-AAAA-AAAA-AAAA"}).expect(http.StatusTooManyRequests).
		code("rate_limited")
	if got.Header.Get("Retry-After") == "" {
		t.Fatal("a 429 must say when to come back")
	}
	h.post("/api/join", "", obj{"name": "Nick"}).expect(http.StatusTooManyRequests)
}

func TestDeviceRateLimitIsPerDevice(t *testing.T) {
	h := newHarness(t, func(s *Server) { s.limits.device = ratelimit.New(60, 4) })
	nick := h.joinAdmin("Nick", "green")
	code := h.invite(nick)
	nadia := h.joinMember(code, "Nadia", "violet")

	for range 3 {
		h.get("/api/me", nick.Token).expect(http.StatusOK)
	}
	got := h.get("/api/me", nick.Token).expect(http.StatusTooManyRequests).code("rate_limited")
	if got.Header.Get("Retry-After") == "" {
		t.Fatal("a 429 must say when to come back")
	}
	h.get("/api/me", nadia.Token).expect(http.StatusOK)
}

func TestHealthPutHasItsOwnBudget(t *testing.T) {
	h := newHarness(t, func(s *Server) { s.limits.healthPut = ratelimit.New(60, 2) })
	nick := h.joinAdmin("Nick", "green")
	h.putHealth(nick, "2026-11-02", "steps", 100).expect(http.StatusOK)
	h.putHealth(nick, "2026-11-02", "steps", 200).expect(http.StatusOK)
	h.putHealth(nick, "2026-11-02", "steps", 300).expect(http.StatusTooManyRequests)
	h.get("/api/today", nick.Token).expect(http.StatusOK)
}

func TestOversizedBodyIs413(t *testing.T) {
	h := newHarness(t)
	big := strings.Repeat("x", 1<<20+1)
	h.post("/api/invites/check", "", obj{"code": big}).expect(http.StatusRequestEntityTooLarge).code("payload_too_large")
}

func TestMalformedAndUnknownFieldsAre400(t *testing.T) {
	h := newHarness(t)
	h.do(http.MethodPost, "/api/invites/check", "", strings.NewReader("{nope")).expect(http.StatusBadRequest).
		code("invalid_json")
	h.post("/api/invites/check", "", obj{"code": "x", "surprise": 1}).expect(http.StatusBadRequest)
}

func TestDevCORS(t *testing.T) {
	origin := func(o string) func(*http.Request) {
		return func(r *http.Request) { r.Header.Set("Origin", o) }
	}
	preflight := func(h *harness, o string) *response {
		return h.do(http.MethodOptions, "/api/me", "", nil, noAppKey, origin(o),
			func(r *http.Request) { r.Header.Set("Access-Control-Request-Method", "PATCH") })
	}

	h := newHarness(t, func(s *Server) { s.cfg.DevCORS = true })
	got := preflight(h, "http://localhost:5173").expect(http.StatusNoContent)
	if got.Header.Get("Access-Control-Allow-Origin") != "http://localhost:5173" {
		t.Fatalf("preflight headers = %v", got.Header)
	}
	for _, header := range []string{"X-App-Key", "Authorization", "X-Client-Version"} {
		if !strings.Contains(got.Header.Get("Access-Control-Allow-Headers"), header) {
			t.Fatalf("preflight must allow %s: %v", header, got.Header)
		}
	}
	actual := h.get("/api/server-info", "", origin("http://127.0.0.1:8081")).expect(http.StatusOK)
	if actual.Header.Get("Access-Control-Allow-Origin") != "http://127.0.0.1:8081" {
		t.Fatalf("actual response headers = %v", actual.Header)
	}
	if preflight(h, "https://evil.example").Header.Get("Access-Control-Allow-Origin") != "" {
		t.Fatal("a non-local origin must not be allowed")
	}
	preflight(h, "https://evil.example").expect(http.StatusForbidden)

	off := newHarness(t)
	if preflight(off, "http://localhost:5173").Header.Get("Access-Control-Allow-Origin") != "" {
		t.Fatal("CORS must stay off unless NEWME_DEV_CORS is set")
	}
}
