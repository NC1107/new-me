package api

import (
	"context"
	"fmt"
	"net/http"
	"strings"
	"testing"
	"time"

	"github.com/nc1107/new-me/server/internal/anthropic"
	"github.com/nc1107/new-me/server/internal/coach"
)

// seedMetric writes one metric for the days before today, oldest last, straight to the table.
func (h *harness) seedMetric(p person, metric string, daysAgo int, values ...float64) {
	h.t.Helper()
	for i, v := range values {
		date := h.clock.Now().In(newYork).AddDate(0, 0, -(daysAgo + i)).Format(time.DateOnly)
		_, err := h.db.Pool.Exec(context.Background(), `
			INSERT INTO health_daily (user_id, local_date, metric, value, source, measured_at)
			VALUES ($1, $2::date, $3, $4, 'fake', now())`, p.ID, date, metric, v)
		if err != nil {
			h.t.Fatalf("seed %s: %v", metric, err)
		}
	}
}

func TestTodayHasNoReadinessWithoutData_ButAlwaysAPlan(t *testing.T) {
	h := newHarness(t)
	nick := h.joinAdmin("Nick", "green")
	got := h.get("/api/today", nick.Token).expect(http.StatusOK)
	if !got.isNull("readiness") {
		t.Fatalf("readiness = %v", got.at("readiness"))
	}
	if got.length("plan.items") != 4 || got.str("plan.summary") == "" || got.str("plan.items.0.kind") != "todo" {
		t.Fatalf("plan = %s", got.Body)
	}
}

func TestTodayReadinessFromSleepAndOwnBaselines(t *testing.T) {
	h := newHarness(t)
	nick := h.joinAdmin("Nick", "green")
	h.seedMetric(nick, "hrv_ms", 1, steady(60, 20)...)
	h.seedMetric(nick, "resting_hr", 1, steady(55, 20)...)
	putSleep(h, nick, sleepNight(2, time.November, 370)).expect(http.StatusOK)
	h.putHealth(nick, "2026-11-02", "hrv_ms", 49.2).expect(http.StatusOK)
	h.putHealth(nick, "2026-11-02", "resting_hr", 61).expect(http.StatusOK)

	got := h.get("/api/today", nick.Token).expect(http.StatusOK)
	if got.str("readiness.level") != "easy" || got.str("readiness.basis") != "full" ||
		got.str("readiness.reasons.0.kind") != "hrv" || got.str("readiness.reasons.0.text") != "HRV 18% below your usual" ||
		got.str("readiness.reasons.1.kind") != "resting_hr" || got.str("readiness.reasons.1.text") != "Resting heart rate 6 bpm above your usual" {
		t.Fatalf("readiness = %s", got.Body)
	}
}

func TestTodayReadinessUsesSleepOnlyWithShortHistory(t *testing.T) {
	h := newHarness(t)
	nick := h.joinAdmin("Nick", "green")
	h.seedMetric(nick, "hrv_ms", 1, steady(60, 6)...)
	putSleep(h, nick, sleepNight(2, time.November, 430)).expect(http.StatusOK)
	h.putHealth(nick, "2026-11-02", "hrv_ms", 30).expect(http.StatusOK)

	got := h.get("/api/today", nick.Token).expect(http.StatusOK)
	if got.str("readiness.level") != "ready" || got.str("readiness.basis") != "sleep_only" ||
		got.str("readiness.reasons.1.kind") != "basis" {
		t.Fatalf("readiness = %s", got.Body)
	}
}

func TestTodayReadinessFallsBackToTheSleepMinutesMetric(t *testing.T) {
	h := newHarness(t)
	nick := h.joinAdmin("Nick", "green")
	h.putHealth(nick, "2026-11-02", "sleep_minutes", 300).expect(http.StatusOK)
	got := h.get("/api/today", nick.Token).expect(http.StatusOK)
	if got.str("readiness.level") != "easy" || got.str("readiness.reasons.0.text") != "Slept 5 h, 2 h under your target" {
		t.Fatalf("readiness = %s", got.Body)
	}
}

