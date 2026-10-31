package api

import (
	"fmt"
	"net/http"
	"testing"
	"time"

	"github.com/nc1107/new-me/server/internal/together"
)

func sharedPath(id int, tail string) string { return fmt.Sprintf("/api/shared-habits/%d%s", id, tail) }

func (h *harness) createShared(p person, name string, schedule obj) *response {
	h.t.Helper()
	return h.post("/api/shared-habits", p.Token, obj{"name": name, "icon": "local_laundry_service", "schedule": schedule})
}

func (h *harness) sharedHabit(p person, id int) *response {
	h.t.Helper()
	list := h.get("/api/shared-habits", p.Token).expect(http.StatusOK)
	for i := 0; i < list.length("habits"); i++ {
		if list.num(fmt.Sprintf("habits.%d.id", i)) == id {
			return &response{t: h.t, Status: list.Status, Body: list.Body, parsed: list.at(fmt.Sprintf("habits.%d", i))}
		}
	}
	h.t.Fatalf("shared habit %d not listed: %s", id, list.Body)
	return nil
}

func TestSharedHabitIsSeenAndDoneByBothPartners(t *testing.T) {
	n := &capture{}
	h := newHarness(t, withPush(n))
	nick, nadia := h.pair()

	before := h.get("/api/today", nick.Token).expect(http.StatusOK)
	created := h.createShared(nick, "Do the laundry", obj{"kind": "weekly"}).expect(http.StatusCreated)
	id := created.num("habit.id")
	if created.str("habit.state") != "today" || !created.isNull("habit.last") || created.num("habit.gems") != 25 {
		t.Fatalf("a new weekly chore is due the day it is created: %s", created.Body)
	}
	if h.sharedHabit(nadia, id).str("name") != "Do the laundry" {
		t.Fatal("the partner sees it too")
	}

	done := h.post(sharedPath(id, "/done"), nick.Token, nil).expect(http.StatusOK)
	if done.num("gemsEarned") != 25 || done.str("habit.state") != "upcoming" || done.num("habit.daysFromToday") != 7 ||
		done.str("habit.dueOn") != "2026-11-09" || !done.flag("habit.doneByMe") || done.str("habit.last.name") != "Nick" {
		t.Fatalf("done = %s", done.Body)
	}
	seen := h.sharedHabit(nadia, id)
	if seen.str("last.name") != "Nick" || !seen.flag("doneToday") || seen.flag("doneByMe") || seen.str("state") != "upcoming" {
		t.Fatalf("partner view = %s", seen.Body)
	}
	if got := n.of(together.EventSharedHabit, nadia.ID); len(got) != 1 || got[0].Title != "Nick did Do the laundry" {
		t.Fatalf("pushes = %+v", n.msgs)
	}

	// The gems are Nick's bonus; neither the percent nor Nadia's day moves.
	after := h.get("/api/today", nick.Token).expect(http.StatusOK)
	if after.num("day.bonusPoints") != before.num("day.bonusPoints")+25 || after.num("day.percent") != before.num("day.percent") ||
		after.num("day.maxBase") != before.num("day.maxBase") || after.flag("day.counted") != before.flag("day.counted") {
		t.Fatalf("before %s\nafter %s", before.Body, after.Body)
	}
	if nadiaDay := h.get("/api/today", nadia.Token).expect(http.StatusOK); nadiaDay.num("day.bonusPoints") != 0 {
		t.Fatalf("Nadia earned nothing: %s", nadiaDay.Body)
	}

	// A second tap the same day, by either person, pays and notifies nothing.
	again := h.post(sharedPath(id, "/done"), nadia.Token, nil).expect(http.StatusOK)
	if again.num("gemsEarned") != 0 || again.str("habit.last.name") != "Nick" || n.count() != 1 {
		t.Fatalf("repeat = %s, pushes %+v", again.Body, n.msgs)
	}

	// A week on it is due again, and now Nadia does it and Nick is told.
	h.clock.Set(ny(2026, time.November, 9, 12, 0))
	if got := h.sharedHabit(nadia, id); got.str("state") != "today" || got.flag("doneToday") {
		t.Fatalf("a week later = %s", got.Body)
	}
	h.post(sharedPath(id, "/done"), nadia.Token, nil).expect(http.StatusOK)
	if got := n.of(together.EventSharedHabit, nick.ID); len(got) != 1 {
		t.Fatalf("pushes = %+v", n.msgs)
	}
	if h.get("/api/today", nadia.Token).expect(http.StatusOK).num("day.bonusPoints") != 25 {
		t.Fatal("Nadia is credited for her own mark")
	}
}

