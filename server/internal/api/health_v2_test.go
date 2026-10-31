package api

import (
	"encoding/json"
	"net/http"
	"strconv"
	"strings"
	"testing"
	"time"
)

func TestHealthPutAcceptsEveryMetric(t *testing.T) {
	h := newHarness(t)
	nick := h.joinAdmin("Nick", "green")
	now := h.clock.Now()
	values := map[string]float64{
		"steps": 1, "active_energy": 2, "basal_energy": 3, "exercise_minutes": 4, "distance_m": 5,
		"flights": 6, "workouts": 1, "workout_minutes": 8, "sleep_minutes": 9, "mindful_minutes": 10,
		"water_ml": 11, "resting_hr": 55, "hrv_ms": 40, "vo2max": 45, "weight_kg": 80.5,
		"body_fat_pct": 18.2, "lean_mass_kg": 60,
	}
	items := make([]obj, 0, len(values))
	for metric, v := range values {
		items = append(items, healthReading("2026-11-02", metric, v, now))
	}
	h.put("/api/health/daily", nick.Token, obj{"items": items}).expect(http.StatusOK)

	today := h.get("/api/today", nick.Token).expect(http.StatusOK)
	for metric, v := range values {
		if got := today.at("health.metrics." + metric); got != v {
			t.Fatalf("metrics.%s = %v, want %v: %s", metric, got, v, today.Body)
		}
	}
	if today.num("health.latest.weight_kg.value") != 80 || today.str("health.latest.weight_kg.date") != "2026-11-02" {
		t.Fatalf("latest = %s", today.Body)
	}
}

func TestHealthPutRejectsOutOfBoundsNewMetrics(t *testing.T) {
	h := newHarness(t)
	nick := h.joinAdmin("Nick", "green")
	now := h.clock.Now()
	for metric, v := range map[string]float64{
		"resting_hr": 19, "weight_kg": 19, "body_fat_pct": 0, "lean_mass_kg": 9, "workouts": 51,
		"exercise_minutes": 1441, "vo2max": 101, "hrv_ms": 501, "water_ml": 20001, "flights": 1001,
	} {
		h.put("/api/health/daily", nick.Token, obj{"items": []obj{healthReading("2026-11-02", metric, v, now)}}).
			expect(http.StatusUnprocessableEntity).code("invalid_request")
	}
}

func TestExerciseAndSleepQuestsAreOptInAndAutomatic(t *testing.T) {
	h := newHarness(t)
	nick := h.joinAdmin("Nick", "green")
	h.patch("/api/me", nick.Token, obj{"questTemplates": []obj{
		{"key": "exercise", "enabled": true, "target": 40},
		{"key": "sleep", "enabled": true},
	}}).expect(http.StatusOK)
	me := h.get("/api/me", nick.Token).expect(http.StatusOK)
	if !me.flag("questTemplates.6.enabled") || me.num("questTemplates.6.target") != 40 || !me.flag("questTemplates.7.enabled") {
		t.Fatalf("me = %s", me.Body)
	}
	h.patch("/api/me", nick.Token, obj{"questTemplates": []obj{{"key": "exercise", "target": 4}}}).
		expect(http.StatusUnprocessableEntity)
	h.patch("/api/me", nick.Token, obj{"questTemplates": []obj{{"key": "sleep", "target": 721}}}).
		expect(http.StatusUnprocessableEntity)

	// Edits apply from the next day, so move there.
	h.clock.Set(ny(2026, time.November, 3, 12, 0))
	before := h.get("/api/today", nick.Token).expect(http.StatusOK)
	if before.length("quests") != 8 || before.num("day.maxBase") != 300 {
		t.Fatalf("exercise and sleep stay out of maxBase until their first reading: %s", before.Body)
	}

	h.put("/api/health/daily", nick.Token, obj{"items": []obj{
		healthReading("2026-11-03", "exercise_minutes", 20, h.clock.Now()),
		healthReading("2026-11-03", "sleep_minutes", 420, h.clock.Now()),
	}}).expect(http.StatusOK)
	after := h.get("/api/today", nick.Token).expect(http.StatusOK)
	if after.length("quests") != 8 || after.num("day.maxBase") != 450 {
		t.Fatalf("quests = %s", after.Body)
	}
	if after.str("quests.5.key") != "exercise" || after.num("quests.5.actual") != 20 || after.num("quests.5.basePoints") != 50 ||
		after.flag("quests.5.done") || after.str("quests.6.key") != "sleep" || !after.flag("quests.6.done") ||
		after.num("quests.6.bonusPoints") != 10 {
		t.Fatalf("quests = %s", after.Body)
	}
}

