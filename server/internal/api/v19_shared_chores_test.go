package api

import (
	"net/http"
	"testing"
	"time"

	"github.com/nc1107/new-me/server/internal/together"
)

func (h *harness) bonus(p person) int {
	h.t.Helper()
	return h.get("/api/today", p.Token).expect(http.StatusOK).num("day.bonusPoints")
}

func TestSharedChoreWorthIsProposedAcceptedAndCountered(t *testing.T) {
	n := &capture{}
	h := newHarness(t, withPush(n))
	nick, nadia := h.pair()

	created := h.post("/api/shared-habits", nick.Token, obj{"name": "Laundry", "icon": "local_laundry_service",
		"schedule": obj{"kind": "weekly"}, "worth": 40}).expect(http.StatusCreated)
	id := created.num("habit.id")
	if created.num("habit.gems") != 25 || created.num("habit.proposedWorth") != 40 || created.str("habit.proposedByName") != "Nick" {
		t.Fatalf("a proposed worth is pending and the default pays meanwhile: %s", created.Body)
	}
	if got := n.of(together.EventSharedHabit, nadia.ID); len(got) != 1 || got[0].Title != "Nick suggests 40 gems for Laundry" {
		t.Fatalf("pushes = %+v", n.msgs)
	}

	// Until it is agreed, a completion pays the default.
	h.post(sharedPath(id, "/done"), nick.Token, nil).expect(http.StatusOK)
	if h.bonus(nick) != 25 {
		t.Fatalf("pending worth pays 25, got %d", h.bonus(nick))
	}
	h.delete(sharedPath(id, "/done"), nick.Token).expect(http.StatusOK)

	// The proposer cannot accept their own number.
	h.post(sharedPath(id, "/worth/accept"), nick.Token, nil).expect(http.StatusUnprocessableEntity)

	// Nadia counters, which hands the question back to Nick.
	countered := h.patch(sharedPath(id, ""), nadia.Token, obj{"worth": 30}).expect(http.StatusOK)
	if countered.num("habit.gems") != 25 || countered.num("habit.proposedWorth") != 30 || countered.str("habit.proposedByName") != "Nadia" {
		t.Fatalf("counter = %s", countered.Body)
	}
	if got := n.of(together.EventSharedHabit, nick.ID); len(got) != 1 || got[0].Title != "Nadia suggests 30 gems for Laundry" {
		t.Fatalf("pushes = %+v", n.msgs)
	}
	h.post(sharedPath(id, "/worth/accept"), nadia.Token, nil).expect(http.StatusUnprocessableEntity)

	agreed := h.post(sharedPath(id, "/worth/accept"), nick.Token, nil).expect(http.StatusOK)
	if agreed.num("habit.gems") != 30 || !agreed.isNull("habit.proposedWorth") {
		t.Fatalf("accepted = %s", agreed.Body)
	}
	if got := n.of(together.EventSharedHabit, nadia.ID); len(got) != 3 || got[2].Title != "Nick agreed: Laundry is worth 30 gems" {
		t.Fatalf("pushes = %+v", n.msgs)
	}
	if h.sharedHabit(nadia, id).num("gems") != 30 {
		t.Fatal("both see the agreed worth")
	}
	h.post(sharedPath(id, "/worth/accept"), nick.Token, nil).expect(http.StatusUnprocessableEntity)

	done := h.post(sharedPath(id, "/done"), nadia.Token, nil).expect(http.StatusOK)
	if done.num("gemsEarned") != 30 || h.bonus(nadia) != 30 {
		t.Fatalf("done at the agreed worth = %s", done.Body)
	}
}

func TestSharedChoreWorthAgreesWhenThePartnerRepeatsTheNumber(t *testing.T) {
	h := newHarness(t)
	nick, nadia := h.pair()
	id := h.createShared(nick, "Dishes", obj{"kind": "daily"}).expect(http.StatusCreated).num("habit.id")

	h.patch(sharedPath(id, ""), nick.Token, obj{"worth": 50}).expect(http.StatusOK)
	// The proposer repeating it changes nothing.
	if got := h.patch(sharedPath(id, ""), nick.Token, obj{"worth": 50}).expect(http.StatusOK); got.num("habit.gems") != 25 {
		t.Fatalf("own number does not agree it: %s", got.Body)
	}
	agreed := h.patch(sharedPath(id, ""), nadia.Token, obj{"worth": 50}).expect(http.StatusOK)
	if agreed.num("habit.gems") != 50 || !agreed.isNull("habit.proposedWorth") {
		t.Fatalf("repeating the partner's number agrees it: %s", agreed.Body)
	}

	// Proposing the agreed number withdraws a pending change.
	h.patch(sharedPath(id, ""), nadia.Token, obj{"worth": 10}).expect(http.StatusOK)
	withdrawn := h.patch(sharedPath(id, ""), nick.Token, obj{"worth": 50}).expect(http.StatusOK)
	if withdrawn.num("habit.gems") != 50 || !withdrawn.isNull("habit.proposedWorth") {
		t.Fatalf("declined = %s", withdrawn.Body)
	}

	h.patch(sharedPath(id, ""), nick.Token, obj{"worth": 0}).expect(http.StatusUnprocessableEntity)
	h.patch(sharedPath(id, ""), nick.Token, obj{"worth": 101}).expect(http.StatusUnprocessableEntity)
	h.post("/api/shared-habits", nick.Token, obj{"name": "X", "icon": "home", "schedule": obj{"kind": "daily"}, "worth": 0}).
		expect(http.StatusUnprocessableEntity)
}

