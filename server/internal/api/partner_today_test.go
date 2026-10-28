package api

import (
	"net/http"
	"testing"
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
