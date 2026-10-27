package api

import (
	"fmt"
	"net/http"
	"strings"
	"testing"
	"time"
)

// sleepNight is the night ending on the morning of day, in bed at 23:00 the evening before.
func sleepNight(day int, month time.Month, asleep int) obj {
	bed := ny(2026, month, day-1, 23, 0)
	return obj{
		"date": fmt.Sprintf("2026-%02d-%02d", int(month), day), "source": "Apple Watch",
		"bedAt": bed.UTC().Format(time.RFC3339), "wakeAt": bed.Add(time.Duration(asleep+30) * time.Minute).UTC().Format(time.RFC3339),
		"asleepMin": asleep, "deepMin": 60, "remMin": 90, "coreMin": asleep - 150, "awakeMin": 30,
	}
}

func putSleep(h *harness, p person, nights ...obj) *response {
	return h.put("/api/health/sleep", p.Token, obj{"nights": nights})
}

func TestSleepPutUpsertsByMorningAndFeedsInsights(t *testing.T) {
	h := newHarness(t)
	nick := h.joinAdmin("Nick", "green")
	if got := putSleep(h, nick, sleepNight(1, time.November, 400), sleepNight(2, time.November, 420)).
		expect(http.StatusOK); got.num("saved") != 2 {
		t.Fatalf("saved = %s", got.Body)
	}
	// A resend with a revised total replaces the night instead of adding one.
	putSleep(h, nick, sleepNight(2, time.November, 450)).expect(http.StatusOK)
	putSleep(h, nick, sleepNight(2, time.November, 450)).expect(http.StatusOK)

	got := h.get("/api/insights", nick.Token).expect(http.StatusOK)
	if got.length("sleep.nights") != 2 || got.num("sleep.lastNight.asleepMin") != 450 || got.str("sleep.lastNight.date") != "2026-11-02" ||
		got.str("sleep.lastNight.bedAt") != "2026-11-02T04:00:00Z" || got.num("sleep.avg7Min") != 425 {
		t.Fatalf("sleep = %s", got.Body)
	}
}

func TestSleepAcceptsWholeMinutesSentAsDecimals(t *testing.T) {
	h := newHarness(t)
	nick := h.joinAdmin("Nick", "green")
	night := sleepNight(2, time.November, 420)
	night["asleepMin"], night["deepMin"] = 419.6, 60.0
	putSleep(h, nick, night).expect(http.StatusOK)
	if got := h.get("/api/insights", nick.Token).expect(http.StatusOK); got.num("sleep.lastNight.asleepMin") != 420 {
		t.Fatalf("sleep = %s", got.Body)
	}
}

func TestSleepValidation(t *testing.T) {
	h := newHarness(t)
	nick := h.joinAdmin("Nick", "green")
	mutate := func(key string, value any) obj {
		n := sleepNight(2, time.November, 420)
		n[key] = value
		return n
	}
	bed := ny(2026, time.November, 1, 23, 0)
	tests := []struct {
		name  string
		night obj
	}{
		{"bad date", mutate("date", "11/02/2026")},
		{"future date", mutate("date", "2026-11-03")},
		{"date over 400 days old", mutate("date", "2025-09-01")},
		{"empty source", mutate("source", "")},
		{"control char in source", mutate("source", "a\nb")},
		{"long source", mutate("source", strings.Repeat("s", 33))},
		{"wake before bed", mutate("wakeAt", bed.Add(-time.Hour).UTC().Format(time.RFC3339))},
		{"wake equals bed", mutate("wakeAt", bed.UTC().Format(time.RFC3339))},
		{"night longer than a day", mutate("wakeAt", bed.Add(25*time.Hour).UTC().Format(time.RFC3339))},
		{"wake in the future", mutate("wakeAt", h.clock.Now().Add(time.Hour).UTC().Format(time.RFC3339))},
		{"negative asleep", mutate("asleepMin", -1)},
		{"asleep over a day", mutate("asleepMin", 1441)},
		{"negative deep", mutate("deepMin", -5)},
		{"rem over a day", mutate("remMin", 1500)},
		{"core over a day", mutate("coreMin", 1441)},
		{"awake over a day", mutate("awakeMin", 1441)},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got := putSleep(h, nick, tt.night).expect(http.StatusUnprocessableEntity).code("invalid_request")
			if got.num("items.0.index") != 0 {
				t.Fatalf("item detail = %s", got.Body)
			}
		})
	}
	if got := h.get("/api/insights", nick.Token).expect(http.StatusOK); got.length("sleep.nights") != 0 {
		t.Fatalf("a rejected night was stored: %s", got.Body)
	}
}

func TestSleepBoundariesAndBatchLimits(t *testing.T) {
	h := newHarness(t)
	nick := h.joinAdmin("Nick", "green")
	edge := sleepNight(2, time.November, 1440)
	edge["deepMin"], edge["remMin"], edge["coreMin"], edge["awakeMin"] = 0, 0, 0, 1440
	bed := ny(2026, time.November, 1, 11, 0)
	edge["bedAt"], edge["wakeAt"] = bed.UTC().Format(time.RFC3339), bed.Add(24*time.Hour).UTC().Format(time.RFC3339)
	putSleep(h, nick, edge).expect(http.StatusOK)

	putSleep(h, nick).expect(http.StatusUnprocessableEntity).code("invalid_request")
	many := make([]obj, 32)
	for i := range many {
		many[i] = sleepNight(2, time.November, 400)
	}
	putSleep(h, nick, many...).expect(http.StatusUnprocessableEntity).code("invalid_request")
	putSleep(h, nick, many[:31]...).expect(http.StatusOK)
}

func TestSleepBatchAppliesNothingWhenOneNightIsBad(t *testing.T) {
	h := newHarness(t)
	nick := h.joinAdmin("Nick", "green")
	bad := sleepNight(2, time.November, 420)
	bad["asleepMin"] = 2000
	got := putSleep(h, nick, sleepNight(1, time.November, 400), bad).
		expect(http.StatusUnprocessableEntity).code("invalid_request")
	if got.length("items") != 1 || got.num("items.0.index") != 1 {
		t.Fatalf("items = %s", got.Body)
	}
	if ins := h.get("/api/insights", nick.Token).expect(http.StatusOK); ins.length("sleep.nights") != 0 {
		t.Fatalf("nothing may apply: %s", ins.Body)
	}
}

func TestSleepRequestShapeAndAuth(t *testing.T) {
	h := newHarness(t)
	nick := h.joinAdmin("Nick", "green")
	h.put("/api/health/sleep", nick.Token, obj{"nights": []obj{{"date": "2026-11-02", "extra": 1}}}).
		expect(http.StatusBadRequest).code("invalid_json")
	h.put("/api/health/sleep", "", obj{"nights": []obj{}}).expect(http.StatusUnauthorized).code("unauthorized")
}

func TestSleepIsScopedToTheCaller(t *testing.T) {
	h := newHarness(t)
	nick, nadia := h.pair()
	putSleep(h, nick, sleepNight(2, time.November, 480)).expect(http.StatusOK)
	putSleep(h, nadia, sleepNight(2, time.November, 360)).expect(http.StatusOK)
	if got := h.get("/api/insights", nick.Token).expect(http.StatusOK); got.num("sleep.lastNight.asleepMin") != 480 {
		t.Fatalf("nick = %s", got.Body)
	}
	if got := h.get("/api/insights", nadia.Token).expect(http.StatusOK); got.num("sleep.lastNight.asleepMin") != 360 {
		t.Fatalf("nadia = %s", got.Body)
	}
}