func TestSharedChoreWorthIsSetOutrightWithNoPartner(t *testing.T) {
	h := newHarness(t)
	nick := h.joinAdmin("Nick", "green")
	created := h.post("/api/shared-habits", nick.Token, obj{"name": "Laundry", "icon": "home",
		"schedule": obj{"kind": "daily"}, "worth": 60}).expect(http.StatusCreated)
	if created.num("habit.gems") != 60 || !created.isNull("habit.proposedWorth") {
		t.Fatalf("alone, the worth is simply set: %s", created.Body)
	}
	h.post(sharedPath(created.num("habit.id"), "/done"), nick.Token, obj{"by": "together"}).expect(http.StatusUnprocessableEntity)
}

func TestSharedChoreDoneAloneByThePartnerAndTogether(t *testing.T) {
	n := &capture{}
	h := newHarness(t, withPush(n))
	nick, nadia := h.pair()
	laundry := h.createShared(nick, "Laundry", obj{"kind": "weekly"}).expect(http.StatusCreated).num("habit.id")
	h.patch(sharedPath(laundry, ""), nick.Token, obj{"worth": 40}).expect(http.StatusOK)
	h.post(sharedPath(laundry, "/worth/accept"), nadia.Token, nil).expect(http.StatusOK)
	dishes := h.createShared(nick, "Dishes", obj{"kind": "daily"}).expect(http.StatusCreated).num("habit.id")
	trash := h.createShared(nick, "Trash", obj{"kind": "daily"}).expect(http.StatusCreated).num("habit.id")
	nickBefore, nadiaBefore := h.bonus(nick), h.bonus(nadia)
	percentBefore := h.get("/api/today", nick.Token).expect(http.StatusOK).num("day.percent")

	// Together: the worth is split evenly and both see who did it.
	together40 := h.post(sharedPath(laundry, "/done"), nick.Token, obj{"by": "together"}).expect(http.StatusOK)
	if together40.num("gemsEarned") != 20 || together40.num("partnerGems") != 20 || !together40.flag("habit.last.together") ||
		together40.length("habit.last.doers") != 2 || !together40.flag("habit.doneByMe") {
		t.Fatalf("together = %s", together40.Body)
	}
	if h.bonus(nick)-nickBefore != 20 || h.bonus(nadia)-nadiaBefore != 20 {
		t.Fatalf("each got half: nick %d nadia %d", h.bonus(nick)-nickBefore, h.bonus(nadia)-nadiaBefore)
	}
	seen := h.sharedHabit(nadia, laundry)
	if !seen.flag("last.together") || seen.num("last.doers.0.gems") != 20 || seen.num("last.doers.1.gems") != 20 || seen.flag("doneByMe") {
		t.Fatalf("partner view = %s", seen.Body)
	}
	if got := n.of(together.EventSharedHabit, nadia.ID); len(got) < 1 || got[len(got)-1].Title != "Nick did Laundry with you" ||
		got[len(got)-1].Body != "You earned 20 gems" {
		t.Fatalf("pushes = %+v", n.msgs)
	}
	if h.get("/api/today", nick.Token).expect(http.StatusOK).num("day.percent") != percentBefore {
		t.Fatal("chores stay out of the daily percent")
	}

	// A second tap on the same day, by either person, pays nobody.
	again := h.post(sharedPath(laundry, "/done"), nadia.Token, obj{"by": "together"}).expect(http.StatusOK)
	if again.num("gemsEarned") != 0 || again.num("partnerGems") != 0 || h.bonus(nick)-nickBefore != 20 || h.bonus(nadia)-nadiaBefore != 20 {
		t.Fatalf("repeat = %s", again.Body)
	}

	// Marked for the partner alone: she gets everything and he gets nothing.
	forHer := h.post(sharedPath(dishes, "/done"), nick.Token, obj{"by": "partner"}).expect(http.StatusOK)
	if forHer.num("gemsEarned") != 0 || forHer.num("partnerGems") != 25 || forHer.num("habit.last.doers.0.userId") != int(nadia.ID) ||
		forHer.length("habit.last.doers") != 1 {
		t.Fatalf("for her = %s", forHer.Body)
	}
	if h.bonus(nick)-nickBefore != 20 || h.bonus(nadia)-nadiaBefore != 45 {
		t.Fatalf("nick %d nadia %d", h.bonus(nick)-nickBefore, h.bonus(nadia)-nadiaBefore)
	}

	// Done by me alone is the whole worth, as before, and a bad value is refused.
	alone := h.post(sharedPath(trash, "/done"), nick.Token, obj{"by": "self"}).expect(http.StatusOK)
	if alone.num("gemsEarned") != 25 || alone.num("partnerGems") != 0 {
		t.Fatalf("alone = %s", alone.Body)
	}
	h.post(sharedPath(trash, "/done"), nick.Token, obj{"by": "everyone"}).expect(http.StatusUnprocessableEntity)
}