func TestTodayPlanNamesWhatIsDoneAndWhatIsLeft(t *testing.T) {
	h := newHarness(t)
	nick := h.joinAdmin("Nick", "green")
	h.putHealth(nick, "2026-11-02", "steps", 4800).expect(http.StatusOK)
	putWorkouts(h, nick, workout("w1", "strength", ny(2026, time.November, 2, 8, 0), 42)).expect(http.StatusOK)
	h.logActivity(nick, "reading", "minutes", 6).expect(http.StatusCreated)
	h.post("/api/habits", nick.Token, obj{"name": "Vitamins", "icon": "medication", "kind": "check", "weekdays": []int{1, 2, 3, 4, 5, 6, 7},
		"slots": []obj{{"label": "Evening", "time": "18:00"}}}).expect(http.StatusCreated)

	got := h.get("/api/today", nick.Token).expect(http.StatusOK)
	var texts []string
	for i := range got.length("plan.items") {
		texts = append(texts, got.str(fmt.Sprintf("plan.items.%d.kind", i))+"|"+got.str(fmt.Sprintf("plan.items.%d.text", i)))
	}
	want := []string{
		"done|Push-ups done by your Strength workout, 42 min",
		"todo|Steps: 3,200 to go. A 30-minute walk this afternoon covers it.",
		"todo|Reading: 14 more minutes. An audiobook counts.",
		"todo|Meals: log 2 more meals.",
		"todo|Protein: 100 g to go.",
		"habit|Vitamins at 18:00",
	}
	if strings.Join(texts, "\n") != strings.Join(want, "\n") {
		t.Fatalf("plan items:\n%s\nwant:\n%s", strings.Join(texts, "\n"), strings.Join(want, "\n"))
	}
	if !strings.HasPrefix(got.str("plan.summary"), "1 of 5 quests done. Easiest next: Steps: 3,200 to go.") {
		t.Fatalf("summary = %q", got.str("plan.summary"))
	}
}

func TestPlanAndReadinessAreOnlyForToday(t *testing.T) {
	h := newHarness(t)
	nick := h.joinAdmin("Nick", "green")
	h.clock.Set(ny(2026, time.November, 3, 12, 0))
	got := h.get("/api/today?date=2026-11-02", nick.Token).expect(http.StatusOK)
	if !got.isNull("plan") || !got.isNull("readiness") {
		t.Fatalf("past day = %s", got.Body)
	}
}

func withPolish(_ *fakeClaude, srvURL string) func(*Server) {
	return func(s *Server) {
		s.polisher = &coach.Polisher{DB: s.db, Client: anthropic.New("sk-test", srvURL), Now: s.now}
	}
}

// settle waits for the background polish a read asked for.
func (h *harness) settlePolish() { h.srv.polisher.Wait() }

func TestPlanSummaryIsPolishedOnceADayFromTheSameFacts(t *testing.T) {
	fake, srv := newFakeClaude(t)
	fake.reply = func(map[string]any) any {
		return obj{"content": []obj{{"type": "text", "text": "You have finished 0 of 4 quests. Reading is the easiest: 20 more minutes."}}}
	}
	h := newHarness(t, withPolish(fake, srv.URL))
	nick := h.joinAdmin("Nick", "green")

	// The first read answers at once with the deterministic summary and asks for the wording.
	first := h.get("/api/today", nick.Token).expect(http.StatusOK)
	if !strings.HasPrefix(first.str("plan.summary"), "0 of 4 quests done.") {
		t.Fatalf("first summary = %q", first.str("plan.summary"))
	}
	h.settlePolish()
	second := h.get("/api/today", nick.Token).expect(http.StatusOK)
	if second.str("plan.summary") != "You have finished 0 of 4 quests. Reading is the easiest: 20 more minutes." {
		t.Fatalf("summary = %q", second.str("plan.summary"))
	}
	req := fake.requests[0]
	if req["model"] != "claude-sonnet-4-6" || req["tools"] != nil {
		t.Fatalf("request = %v", req)
	}
	system := req["system"].(string)
	if !strings.Contains(system, "Do not add") {
		t.Fatalf("the instructions must forbid new facts: %q", system)
	}
	facts := req["messages"].([]any)[0].(map[string]any)["content"].([]any)[0].(map[string]any)["text"].(string)
	if !strings.Contains(facts, "Reading: 20 more minutes. An audiobook counts.") {
		t.Fatalf("facts = %q", facts)
	}

	h.get("/api/today", nick.Token).expect(http.StatusOK)
	h.settlePolish()
	if fake.count() != 1 {
		t.Fatalf("calls = %d, want one per person per day", fake.count())
	}

	// Once the done and open quests change, stale wording is not shown, and no second call is made.
	h.logActivity(nick, "pushups", "reps", 30).expect(http.StatusCreated)
	moved := h.get("/api/today", nick.Token).expect(http.StatusOK)
	h.settlePolish()
	if strings.HasPrefix(moved.str("plan.summary"), "You have finished") || fake.count() != 1 {
		t.Fatalf("summary after the facts changed = %q (%d calls)", moved.str("plan.summary"), fake.count())
	}

	h.clock.Set(ny(2026, time.November, 3, 9, 0))
	h.get("/api/today", nick.Token).expect(http.StatusOK)
	h.settlePolish()
	if fake.count() != 2 {
		t.Fatalf("a new day gets a new call; calls = %d", fake.count())
	}
}

