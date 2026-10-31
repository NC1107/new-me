package api

import (
	"net/http"
	"testing"
	"time"
)

func TestQuestsCarryTheirEffortWorthAndWhy(t *testing.T) {
	h := newHarness(t)
	nick := h.joinAdmin("Nick", "green")

	got := h.get("/api/today", nick.Token).expect(http.StatusOK)
	byKey := questsByKey(got)
	want := map[string]int{"steps": 150, "pushups": 20, "reading": 20, "meals_logged": 20, "protein": 20,
		"exercise": 85, "sleep": 20, "water": 20}
	for key, points := range want {
		if byKey[key].points != points {
			t.Errorf("%s is worth %d, want %d", key, byKey[key].points, points)
		}
	}
	why := map[string]string{
		"exercise": "Worth 85: about 30 min of moderate effort.",
		"water":    "Worth 20, the game's minimum: no measured effort.",
		"steps":    "Worth 150, the game's maximum: about 80 min of walking at a moderate pace.",
	}
	for i := range got.length("quests") {
		p := "quests." + itoa(i)
		if w, ok := why[got.str(p+".key")]; ok && got.str(p+".pointsWhy") != w {
			t.Errorf("%s pointsWhy = %q, want %q", got.str(p+".key"), got.str(p+".pointsWhy"), w)
		}
	}
}

func TestChangingATargetRepricesTodayButNotThePast(t *testing.T) {
	h := newHarness(t)
	nick := h.joinAdmin("Nick", "green")
	h.clock.Set(ny(2026, time.November, 3, 9, 0))
	h.get("/api/today", nick.Token).expect(http.StatusOK)
	h.clock.Set(ny(2026, time.November, 4, 9, 0))
	before := h.get("/api/today", nick.Token).expect(http.StatusOK)
	if questsByKey(before)["exercise"].points != 85 {
		t.Fatalf("exercise before the edit: %s", before.Body)
	}

	h.patch("/api/me", nick.Token, obj{"questTemplates": []obj{
		{"key": "exercise", "target": 20}, {"key": "pushups", "target": 100},
	}}).expect(http.StatusOK)

	today := h.get("/api/today", nick.Token).expect(http.StatusOK)
	byKey := questsByKey(today)
	if byKey["exercise"].points != 55 || byKey["pushups"].points != 45 {
		t.Fatalf("today must follow the targets: %s", today.Body)
	}
	if today.num("day.maxBase") != before.num("day.maxBase")+25 {
		t.Fatalf("maxBase = %d: %s", today.num("day.maxBase"), today.Body)
	}

	yesterday := h.get("/api/today?date=2026-11-03", nick.Token).expect(http.StatusOK)
	if got := questsByKey(yesterday)["exercise"].points; got != 85 {
		t.Fatalf("a frozen day keeps its points, got %d: %s", got, yesterday.Body)
	}
}

func TestSwitchingTheRepsExerciseRepricesThePushupsQuest(t *testing.T) {
	h := newHarness(t)
	nick := h.joinAdmin("Nick", "green")
	h.patch("/api/me", nick.Token, obj{"questTemplates": []obj{{"key": "pushups", "target": 100}}}).expect(http.StatusOK)
	if got := questsByKey(h.get("/api/today", nick.Token).expect(http.StatusOK))["pushups"].points; got != 45 {
		t.Fatalf("100 push-ups = %d", got)
	}
	h.patch("/api/me", nick.Token, obj{"questTemplates": []obj{{"key": "pushups", "exercise": "crunch"}}}).expect(http.StatusOK)
	if got := questsByKey(h.get("/api/today", nick.Token).expect(http.StatusOK))["pushups"].points; got != 30 {
		t.Fatalf("100 crunches = %d", got)
	}
}
