package api

import (
	"net/http"
	"strings"
	"testing"
	"time"
)

func TestPartnerTodayShowsTheirQuestsAndHabits(t *testing.T) {
	h := newHarness(t)
	nick, nadia := h.pair()
	id := h.brushFor(nadia, nil)
	h.put(markPath(id, "2026-11-02"), nadia.Token, obj{"slot": 0, "done": true}).expect(http.StatusOK)
	h.logActivity(nadia, "pushups", "reps", 15).expect(http.StatusCreated)

	got := h.get("/api/partner/today", nick.Token).expect(http.StatusOK)
	if got.str("name") != "Nadia" || got.str("date") != "2026-11-02" {
		t.Fatalf("partner = %s", got.Body)
	}
	pushups := -1
	for i := range got.length("quests") {
		if got.str("quests."+itoa(i)+".key") == "pushups" {
			pushups = i
		}
	}
	if pushups < 0 || got.num("quests."+itoa(pushups)+".actual") != 15 {
		t.Fatalf("quests = %s", got.Body)
	}
	for i := range got.length("quests") {
		if got.str("quests."+itoa(i)+".key") == "steps" {
			t.Fatalf("steps are not part of a day without Health: %s", got.Body)
		}
	}
	if got.length("habits") != 1 || got.str("habits.0.name") != "Brush teeth" || !got.flag("habits.0.slots.0.done") {
		t.Fatalf("habits = %s", got.Body)
	}
	if mine := h.get("/api/partner/today", nadia.Token).expect(http.StatusOK); mine.str("name") != "Nick" {
		t.Fatalf("Nadia sees %s", mine.Body)
	}
}

func TestPartnerTodayWithoutAPartnerIsNotFound(t *testing.T) {
	h := newHarness(t)
	only := h.joinAdmin("Nick", "green")
	h.get("/api/partner/today", only.Token).expect(http.StatusNotFound)
}

// Nadia in Los Angeles is still on Monday when it is already Tuesday in New York; her day is
// read on her own clock, and nothing of her food or health leaves the endpoint.
func TestPartnerTodayUsesThePartnersClockAndKeepsTheirFoodPrivate(t *testing.T) {
	h := newHarness(t)
	h.clock.Set(ny(2026, time.November, 3, 1, 30))
	nick := h.joinAdmin("Nick", "green")
	nadia := h.finishJoin(h.post("/api/join", "", obj{"code": h.invite(nick), "name": "Nadia",
		"color": "violet", "timezone": "America/Los_Angeles"}))
	h.logMeal(nadia, "Secret burrito", 900, 40).expect(http.StatusCreated)
	h.logActivity(nadia, "pushups", "reps", 12).expect(http.StatusCreated)

	got := h.get("/api/partner/today", nick.Token).expect(http.StatusOK)
	if got.str("date") != "2026-11-02" {
		t.Fatalf("Nadia's day is %s, want her own Monday: %s", got.str("date"), got.Body)
	}
	if got.num("day.points") <= 0 || got.num("streak.current") != 0 {
		t.Fatalf("day and streak = %s", got.Body)
	}
	body := string(got.Body)
	for _, leak := range []string{"Secret burrito", `"food"`, `"health"`, `"plan"`, `"kcal"`} {
		if strings.Contains(body, leak) {
			t.Fatalf("partner view carries %s: %s", leak, body)
		}
	}
}