func TestTodayHealthLatestAndMetrics(t *testing.T) {
	h := newHarness(t)
	h.clock.Set(ny(2026, time.November, 2, 22, 0))
	nick := h.joinAdmin("Nick", "green")
	h.clock.Set(ny(2026, time.November, 3, 8, 0))
	h.put("/api/health/daily", nick.Token, obj{"items": []obj{
		healthReading("2026-11-02", "weight_kg", 81, h.clock.Now()),
		healthReading("2026-11-02", "vo2max", 44, h.clock.Now()),
		healthReading("2026-11-03", "vo2max", 45, h.clock.Now()),
		healthReading("2026-11-03", "sleep_minutes", 400, h.clock.Now()),
	}}).expect(http.StatusOK)

	got := h.get("/api/today", nick.Token).expect(http.StatusOK)
	if got.num("health.metrics.sleep_minutes") != 400 || member(t, got, "health.metrics.weight_kg") ||
		got.num("health.latest.weight_kg.value") != 81 || got.str("health.latest.weight_kg.date") != "2026-11-02" ||
		got.num("health.latest.vo2max.value") != 45 || got.str("health.latest.vo2max.date") != "2026-11-03" ||
		member(t, got, "health.latest.body_fat_pct") || got.flag("health.stepsEverSynced") || got.isNull("health.syncedAt") {
		t.Fatalf("health = %s", got.Body)
	}
	past := h.get("/api/today?date=2026-11-02", nick.Token).expect(http.StatusOK)
	if past.num("health.latest.vo2max.value") != 44 || member(t, past, "health.metrics.sleep_minutes") {
		t.Fatalf("past day health = %s", past.Body)
	}

	fresh := newHarness(t)
	empty := fresh.joinAdmin("Nick", "green")
	none := fresh.get("/api/today", empty.Token).expect(http.StatusOK)
	if size(t, none, "health.metrics") != 0 || size(t, none, "health.latest") != 0 {
		t.Fatalf("empty health = %s", none.Body)
	}
}

func TestHealthTrends(t *testing.T) {
	h := newHarness(t)
	h.clock.Set(ny(2026, time.November, 2, 22, 0))
	nick, nadia := h.pair()
	h.clock.Set(ny(2026, time.November, 3, 8, 0))
	h.put("/api/health/daily", nick.Token, obj{"items": []obj{
		healthReading("2026-11-02", "weight_kg", 81, h.clock.Now()),
		healthReading("2026-11-03", "weight_kg", 80.5, h.clock.Now()),
	}}).expect(http.StatusOK)
	h.put("/api/health/daily", nadia.Token, obj{"items": []obj{
		healthReading("2026-11-03", "weight_kg", 60, h.clock.Now())}}).expect(http.StatusOK)

	got := h.get("/api/health/trends?metric=weight_kg&days=30", nick.Token).expect(http.StatusOK)
	if got.str("metric") != "weight_kg" || got.length("points") != 2 || got.str("points.0.date") != "2026-11-02" ||
		got.at("points.0.value") != 81.0 || got.str("points.1.date") != "2026-11-03" || got.at("points.1.value") != 80.5 {
		t.Fatalf("trends = %s", got.Body)
	}
	one := h.get("/api/health/trends?metric=weight_kg&days=1", nick.Token).expect(http.StatusOK)
	if one.length("points") != 1 || one.str("points.0.date") != "2026-11-03" {
		t.Fatalf("one day = %s", one.Body)
	}
	empty := h.get("/api/health/trends?metric=steps&days=7", nick.Token).expect(http.StatusOK)
	if empty.length("points") != 0 || empty.str("metric") != "steps" {
		t.Fatalf("empty = %s", empty.Body)
	}

	for _, q := range []string{"", "metric=weight_kg", "metric=weight_kg&days=0", "metric=weight_kg&days=366",
		"metric=weight_kg&days=x", "metric=heart_rate&days=7", "days=7"} {
		h.get("/api/health/trends?"+q, nick.Token).expect(http.StatusUnprocessableEntity).code("invalid_request")
	}
	h.get("/api/health/trends?metric=steps&days=7", "").expect(http.StatusUnauthorized)
}

