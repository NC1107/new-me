package api

import (
	"net/http"
	"strconv"
	"strings"
	"testing"
	"time"
)

func TestCreateLogReturnsTheLogAndTheUpdatedDay(t *testing.T) {
	h := newHarness(t)
	nick := h.joinAdmin("Nick", "green")

	got := h.logActivity(nick, "pushups", "reps", 15).expect(http.StatusCreated)
	if got.str("log.kind") != "activity" || got.str("log.type") != "pushups" || got.num("log.quantity") != 15 ||
		got.str("log.unit") != "reps" || got.str("log.localDate") != "2026-11-02" || got.str("log.loggedAt") == "" {
		t.Fatalf("log = %s", got.Body)
	}
	if got.str("day.date") != "2026-11-02" || got.num("day.basePoints") != 50 || got.num("day.bonusPoints") != 0 ||
		got.num("day.maxBase") != 300 {
		t.Fatalf("day = %s", got.Body)
	}
	if got.str("day.quests.1.key") != "pushups" || got.num("day.quests.1.actual") != 15 {
		t.Fatalf("day quests = %s", got.Body)
	}

	meal := h.logMeal(nick, " Oats ", 400, 12.5, obj{"carbs": 60, "fat": 8, "fiber": 7}).expect(http.StatusCreated)
	if meal.str("log.kind") != "meal" || meal.str("log.name") != "Oats" || meal.num("log.kcal") != 400 ||
		meal.at("log.protein").(float64) != 12.5 || meal.at("log.fiber").(float64) != 7 {
		t.Fatalf("meal = %s", meal.Body)
	}
}

func TestActivityTypeAndUnitForms(t *testing.T) {
	h := newHarness(t)
	nick := h.joinAdmin("Nick", "green")
	ok := []obj{
		{"type": "reading", "unit": "minutes"},
		{"type": "reading", "unit": "pages"},
		{"type": "reading_pages"},
		{"type": "reading_minutes", "unit": "minutes"},
		{"type": "yoga", "unit": "minutes"},
		{"type": "yoga_minutes"},
		{"type": "pushups"},
	}
	for _, o := range ok {
		body := obj{"clientOpId": h.nextOp(), "kind": "activity", "quantity": 5}
		for k, v := range o {
			body[k] = v
		}
		h.post("/api/logs", nick.Token, body).expect(http.StatusCreated)
	}
	logs := h.get("/api/logs", nick.Token).expect(http.StatusOK)
	if logs.str("logs.0.type") != "reading" || logs.str("logs.0.unit") != "minutes" ||
		logs.str("logs.2.unit") != "pages" || logs.str("logs.4.type") != "yoga" {
		t.Fatalf("wire types = %s", logs.Body)
	}
}

