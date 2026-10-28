package api

import (
	"fmt"
	"net/http"
	"strings"
	"testing"
	"time"
)

func twoSlots() []obj {
	return []obj{{"label": "Morning", "time": "07:30"}, {"label": "Evening", "time": "22:00"}}
}

func (h *harness) createHabit(p person, body obj) *response {
	h.t.Helper()
	return h.post("/api/habits", p.Token, body)
}

func (h *harness) brushTeeth(p person) int {
	h.t.Helper()
	got := h.createHabit(p, obj{"name": "Brush teeth", "icon": "brush", "kind": "check", "slots": twoSlots()}).
		expect(http.StatusCreated)
	return got.num("habit.id")
}

func (h *harness) water(p person, target int) int {
	h.t.Helper()
	return h.createHabit(p, obj{"name": "Water", "icon": "water_drop", "kind": "count", "target": target}).
		expect(http.StatusCreated).num("habit.id")
}

func markPath(id int, date string) string { return fmt.Sprintf("/api/habits/%d/marks/%s", id, date) }

func TestCreateHabitReturnsTheScheduleWithDefaults(t *testing.T) {
	h := newHarness(t)
	nick := h.joinAdmin("Nick", "green")
	got := h.createHabit(nick, obj{"name": "  Brush teeth ", "icon": "brush", "kind": "check", "slots": twoSlots()}).
		expect(http.StatusCreated)
	if got.str("habit.name") != "Brush teeth" || got.str("habit.kind") != "check" || got.length("habit.weekdays") != 7 ||
		got.length("habit.slots") != 2 || got.str("habit.slots.0.time") != "07:30" || !got.isNull("habit.target") ||
		got.flag("habit.paused") || got.num("habit.position") != 0 {
		t.Fatalf("habit = %s", got.Body)
	}
	count := h.createHabit(nick, obj{"name": "Water", "icon": "water_drop", "kind": "count", "target": 8,
		"weekdays": []int{1, 3, 5}}).expect(http.StatusCreated)
	if count.num("habit.target") != 8 || count.length("habit.slots") != 0 || count.length("habit.weekdays") != 3 ||
		count.num("habit.position") != 1 {
		t.Fatalf("count habit = %s", count.Body)
	}
	if list := h.get("/api/habits", nick.Token).expect(http.StatusOK); list.length("habits") != 2 ||
		list.str("habits.0.name") != "Brush teeth" {
		t.Fatalf("list = %s", list.Body)
	}
}

