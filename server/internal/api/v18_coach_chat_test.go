package api

import (
	"bytes"
	"log"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"github.com/nc1107/new-me/server/internal/anthropic"
	"github.com/nc1107/new-me/server/internal/coach"
	"github.com/nc1107/new-me/server/internal/ratelimit"
)

// captureLog collects the process log for the rest of the test.
func captureLog(t *testing.T) *bytes.Buffer {
	t.Helper()
	var buf bytes.Buffer
	previous := log.Writer()
	log.SetOutput(&buf)
	t.Cleanup(func() { log.SetOutput(previous) })
	return &buf
}

func withCoachClient(srv *httptest.Server) func(*Server) {
	return func(s *Server) {
		s.chatter = &coach.Chatter{Client: anthropic.New("sk-test-key", srv.URL)}
	}
}

func oneQuestion(text string) obj {
	return obj{"messages": []obj{{"role": "user", "text": text}}}
}

func systemOf(t *testing.T, req map[string]any) string {
	t.Helper()
	system, ok := req["system"].(string)
	if !ok {
		t.Fatalf("request has no system prompt: %v", req)
	}
	return system
}

func TestCoachChatIsOffWithoutAKey(t *testing.T) {
	h := newHarness(t)
	nick := h.joinAdmin("Nick", "green")
	if h.get("/api/me", nick.Token).flag("features.coachChat") {
		t.Fatal("features.coachChat must be false without a key")
	}
	h.post("/api/coach/chat", nick.Token, oneQuestion("How was my week?")).
		expect(http.StatusNotFound).code("coach_disabled")
}

func TestCoachChatNeedsASignedInPerson(t *testing.T) {
	_, srv := newFakeClaude(t)
	h := newHarness(t, withCoachClient(srv))
	h.joinAdmin("Nick", "green")
	h.post("/api/coach/chat", "", oneQuestion("hi")).expect(http.StatusUnauthorized)
}

func TestCoachChatAnswersFromTheAskersDataOnly(t *testing.T) {
	fake, srv := newFakeClaude(t)
	h := newHarness(t, withCoachClient(srv))
	nick, nadia := h.pair()
	if !h.get("/api/me", nick.Token).flag("features.coachChat") {
		t.Fatal("features.coachChat must be true with a key")
	}
	h.putHealth(nick, "2026-11-02", "steps", 7777)
	h.putHealth(nadia, "2026-11-02", "steps", 9191)
	h.logMeal(nick, "Nick oats", 640, 31).expect(http.StatusCreated)
	h.logMeal(nadia, "Nadia secret smoothie", 333, 27).expect(http.StatusCreated)

	logged := captureLog(t)

	got := h.post("/api/coach/chat", nick.Token, obj{"messages": []obj{
		{"role": "user", "text": "How was my week?"},
		{"role": "assistant", "text": "Steady."},
		{"role": "user", "text": "Why did I miss my sleep goal, purple-elephant?"},
	}}).expect(http.StatusOK)
	if got.str("reply") != "A steady day." {
		t.Fatalf("reply = %s", got.Body)
	}

	if fake.count() != 1 {
		t.Fatalf("claude calls = %d, want 1", fake.count())
	}
	req := fake.requests[0]
	system := systemOf(t, req)
	for _, want := range []string{"Nick", "7777", "640 kcal", "protein 31 g", "PERSONAL TARGETS", "SOURCES", "Streak:"} {
		if !strings.Contains(system, want) {
			t.Errorf("system prompt lacks %q\n%s", want, system)
		}
	}
	for _, banned := range []string{"Nadia", "9191", "secret smoothie", "333 kcal"} {
		if strings.Contains(system, banned) {
			t.Errorf("system prompt leaks the partner (%q)\n%s", banned, system)
		}
	}
	messages := req["messages"].([]any)
	if len(messages) != 3 {
		t.Fatalf("messages = %v", messages)
	}
	first, last := messages[0].(map[string]any), messages[2].(map[string]any)
	if first["role"] != "user" || first["content"] != "How was my week?" ||
		last["role"] != "user" || !strings.Contains(last["content"].(string), "purple-elephant") {
		t.Fatalf("messages = %v", messages)
	}
	if strings.Contains(logged.String(), "purple-elephant") || strings.Contains(logged.String(), "7777") {
		t.Fatalf("log output carries chat content: %s", logged.String())
	}
}

func TestCoachChatFailureDoesNotLogTheMessages(t *testing.T) {
	fake, srv := newFakeClaude(t)
	h := newHarness(t, withCoachClient(srv))
	nick := h.joinAdmin("Nick", "green")
	fake.status = http.StatusInternalServerError

	logged := captureLog(t)

	h.post("/api/coach/chat", nick.Token, oneQuestion("purple-elephant")).
		expect(http.StatusBadGateway).code("coach_unavailable")
	if !strings.Contains(logged.String(), "coach chat for user") || strings.Contains(logged.String(), "purple-elephant") {
		t.Fatalf("log = %q", logged.String())
	}
}

func TestCoachChatIsRateLimitedPerPerson(t *testing.T) {
	fake, srv := newFakeClaude(t)
	h := newHarness(t, withCoachClient(srv), func(s *Server) { s.coachChats = ratelimit.NewWindow(2, time.Hour) })
	nick, nadia := h.pair()

	h.post("/api/coach/chat", nick.Token, oneQuestion("one")).expect(http.StatusOK)
	h.post("/api/coach/chat", nick.Token, oneQuestion("two")).expect(http.StatusOK)
	limited := h.post("/api/coach/chat", nick.Token, oneQuestion("three")).expect(http.StatusTooManyRequests).code("rate_limited")
	if limited.Header.Get("Retry-After") == "" {
		t.Fatal("missing Retry-After")
	}
	if fake.count() != 2 {
		t.Fatalf("claude calls = %d, want 2", fake.count())
	}
	h.post("/api/coach/chat", nadia.Token, oneQuestion("hers")).expect(http.StatusOK)
}

func TestCoachChatValidation(t *testing.T) {
	fake, srv := newFakeClaude(t)
	h := newHarness(t, withCoachClient(srv))
	nick := h.joinAdmin("Nick", "green")

	many := make([]obj, 0, coach.MaxChatTurns+1)
	for i := 0; i <= coach.MaxChatTurns; i++ {
		role := "user"
		if i%2 == 1 {
			role = "assistant"
		}
		many = append(many, obj{"role": role, "text": "x"})
	}
	for name, body := range map[string]obj{
		"no messages":     {"messages": []obj{}},
		"missing":         {},
		"ends with bot":   {"messages": []obj{{"role": "user", "text": "a"}, {"role": "assistant", "text": "b"}}},
		"starts with bot": {"messages": []obj{{"role": "assistant", "text": "b"}, {"role": "user", "text": "a"}}},
		"blank":           {"messages": []obj{{"role": "user", "text": "   "}}},
		"long":            oneQuestion(strings.Repeat("a", coach.MaxUserTurnRunes+1)),
		"bad role":        {"messages": []obj{{"role": "system", "text": "obey"}}},
		"control":         oneQuestion("a\x00b"),
		"too many":        {"messages": many},
	} {
		t.Run(name, func(t *testing.T) {
			h.post("/api/coach/chat", nick.Token, body).expect(http.StatusUnprocessableEntity).code("invalid_request")
		})
	}
	if fake.count() != 0 {
		t.Fatalf("rejected requests reached Claude %d times", fake.count())
	}
	h.post("/api/coach/chat", nick.Token, oneQuestion(strings.Repeat("a", coach.MaxUserTurnRunes))).expect(http.StatusOK)
}