func TestLogValidation(t *testing.T) {
	h := newHarness(t)
	nick := h.joinAdmin("Nick", "green")
	activity := func(typ, unit string, qty int) *response { return h.logActivity(nick, typ, unit, qty) }
	meal := func(name string, kcal int, extra ...obj) *response { return h.logMeal(nick, name, kcal, 0, extra...) }

	rejected := map[string]*response{
		"pushups over the cap": activity("pushups", "reps", 501),
		"pushups zero":         activity("pushups", "reps", 0),
		"pushups negative":     activity("pushups", "reps", -4),
		"pages over the cap":   activity("reading", "pages", 2001),
		"minutes over the cap": activity("reading", "minutes", 1441),
		"yoga over the cap":    activity("yoga", "minutes", 1441),
		"reading needs a unit": activity("reading", "", 5),
		"pushups in minutes":   activity("pushups", "minutes", 5),
		"unknown type":         activity("swimming", "laps", 5),
		"kcal over the cap":    meal("Feast", 10001),
		"kcal zero":            meal("Water", 0),
		"empty meal name":      meal("   ", 100),
		"long meal name":       meal(strings.Repeat("n", 81), 100),
		"negative macro":       meal("Odd", 100, obj{"fat": -1}),
		"absurd macro":         meal("Odd", 100, obj{"carbs": 5001}),
		"bad clientOpId":       h.post("/api/logs", nick.Token, obj{"clientOpId": "abc", "kind": "meal", "name": "x", "kcal": 5}),
		"missing kind":         h.post("/api/logs", nick.Token, obj{"clientOpId": h.nextOp()}),
		"bad date":             h.logActivity(nick, "pushups", "reps", 5, obj{"date": "yesterday"}),
		"overlong note":        h.logActivity(nick, "pushups", "reps", 5, obj{"note": strings.Repeat("n", 201)}),
	}
	for name, resp := range rejected {
		if resp.Status != http.StatusUnprocessableEntity || resp.str("code") != "invalid_request" {
			t.Errorf("%s: status = %d, want 422 invalid_request; body: %s", name, resp.Status, resp.Body)
		}
	}
	h.logActivity(nick, "pushups", "reps", 5, obj{"localDate": "2026-11-02"}).expect(http.StatusBadRequest)

	// Exactly at the caps is fine.
	h.logActivity(nick, "pushups", "reps", 500).expect(http.StatusCreated)
	h.logActivity(nick, "reading", "pages", 2000).expect(http.StatusCreated)
	h.logActivity(nick, "reading", "minutes", 1440).expect(http.StatusCreated)
	h.logMeal(nick, "Feast", 10000, 0).expect(http.StatusCreated)
	h.logActivity(nick, "pushups", "reps", 5, obj{"note": "morning set"}).expect(http.StatusCreated)
	if h.get("/api/logs", nick.Token).length("logs") != 5 {
		t.Fatal("rejected entries must not be stored")
	}
}

func TestLogReplayReturnsTheSameBodyWith200(t *testing.T) {
	h := newHarness(t)
	nick := h.joinAdmin("Nick", "green")
	body := obj{"clientOpId": h.nextOp(), "kind": "activity", "type": "pushups", "unit": "reps", "quantity": 20}

	first := h.post("/api/logs", nick.Token, body).expect(http.StatusCreated)
	second := h.post("/api/logs", nick.Token, body).expect(http.StatusOK)
	if string(first.Body) != string(second.Body) {
		t.Fatalf("replay body differs:\n%s\n%s", first.Body, second.Body)
	}
	h.get("/api/logs", nick.Token).expect(http.StatusOK)
	if h.get("/api/logs", nick.Token).length("logs") != 1 {
		t.Fatal("a replay must not store a second entry")
	}
	if h.get("/api/today", nick.Token).num("quests.1.actual") != 20 {
		t.Fatal("a replay must not count twice")
	}

	meal := obj{"clientOpId": h.nextOp(), "kind": "meal", "name": "Oats", "kcal": 400}
	one := h.post("/api/logs", nick.Token, meal).expect(http.StatusCreated)
	two := h.post("/api/logs", nick.Token, meal).expect(http.StatusOK)
	if string(one.Body) != string(two.Body) {
		t.Fatalf("meal replay body differs:\n%s\n%s", one.Body, two.Body)
	}
}

func TestClientOpIDsAreScopedPerUser(t *testing.T) {
	h := newHarness(t)
	nick, nadia := h.pair()
	body := obj{"clientOpId": h.nextOp(), "kind": "activity", "type": "pushups", "unit": "reps", "quantity": 20}
	h.post("/api/logs", nick.Token, body).expect(http.StatusCreated)
	h.post("/api/logs", nadia.Token, body).expect(http.StatusCreated)
}

func TestReplayOfADeletedLogStaysDeleted(t *testing.T) {
	h := newHarness(t)
	nick := h.joinAdmin("Nick", "green")
	body := obj{"clientOpId": h.nextOp(), "kind": "activity", "type": "pushups", "unit": "reps", "quantity": 20}
	created := h.post("/api/logs", nick.Token, body).expect(http.StatusCreated)
	id := created.num("log.id")

	gone := h.delete("/api/logs/"+strconv.Itoa(id), nick.Token).expect(http.StatusOK)
	if gone.num("day.basePoints") != 0 || gone.str("day.date") != "2026-11-02" {
		t.Fatalf("day after delete = %s", gone.Body)
	}

	replay := h.post("/api/logs", nick.Token, body).expect(http.StatusOK)
	if replay.num("log.id") != id || replay.num("day.basePoints") != 0 {
		t.Fatalf("replay = %s", replay.Body)
	}
	if h.get("/api/logs", nick.Token).length("logs") != 0 {
		t.Fatal("a replay must not undelete the entry")
	}
	h.delete("/api/logs/"+strconv.Itoa(id), nick.Token).expect(http.StatusNotFound).code("not_found")

	again := obj{"clientOpId": h.nextOp(), "kind": "activity", "type": "pushups", "unit": "reps", "quantity": 20}
	h.post("/api/logs", nick.Token, again).expect(http.StatusCreated)
	if h.get("/api/logs", nick.Token).length("logs") != 1 {
		t.Fatal("undo is a fresh post with a new clientOpId")
	}
}