func TestBoardHighlightsAreTodayOnlyAndOmittedWithoutRows(t *testing.T) {
	h := newHarness(t)
	h.clock.Set(ny(2026, time.November, 2, 22, 0))
	nick, nadia := h.pair()
	h.clock.Set(ny(2026, time.November, 3, 8, 0))
	h.put("/api/health/daily", nick.Token, obj{"items": []obj{
		healthReading("2026-11-03", "steps", 5000, h.clock.Now()),
		healthReading("2026-11-03", "exercise_minutes", 25, h.clock.Now()),
		healthReading("2026-11-03", "weight_kg", 80, h.clock.Now()),
		healthReading("2026-11-02", "sleep_minutes", 400, h.clock.Now()),
	}}).expect(http.StatusOK)

	got := h.get("/api/board", nadia.Token).expect(http.StatusOK)
	if size(t, got, "users.0.highlights") != 0 {
		t.Fatalf("Nadia has no readings: %s", got.Body)
	}
	if got.num("users.1.highlights.steps") != 5000 || got.num("users.1.highlights.exercise_minutes") != 25 ||
		member(t, got, "users.1.highlights.sleep_minutes") || size(t, got, "users.1.highlights") != 2 {
		t.Fatalf("Nick highlights = %s", got.Body)
	}
}

// member reports whether the dotted path exists in the body, which response.at cannot do
// because it fails the test on a missing key.
func member(t *testing.T, r *response, path string) bool {
	t.Helper()
	var cur any
	if err := json.Unmarshal(r.Body, &cur); err != nil {
		t.Fatal(err)
	}
	for _, part := range strings.Split(path, ".") {
		node, ok := cur.(map[string]any)
		if !ok {
			return false
		}
		if cur, ok = node[part]; !ok {
			return false
		}
	}
	return true
}

// size is the number of keys of the object at path.
func size(t *testing.T, r *response, path string) int {
	t.Helper()
	node, ok := r.at(path).(map[string]any)
	if !ok {
		t.Fatalf("%s is not an object: %s", path, r.Body)
	}
	return len(node)
}

func TestJoinDayPatchResnapshotsToday(t *testing.T) {
	h := newHarness(t)
	nick := h.joinAdmin("Nick", "green")
	h.logActivity(nick, "pushups", "reps", 30).expect(http.StatusCreated)
	before := h.get("/api/today", nick.Token).expect(http.StatusOK)
	if before.length("quests") != 8 || before.num("day.basePoints") != 100 {
		t.Fatalf("defaults = %s", before.Body)
	}

	h.patch("/api/me", nick.Token, obj{
		"targets": obj{"protein": 150},
		"questTemplates": []obj{
			{"key": "pushups", "enabled": false},
			{"key": "yoga", "enabled": true, "target": 10},
		}}).expect(http.StatusOK)
	got := h.get("/api/today", nick.Token).expect(http.StatusOK)
	keys := ""
	for i := 0; i < got.length("quests"); i++ {
		keys += got.str("quests."+strconv.Itoa(i)+".key") + " "
	}
	if keys != "steps reading meals_logged protein yoga exercise sleep water " || got.num("quests.3.target") != 150 ||
		got.num("quests.4.target") != 10 {
		t.Fatalf("join-day quests = %s", got.Body)
	}

	// Pushups are no longer a quest, and a log made before the edit still counts for yoga.
	h.logActivity(nick, "yoga", "minutes", 10).expect(http.StatusCreated)
	h.patch("/api/me", nick.Token, obj{"questTemplates": []obj{{"key": "pushups", "enabled": true}}}).expect(http.StatusOK)
	again := h.get("/api/today", nick.Token).expect(http.StatusOK)
	if again.length("quests") != 9 || again.num("quests.1.actual") != 30 || again.str("quests.1.key") != "pushups" ||
		!again.flag("quests.5.done") {
		t.Fatalf("logs must survive the re-snapshot: %s", again.Body)
	}
}

func TestPatchAfterJoinDayAppliesToday(t *testing.T) {
	h := newHarness(t)
	nick := h.joinAdmin("Nick", "green")
	h.clock.Set(ny(2026, time.November, 3, 12, 0))
	h.get("/api/today", nick.Token).expect(http.StatusOK)

	h.patch("/api/me", nick.Token, obj{"questTemplates": []obj{{"key": "pushups", "enabled": false}}}).expect(http.StatusOK)
	if got := h.get("/api/today", nick.Token).expect(http.StatusOK); got.length("quests") != 7 {
		t.Fatalf("today must follow the switch: %s", got.Body)
	}
	h.clock.Set(ny(2026, time.November, 4, 12, 0))
	if got := h.get("/api/today", nick.Token).expect(http.StatusOK); got.length("quests") != 7 {
		t.Fatalf("tomorrow must use the edit: %s", got.Body)
	}
}
