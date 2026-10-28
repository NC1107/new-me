package api

import (
	"net/http"
	"testing"
	"time"
)

func TestHealthHistoryFillsClosedDaysWithoutRescoring(t *testing.T) {
	h := newHarness(t)
	h.clock.Set(ny(2026, time.November, 2, 12, 0))
	nick := h.joinAdmin("Nick", "green")
	at := ny(2026, time.November, 2, 11, 0).UTC().Format(time.RFC3339)
	item := func(date string, steps float64) obj {
		return obj{"date": date, "metric": "steps", "value": steps, "source": "healthkit", "measuredAt": at}
	}

	got := h.put("/api/health/history", nick.Token, obj{"items": []obj{item("2026-10-01", 9000), item("2026-05-01", 7000)}}).
		expect(http.StatusOK)
	if got.num("stored") != 2 || got.num("received") != 2 {
		t.Fatalf("history = %s", got.Body)
	}
	again := h.put("/api/health/history", nick.Token, obj{"items": []obj{item("2026-10-01", 1)}}).expect(http.StatusOK)
	if again.num("stored") != 0 {
		t.Fatalf("history never overwrites a reading: %s", again.Body)
	}
	trend := h.get("/api/health/trends?metric=steps&days=60", nick.Token).expect(http.StatusOK)
	if trend.length("points") != 1 || trend.at("points.0.value").(float64) != 9000 {
		t.Fatalf("history should show in trends: %s", trend.Body)
	}

	for _, date := range []string{"2026-11-02", "2016-01-01", "2026-11-05"} {
		h.put("/api/health/history", nick.Token, obj{"items": []obj{item(date, 1000)}}).
			expect(http.StatusUnprocessableEntity)
	}
	if h.get("/api/today", nick.Token).expect(http.StatusOK).num("day.basePoints") != 0 {
		t.Fatal("history must not touch today's score")
	}
}
