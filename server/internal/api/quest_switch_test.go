package api

import (
	"net/http"
	"testing"
	"time"
)

func hasQuest(today *response, key string) bool {
	for i := range today.length("quests") {
		if today.str("quests."+itoa(i)+".key") == key {
			return true
		}
	}
	return false
}

func TestTurningProteinOffRemovesItFromTodayAndItsPossiblePoints(t *testing.T) {
	h := newHarness(t)
	nick := h.joinAdmin("Nick", "green")
	// A day after joining, so this is not the onboarding exception.
	h.clock.Set(ny(2026, time.November, 3, 9, 0))

	before := h.get("/api/today", nick.Token).expect(http.StatusOK)
	if !hasQuest(before, "protein") {
		t.Fatalf("protein should start on: %s", before.Body)
	}
	maxBefore := before.num("day.maxBase")

	h.patch("/api/me", nick.Token, obj{"questTemplates": []obj{{"key": "protein", "enabled": false}}}).expect(http.StatusOK)

	after := h.get("/api/today", nick.Token).expect(http.StatusOK)
	if hasQuest(after, "protein") {
		t.Fatalf("protein must leave today at once: %s", after.Body)
	}
	if after.num("day.maxBase") != maxBefore-50 {
		t.Fatalf("maxBase = %d, want %d: %s", after.num("day.maxBase"), maxBefore-50, after.Body)
	}
}

func TestTurningAQuestOnAddsItToToday(t *testing.T) {
	h := newHarness(t)
	nick := h.joinAdmin("Nick", "green")
	h.clock.Set(ny(2026, time.November, 3, 9, 0))

	before := h.get("/api/today", nick.Token).expect(http.StatusOK)
	if hasQuest(before, "yoga") {
		t.Fatalf("yoga should start off: %s", before.Body)
	}
	h.patch("/api/me", nick.Token, obj{"questTemplates": []obj{{"key": "yoga", "enabled": true, "target": 15}}}).expect(http.StatusOK)

	after := h.get("/api/today", nick.Token).expect(http.StatusOK)
	if !questsByKeyHas(after, "yoga") || questsByKey(after)["yoga"].target != 15 {
		t.Fatalf("yoga must join today: %s", after.Body)
	}
	if after.num("day.maxBase") != before.num("day.maxBase")+50 {
		t.Fatalf("maxBase = %d: %s", after.num("day.maxBase"), after.Body)
	}
}

func questsByKeyHas(r *response, key string) bool {
	_, ok := questsByKey(r)[key]
	return ok
}

func TestChangingATargetKeepsTodaysLogsAndLeavesThePastAlone(t *testing.T) {
	h := newHarness(t)
	nick := h.joinAdmin("Nick", "green")
	h.clock.Set(ny(2026, time.November, 3, 9, 0))
	h.get("/api/today", nick.Token).expect(http.StatusOK)

	// Yesterday keeps the goals it was scored with, even after its grace hour is over.
	h.clock.Set(ny(2026, time.November, 4, 9, 0))
	h.logMeal(nick, "Eggs", 300, 30).expect(http.StatusCreated)
	h.patch("/api/me", nick.Token, obj{"questTemplates": []obj{
		{"key": "protein", "enabled": false}, {"key": "meals_logged", "target": 4},
	}}).expect(http.StatusOK)

	today := h.get("/api/today", nick.Token).expect(http.StatusOK)
	byKey := questsByKey(today)
	if _, ok := byKey["protein"]; ok || byKey["meals_logged"].target != 4 || byKey["meals_logged"].actual != 1 {
		t.Fatalf("today after the edit: %s", today.Body)
	}

	history := h.get("/api/quests/protein/history?days=2", nick.Token).expect(http.StatusOK)
	n := history.length("days")
	if n != 2 {
		t.Fatalf("history = %s", history.Body)
	}
	// The day before keeps its protein quest; today no longer tracks it.
	if !history.flag("days.0.tracked") || history.num("days.0.target") != 100 {
		t.Fatalf("a past day was rewritten: %s", history.Body)
	}
	if history.flag("days.1.tracked") {
		t.Fatalf("today still tracks protein: %s", history.Body)
	}
}

func TestQuestHistoryReportsValueTargetAndDone(t *testing.T) {
	h := newHarness(t)
	nick := h.joinAdmin("Nick", "green")
	h.logMeal(nick, "Chicken", 500, 110).expect(http.StatusCreated)

	got := h.get("/api/quests/protein/history", nick.Token).expect(http.StatusOK)
	last := got.length("days") - 1
	p := "days." + itoa(last)
	if !got.flag(p+".tracked") || got.num(p+".actual") != 110 || got.num(p+".target") != 100 || !got.flag(p+".done") {
		t.Fatalf("history = %s", got.Body)
	}

	h.get("/api/quests/nope/history", nick.Token).expect(http.StatusNotFound)
	h.get("/api/quests/protein/history?days=0", nick.Token).expect(http.StatusUnprocessableEntity)
}
