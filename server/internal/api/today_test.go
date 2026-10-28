package api

import (
	"net/http"
	"testing"
	"time"
)

// fixtureDay logs the design's worked example: steps 5000 of 8000, pushups 30 of 30, reading
// 12 minutes and 5 pages, two meals and no protein.
func fixtureDay(h *harness, p person) {
	h.t.Helper()
	h.putHealth(p, "2026-11-02", "steps", 5000).expect(http.StatusOK)
	h.logActivity(p, "pushups", "reps", 30).expect(http.StatusCreated)
	h.logActivity(p, "reading", "minutes", 12).expect(http.StatusCreated)
	h.logActivity(p, "reading", "pages", 5).expect(http.StatusCreated)
	h.logMeal(p, "Oats", 400, 0).expect(http.StatusCreated)
	h.logMeal(p, "Rice", 600, 0).expect(http.StatusCreated)
}

func TestTodayScoresAKnownFixture(t *testing.T) {
	h := newHarness(t)
	nick := h.joinAdmin("Nick", "green")
	fixtureDay(h, nick)

	got := h.get("/api/today", nick.Token).expect(http.StatusOK)
	if got.num("day.basePoints") != 306 || got.num("day.bonusPoints") != 30 || got.num("day.points") != 336 ||
		got.num("day.maxBase") != 400 || got.num("day.percent") != 76 || got.num("day.goalPercent") != 109 || !got.flag("day.counted") ||
		got.num("day.streakLine") != 70 {
		t.Fatalf("day = %s", got.Body)
	}

	want := map[string]questView{
		"steps":        {target: 8000, actual: 5000, points: 100, base: 63},
		"pushups":      {target: 30, actual: 30, points: 100, base: 100, bonus: 20, done: true},
		"reading":      {target: 20, actual: 12, points: 100, base: 93},
		"meals_logged": {target: 2, actual: 2, points: 50, base: 50, bonus: 10, done: true},
		"protein":      {target: 100, actual: 0, points: 50},
		"exercise":     {target: 30, points: 100},
		"sleep":        {target: 420, points: 50},
		"water":        {target: 2200, points: 50},
	}
	have := questsByKey(got)
	if len(have) != len(want) {
		t.Fatalf("quests = %v, want %v", have, want)
	}
	for key, w := range want {
		if have[key] != w {
			t.Errorf("%s = %+v, want %+v", key, have[key], w)
		}
	}
	if got.num("quests.2.actualAlt") != 5 || got.num("quests.2.targetAlt") != 15 || got.str("quests.2.unitAlt") != "pages" {
		t.Fatalf("reading detail = %s", got.Body)
	}

	if got.num("food.kcal") != 1000 || got.num("food.burned") != 0 || !got.flag("health.stepsEverSynced") ||
		got.isNull("health.syncedAt") {
		t.Fatalf("food and health = %s", got.Body)
	}
	if got.num("streak.current") != 1 || !got.flag("streak.restAvailable") || !got.isNull("streak.restUsedOn") {
		t.Fatalf("streak = %s", got.Body)
	}
	if got.str("date") != "2026-11-02" || got.str("localToday") != "2026-11-02" {
		t.Fatalf("dates = %s", got.Body)
	}
}

func TestStepsStayOutOfTheMaximumUntilHealthIsConnected(t *testing.T) {
	h := newHarness(t)
	nick := h.joinAdmin("Nick", "green")
	h.logActivity(nick, "pushups", "reps", 30).expect(http.StatusCreated)

	before := h.get("/api/today", nick.Token).expect(http.StatusOK)
	if before.num("day.maxBase") != 300 || before.flag("health.stepsEverSynced") || before.num("day.percent") != 33 {
		t.Fatalf("before connecting = %s", before.Body)
	}
	if q := questsByKey(before)["steps"]; q.target != 8000 || q.base != 0 {
		t.Fatalf("the steps quest is still listed, with nothing earned: %s", before.Body)
	}

	h.putHealth(nick, "2026-11-02", "steps", 0).expect(http.StatusOK)
	after := h.get("/api/today", nick.Token).expect(http.StatusOK)
	if after.num("day.maxBase") != 400 || !after.flag("health.stepsEverSynced") || after.num("day.percent") != 25 {
		t.Fatalf("after connecting = %s", after.Body)
	}
}