func TestCreateHabitValidation(t *testing.T) {
	h := newHarness(t)
	nick := h.joinAdmin("Nick", "green")
	slots := func(n int) []obj {
		out := make([]obj, n)
		for i := range out {
			out[i] = obj{"label": fmt.Sprintf("Slot %d", i+1)}
		}
		return out
	}
	base := func(edit func(obj)) obj {
		b := obj{"name": "Stretch", "icon": "spa", "kind": "check", "slots": slots(1)}
		edit(b)
		return b
	}
	bad := map[string]obj{
		"empty name":           base(func(b obj) { b["name"] = "  " }),
		"long name":            base(func(b obj) { b["name"] = strings.Repeat("x", 41) }),
		"control char name":    base(func(b obj) { b["name"] = "a\u0007b" }),
		"unknown icon":         base(func(b obj) { b["icon"] = "rocket" }),
		"unknown kind":         base(func(b obj) { b["kind"] = "timer" }),
		"no slots":             base(func(b obj) { b["slots"] = []obj{} }),
		"nine slots":           base(func(b obj) { b["slots"] = slots(9) }),
		"empty label":          base(func(b obj) { b["slots"] = []obj{{"label": " "}} }),
		"long label":           base(func(b obj) { b["slots"] = []obj{{"label": strings.Repeat("x", 25)}} }),
		"time 24:00":           base(func(b obj) { b["slots"] = []obj{{"label": "A", "time": "24:00"}} }),
		"time 7:30":            base(func(b obj) { b["slots"] = []obj{{"label": "A", "time": "7:30"}} }),
		"time with seconds":    base(func(b obj) { b["slots"] = []obj{{"label": "A", "time": "07:30:00"}} }),
		"check with target":    base(func(b obj) { b["target"] = 3 }),
		"count without target": {"name": "Water", "icon": "water_drop", "kind": "count"},
		"count target 0":       {"name": "Water", "icon": "water_drop", "kind": "count", "target": 0},
		"count target 51":      {"name": "Water", "icon": "water_drop", "kind": "count", "target": 51},
		"count with slots":     {"name": "Water", "icon": "water_drop", "kind": "count", "target": 8, "slots": slots(1)},
		"weekday 0":            base(func(b obj) { b["weekdays"] = []int{0} }),
		"weekday 8":            base(func(b obj) { b["weekdays"] = []int{8} }),
		"no weekdays":          base(func(b obj) { b["weekdays"] = []int{} }),
		"missing kind":         {"name": "Water", "icon": "water_drop"},
	}
	for name, body := range bad {
		got := h.createHabit(nick, body).expect(http.StatusUnprocessableEntity)
		got.code("invalid_request")
		_ = name
	}
	// Eight slots and the longest name are fine.
	h.createHabit(nick, base(func(b obj) { b["slots"] = slots(8); b["name"] = strings.Repeat("é", 40) })).
		expect(http.StatusCreated)
	h.post("/api/habits", nick.Token, obj{"name": "X", "icon": "star", "kind": "check", "slots": slots(1), "surprise": 1}).
		expect(http.StatusBadRequest).code("invalid_json")
	if list := h.get("/api/habits", nick.Token).expect(http.StatusOK); list.length("habits") != 1 {
		t.Fatalf("rejected habits were stored: %s", list.Body)
	}
}

func TestAPersonCanHaveAtMostThirtyHabits(t *testing.T) {
	h := newHarness(t)
	nick, nadia := h.pair()
	for i := range 30 {
		h.createHabit(nick, obj{"name": fmt.Sprintf("Habit %d", i), "icon": "star", "kind": "count", "target": 1}).
			expect(http.StatusCreated)
	}
	h.createHabit(nick, obj{"name": "One too many", "icon": "star", "kind": "count", "target": 1}).
		expect(http.StatusUnprocessableEntity).code("invalid_request")
	h.createHabit(nadia, obj{"name": "Hers", "icon": "star", "kind": "count", "target": 1}).expect(http.StatusCreated)

	// A deleted habit frees its place.
	id := h.get("/api/habits", nick.Token).num("habits.0.id")
	h.delete(fmt.Sprintf("/api/habits/%d", id), nick.Token).expect(http.StatusNoContent)
	h.createHabit(nick, obj{"name": "Again", "icon": "star", "kind": "count", "target": 1}).expect(http.StatusCreated)
}

func TestHabitsArePrivateToTheirOwner(t *testing.T) {
	h := newHarness(t)
	nick, nadia := h.pair()
	id := h.brushTeeth(nick)
	if got := h.get("/api/habits", nadia.Token).expect(http.StatusOK); got.length("habits") != 0 {
		t.Fatalf("Nadia sees %s", got.Body)
	}
	h.patch(fmt.Sprintf("/api/habits/%d", id), nadia.Token, obj{"name": "Mine now"}).expect(http.StatusNotFound)
	h.delete(fmt.Sprintf("/api/habits/%d", id), nadia.Token).expect(http.StatusNotFound)
	h.put(markPath(id, "2026-11-02"), nadia.Token, obj{"slot": 0, "done": true}).expect(http.StatusNotFound)
	h.get("/api/habits", "").expect(http.StatusUnauthorized)
}

