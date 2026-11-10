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
	want := map[string]int{"steps": 100, "pushups": 75, "reading": 20, "protein": 20,
		"exercise": 85, "sleep": 20, "water": 20}
	for key, points := range want {
		if byKey[key].points != points {
			t.Errorf("%s is worth %d, want %d", key, byKey[key].points, points)
		}
	}
	why := map[string]string{
		"exercise": "Worth 85: about 30 min of moderate effort.",
		"water":    "Worth 20, the least any goal earns: no measured effort.",
		"steps":    "Worth 100, the most any goal earns: about 80 min of walking at a moderate pace.",
		"pushups":  "Worth 75: priced as a 30 min strength session (a game default), which this goal also accepts.",
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

	h.patch("/api/me", nick.Token, obj{"questTemplates": []obj{{"key": "exercise", "target": 20}}}).expect(http.StatusOK)

	today := h.get("/api/today", nick.Token).expect(http.StatusOK)
	if got := questsByKey(today)["exercise"].points; got != 55 {
		t.Fatalf("today must follow the target, exercise is worth %d: %s", got, today.Body)
	}
	yesterday := h.get("/api/today?date=2026-11-03", nick.Token).expect(http.StatusOK)
	if got := questsByKey(yesterday)["exercise"].points; got != 85 {
		t.Fatalf("a frozen day keeps its points, got %d: %s", got, yesterday.Body)
	}
}

func TestPlanningAStrengthSessionRepricesTheStrengthQuest(t *testing.T) {
	h := newHarness(t)
	nick := h.joinAdmin("Nick", "green")
	h.clock.Set(ny(2026, time.November, 3, 9, 0))
	h.get("/api/today", nick.Token).expect(http.StatusOK)
	h.clock.Set(ny(2026, time.November, 4, 9, 0))
	before := h.get("/api/today", nick.Token).expect(http.StatusOK)
	if questsByKey(before)["pushups"].points != 75 {
		t.Fatalf("strength before a plan: %s", before.Body)
	}

	profile := obj{"equipment": []string{}, "daysPerWeek": 3, "sessionMinutes": 20, "experience": "new", "focus": ""}
	h.put("/api/training/profile", nick.Token, profile).expect(http.StatusOK)

	today := h.get("/api/today", nick.Token).expect(http.StatusOK)
	byKey := questsByKey(today)
	if byKey["pushups"].points != 50 || today.num("day.maxBase") != before.num("day.maxBase")-25 {
		t.Fatalf("today must follow the session length: %s", today.Body)
	}
	for i := range today.length("quests") {
		p := "quests." + itoa(i)
		if today.str(p+".key") == "pushups" &&
			today.str(p+".pointsWhy") != "Worth 50: priced as your 20 min strength session, which this goal also accepts." {
			t.Fatalf("pointsWhy = %q", today.str(p+".pointsWhy"))
		}
	}
	yesterday := h.get("/api/today?date=2026-11-03", nick.Token).expect(http.StatusOK)
	if got := questsByKey(yesterday)["pushups"].points; got != 75 {
		t.Fatalf("a frozen day keeps its points, got %d: %s", got, yesterday.Body)
	}

	// The reps target and exercise no longer matter to what the quest is worth.
	h.patch("/api/me", nick.Token, obj{"questTemplates": []obj{{"key": "pushups", "target": 100}}}).expect(http.StatusOK)
	if got := questsByKey(h.get("/api/today", nick.Token).expect(http.StatusOK))["pushups"].points; got != 50 {
		t.Fatalf("100 reps = %d, want the planned session's 50", got)
	}
}
