package api

import (
	"net/http"
	"strconv"
	"strings"
	"testing"
	"time"
)

func logID(r *response) string { return strconv.Itoa(r.num("log.id")) }

func dayQuest(r *response, key string) (actual, points int) {
	for i := range r.length("day.quests") {
		p := "day.quests." + itoa(i) + "."
		if r.str(p+"key") == key {
			return r.num(p + "actual"), r.num(p + "basePoints")
		}
	}
	r.t.Fatalf("no %s quest in %s", key, r.Body)
	return 0, 0
}

func TestPatchMealChangesTotalsAndRescoresTheDay(t *testing.T) {
	h := newHarness(t)
	nick := h.joinAdmin("Nick", "green")
	meal := h.logMeal(nick, "Oats", 400, 10, obj{"carbs": 60, "fat": 8, "fiber": 7}).expect(http.StatusCreated)
	beforeActual, beforePoints := dayQuest(meal, "protein")

	got := h.patch("/api/logs/"+logID(meal), nick.Token,
		obj{"name": " Big oats ", "kcal": 800, "protein": 60}).expect(http.StatusOK)
	if got.str("log.name") != "Big oats" || got.num("log.kcal") != 800 || got.at("log.protein").(float64) != 60 {
		t.Fatalf("log = %s", got.Body)
	}
	actual, points := dayQuest(got, "protein")
	if actual <= beforeActual || points <= beforePoints {
		t.Fatalf("protein quest %d/%d pts -> %d/%d pts, want it to grow", beforeActual, beforePoints, actual, points)
	}
	if got.str("day.date") != "2026-11-02" {
		t.Fatalf("day = %s", got.Body)
	}
}

func TestPatchMealKeepsFieldsThatWereNotSent(t *testing.T) {
	h := newHarness(t)
	nick := h.joinAdmin("Nick", "green")
	meal := h.logMeal(nick, "Oats", 400, 10, obj{"carbs": 60, "fat": 8, "fiber": 7}).expect(http.StatusCreated)

	got := h.patch("/api/logs/"+logID(meal), nick.Token, obj{"fat": 9.5}).expect(http.StatusOK)
	if got.str("log.name") != "Oats" || got.num("log.kcal") != 400 || got.at("log.fat").(float64) != 9.5 ||
		got.at("log.protein").(float64) != 10 || got.at("log.carbs").(float64) != 60 || got.at("log.fiber").(float64) != 7 {
		t.Fatalf("log = %s", got.Body)
	}
	// Zero is a value, not an absent field.
	got = h.patch("/api/logs/"+logID(meal), nick.Token, obj{"fiber": 0}).expect(http.StatusOK)
	if got.at("log.fiber").(float64) != 0 || got.num("log.kcal") != 400 {
		t.Fatalf("log = %s", got.Body)
	}
	listed := h.get("/api/logs", nick.Token).expect(http.StatusOK)
	if listed.num("logs.0.kcal") != 400 || listed.at("logs.0.fat").(float64) != 9.5 {
		t.Fatalf("stored = %s", listed.Body)
	}
}

func TestPatchMealValidation(t *testing.T) {
	h := newHarness(t)
	nick := h.joinAdmin("Nick", "green")
	path := "/api/logs/" + logID(h.logMeal(nick, "Oats", 400, 10).expect(http.StatusCreated))

	rejected := map[string]obj{
		"empty body":     {},
		"empty name":     {"name": "   "},
		"long name":      {"name": strings.Repeat("n", 81)},
		"control chars":  {"name": "a\u0007b"},
		"kcal zero":      {"kcal": 0},
		"kcal too big":   {"kcal": 10001},
		"negative macro": {"carbs": -1},
		"absurd macro":   {"protein": 5001},
	}
	for name, body := range rejected {
		resp := h.patch(path, nick.Token, body)
		if resp.Status != http.StatusUnprocessableEntity || resp.str("code") != "invalid_request" {
			t.Errorf("%s: status = %d, want 422 invalid_request; body: %s", name, resp.Status, resp.Body)
		}
	}
	h.patch(path, nick.Token, obj{"clientOpId": "x"}).expect(http.StatusBadRequest)
	h.patch(path, nick.Token, obj{"kcal": "lots"}).expect(http.StatusBadRequest)

	h.patch(path, nick.Token, obj{"kcal": 10000, "protein": 5000, "name": strings.Repeat("n", 80)}).expect(http.StatusOK)
}

func TestPatchMealIsPrivateAndNeedsALiveMeal(t *testing.T) {
	h := newHarness(t)
	nick, nadia := h.pair()
	id := logID(h.logMeal(nick, "Oats", 400, 10).expect(http.StatusCreated))

	h.patch("/api/logs/"+id, nadia.Token, obj{"kcal": 1}).expect(http.StatusNotFound)
	if h.get("/api/logs", nick.Token).num("logs.0.kcal") != 400 {
		t.Fatal("someone else's edit must change nothing")
	}
	h.patch("/api/logs/abc", nick.Token, obj{"kcal": 1}).expect(http.StatusNotFound)
	h.patch("/api/logs/999999", nick.Token, obj{"kcal": 1}).expect(http.StatusNotFound)

	h.delete("/api/logs/"+id, nick.Token).expect(http.StatusOK)
	h.patch("/api/logs/"+id, nick.Token, obj{"kcal": 500}).expect(http.StatusNotFound)
}

func TestPatchMealObeysTheDayWindow(t *testing.T) {
	h := newHarness(t)
	h.clock.Set(ny(2026, time.November, 2, 22, 0))
	nick := h.joinAdmin("Nick", "green")
	id := logID(h.logMeal(nick, "Oats", 400, 10).expect(http.StatusCreated))

	h.clock.Set(ny(2026, time.November, 3, 9, 0))
	h.patch("/api/logs/"+id, nick.Token, obj{"kcal": 450}).expect(http.StatusOK)

	h.clock.Set(ny(2026, time.November, 3, 10, 30))
	h.patch("/api/logs/"+id, nick.Token, obj{"kcal": 500}).expect(http.StatusUnprocessableEntity).code("date_closed")
	if got := h.get("/api/logs?date=2026-11-02", nick.Token); got.num("logs.0.kcal") != 450 {
		t.Fatalf("a refused edit must leave the meal as it was: %s", got.Body)
	}
}

func TestPatchRefusesActivities(t *testing.T) {
	h := newHarness(t)
	nick := h.joinAdmin("Nick", "green")
	id := logID(h.logActivity(nick, "pushups", "reps", 15).expect(http.StatusCreated))

	got := h.patch("/api/logs/"+id, nick.Token, obj{"kcal": 100}).expect(http.StatusUnprocessableEntity).code("invalid_request")
	if !strings.Contains(got.str("error"), "only meals") {
		t.Fatalf("body = %s", got.Body)
	}
}