func TestPatchHabitEditsScheduleAndPausesWithoutChangingKind(t *testing.T) {
	h := newHarness(t)
	nick := h.joinAdmin("Nick", "green")
	id := h.brushTeeth(nick)
	path := fmt.Sprintf("/api/habits/%d", id)

	got := h.patch(path, nick.Token, obj{"name": "Floss", "icon": "spa", "weekdays": []int{1, 2},
		"slots": []obj{{"label": "Night", "time": nil}}}).expect(http.StatusOK)
	if got.str("habit.name") != "Floss" || got.str("habit.icon") != "spa" || got.length("habit.slots") != 1 ||
		!got.isNull("habit.slots.0.time") || got.length("habit.weekdays") != 2 {
		t.Fatalf("patched = %s", got.Body)
	}
	if got := h.patch(path, nick.Token, obj{"paused": true}).expect(http.StatusOK); !got.flag("habit.paused") ||
		got.str("habit.name") != "Floss" {
		t.Fatalf("paused = %s", got.Body)
	}
	h.patch(path, nick.Token, obj{"kind": "count"}).expect(http.StatusUnprocessableEntity).code("invalid_request")
	h.patch(path, nick.Token, obj{"target": 3}).expect(http.StatusUnprocessableEntity)
	h.patch(path, nick.Token, obj{"slots": []obj{}}).expect(http.StatusUnprocessableEntity)
	h.patch(path, nick.Token, obj{"icon": "rocket"}).expect(http.StatusUnprocessableEntity)
	h.patch("/api/habits/999", nick.Token, obj{"name": "x"}).expect(http.StatusNotFound)
	h.patch("/api/habits/abc", nick.Token, obj{"name": "x"}).expect(http.StatusNotFound)
}

func TestDeleteHabitIsSoftAndOrderRequiresEveryHabit(t *testing.T) {
	h := newHarness(t)
	nick := h.joinAdmin("Nick", "green")
	a, b, c := h.brushTeeth(nick), h.water(nick, 8), h.water(nick, 4)

	h.put("/api/habits/order", nick.Token, obj{"ids": []int{c, a}}).expect(http.StatusUnprocessableEntity)
	h.put("/api/habits/order", nick.Token, obj{"ids": []int{c, a, a}}).expect(http.StatusUnprocessableEntity)
	h.put("/api/habits/order", nick.Token, obj{"ids": []int{c, a, 12345}}).expect(http.StatusUnprocessableEntity)
	got := h.put("/api/habits/order", nick.Token, obj{"ids": []int{c, a, b}}).expect(http.StatusOK)
	if got.num("habits.0.id") != c || got.num("habits.1.id") != a || got.num("habits.2.id") != b ||
		got.num("habits.0.position") != 0 || got.num("habits.2.position") != 2 {
		t.Fatalf("order = %s", got.Body)
	}

	h.delete(fmt.Sprintf("/api/habits/%d", a), nick.Token).expect(http.StatusNoContent)
	h.delete(fmt.Sprintf("/api/habits/%d", a), nick.Token).expect(http.StatusNotFound)
	if list := h.get("/api/habits", nick.Token).expect(http.StatusOK); list.length("habits") != 2 {
		t.Fatalf("list after delete = %s", list.Body)
	}
	h.put(markPath(a, "2026-11-02"), nick.Token, obj{"slot": 0, "done": true}).expect(http.StatusNotFound)
	h.put("/api/habits/order", nick.Token, obj{"ids": []int{b, c}}).expect(http.StatusOK)
}

