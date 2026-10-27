package api

import (
	"net/http"
	"strings"
	"testing"
	"time"
)

func healthReading(date, metric string, value float64, measuredAt time.Time) obj {
	return obj{"date": date, "metric": metric, "value": value, "source": "healthkit",
		"measuredAt": measuredAt.UTC().Format(time.RFC3339)}
}

func TestHealthPutRecomputesAndReturnsTheDays(t *testing.T) {
	h := newHarness(t)
	nick := h.joinAdmin("Nick", "green")

	got := h.put("/api/health/daily", nick.Token, obj{"items": []obj{
		healthReading("2026-11-02", "steps", 4000, h.clock.Now()),
		healthReading("2026-11-02", "active_energy", 350.6, h.clock.Now()),
	}}).expect(http.StatusOK)
	if got.length("days") != 1 || got.str("days.0.date") != "2026-11-02" {
		t.Fatalf("days = %s", got.Body)
	}
	if got.num("days.0.basePoints") != 50 || got.num("days.0.maxBase") != 400 || got.num("days.0.quests.0.actual") != 4000 {
		t.Fatalf("rescored day = %s", got.Body)
	}
	today := h.get("/api/today", nick.Token).expect(http.StatusOK)
	if today.num("food.burned") != 351 || today.num("day.basePoints") != 50 {
		t.Fatalf("today after sync = %s", today.Body)
	}
}

func TestHealthPutAcrossDaysRescoresEach(t *testing.T) {
	h := newHarness(t)
	h.clock.Set(ny(2026, time.November, 2, 22, 0))
	nick := h.joinAdmin("Nick", "green")
	h.clock.Set(ny(2026, time.November, 3, 8, 0))

	got := h.put("/api/health/daily", nick.Token, obj{"items": []obj{
		healthReading("2026-11-03", "steps", 8000, h.clock.Now()),
		healthReading("2026-11-02", "steps", 2000, h.clock.Now()),
		healthReading("2026-11-02", "active_energy", 100, h.clock.Now()),
	}}).expect(http.StatusOK)
	if got.length("days") != 2 || got.str("days.0.date") != "2026-11-02" || got.str("days.1.date") != "2026-11-03" {
		t.Fatalf("days must come back oldest first: %s", got.Body)
	}
	if got.num("days.0.basePoints") != 25 || got.num("days.1.basePoints") != 100 {
		t.Fatalf("days = %s", got.Body)
	}
}

func TestHealthStaleReadingNeverLowersACount(t *testing.T) {
	h := newHarness(t)
	nick := h.joinAdmin("Nick", "green")
	now := h.clock.Now()

	h.put("/api/health/daily", nick.Token, obj{"items": []obj{healthReading("2026-11-02", "steps", 8000, now)}}).
		expect(http.StatusOK)
	// A retry that was measured earlier, or a second device that lags, arrives later.
	stale := h.put("/api/health/daily", nick.Token, obj{"items": []obj{
		healthReading("2026-11-02", "steps", 1000, now.Add(-time.Hour))}}).expect(http.StatusOK)
	if stale.num("days.0.quests.0.actual") != 8000 || stale.num("days.0.basePoints") != 100 || !stale.flag("days.0.quests.0.done") {
		t.Fatalf("a stale reading lowered the count: %s", stale.Body)
	}

	// A newer reading may lower it, since Health itself can revise a count.
	newer := h.put("/api/health/daily", nick.Token, obj{"items": []obj{
		healthReading("2026-11-02", "steps", 7000, now.Add(time.Minute))}}).expect(http.StatusOK)
	if newer.num("days.0.quests.0.actual") != 7000 {
		t.Fatalf("a newer reading must win: %s", newer.Body)
	}
}

func TestHealthPutReportsPerItemErrorsAndAppliesNothing(t *testing.T) {
	h := newHarness(t)
	nick := h.joinAdmin("Nick", "green")
	now := h.clock.Now()

	got := h.put("/api/health/daily", nick.Token, obj{"items": []obj{
		healthReading("2026-11-02", "steps", 5000, now),
		healthReading("2026-11-02", "heart_rate", 60, now),
		healthReading("2026-11-02", "steps", -1, now),
		healthReading("2026-11-02", "steps", 200001, now),
		healthReading("2026-11-02", "active_energy", 20001, now),
		healthReading("not-a-date", "steps", 5, now),
		healthReading("2026-11-02", "steps", 5, now.Add(time.Hour)),
		{"date": "2026-11-02", "metric": "steps", "value": 5, "source": "", "measuredAt": now.Format(time.RFC3339)},
		{"date": "2026-11-02", "metric": "steps", "value": 5, "source": strings.Repeat("s", 33), "measuredAt": now.Format(time.RFC3339)},
	}}).expect(http.StatusUnprocessableEntity).code("invalid_request")

	if got.length("items") != 8 {
		t.Fatalf("items = %s", got.Body)
	}
	if got.num("items.0.index") != 1 || got.str("items.0.code") != "invalid_request" || got.str("items.0.error") == "" {
		t.Fatalf("first item error = %s", got.Body)
	}
	today := h.get("/api/today", nick.Token).expect(http.StatusOK)
	if today.flag("health.stepsEverSynced") {
		t.Fatal("a rejected batch must not apply its valid items")
	}
}

func TestHealthPutBatchLimits(t *testing.T) {
	h := newHarness(t)
	nick := h.joinAdmin("Nick", "green")
	h.put("/api/health/daily", nick.Token, obj{"items": []obj{}}).expect(http.StatusUnprocessableEntity)

	many := make([]obj, 51)
	for i := range many {
		many[i] = healthReading("2026-11-02", "steps", float64(i), h.clock.Now())
	}
	h.put("/api/health/daily", nick.Token, obj{"items": many}).expect(http.StatusUnprocessableEntity)
	h.put("/api/health/daily", nick.Token, obj{"items": many[:50]}).expect(http.StatusOK)
}

func TestHealthPutHonorsTheDayWindow(t *testing.T) {
	h := newHarness(t)
	h.clock.Set(ny(2026, time.November, 2, 22, 0))
	nick := h.joinAdmin("Nick", "green")

	h.clock.Set(ny(2026, time.November, 3, 11, 0))
	got := h.put("/api/health/daily", nick.Token, obj{"items": []obj{
		healthReading("2026-11-02", "steps", 8000, h.clock.Now()),
		healthReading("2026-11-03", "steps", 100, h.clock.Now()),
	}}).expect(http.StatusUnprocessableEntity).code("date_closed")
	if got.length("items") != 1 || got.num("items.0.index") != 0 || got.str("items.0.code") != "date_closed" {
		t.Fatalf("items = %s", got.Body)
	}

	h.clock.Set(ny(2026, time.November, 4, 9, 0))
	h.put("/api/health/daily", nick.Token, obj{"items": []obj{
		healthReading("2026-11-05", "steps", 5, h.clock.Now())}}).expect(http.StatusUnprocessableEntity).code("date_closed")
}

func TestHealthPutBeforeJoiningIsClosed(t *testing.T) {
	h := newHarness(t)
	h.clock.Set(ny(2026, time.November, 2, 8, 0))
	nick := h.joinAdmin("Nick", "green")
	h.put("/api/health/daily", nick.Token, obj{"items": []obj{
		healthReading("2026-11-01", "steps", 5, h.clock.Now())}}).expect(http.StatusUnprocessableEntity).code("date_closed")
}