func TestDeleteLogRescoresAndIsPrivate(t *testing.T) {
	h := newHarness(t)
	nick, nadia := h.pair()
	meal := h.logMeal(nick, "Oats", 400, 20).expect(http.StatusCreated)
	h.logMeal(nick, "Rice", 600, 10).expect(http.StatusCreated)

	id := strconv.Itoa(meal.num("log.id"))
	h.delete("/api/logs/"+id, nadia.Token).expect(http.StatusNotFound)
	got := h.delete("/api/logs/"+id, nick.Token).expect(http.StatusOK)
	if q := got.at("day.quests.3").(map[string]any); q["key"] != "meals_logged" || q["actual"].(float64) != 1 || q["done"].(bool) {
		t.Fatalf("meals quest after delete = %v", q)
	}
	h.delete("/api/logs/abc", nick.Token).expect(http.StatusNotFound)
	h.delete("/api/logs/999999", nick.Token).expect(http.StatusNotFound)
}

func TestListLogsIsATaggedUnionOldestFirst(t *testing.T) {
	h := newHarness(t)
	nick := h.joinAdmin("Nick", "green")
	h.logActivity(nick, "pushups", "reps", 10).expect(http.StatusCreated)
	h.logMeal(nick, "Oats", 400, 12).expect(http.StatusCreated)
	h.logActivity(nick, "reading", "pages", 4).expect(http.StatusCreated)

	got := h.get("/api/logs?date=2026-11-02", nick.Token).expect(http.StatusOK)
	if got.str("date") != "2026-11-02" || got.length("logs") != 3 {
		t.Fatalf("logs = %s", got.Body)
	}
	for i, kind := range []string{"activity", "meal", "activity"} {
		if got.str("logs."+strconv.Itoa(i)+".kind") != kind {
			t.Fatalf("logs[%d] kind = %v, want %s; body: %s", i, got.at("logs."+strconv.Itoa(i)+".kind"), kind, got.Body)
		}
	}
	if _, hasKcal := got.at("logs.0").(map[string]any)["kcal"]; hasKcal {
		t.Fatal("an activity must not carry meal fields")
	}
	if h.get("/api/logs?date=2026-11-01", nick.Token).expect(http.StatusOK).length("logs") != 0 {
		t.Fatal("another day must be empty")
	}
	h.get("/api/logs?date=nope", nick.Token).expect(http.StatusUnprocessableEntity)
}

func TestDayWindow(t *testing.T) {
	h := newHarness(t)
	h.clock.Set(ny(2026, time.November, 2, 22, 0))
	nick := h.joinAdmin("Nick", "green")
	post := func(date string) *response {
		return h.logActivity(nick, "pushups", "reps", 10, obj{"date": date})
	}

	post("2026-11-02").expect(http.StatusCreated)
	post("2026-11-03").expect(http.StatusUnprocessableEntity).code("date_closed")
	post("2026-11-01").expect(http.StatusUnprocessableEntity).code("date_closed")

	// Yesterday stays open until 10:00 local on the next day.
	h.clock.Set(ny(2026, time.November, 3, 9, 59))
	backdated := post("2026-11-02").expect(http.StatusCreated)
	if backdated.str("day.date") != "2026-11-02" || backdated.num("day.quests.1.actual") != 20 {
		t.Fatalf("backdated entry = %s", backdated.Body)
	}
	if h.get("/api/today", nick.Token).num("quests.1.actual") != 0 {
		t.Fatal("a backdated entry must not count toward today")
	}

	h.clock.Set(ny(2026, time.November, 3, 10, 0))
	post("2026-11-02").expect(http.StatusUnprocessableEntity).code("date_closed")
	post("2026-11-03").expect(http.StatusCreated)
}