func TestMarkingASlotEarnsItsShareOfTheHabitsWorth(t *testing.T) {
	h := newHarness(t)
	nick := h.joinAdmin("Nick", "green")
	before := h.get("/api/today", nick.Token).expect(http.StatusOK)
	id := h.brushTeeth(nick)
	due := h.get("/api/today", nick.Token).expect(http.StatusOK)
	if due.num("day.maxBase") != before.num("day.maxBase")+25 || due.num("habits.0.points") != 25 {
		t.Fatalf("a due Medium habit adds 25 possible points: %s", due.Body)
	}

	got := h.put(markPath(id, "2026-11-02"), nick.Token, obj{"slot": 0, "done": true}).expect(http.StatusOK)
	if got.str("date") != "2026-11-02" || !got.flag("habits.0.slots.0.done") || got.flag("habits.0.slots.1.done") ||
		got.num("day.basePoints") != due.num("day.basePoints")+12 || got.num("day.bonusPoints") != due.num("day.bonusPoints") {
		t.Fatalf("after first slot = %s", got.Body)
	}
	got = h.put(markPath(id, "2026-11-02"), nick.Token, obj{"slot": 1, "done": true}).expect(http.StatusOK)
	if got.num("day.basePoints") != due.num("day.basePoints")+25 {
		t.Fatalf("after second slot = %s", got.Body)
	}

	// Idempotent: the same call again changes nothing.
	again := h.put(markPath(id, "2026-11-02"), nick.Token, obj{"slot": 1, "done": true}).expect(http.StatusOK)
	if again.num("day.basePoints") != due.num("day.basePoints")+25 {
		t.Fatalf("repeat changed the score: %s", again.Body)
	}

	undone := h.put(markPath(id, "2026-11-02"), nick.Token, obj{"slot": 0, "done": false}).expect(http.StatusOK)
	if undone.flag("habits.0.slots.0.done") || undone.num("day.basePoints") != due.num("day.basePoints")+12 {
		t.Fatalf("after undo = %s", undone.Body)
	}
}

func TestHabitWorthIsChosenAndChangedAndCanJustTrack(t *testing.T) {
	h := newHarness(t)
	nick := h.joinAdmin("Nick", "green")
	base := h.get("/api/today", nick.Token).expect(http.StatusOK).num("day.maxBase")
	big := h.post("/api/habits", nick.Token, obj{"name": "Creatine", "icon": "medication", "kind": "check",
		"slots": []obj{{"label": "Morning", "time": nil}}, "points": 50}).expect(http.StatusCreated)
	if big.num("habit.points") != 50 {
		t.Fatalf("created = %s", big.Body)
	}
	if got := h.get("/api/today", nick.Token).num("day.maxBase"); got != base+50 {
		t.Fatalf("maxBase = %d, want %d", got, base+50)
	}
	id := big.num("habit.id")
	h.patch(fmt.Sprintf("/api/habits/%d", id), nick.Token, obj{"points": 0}).expect(http.StatusOK)
	if got := h.get("/api/today", nick.Token).num("day.maxBase"); got != base {
		t.Fatalf("a just-track habit adds nothing: maxBase = %d", got)
	}
	h.patch(fmt.Sprintf("/api/habits/%d", id), nick.Token, obj{"points": 30}).expect(http.StatusUnprocessableEntity)
	h.post("/api/habits", nick.Token, obj{"name": "Bad", "icon": "medication", "kind": "check",
		"slots": []obj{{"label": "Morning", "time": nil}}, "points": 7}).expect(http.StatusUnprocessableEntity)
}

func TestCountHabitEarnsItsShareAndClearsAtZero(t *testing.T) {
	h := newHarness(t)
	nick := h.joinAdmin("Nick", "green")
	id := h.water(nick, 8)
	path := markPath(id, "2026-11-02")
	zero := h.get("/api/today", nick.Token).num("day.basePoints")

	got := h.put(path, nick.Token, obj{"count": 4}).expect(http.StatusOK)
	if got.num("habits.0.count") != 4 || got.num("habits.0.target") != 8 || got.num("day.basePoints") != zero+12 {
		t.Fatalf("4 of 8 = %s", got.Body)
	}
	if got = h.put(path, nick.Token, obj{"count": 8}).expect(http.StatusOK); got.num("day.basePoints") != zero+25 {
		t.Fatalf("8 of 8 = %s", got.Body)
	}
	if got = h.put(path, nick.Token, obj{"count": 12}).expect(http.StatusOK); got.num("day.basePoints") != zero+25 ||
		got.num("habits.0.count") != 12 {
		t.Fatalf("12 of 8 = %s", got.Body)
	}
	if got = h.put(path, nick.Token, obj{"count": 0}).expect(http.StatusOK); got.num("day.basePoints") != zero ||
		got.num("habits.0.count") != 0 {
		t.Fatalf("cleared = %s", got.Body)
	}
}