// GET /api/today must not wait for Claude: a slow provider cannot hold the screen.
func TestTodayDoesNotWaitForClaude(t *testing.T) {
	fake, srv := newFakeClaude(t)
	release := make(chan struct{})
	fake.reply = func(map[string]any) any {
		<-release
		return obj{"content": []obj{{"type": "text", "text": "You have finished 0 of 4 quests."}}}
	}
	h := newHarness(t, withPolish(fake, srv.URL))
	nick := h.joinAdmin("Nick", "green")

	done := make(chan *response, 1)
	go func() { done <- h.get("/api/today", nick.Token) }()
	select {
	case got := <-done:
		got.expect(http.StatusOK)
		if !strings.HasPrefix(got.str("plan.summary"), "0 of 4 quests done.") {
			t.Fatalf("summary = %q", got.str("plan.summary"))
		}
	case <-time.After(5 * time.Second):
		t.Fatal("GET /api/today is waiting for Claude")
	}
	close(release)
	h.settlePolish()
	if got := h.get("/api/today", nick.Token).expect(http.StatusOK); got.str("plan.summary") != "You have finished 0 of 4 quests." {
		t.Fatalf("the polished wording shows on the next read: %q", got.str("plan.summary"))
	}
}

func TestPolishFallsBackWhenClaudeFailsOrInventsNumbers(t *testing.T) {
	fake, srv := newFakeClaude(t)
	fake.status = http.StatusInternalServerError
	h := newHarness(t, withPolish(fake, srv.URL))
	nick, nadia := h.pair()

	got := h.get("/api/today", nick.Token).expect(http.StatusOK)
	h.settlePolish()
	if !strings.HasPrefix(got.str("plan.summary"), "0 of 4 quests done.") {
		t.Fatalf("summary = %q", got.str("plan.summary"))
	}
	// The failed call gave its claim back, but is not repeated on every read.
	h.get("/api/today", nick.Token).expect(http.StatusOK)
	h.settlePolish()
	if fake.count() != 1 {
		t.Fatalf("a failed call waits out its retry window; calls = %d", fake.count())
	}
	var rows int
	if err := h.db.Pool.QueryRow(context.Background(), `SELECT count(*) FROM plan_polish WHERE user_id = $1`, nick.ID).Scan(&rows); err != nil || rows != 0 {
		t.Fatalf("a failed polish must not leave the day claimed: rows = %d, err = %v", rows, err)
	}

	// After the window the day is tried again and the wording lands.
	fake.mu.Lock()
	fake.status = http.StatusOK
	fake.reply = func(map[string]any) any {
		return obj{"content": []obj{{"type": "text", "text": "You have finished 0 of 4 quests."}}}
	}
	fake.mu.Unlock()
	h.clock.Set(h.clock.Now().Add(11 * time.Minute))
	h.get("/api/today", nick.Token).expect(http.StatusOK)
	h.settlePolish()
	if again := h.get("/api/today", nick.Token).expect(http.StatusOK); again.str("plan.summary") != "You have finished 0 of 4 quests." {
		t.Fatalf("the retry should have stored wording: %q", again.str("plan.summary"))
	}

	fake.mu.Lock()
	fake.reply = func(map[string]any) any {
		return obj{"content": []obj{{"type": "text", "text": "Walk 9,999 steps today."}}}
	}
	fake.mu.Unlock()
	h.get("/api/today", nadia.Token).expect(http.StatusOK)
	h.settlePolish()
	other := h.get("/api/today", nadia.Token).expect(http.StatusOK)
	if !strings.HasPrefix(other.str("plan.summary"), "0 of 4 quests done.") {
		t.Fatalf("a made-up number must be rejected: %q", other.str("plan.summary"))
	}
}