func TestSharedHabitUndoTakesTheGemsBack(t *testing.T) {
	h := newHarness(t)
	nick, nadia := h.pair()
	id := h.createShared(nick, "Dishes", obj{"kind": "daily"}).expect(http.StatusCreated).num("habit.id")
	h.post(sharedPath(id, "/done"), nick.Token, nil).expect(http.StatusOK)
	if h.get("/api/today", nick.Token).expect(http.StatusOK).num("day.bonusPoints") != 25 {
		t.Fatal("gems earned")
	}

	h.delete(sharedPath(id, "/done"), nadia.Token).expect(http.StatusUnprocessableEntity)
	undone := h.delete(sharedPath(id, "/done"), nick.Token).expect(http.StatusOK)
	if undone.str("habit.state") != "today" || !undone.isNull("habit.last") {
		t.Fatalf("undone = %s", undone.Body)
	}
	if h.get("/api/today", nick.Token).expect(http.StatusOK).num("day.bonusPoints") != 0 {
		t.Fatal("the gems left with the mark")
	}
	h.delete(sharedPath(id, "/done"), nick.Token).expect(http.StatusUnprocessableEntity)

	// Nick cannot undo once Nadia has marked it after him.
	h.post(sharedPath(id, "/done"), nick.Token, nil).expect(http.StatusOK)
	h.clock.Set(ny(2026, time.November, 3, 12, 0))
	h.post(sharedPath(id, "/done"), nadia.Token, nil).expect(http.StatusOK)
	h.delete(sharedPath(id, "/done"), nick.Token).expect(http.StatusUnprocessableEntity)

	// Her own mark is undone while its day is open, and not after it is closed.
	h.clock.Set(ny(2026, time.November, 5, 12, 0))
	h.delete(sharedPath(id, "/done"), nadia.Token).code("date_closed")
}

func TestSharedHabitDueAndOverdueFollowTheViewersZone(t *testing.T) {
	h := newHarness(t)
	nick := h.joinAdmin("Nick", "green")
	nadia := h.finishJoin(h.post("/api/join", "", obj{"code": h.invite(nick), "name": "Nadia", "color": "violet",
		"timezone": "America/Los_Angeles"}))
	id := h.createShared(nick, "Vacuum", obj{"kind": "daily"}).expect(http.StatusCreated).num("habit.id")

	// 22:00 on Monday in New York is 19:00 in Los Angeles.
	h.clock.Set(ny(2026, time.November, 2, 22, 0))
	h.post(sharedPath(id, "/done"), nick.Token, nil).expect(http.StatusOK)

	// At 02:00 Tuesday in New York it is still Monday evening for Nadia.
	h.clock.Set(ny(2026, time.November, 3, 2, 0))
	if got := h.sharedHabit(nick, id); got.str("state") != "today" || got.flag("doneToday") {
		t.Fatalf("Nick, on Tuesday: %s", got.Body)
	}
	if got := h.sharedHabit(nadia, id); got.str("state") != "upcoming" || !got.flag("doneToday") || got.str("dueOn") != "2026-11-03" {
		t.Fatalf("Nadia, still on Monday: %s", got.Body)
	}

	// A weekly chore done on Monday is overdue by two days on the second Wednesday.
	weekly := h.createShared(nick, "Sheets", obj{"kind": "weekly"}).expect(http.StatusCreated).num("habit.id")
	h.clock.Set(ny(2026, time.November, 4, 12, 0))
	h.post(sharedPath(weekly, "/done"), nick.Token, nil).expect(http.StatusOK)
	h.clock.Set(ny(2026, time.November, 13, 12, 0))
	got := h.sharedHabit(nick, weekly)
	if got.str("state") != "overdue" || got.num("daysFromToday") != -2 || got.str("dueOn") != "2026-11-11" {
		t.Fatalf("overdue = %s", got.Body)
	}
}