func TestTodayFood(t *testing.T) {
	h := newHarness(t)
	nick := h.joinAdmin("Nick", "green")
	h.patch("/api/me", nick.Token, obj{"targets": obj{"kcal": 2200, "protein": 150}}).expect(http.StatusOK)
	h.logMeal(nick, "Chicken", 500, 41.3, obj{"carbs": 10.2, "fat": 4.1, "fiber": 2.5}).expect(http.StatusCreated)
	h.logMeal(nick, "Skyr", 250, 24.9, obj{"carbs": 9.9, "fat": 0.5}).expect(http.StatusCreated)
	h.putHealth(nick, "2026-11-02", "active_energy", 540.4).expect(http.StatusOK)

	got := h.get("/api/today", nick.Token).expect(http.StatusOK)
	food := map[string]float64{"kcal": 750, "protein": 66.2, "carbs": 20.1, "fat": 4.6, "fiber": 2.5, "burned": 540}
	for key, want := range food {
		if have := got.at("food." + key).(float64); have != want {
			t.Errorf("food.%s = %v, want %v", key, have, want)
		}
	}
	if got.num("food.targets.kcal") != 2200 || got.num("food.targets.protein") != 150 || !got.isNull("food.targets.fat") {
		t.Fatalf("targets = %s", got.Body)
	}
}

func TestTodayDateParameter(t *testing.T) {
	h := newHarness(t)
	h.clock.Set(ny(2026, time.November, 2, 22, 0))
	nick := h.joinAdmin("Nick", "green")
	h.logActivity(nick, "pushups", "reps", 30).expect(http.StatusCreated)

	h.clock.Set(ny(2026, time.November, 3, 9, 0))
	yesterday := h.get("/api/today?date=2026-11-02", nick.Token).expect(http.StatusOK)
	if yesterday.str("date") != "2026-11-02" || questsByKey(yesterday)["pushups"].actual != 30 ||
		yesterday.str("localToday") != "2026-11-03" {
		t.Fatalf("yesterday = %s", yesterday.Body)
	}
	if h.get("/api/today", nick.Token).expect(http.StatusOK).num("day.points") != 0 {
		t.Fatal("today must not include yesterday's entries")
	}
	h.get("/api/today?date=2026-11-04", nick.Token).expect(http.StatusUnprocessableEntity).code("invalid_request")
	h.get("/api/today?date=2026-11-01", nick.Token).expect(http.StatusUnprocessableEntity).code("invalid_request")
	h.get("/api/today?date=soon", nick.Token).expect(http.StatusUnprocessableEntity).code("invalid_request")
}

func TestTodayUsesTheUsersOwnTimezone(t *testing.T) {
	h := newHarness(t)
	h.clock.Set(ny(2026, time.November, 2, 23, 0))
	tokyo := h.post("/api/join", "", obj{"name": "Kai", "color": "sky", "timezone": "Asia/Tokyo"}).
		expect(http.StatusCreated)
	got := h.get("/api/today", tokyo.str("token")).expect(http.StatusOK)
	if got.str("localToday") != "2026-11-03" {
		t.Fatalf("23:00 in New York is already the 3rd in Tokyo: %s", got.Body)
	}
}

func TestStreakFreezesAndBrokenDays(t *testing.T) {
	h := newHarness(t)
	h.clock.Set(ny(2026, time.November, 2, 9, 0))
	nick := h.joinAdmin("Nick", "green")
	// Mon-Wed counted, Thu missed (a freeze covers it), Fri counted.
	h.storeScore(nick, "2026-11-02", 300, 0, 400)
	h.storeScore(nick, "2026-11-03", 300, 0, 400)
	h.storeScore(nick, "2026-11-04", 300, 0, 400)
	h.storeScore(nick, "2026-11-06", 300, 0, 400)

	h.clock.Set(ny(2026, time.November, 7, 15, 0))
	got := h.get("/api/today", nick.Token).expect(http.StatusOK)
	if got.num("streak.current") != 4 || !got.flag("streak.restAvailable") || got.str("streak.restUsedOn") != "2026-11-05" ||
		got.num("freezes.held") != 1 || got.num("freezes.earnedTowardNext") != 4 {
		t.Fatalf("streak = %s", got.Body)
	}

	// Saturday spends the last freeze and Sunday has none left, so the streak breaks.
	h.clock.Set(ny(2026, time.November, 9, 15, 0))
	got = h.get("/api/today", nick.Token).expect(http.StatusOK)
	if got.num("streak.current") != 0 || got.flag("streak.restAvailable") || got.num("freezes.held") != 0 {
		t.Fatalf("streak after two misses = %s", got.Body)
	}
}
