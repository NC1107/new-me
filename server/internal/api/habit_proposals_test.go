package api

import (
	"fmt"
	"net/http"
	"testing"
	"time"

	"github.com/nc1107/new-me/server/internal/together"
)

func habitPath(id int, tail string) string { return fmt.Sprintf("/api/habits/%d%s", id, tail) }

func (h *harness) brushFor(p person, extra obj) int {
	h.t.Helper()
	body := obj{"name": "Brush teeth", "icon": "brush", "kind": "check", "slots": twoSlots()}
	for k, v := range extra {
		body[k] = v
	}
	return h.createHabit(p, body).expect(http.StatusCreated).num("habit.id")
}

func TestWithoutAPartnerMinutesApplyAtOnce(t *testing.T) {
	h := newHarness(t)
	nick := h.joinAdmin("Nick", "green")
	got := h.createHabit(nick, obj{"name": "Brush teeth", "icon": "brush", "kind": "check", "slots": twoSlots(),
		"minutes": 2}).expect(http.StatusCreated)
	if got.num("habit.points") != 6 || got.num("habit.minutes") != 2 || !got.isNull("habit.proposedPoints") {
		t.Fatalf("habit = %s", got.Body)
	}
	id := got.num("habit.id")
	capped := h.patch(habitPath(id, ""), nick.Token, obj{"minutes": 30}).expect(http.StatusOK)
	if capped.num("habit.points") != 90 {
		t.Fatalf("30 minutes = %s", capped.Body)
	}
	tracked := h.patch(habitPath(id, ""), nick.Token, obj{"minutes": nil}).expect(http.StatusOK)
	if tracked.num("habit.points") != 0 || !tracked.isNull("habit.minutes") {
		t.Fatalf("only tracked = %s", tracked.Body)
	}
	h.patch(habitPath(id, ""), nick.Token, obj{"minutes": 31}).expect(http.StatusUnprocessableEntity)
	h.patch(habitPath(id, ""), nick.Token, obj{"minutes": 0}).expect(http.StatusUnprocessableEntity)
}

func TestWithAPartnerMinutesAreProposedAndPointsStay(t *testing.T) {
	n := &capture{}
	h := newHarness(t, withPush(n))
	nick, nadia := h.pair()

	created := h.createHabit(nick, obj{"name": "Brush teeth", "icon": "brush", "kind": "check",
		"slots": twoSlots(), "minutes": 2}).expect(http.StatusCreated)
	id := created.num("habit.id")
	if created.num("habit.points") != 0 || !created.isNull("habit.minutes") ||
		created.num("habit.proposedPoints") != 6 || created.num("habit.proposedMinutes") != 2 {
		t.Fatalf("a new habit starts at zero with a proposal: %s", created.Body)
	}
	if got := n.of(together.EventHabitProposal, nadia.ID); len(got) != 1 {
		t.Fatalf("pushes = %+v", n.msgs)
	}

	// The proposer sees nothing to answer; the partner sees it.
	if mine := h.get("/api/habits/proposals", nick.Token).expect(http.StatusOK); mine.length("proposals") != 0 {
		t.Fatalf("own proposals = %s", mine.Body)
	}
	list := h.get("/api/habits/proposals", nadia.Token).expect(http.StatusOK)
	if list.length("proposals") != 1 || list.str("from") != "Nick" || list.num("proposals.0.habitId") != id ||
		list.str("proposals.0.name") != "Brush teeth" || list.num("proposals.0.points") != 6 ||
		list.num("proposals.0.minutes") != 2 || list.num("proposals.0.currentPoints") != 0 {
		t.Fatalf("proposals = %s", list.Body)
	}
	// The habit comes whole, so Nadia can see how often and when before answering.
	if list.str("proposals.0.habit.kind") != "check" || list.length("proposals.0.habit.weekdays") != 7 ||
		list.str("proposals.0.habit.slots.0.time") != "07:30" || list.str("proposals.0.habit.slots.1.label") != "Evening" {
		t.Fatalf("proposal habit = %s", list.Body)
	}
	if got := n.of(together.EventHabitProposal, nadia.ID); got[0].Body != "Nick wants Brush teeth worth 6 gems (2 min), every day" {
		t.Fatalf("push body = %q", got[0].Body)
	}

	// Asking again for the same thing does not push again.
	h.patch(habitPath(id, ""), nick.Token, obj{"minutes": 2, "name": "Brush"}).expect(http.StatusOK)
	if got := n.of(together.EventHabitProposal, nadia.ID); len(got) != 1 {
		t.Fatalf("a repeat proposal pushed again: %+v", n.msgs)
	}

	// Pending gems pay nothing yet.
	before := h.get("/api/today", nick.Token).expect(http.StatusOK)
	if before.num("habits.0.points") != 0 {
		t.Fatalf("habit pays before approval: %s", before.Body)
	}

	approved := h.post(habitPath(id, "/approve"), nadia.Token, nil).expect(http.StatusOK)
	if approved.num("habit.points") != 6 || approved.num("habit.minutes") != 2 || !approved.isNull("habit.proposedPoints") {
		t.Fatalf("approved = %s", approved.Body)
	}
	after := h.get("/api/today", nick.Token).expect(http.StatusOK)
	if after.num("habits.0.points") != 6 || after.num("day.maxBase") != before.num("day.maxBase")+6 {
		t.Fatalf("approved gems are scored on the open day: %s", after.Body)
	}
	if list := h.get("/api/habits/proposals", nadia.Token).expect(http.StatusOK); list.length("proposals") != 0 {
		t.Fatalf("proposal still listed: %s", list.Body)
	}
	h.post(habitPath(id, "/approve"), nadia.Token, nil).expect(http.StatusNotFound)
}