func TestSharedHabitsAreListedDueFirst(t *testing.T) {
	h := newHarness(t)
	nick := h.joinAdmin("Nick", "green")
	later := h.createShared(nick, "Plants", obj{"kind": "every_n", "everyDays": 4}).expect(http.StatusCreated).num("habit.id")
	h.post(sharedPath(later, "/done"), nick.Token, nil).expect(http.StatusOK)
	due := h.createShared(nick, "Trash", obj{"kind": "daily"}).expect(http.StatusCreated).num("habit.id")
	days := h.createShared(nick, "Bathroom", obj{"kind": "weekdays", "weekdays": []int{3, 5}}).expect(http.StatusCreated).num("habit.id")

	list := h.get("/api/shared-habits", nick.Token).expect(http.StatusOK)
	if list.num("habits.0.id") != due || list.num("habits.1.id") != days || list.num("habits.2.id") != later {
		t.Fatalf("order = %s", list.Body)
	}
	// Monday 2026-11-02: the next Wednesday is two days off.
	if list.str("habits.1.dueOn") != "2026-11-04" || list.num("habits.1.daysFromToday") != 2 {
		t.Fatalf("weekdays = %s", list.Body)
	}
}

func TestSharedHabitEditDeleteAndValidation(t *testing.T) {
	h := newHarness(t)
	nick, nadia := h.pair()
	id := h.createShared(nick, "Vacuum", obj{"kind": "daily"}).expect(http.StatusCreated).num("habit.id")

	h.createShared(nick, "", obj{"kind": "daily"}).expect(http.StatusUnprocessableEntity)
	h.createShared(nick, "X", obj{"kind": "monthly"}).expect(http.StatusUnprocessableEntity)
	h.createShared(nick, "X", obj{"kind": "weekdays", "weekdays": []int{}}).expect(http.StatusUnprocessableEntity)
	h.createShared(nick, "X", obj{"kind": "every_n", "everyDays": 1}).expect(http.StatusUnprocessableEntity)
	h.post("/api/shared-habits", nick.Token, obj{"name": "X", "icon": "nope", "schedule": obj{"kind": "daily"}}).
		expect(http.StatusUnprocessableEntity)

	edited := h.patch(sharedPath(id, ""), nadia.Token, obj{"name": "Vacuum the flat", "schedule": obj{"kind": "every_n", "everyDays": 3}}).
		expect(http.StatusOK)
	if edited.str("habit.name") != "Vacuum the flat" || edited.str("habit.schedule.kind") != "every_n" || edited.num("habit.schedule.everyDays") != 3 {
		t.Fatalf("edited = %s", edited.Body)
	}
	h.patch(sharedPath(id, ""), nadia.Token, obj{"icon": "nope"}).expect(http.StatusUnprocessableEntity)

	h.delete(sharedPath(id, ""), nadia.Token).expect(http.StatusNoContent)
	if h.get("/api/shared-habits", nick.Token).expect(http.StatusOK).length("habits") != 0 {
		t.Fatal("deleted for both")
	}
	h.post(sharedPath(id, "/done"), nick.Token, nil).expect(http.StatusNotFound)
	h.delete(sharedPath(id, ""), nick.Token).expect(http.StatusNotFound)
}

func TestSharedHabitPushWaitsForQuietHours(t *testing.T) {
	n := &capture{}
	h := newHarness(t, withPush(n))
	nick, nadia := h.pair()
	id := h.createShared(nick, "Dishes", obj{"kind": "daily"}).expect(http.StatusCreated).num("habit.id")

	h.clock.Set(ny(2026, time.November, 3, 3, 0))
	h.post(sharedPath(id, "/done"), nick.Token, nil).expect(http.StatusOK)
	if n.count() != 0 || h.holdCount() != 1 {
		t.Fatalf("held = %d, sent = %+v", h.holdCount(), n.msgs)
	}
	h.clock.Set(ny(2026, time.November, 3, 7, 10))
	h.deliverHeld()
	if len(n.of(together.EventSharedHabit, nadia.ID)) != 1 {
		t.Fatalf("after wake: %+v", n.msgs)
	}
}
