package api

import (
	"fmt"
	"net/http"
	"testing"
)

// questActual finds a quest by key in a response's day and returns its actual.
func questActual(t *testing.T, r *response, prefix, key string) int {
	t.Helper()
	for i := 0; i < r.length(prefix+".quests"); i++ {
		if r.str(fmt.Sprintf("%s.quests.%d.key", prefix, i)) == key {
			return r.num(fmt.Sprintf("%s.quests.%d.actual", prefix, i))
		}
	}
	t.Fatalf("no %s quest in %s", key, r.Body)
	return 0
}

func exerciseIndex(t *testing.T, r *response, key string) int {
	t.Helper()
	for i := 0; i < r.length("exercises"); i++ {
		if r.str(fmt.Sprintf("exercises.%d.key", i)) == key {
			return i
		}
	}
	t.Fatalf("no exercise %s in %s", key, r.Body)
	return -1
}

func TestCatalogListsSeededExercisesWithVocabularies(t *testing.T) {
	h := newHarness(t)
	nick := h.joinAdmin("Nick", "green")
	got := h.get("/api/exercises", nick.Token).expect(http.StatusOK)
	if got.length("exercises") < 35 || got.length("muscles") != 11 || got.length("equipment") != 8 {
		t.Fatalf("catalog = %d exercises, %d muscles, %d equipment", got.length("exercises"),
			got.length("muscles"), got.length("equipment"))
	}
	i := exerciseIndex(t, got, "pull_up")
	p := fmt.Sprintf("exercises.%d.", i)
	if got.str(p+"name") != "Pull-up" || got.str(p+"measure") != "reps" || got.str(p+"load") != "bodyweight" ||
		got.str(p+"easierKey") != "negative_pull_up" || !got.isNull(p+"harderKey") || got.flag(p+"custom") ||
		got.str(p+"primaryMuscles.0") != "back" || got.str(p+"equipment.0") != "pullup_bar" || !got.isNull(p+"best") {
		t.Fatalf("pull-up = %s", got.Body)
	}
}

func TestSetsLogOnceAndPushupSetsMoveTheQuest(t *testing.T) {
	h := newHarness(t)
	nick := h.joinAdmin("Nick", "green")
	op := h.nextOp()
	first := h.post("/api/sets", nick.Token, obj{"clientOpId": op, "exercise": "push_up", "reps": 12, "rir": 2}).
		expect(http.StatusCreated)
	if first.str("set.exercise") != "push_up" || first.num("set.reps") != 12 || first.num("set.rir") != 2 ||
		!first.isNull("set.seconds") || first.str("set.localDate") != "2026-11-02" {
		t.Fatalf("set = %s", first.Body)
	}
	if questActual(t, first, "day", "pushups") != 12 {
		t.Fatalf("push-up quest did not move: %s", first.Body)
	}
	replay := h.post("/api/sets", nick.Token, obj{"clientOpId": op, "exercise": "push_up", "reps": 12}).
		expect(http.StatusOK)
	if replay.num("set.id") != first.num("set.id") {
		t.Fatalf("replay made a second set: %s", replay.Body)
	}
	h.post("/api/sets", nick.Token, obj{"clientOpId": h.nextOp(), "exercise": "incline_push_up", "reps": 8}).
		expect(http.StatusCreated)
	logged := h.logActivity(nick, "pushups", "reps", 5).expect(http.StatusCreated)
	if questActual(t, logged, "day", "pushups") != 25 {
		t.Fatalf("logs and sets should add up to 25: %s", logged.Body)
	}
	pull := h.post("/api/sets", nick.Token, obj{"clientOpId": h.nextOp(), "exercise": "pull_up", "reps": 6}).
		expect(http.StatusCreated)
	if questActual(t, pull, "day", "pushups") != 25 {
		t.Fatalf("pull-ups must not count as push-ups: %s", pull.Body)
	}

	deleted := h.delete(fmt.Sprintf("/api/sets/%d", first.num("set.id")), nick.Token).expect(http.StatusOK)
	if questActual(t, deleted, "day", "pushups") != 13 {
		t.Fatalf("delete did not rescore: %s", deleted.Body)
	}
	h.delete(fmt.Sprintf("/api/sets/%d", first.num("set.id")), nick.Token).expect(http.StatusNotFound)

	list := h.get("/api/sets?exercise=pull_up&days=7", nick.Token).expect(http.StatusOK)
	if list.length("sets") != 1 || list.num("sets.0.reps") != 6 {
		t.Fatalf("pull-up sets = %s", list.Body)
	}
	if h.get("/api/sets", nick.Token).expect(http.StatusOK).length("sets") != 2 {
		t.Fatal("all live sets should list")
	}
}