func TestDecliningKeepsTheCurrentGems(t *testing.T) {
	n := &capture{}
	h := newHarness(t, withPush(n))
	nick, nadia := h.pair()
	id := h.brushFor(nick, obj{"minutes": 2})
	h.post(habitPath(id, "/approve"), nadia.Token, nil).expect(http.StatusOK)

	h.patch(habitPath(id, ""), nick.Token, obj{"minutes": 10}).expect(http.StatusOK)
	if got := n.of(together.EventHabitProposal, nadia.ID); len(got) != 2 {
		t.Fatalf("a changed proposal pushes: %+v", n.msgs)
	}
	declined := h.post(habitPath(id, "/decline"), nadia.Token, nil).expect(http.StatusOK)
	if declined.num("habit.points") != 6 || declined.num("habit.minutes") != 2 || !declined.isNull("habit.proposedPoints") {
		t.Fatalf("declined = %s", declined.Body)
	}
	if day := h.get("/api/today", nick.Token).expect(http.StatusOK); day.num("habits.0.points") != 6 {
		t.Fatalf("today = %s", day.Body)
	}
}

func TestOnlyThePartnerCanAnswerAndOnlyWhatIsPending(t *testing.T) {
	h := newHarness(t)
	nick, nadia := h.pair()
	id := h.brushFor(nick, obj{"minutes": 5})
	h.post(habitPath(id, "/approve"), nick.Token, nil).expect(http.StatusNotFound)
	h.post(habitPath(id, "/decline"), nick.Token, nil).expect(http.StatusNotFound)
	h.post(habitPath(9999, "/approve"), nadia.Token, nil).expect(http.StatusNotFound)
	h.post(habitPath(id, "/decline"), nadia.Token, nil).expect(http.StatusOK)
	h.post(habitPath(id, "/decline"), nadia.Token, nil).expect(http.StatusNotFound)

	solo := newHarness(t)
	only := solo.joinAdmin("Nick", "green")
	solo.get("/api/habits/proposals", only.Token).expect(http.StatusOK)
	solo.post(habitPath(1, "/approve"), only.Token, nil).expect(http.StatusNotFound)
}