func TestSharedChoreTogetherSplitGivesTheOddGemToWhoMarkedIt(t *testing.T) {
	h := newHarness(t)
	nick, nadia := h.pair()
	id := h.createShared(nick, "Sheets", obj{"kind": "weekly"}).expect(http.StatusCreated).num("habit.id")
	nickBefore, nadiaBefore := h.bonus(nick), h.bonus(nadia)

	done := h.post(sharedPath(id, "/done"), nadia.Token, obj{"by": "together"}).expect(http.StatusOK)
	if done.num("gemsEarned") != 13 || done.num("partnerGems") != 12 {
		t.Fatalf("25 gems split 13 and 12: %s", done.Body)
	}
	if h.bonus(nadia)-nadiaBefore != 13 || h.bonus(nick)-nickBefore != 12 {
		t.Fatalf("nadia %d nick %d", h.bonus(nadia)-nadiaBefore, h.bonus(nick)-nickBefore)
	}
}

func TestSharedChoreUndoTakesBackBothHalves(t *testing.T) {
	h := newHarness(t)
	nick, nadia := h.pair()
	id := h.createShared(nick, "Laundry", obj{"kind": "weekly"}).expect(http.StatusCreated).num("habit.id")
	nickBefore, nadiaBefore := h.bonus(nick), h.bonus(nadia)
	h.post(sharedPath(id, "/done"), nick.Token, obj{"by": "together"}).expect(http.StatusOK)

	h.delete(sharedPath(id, "/done"), nadia.Token).expect(http.StatusUnprocessableEntity)
	h.delete(sharedPath(id, "/done"), nick.Token).expect(http.StatusOK)
	if h.bonus(nick) != nickBefore || h.bonus(nadia) != nadiaBefore {
		t.Fatalf("both halves left: nick %d nadia %d", h.bonus(nick), h.bonus(nadia))
	}

	// Once undone it can be marked again and pays once more.
	again := h.post(sharedPath(id, "/done"), nick.Token, obj{"by": "partner"}).expect(http.StatusOK)
	if again.num("partnerGems") != 25 || h.bonus(nadia)-nadiaBefore != 25 {
		t.Fatalf("again = %s", again.Body)
	}
}

func TestSharedChoreOnlyOneCompletionPerDueDay(t *testing.T) {
	h := newHarness(t)
	nick, nadia := h.pair()
	id := h.createShared(nick, "Dishes", obj{"kind": "daily"}).expect(http.StatusCreated).num("habit.id")
	nadiaBefore := h.bonus(nadia)

	h.post(sharedPath(id, "/done"), nick.Token, obj{"by": "together"}).expect(http.StatusOK)
	h.post(sharedPath(id, "/done"), nick.Token, obj{"by": "partner"}).expect(http.StatusOK)
	h.post(sharedPath(id, "/done"), nadia.Token, obj{"by": "self"}).expect(http.StatusOK)
	if got := h.bonus(nadia) - nadiaBefore; got != 12 {
		t.Fatalf("Nadia was paid once for the day, got %d", got)
	}

	h.clock.Set(ny(2026, time.November, 3, 12, 0))
	next := h.post(sharedPath(id, "/done"), nadia.Token, obj{"by": "self"}).expect(http.StatusOK)
	if next.num("gemsEarned") != 25 {
		t.Fatalf("the next day pays again: %s", next.Body)
	}
}

// Nick saw "no shared habits" for a chore created on a Saturday for Sunday: it is not due until
// the next day, so Today stays quiet, while the list still carries it with its due date.
func TestSharedChoreForSundayCreatedOnSaturdayIsListedAsDueTomorrow(t *testing.T) {
	h := newHarness(t)
	nick, nadia := h.pair()
	h.clock.Set(ny(2026, time.October, 31, 11, 14))
	created := h.createShared(nick, "Laundry", obj{"kind": "weekdays", "weekdays": []int{7}}).expect(http.StatusCreated)
	if created.str("habit.state") != "upcoming" || created.str("habit.dueOn") != "2026-11-01" || created.num("habit.daysFromToday") != 1 {
		t.Fatalf("Sunday chore on Saturday = %s", created.Body)
	}
	for _, p := range []person{nick, nadia} {
		if h.get("/api/shared-habits", p.Token).expect(http.StatusOK).length("habits") != 1 {
			t.Fatalf("%s sees the chore", p.Name)
		}
	}

	saturday := h.createShared(nick, "Dishes", obj{"kind": "weekdays", "weekdays": []int{6}}).expect(http.StatusCreated)
	if saturday.str("habit.state") != "today" {
		t.Fatalf("Saturday chore on Saturday = %s", saturday.Body)
	}
	h.clock.Set(ny(2026, time.November, 1, 9, 0))
	if got := h.sharedHabit(nadia, created.num("habit.id")); got.str("state") != "today" {
		t.Fatalf("due on Sunday = %s", got.Body)
	}
}