func TestSetValidation(t *testing.T) {
	h := newHarness(t)
	nick := h.joinAdmin("Nick", "green")
	set := func(body obj) *response {
		body["clientOpId"] = h.nextOp()
		return h.post("/api/sets", nick.Token, body)
	}
	set(obj{"exercise": "plank", "reps": 10}).expect(http.StatusUnprocessableEntity)
	set(obj{"exercise": "push_up", "seconds": 30}).expect(http.StatusUnprocessableEntity)
	set(obj{"exercise": "push_up", "reps": 501}).expect(http.StatusUnprocessableEntity)
	set(obj{"exercise": "push_up", "reps": 10, "rir": 11}).expect(http.StatusUnprocessableEntity)
	set(obj{"exercise": "db_row", "reps": 10, "loadKg": 0}).expect(http.StatusUnprocessableEntity)
	set(obj{"exercise": "flying", "reps": 10}).expect(http.StatusNotFound)
	h.post("/api/sets", nick.Token, obj{"clientOpId": "nope", "exercise": "push_up", "reps": 5}).
		expect(http.StatusUnprocessableEntity)
	set(obj{"exercise": "push_up", "reps": 5, "date": "2026-10-20"}).code("date_closed")
	set(obj{"exercise": "plank", "seconds": 45}).expect(http.StatusCreated)
	set(obj{"exercise": "db_row", "reps": 10, "loadKg": 22.5}).expect(http.StatusCreated)
}

func TestBestSetAndMaxTests(t *testing.T) {
	h := newHarness(t)
	nick := h.joinAdmin("Nick", "green")
	for _, load := range []float64{20, 24} {
		h.post("/api/sets", nick.Token, obj{"clientOpId": h.nextOp(), "exercise": "db_row", "reps": 10, "loadKg": load}).
			expect(http.StatusCreated)
	}
	h.post("/api/exercises/pull_up/max", nick.Token, obj{"reps": 7}).expect(http.StatusCreated)
	h.post("/api/exercises/push_up/max", nick.Token, obj{"reps": 32}).expect(http.StatusCreated)
	h.post("/api/exercises/dead_hang/max", nick.Token, obj{"seconds": 55}).expect(http.StatusCreated)
	h.post("/api/exercises/dead_hang/max", nick.Token, obj{"reps": 5}).expect(http.StatusUnprocessableEntity)

	got := h.get("/api/exercises", nick.Token).expect(http.StatusOK)
	row := fmt.Sprintf("exercises.%d.", exerciseIndex(t, got, "db_row"))
	if got.at(row+"best.loadKg").(float64) != 24 || got.at(row+"best.e1rmKg").(float64) != 32 {
		t.Fatalf("db row best = %s", got.Body)
	}
	pull := fmt.Sprintf("exercises.%d.", exerciseIndex(t, got, "pull_up"))
	if got.num(pull+"maxTest.reps") != 7 {
		t.Fatalf("pull-up max = %s", got.Body)
	}
	hang := fmt.Sprintf("exercises.%d.", exerciseIndex(t, got, "dead_hang"))
	if got.num(hang+"maxTest.seconds") != 55 {
		t.Fatalf("hang max = %s", got.Body)
	}
	h.get("/api/targets", nick.Token).expect(http.StatusOK)
	push := fmt.Sprintf("exercises.%d.", exerciseIndex(t, got, "push_up"))
	if got.num(push+"maxTest.reps") != 32 {
		t.Fatalf("push-up max should come from the shared tables: %s", got.Body)
	}
}