func TestMarkValidation(t *testing.T) {
	h := newHarness(t)
	nick := h.joinAdmin("Nick", "green")
	check, count := h.brushTeeth(nick), h.water(nick, 8)
	cases := []struct {
		name string
		path string
		body obj
	}{
		{"slot past the end", markPath(check, "2026-11-02"), obj{"slot": 2, "done": true}},
		{"negative slot", markPath(check, "2026-11-02"), obj{"slot": -1, "done": true}},
		{"missing done", markPath(check, "2026-11-02"), obj{"slot": 0}},
		{"missing slot", markPath(check, "2026-11-02"), obj{"done": true}},
		{"count on a check habit", markPath(check, "2026-11-02"), obj{"slot": 0, "done": true, "count": 1}},
		{"slot on a count habit", markPath(count, "2026-11-02"), obj{"count": 1, "slot": 0}},
		{"missing count", markPath(count, "2026-11-02"), obj{}},
		{"negative count", markPath(count, "2026-11-02"), obj{"count": -1}},
		{"count over 1000", markPath(count, "2026-11-02"), obj{"count": 1001}},
		{"bad date", markPath(check, "tomorrow"), obj{"slot": 0, "done": true}},
	}
	for _, tc := range cases {
		h.put(tc.path, nick.Token, tc.body).expect(http.StatusUnprocessableEntity).code("invalid_request")
	}
}

func TestMarkFollowsTheLogDayWindow(t *testing.T) {
	h := newHarness(t)
	h.clock.Set(ny(2026, time.November, 2, 9, 0))
	nick := h.joinAdmin("Nick", "green")
	id := h.brushTeeth(nick)

	// Yesterday is open until 10:00, but never before the day the person joined.
	h.put(markPath(id, "2026-11-01"), nick.Token, obj{"slot": 0, "done": true}).expect(http.StatusUnprocessableEntity).
		code("date_closed")

	h.clock.Set(ny(2026, time.November, 3, 9, 59))
	got := h.put(markPath(id, "2026-11-02"), nick.Token, obj{"slot": 0, "done": true}).expect(http.StatusOK)
	if got.num("day.basePoints") != 12 {
		t.Fatalf("yesterday inside the grace = %s", got.Body)
	}
	h.put(markPath(id, "2026-11-03"), nick.Token, obj{"slot": 0, "done": true}).expect(http.StatusOK)
	h.put(markPath(id, "2026-11-04"), nick.Token, obj{"slot": 0, "done": true}).expect(http.StatusUnprocessableEntity).
		code("date_closed")

	h.clock.Set(ny(2026, time.November, 3, 10, 0))
	h.put(markPath(id, "2026-11-02"), nick.Token, obj{"slot": 1, "done": true}).expect(http.StatusUnprocessableEntity).
		code("date_closed")
	h.put(markPath(id, "2026-11-02"), nick.Token, obj{"slot": 0, "done": false}).expect(http.StatusUnprocessableEntity).
		code("date_closed")
}

func TestMarkRefusesPausedHabitsAndDaysNotScheduled(t *testing.T) {
	h := newHarness(t)
	nick := h.joinAdmin("Nick", "green")
	// 2026-11-02 is a Monday.
	weekend := h.createHabit(nick, obj{"name": "Long walk", "icon": "directions_walk", "kind": "check",
		"weekdays": []int{6, 7}, "slots": []obj{{"label": "Any"}}}).expect(http.StatusCreated).num("habit.id")
	h.put(markPath(weekend, "2026-11-02"), nick.Token, obj{"slot": 0, "done": true}).
		expect(http.StatusUnprocessableEntity).code("invalid_request")

	id := h.brushTeeth(nick)
	h.patch(fmt.Sprintf("/api/habits/%d", id), nick.Token, obj{"paused": true}).expect(http.StatusOK)
	h.put(markPath(id, "2026-11-02"), nick.Token, obj{"slot": 0, "done": true}).
		expect(http.StatusUnprocessableEntity).code("invalid_request")
}