func TestRevertingMinutesWithdrawsTheProposal(t *testing.T) {
	h := newHarness(t)
	nick, nadia := h.pair()
	id := h.brushFor(nick, obj{"minutes": 2})
	h.post(habitPath(id, "/approve"), nadia.Token, nil).expect(http.StatusOK)
	h.patch(habitPath(id, ""), nick.Token, obj{"minutes": 20}).expect(http.StatusOK)
	back := h.patch(habitPath(id, ""), nick.Token, obj{"minutes": 2}).expect(http.StatusOK)
	if !back.isNull("habit.proposedPoints") || back.num("habit.points") != 6 {
		t.Fatalf("reverted = %s", back.Body)
	}
}

func TestOlderBuildsPointsFieldNeedsApprovalToo(t *testing.T) {
	h := newHarness(t)
	nick, nadia := h.pair()
	created := h.createHabit(nick, obj{"name": "Brush teeth", "icon": "brush", "kind": "check",
		"slots": twoSlots(), "points": 50}).expect(http.StatusCreated)
	if created.num("habit.points") != 0 || created.num("habit.proposedPoints") != 50 ||
		!created.isNull("habit.proposedMinutes") {
		t.Fatalf("created = %s", created.Body)
	}
	id := created.num("habit.id")
	h.patch(habitPath(id, ""), nick.Token, obj{"points": 30}).expect(http.StatusUnprocessableEntity)
	approved := h.post(habitPath(id, "/approve"), nadia.Token, nil).expect(http.StatusOK)
	if approved.num("habit.points") != 50 || !approved.isNull("habit.minutes") {
		t.Fatalf("approved = %s", approved.Body)
	}
	// Resending the same points, as an older build does on every edit, proposes nothing.
	same := h.patch(habitPath(id, ""), nick.Token, obj{"points": 50, "name": "Floss"}).expect(http.StatusOK)
	if !same.isNull("habit.proposedPoints") || same.str("habit.name") != "Floss" {
		t.Fatalf("same = %s", same.Body)
	}
}

func TestApprovedGemsNeverChangeAFinalizedDay(t *testing.T) {
	h := newHarness(t)
	nick, nadia := h.pair()
	id := h.brushFor(nick, obj{"minutes": 10})
	h.post(habitPath(id, "/approve"), nadia.Token, nil).expect(http.StatusOK)
	h.put(markPath(id, "2026-11-02"), nick.Token, obj{"slot": 0, "done": true}).expect(http.StatusOK)
	h.put(markPath(id, "2026-11-02"), nick.Token, obj{"slot": 1, "done": true}).expect(http.StatusOK)

	h.clock.Set(ny(2026, time.November, 3, 10, 30))
	frozen := h.get("/api/today?date=2026-11-02", nick.Token).expect(http.StatusOK).num("day.basePoints")
	if frozen != 30 {
		t.Fatalf("finalized base points = %d", frozen)
	}
	h.patch(habitPath(id, ""), nick.Token, obj{"minutes": 30}).expect(http.StatusOK)
	h.post(habitPath(id, "/approve"), nadia.Token, nil).expect(http.StatusOK)
	if got := h.get("/api/today?date=2026-11-02", nick.Token).expect(http.StatusOK); got.num("day.basePoints") != frozen {
		t.Fatalf("a finalized day changed: %s", got.Body)
	}
	if got := h.get("/api/today", nick.Token).expect(http.StatusOK); got.num("habits.0.points") != 90 {
		t.Fatalf("today = %s", got.Body)
	}
}

func TestDaysSummaryWordsDaysAsTheAppDoes(t *testing.T) {
	cases := map[string][]int{
		"Every day":     {7, 1, 2, 3, 4, 5, 6},
		"Weekdays":      {5, 4, 3, 2, 1},
		"Weekends":      {7, 6},
		"Mon, Wed, Fri": {5, 1, 3},
		"Thu":           {4},
	}
	for want, days := range cases {
		if got := daysSummary(days); got != want {
			t.Errorf("daysSummary(%v) = %q, want %q", days, got, want)
		}
	}
}