func TestCustomExercises(t *testing.T) {
	h := newHarness(t)
	nick, nadia := h.pair()
	created := h.post("/api/exercises", nick.Token, obj{"name": "Kettlebell swing", "primaryMuscles": []string{"glutes"},
		"secondaryMuscles": []string{"hamstrings", "core"}, "measure": "reps", "load": "external",
		"equipment": []string{"gym"}}).expect(http.StatusCreated)
	key := created.str("exercise.key")
	if !created.flag("exercise.custom") || created.str("exercise.name") != "Kettlebell swing" || key == "" {
		t.Fatalf("custom = %s", created.Body)
	}
	h.post("/api/sets", nick.Token, obj{"clientOpId": h.nextOp(), "exercise": key, "reps": 15, "loadKg": 16}).
		expect(http.StatusCreated)
	h.post("/api/sets", nadia.Token, obj{"clientOpId": h.nextOp(), "exercise": key, "reps": 15}).
		expect(http.StatusNotFound)
	if got := h.get("/api/exercises", nadia.Token).expect(http.StatusOK); got.length("exercises") >= h.get("/api/exercises", nick.Token).length("exercises") {
		t.Fatal("Nadia must not see Nick's custom exercise")
	}

	h.patch("/api/exercises/"+key, nick.Token, obj{"name": "KB swing", "primaryMuscles": []string{"glutes"},
		"measure": "reps", "load": "external"}).expect(http.StatusOK)
	h.patch("/api/exercises/pull_up", nick.Token, obj{"name": "Mine", "primaryMuscles": []string{"back"},
		"measure": "reps", "load": "bodyweight"}).expect(http.StatusNotFound)
	h.post("/api/exercises", nick.Token, obj{"name": "Bad", "primaryMuscles": []string{"wings"},
		"measure": "reps", "load": "bodyweight"}).expect(http.StatusUnprocessableEntity)
	h.post("/api/exercises", nick.Token, obj{"name": "Bad", "primaryMuscles": []string{"core"},
		"measure": "laps", "load": "bodyweight"}).expect(http.StatusUnprocessableEntity)

	h.delete("/api/exercises/"+key, nick.Token).expect(http.StatusNoContent)
	if h.get("/api/sets", nick.Token).expect(http.StatusOK).length("sets") != 1 {
		t.Fatal("deleting an exercise must keep its sets")
	}
	h.delete("/api/exercises/"+key, nick.Token).expect(http.StatusNotFound)
}

func TestLookbackListsTheMonthsLifts(t *testing.T) {
	h := newHarness(t)
	nick := h.joinAdmin("Nick", "green")
	for _, reps := range []int{6, 9, 7} {
		h.post("/api/sets", nick.Token, obj{"clientOpId": h.nextOp(), "exercise": "pull_up", "reps": reps}).
			expect(http.StatusCreated)
	}
	got := h.get("/api/lookback?month=2026-11", nick.Token).expect(http.StatusOK)
	if got.length("people.0.lifts") != 1 || got.str("people.0.lifts.0.key") != "pull_up" ||
		got.num("people.0.lifts.0.best.reps") != 9 || got.str("people.0.lifts.0.measure") != "reps" ||
		!got.isNull("people.0.lifts.0.first") {
		t.Fatalf("lifts = %s", got.Body)
	}
	if h.get("/api/lookback?month=2026-10", nick.Token).expect(http.StatusOK).length("people.0.lifts") != 0 {
		t.Fatal("October had no sets")
	}
}