func TestTodayListsOnlyDueUnpausedHabitsInOrder(t *testing.T) {
	h := newHarness(t)
	nick := h.joinAdmin("Nick", "green")
	brush := h.brushTeeth(nick)
	water := h.water(nick, 8)
	h.createHabit(nick, obj{"name": "Sundays", "icon": "star", "kind": "check", "weekdays": []int{7},
		"slots": []obj{{"label": "Any"}}}).expect(http.StatusCreated)
	paused := h.createHabit(nick, obj{"name": "Paused", "icon": "star", "kind": "count", "target": 2}).
		expect(http.StatusCreated).num("habit.id")
	h.patch(fmt.Sprintf("/api/habits/%d", paused), nick.Token, obj{"paused": true}).expect(http.StatusOK)

	got := h.get("/api/today", nick.Token).expect(http.StatusOK)
	if got.length("habits") != 2 || got.num("habits.0.id") != brush || got.num("habits.1.id") != water {
		t.Fatalf("habits = %s", got.Body)
	}
	if got.str("habits.0.slots.1.label") != "Evening" || got.str("habits.0.slots.1.time") != "22:00" ||
		got.num("habits.0.slots.1.index") != 1 || !got.isNull("habits.0.target") || got.num("habits.0.count") != 0 ||
		got.str("habits.1.kind") != "count" || got.length("habits.1.slots") != 0 {
		t.Fatalf("habit shapes = %s", got.Body)
	}

	h.clock.Set(ny(2026, time.November, 8, 12, 0))
	if sunday := h.get("/api/today", nick.Token).expect(http.StatusOK); sunday.length("habits") != 3 {
		t.Fatalf("on Sunday = %s", sunday.Body)
	}
}

func TestEditingOrDeletingAHabitRescoresTodayButNeverAFinalizedDay(t *testing.T) {
	h := newHarness(t)
	nick := h.joinAdmin("Nick", "green")
	id := h.brushTeeth(nick)
	h.put(markPath(id, "2026-11-02"), nick.Token, obj{"slot": 0, "done": true}).expect(http.StatusOK)
	h.put(markPath(id, "2026-11-02"), nick.Token, obj{"slot": 1, "done": true}).expect(http.StatusOK)

	// Pausing drops the open day's habit points straight away.
	h.patch(fmt.Sprintf("/api/habits/%d", id), nick.Token, obj{"paused": true}).expect(http.StatusOK)
	if got := h.get("/api/today", nick.Token).expect(http.StatusOK); got.num("day.basePoints") != 0 {
		t.Fatalf("paused habit still pays: %s", got.Body)
	}
	h.patch(fmt.Sprintf("/api/habits/%d", id), nick.Token, obj{"paused": false}).expect(http.StatusOK)

	// Once the day is finalized its points are history.
	h.clock.Set(ny(2026, time.November, 3, 10, 30))
	if got := h.get("/api/today?date=2026-11-02", nick.Token).expect(http.StatusOK); got.num("day.basePoints") != 25 {
		t.Fatalf("finalizing read = %s", got.Body)
	}
	h.delete(fmt.Sprintf("/api/habits/%d", id), nick.Token).expect(http.StatusNoContent)
	if got := h.get("/api/today?date=2026-11-02", nick.Token).expect(http.StatusOK); got.num("day.basePoints") != 25 {
		t.Fatalf("a finalized day changed after the habit was deleted: %s", got.Body)
	}
	if got := h.get("/api/today", nick.Token).expect(http.StatusOK); got.length("habits") != 0 {
		t.Fatalf("deleted habit still due: %s", got.Body)
	}
}