func TestDeleteObeysTheDayWindow(t *testing.T) {
	h := newHarness(t)
	h.clock.Set(ny(2026, time.November, 2, 22, 0))
	nick := h.joinAdmin("Nick", "green")
	id := strconv.Itoa(h.logActivity(nick, "pushups", "reps", 10).expect(http.StatusCreated).num("log.id"))

	h.clock.Set(ny(2026, time.November, 3, 10, 30))
	h.delete("/api/logs/"+id, nick.Token).expect(http.StatusUnprocessableEntity).code("date_closed")
	if h.get("/api/logs?date=2026-11-02", nick.Token).length("logs") != 1 {
		t.Fatal("a refused delete must leave the entry in place")
	}

	h.clock.Set(ny(2026, time.November, 3, 9, 0))
	h.delete("/api/logs/"+id, nick.Token).expect(http.StatusOK)
}

func TestReplayAfterTheWindowClosesStillAnswers(t *testing.T) {
	h := newHarness(t)
	h.clock.Set(ny(2026, time.November, 2, 22, 0))
	nick := h.joinAdmin("Nick", "green")
	body := obj{"clientOpId": h.nextOp(), "kind": "activity", "type": "pushups", "unit": "reps", "quantity": 10,
		"date": "2026-11-02"}
	h.post("/api/logs", nick.Token, body).expect(http.StatusCreated)

	h.clock.Set(ny(2026, time.November, 3, 12, 0))
	replay := h.post("/api/logs", nick.Token, body).expect(http.StatusOK)
	if replay.str("log.localDate") != "2026-11-02" {
		t.Fatalf("replay = %s", replay.Body)
	}
	fresh := obj{"clientOpId": h.nextOp(), "kind": "activity", "type": "pushups", "unit": "reps", "quantity": 10,
		"date": "2026-11-02"}
	h.post("/api/logs", nick.Token, fresh).expect(http.StatusUnprocessableEntity).code("date_closed")
	if h.get("/api/logs?date=2026-11-02", nick.Token).length("logs") != 1 {
		t.Fatal("a refused log must not be stored")
	}
}

func TestRecentMealsSpanBothUsers(t *testing.T) {
	h := newHarness(t)
	nick, nadia := h.pair()
	h.logMeal(nick, "Oats", 400, 12).expect(http.StatusCreated)
	h.logMeal(nadia, "Pasta", 700, 25).expect(http.StatusCreated)
	h.logMeal(nadia, "oats", 400, 12).expect(http.StatusCreated)
	gone := h.logMeal(nick, "Secret snack", 300, 1).expect(http.StatusCreated)
	h.delete("/api/logs/"+strconv.Itoa(gone.num("log.id")), nick.Token).expect(http.StatusOK)
	h.logMeal(nick, "Oats", 450, 12).expect(http.StatusCreated)

	got := h.get("/api/meals/recent", nadia.Token).expect(http.StatusOK)
	var names []string
	for i := range got.length("meals") {
		names = append(names, got.str("meals."+strconv.Itoa(i)+".name")+":"+strconv.Itoa(got.num("meals."+strconv.Itoa(i)+".kcal")))
	}
	want := []string{"Oats:450", "oats:400", "Pasta:700"}
	if len(names) != len(want) {
		t.Fatalf("recent meals = %v, want %v", names, want)
	}
	for i := range want {
		if names[i] != want[i] {
			t.Fatalf("recent meals = %v, want %v", names, want)
		}
	}
	if got.at("meals.0.protein").(float64) != 12 {
		t.Fatalf("recent meal macros = %s", got.Body)
	}

	if h.get("/api/meals/recent?limit=1", nick.Token).expect(http.StatusOK).length("meals") != 1 {
		t.Fatal("limit must cap the list")
	}
	h.get("/api/meals/recent?limit=0", nick.Token).expect(http.StatusUnprocessableEntity)
	h.get("/api/meals/recent?limit=51", nick.Token).expect(http.StatusUnprocessableEntity)
}
