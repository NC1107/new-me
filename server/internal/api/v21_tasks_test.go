package api

import (
	"context"
	"fmt"
	"net/http"
	"sync"
	"testing"
	"time"

	"github.com/nc1107/new-me/server/internal/together"
)

func taskPath(id int, tail string) string { return fmt.Sprintf("/api/tasks/%d%s", id, tail) }

func (h *harness) proposeTask(p, assignee person, title string, stake int, deadline string) int {
	h.t.Helper()
	return h.post("/api/tasks", p.Token, obj{"title": title, "assigneeId": assignee.ID, "stake": stake, "deadline": deadline}).
		expect(http.StatusCreated).num("task.id")
}

// proposeRisky proposes a task the person takes on for themselves with the gems on the line.
func (h *harness) proposeRisky(p person, title string, stake int, deadline string) int {
	h.t.Helper()
	return h.post("/api/tasks", p.Token, obj{"title": title, "assigneeId": p.ID, "stake": stake, "deadline": deadline,
		"loseIfMissed": true}).expect(http.StatusCreated).num("task.id")
}

func (h *harness) settleAll() {
	h.t.Helper()
	if err := h.srv.together.Settle(context.Background()); err != nil {
		h.t.Fatalf("settle: %v", err)
	}
}

// balanceOf reads one person's row from the balances card.
func balanceOf(r *response, p person) (earned, tasks, balance int) {
	for i := 0; i < r.length("balances"); i++ {
		if r.num(fmt.Sprintf("balances.%d.userId", i)) == int(p.ID) {
			return r.num(fmt.Sprintf("balances.%d.earned", i)), r.num(fmt.Sprintf("balances.%d.tasks", i)),
				r.num(fmt.Sprintf("balances.%d.balance", i))
		}
	}
	r.t.Fatalf("no balance for %s in %s", p.Name, r.Body)
	return 0, 0, 0
}

func TestATaskNeedsTheOtherPersonsAgreementAndFinishingItWinsTheStake(t *testing.T) {
	n := &capture{}
	h := newHarness(t, withPush(n))
	nick, nadia := h.pair()
	h.gems(nadia, "2026-10-30", 100)

	for _, bad := range []obj{
		{"title": " ", "assigneeId": nadia.ID, "stake": 40, "deadline": "2026-11-04"},
		{"title": "Call the vet", "assigneeId": nadia.ID, "stake": 0, "deadline": "2026-11-04"},
		{"title": "Call the vet", "assigneeId": nadia.ID, "stake": 100001, "deadline": "2026-11-04"},
		{"title": "Call the vet", "assigneeId": nadia.ID, "stake": 40, "deadline": "2026-11-01"},
		{"title": "Call the vet", "assigneeId": nadia.ID, "stake": 40, "deadline": "2028-01-01"},
		{"title": "Call the vet", "assigneeId": nadia.ID, "stake": 40, "deadline": "tomorrow"},
		{"title": "Call the vet", "assigneeId": 9999, "stake": 40, "deadline": "2026-11-04"},
		{"title": "Call the vet", "stake": 40},
	} {
		h.post("/api/tasks", nick.Token, bad).expect(http.StatusUnprocessableEntity).code("invalid_request")
	}

	made := h.post("/api/tasks", nick.Token, obj{"title": "Call the vet", "assigneeId": nadia.ID, "stake": 40,
		"deadline": "2026-11-04"}).expect(http.StatusCreated)
	id := made.num("task.id")
	if made.str("task.status") != "proposed" || made.str("task.assigneeName") != "Nadia" || made.str("task.creatorName") != "Nick" ||
		made.num("task.daysLeft") != 2 {
		t.Fatalf("created = %s", made.Body)
	}
	if got := n.of(together.EventTaskProposal, nadia.ID); len(got) != 1 ||
		got[0].Body != `Nick asks you to do "Call the vet" for 40 gems by Wed Nov 4` || len(n.of(together.EventTaskProposal, nick.ID)) != 0 {
		t.Fatalf("pushes = %+v", n.msgs)
	}
	// Retrying the same proposal answers with the one that exists and asks nobody twice.
	if again := h.post("/api/tasks", nick.Token, obj{"title": "Call the vet", "assigneeId": nadia.ID, "stake": 40,
		"deadline": "2026-11-04"}).expect(http.StatusOK); again.num("task.id") != id || len(n.of(together.EventTaskProposal, nadia.ID)) != 1 {
		t.Fatalf("retry = %s", again.Body)
	}

	// Nothing is live yet: the assignee cannot finish it and the proposer cannot agree to it.
	h.post(taskPath(id, "/done"), nadia.Token, nil).expect(http.StatusConflict).code("task_state")
	h.post(taskPath(id, "/agree"), nick.Token, nil).expect(http.StatusForbidden)

	h.post(taskPath(id, "/agree"), nadia.Token, nil).expect(http.StatusOK)
	h.post(taskPath(id, "/agree"), nadia.Token, nil).expect(http.StatusConflict).code("task_state")
	h.post(taskPath(id, "/done"), nick.Token, nil).expect(http.StatusForbidden)

	done := h.post(taskPath(id, "/done"), nadia.Token, nil).expect(http.StatusOK)
	if done.str("task.status") != "done" {
		t.Fatalf("done = %s", done.Body)
	}
	if earned, tasks, balance := balanceOf(done, nadia); earned != 100 || tasks != 40 || balance != 140 {
		t.Fatalf("nadia earned %d tasks %d balance %d: %s", earned, tasks, balance, done.Body)
	}
	if done.num("bank") != 140 {
		t.Fatalf("bank = %d", done.num("bank"))
	}
	if got := n.of(together.EventTask, nick.ID); len(got) != 1 || got[0].Body != "Nadia finished Call the vet, +40 gems" ||
		len(n.of(together.EventTask, nadia.ID)) != 0 {
		t.Fatalf("pushes = %+v", n.msgs)
	}
	// A repeat tap changes and pushes nothing.
	h.post(taskPath(id, "/done"), nadia.Token, nil).expect(http.StatusOK)
	if len(n.of(together.EventTask, nick.ID)) != 1 {
		t.Fatalf("pushes = %+v", n.msgs)
	}

	list := h.get("/api/tasks", nick.Token).expect(http.StatusOK)
	if list.length("tasks") != 0 || list.length("history") != 1 || list.str("history.0.status") != "done" {
		t.Fatalf("list = %s", list.Body)
	}
	// The stake is a ledger of its own: it never becomes a day score.
	if earned, _, _ := balanceOf(list, nadia); earned != 100 {
		t.Fatalf("earned changed to %d", earned)
	}
	var points int
	if err := h.db.Pool.QueryRow(context.Background(),
		`SELECT COALESCE(sum(base_points + bonus_points), 0)::int FROM day_scores`).Scan(&points); err != nil || points != 100 {
		t.Fatalf("day points = %d, %v", points, err)
	}
}

func TestAMissedTaskCostsNothingByDefaultAndTheOptedInLossOnlyOnce(t *testing.T) {
	n := &capture{}
	h := newHarness(t, withPush(n))
	nick, nadia := h.pair()
	h.gems(nadia, "2026-10-30", 100)
	id := h.proposeTask(nick, nadia, "Call the vet", 40, "2026-11-03")
	h.post(taskPath(id, "/agree"), nadia.Token, nil).expect(http.StatusOK)
	risky := h.proposeRisky(nadia, "Renew the car tag", 40, "2026-11-03")
	h.post(taskPath(risky, "/agree"), nick.Token, nil).expect(http.StatusOK)

	// Late on the deadline day it is still on time.
	h.clock.Set(ny(2026, time.November, 3, 23, 30))
	h.settleAll()
	if len(n.of(together.EventTask, nadia.ID)) != 0 {
		t.Fatalf("settled early: %+v", n.msgs)
	}

	// Once the day is over the scheduler's settle misses it, with no request from anyone. The
	// morning is outside quiet hours, so the pushes are sent rather than held.
	h.clock.Set(ny(2026, time.November, 4, 9, 0))
	h.settleAll()
	h.settleAll()
	var wg sync.WaitGroup
	for range 6 {
		wg.Add(1)
		go func() { defer wg.Done(); _ = h.srv.together.Settle(context.Background()) }()
	}
	wg.Wait()

	gotNadia, gotNick := n.of(together.EventTask, nadia.ID), n.of(together.EventTask, nick.ID)
	if len(gotNadia) != 2 || len(gotNick) != 2 {
		t.Fatalf("each miss is announced once to each person: %+v", n.msgs)
	}
	bodies := map[string]bool{}
	for _, m := range append(gotNadia, gotNick...) {
		bodies[m.Body] = true
	}
	for _, want := range []string{"You missed Call the vet", "Nadia missed Call the vet",
		"You missed Renew the car tag, -40 gems", "Nadia missed Renew the car tag, -40 gems"} {
		if !bodies[want] {
			t.Fatalf("no push %q in %+v", want, n.msgs)
		}
	}
	list := h.get("/api/tasks", nadia.Token).expect(http.StatusOK)
	if earned, tasks, balance := balanceOf(list, nadia); earned != 100 || tasks != -40 || balance != 60 {
		t.Fatalf("only the opted-in miss costs: earned %d tasks %d balance %d: %s", earned, tasks, balance, list.Body)
	}
	if list.str("history.0.status") != "missed" || list.num("history.0.daysLeft") != -1 {
		t.Fatalf("history = %s", list.Body)
	}
	lost := map[int]int{}
	for i := 0; i < list.length("history"); i++ {
		lost[list.num(fmt.Sprintf("history.%d.id", i))] = list.num(fmt.Sprintf("history.%d.lost", i))
	}
	if lost[id] != 0 || lost[risky] != 40 {
		t.Fatalf("lost = %v", lost)
	}
	// Too late to finish.
	h.post(taskPath(id, "/done"), nadia.Token, nil).expect(http.StatusConflict).code("task_state")
}

func TestALossIsOptInOnlyForYourOwnTaskAndCappedAtWhatYouHold(t *testing.T) {
	h := newHarness(t)
	nick, nadia := h.pair()
	h.gems(nadia, "2026-10-30", 30)
	h.gems(nick, "2026-10-30", 200)

	// Asking the partner to put gems on the line is refused, and so is a stray flag on edit.
	h.post("/api/tasks", nick.Token, obj{"title": "Fix the fence", "assigneeId": nadia.ID, "stake": 100,
		"deadline": "2026-11-02", "loseIfMissed": true}).expect(http.StatusUnprocessableEntity).code("invalid_request")
	own := h.proposeRisky(nadia, "Fix the fence", 100, "2026-11-02")
	if h.patch(taskPath(own, ""), nadia.Token, obj{"assigneeId": nick.ID}).expect(http.StatusOK).flag("task.loseIfMissed") {
		t.Fatal("handing a task to the partner drops the opt-in")
	}
	if !h.patch(taskPath(own, ""), nadia.Token, obj{"assigneeId": nadia.ID, "loseIfMissed": true}).expect(http.StatusOK).flag("task.loseIfMissed") {
		t.Fatal("taking it back for yourself can opt in again")
	}
	h.post(taskPath(own, "/agree"), nick.Token, nil).expect(http.StatusOK)

	h.clock.Set(ny(2026, time.November, 3, 9, 0))
	h.settleAll()

	list := h.get("/api/rewards", nadia.Token).expect(http.StatusOK)
	if _, tasks, balance := balanceOf(list, nadia); tasks != -30 || balance != 0 {
		t.Fatalf("a 100 gem loss takes the 30 held and leaves no debt: tasks %d balance %d: %s", tasks, balance, list.Body)
	}
	if list.num("bank") != 200 {
		t.Fatalf("bank = %d, want only Nick's 200", list.num("bank"))
	}
	if hist := h.get("/api/tasks", nadia.Token).expect(http.StatusOK); hist.num("history.0.lost") != 30 || hist.num("history.0.stake") != 100 {
		t.Fatalf("history = %s", hist.Body)
	}

	// Earning again is spendable at once; nothing is owed first.
	h.gems(nadia, "2026-11-01", 100)
	paid := h.get("/api/rewards", nadia.Token).expect(http.StatusOK)
	if _, _, balance := balanceOf(paid, nadia); balance != 100 {
		t.Fatalf("balance after earning = %d, want 100: %s", balance, paid.Body)
	}
}

func TestCounteringAProposalPutsItBackToTheProposer(t *testing.T) {
	n := &capture{}
	h := newHarness(t, withPush(n))
	nick, nadia := h.pair()
	id := h.proposeTask(nick, nadia, "Call the vet", 60, "2026-11-05")

	h.post(taskPath(id, "/counter"), nick.Token, obj{"stake": 30}).expect(http.StatusForbidden)
	h.post(taskPath(id, "/counter"), nadia.Token, obj{"stake": 0}).expect(http.StatusUnprocessableEntity)
	countered := h.post(taskPath(id, "/counter"), nadia.Token, obj{"stake": 30}).expect(http.StatusOK)
	if countered.num("task.stake") != 30 || countered.str("task.status") != "proposed" || countered.str("task.creatorName") != "Nadia" {
		t.Fatalf("countered = %s", countered.Body)
	}
	if got := n.of(together.EventTaskProposal, nick.ID); len(got) != 1 {
		t.Fatalf("pushes = %+v", n.msgs)
	}
	// Now Nick is the one asked: Nadia can not agree to her own counter, Nick can.
	h.post(taskPath(id, "/agree"), nadia.Token, nil).expect(http.StatusForbidden)
	h.post(taskPath(id, "/agree"), nick.Token, nil).expect(http.StatusOK)
	h.post(taskPath(id, "/counter"), nick.Token, obj{"stake": 10}).expect(http.StatusConflict).code("task_state")
}

func TestADeadlineEndsOnTheAssigneesCalendarNotTheCreators(t *testing.T) {
	h := newHarness(t)
	nick, nadia := h.pair()
	h.patch("/api/me", nadia.Token, obj{"timezone": "America/Los_Angeles"}).expect(http.StatusOK)
	h.clock.Set(ny(2026, time.November, 3, 12, 0))
	id := h.proposeTask(nick, nadia, "Renew passport", 25, "2026-11-03")
	h.post(taskPath(id, "/agree"), nadia.Token, nil).expect(http.StatusOK)

	// 02:00 in New York on the 4th is 23:00 on the 3rd in Los Angeles: still due today there.
	h.clock.Set(ny(2026, time.November, 4, 2, 0))
	h.settleAll()
	if open := h.get("/api/tasks", nadia.Token).expect(http.StatusOK); open.length("tasks") != 1 || open.num("tasks.0.daysLeft") != 0 {
		t.Fatalf("open = %s", open.Body)
	}
	h.post(taskPath(id, "/done"), nadia.Token, nil).expect(http.StatusOK)
}

func TestProposalsAreEditedWithdrawnDeclinedAndLapse(t *testing.T) {
	n := &capture{}
	h := newHarness(t, withPush(n))
	nick, nadia := h.pair()
	id := h.proposeTask(nick, nick, "Book dentist", 30, "2026-11-05")

	if got := n.of(together.EventTaskProposal, nadia.ID); len(got) != 1 || got[0].Body != `Nick will Book dentist for 30 gems by Thu Nov 5` {
		t.Fatalf("pushes = %+v", n.msgs)
	}
	h.patch(taskPath(id, ""), nadia.Token, obj{"stake": 1}).expect(http.StatusForbidden)
	h.delete(taskPath(id, ""), nadia.Token).expect(http.StatusForbidden)
	edited := h.patch(taskPath(id, ""), nick.Token, obj{"stake": 50, "assigneeId": nadia.ID}).expect(http.StatusOK)
	if edited.num("task.stake") != 50 || edited.str("task.assigneeName") != "Nadia" || edited.str("task.status") != "proposed" ||
		len(n.of(together.EventTaskProposal, nadia.ID)) != 2 {
		t.Fatalf("edited = %s %+v", edited.Body, n.msgs)
	}
	h.post(taskPath(id, "/decline"), nadia.Token, nil).expect(http.StatusOK)
	if list := h.get("/api/tasks", nick.Token).expect(http.StatusOK); list.str("tasks.0.status") != "declined" {
		t.Fatalf("list = %s", list.Body)
	}
	h.post(taskPath(id, "/agree"), nadia.Token, nil).expect(http.StatusConflict).code("task_state")
	// Editing a declined task proposes it again, and it can then be agreed.
	h.patch(taskPath(id, ""), nick.Token, obj{"stake": 20}).expect(http.StatusOK)
	h.post(taskPath(id, "/agree"), nadia.Token, nil).expect(http.StatusOK)
	// An agreed task is a promise: neither edited nor withdrawn.
	h.patch(taskPath(id, ""), nick.Token, obj{"stake": 1}).expect(http.StatusConflict).code("task_state")
	h.delete(taskPath(id, ""), nick.Token).expect(http.StatusConflict).code("task_state")

	gone := h.proposeTask(nick, nadia, "Sort the garage", 10, "2026-11-06")
	h.delete(taskPath(gone, ""), nick.Token).expect(http.StatusNoContent)
	h.post(taskPath(gone, "/agree"), nadia.Token, nil).expect(http.StatusConflict).code("task_state")
	h.post("/api/tasks/999/agree", nadia.Token, nil).expect(http.StatusNotFound)

	// A proposal nobody answered before its deadline lapses without costing anyone anything.
	stale := h.proposeTask(nick, nadia, "Old idea", 10, "2026-11-02")
	h.clock.Set(ny(2026, time.November, 3, 9, 0))
	h.post(taskPath(stale, "/agree"), nadia.Token, nil).expect(http.StatusConflict).code("task_state")
	h.settleAll()
	list := h.get("/api/tasks", nick.Token).expect(http.StatusOK)
	for i := 0; i < list.length("tasks"); i++ {
		if list.num(fmt.Sprintf("tasks.%d.id", i)) == stale {
			t.Fatalf("a lapsed proposal must leave the list: %s", list.Body)
		}
	}
	if _, tasks, _ := balanceOf(list, nadia); tasks != 0 {
		t.Fatalf("tasks = %d", tasks)
	}
}

func TestAloneATaskIsAgreedAtOnce(t *testing.T) {
	h := newHarness(t)
	nick := h.joinAdmin("Nick", "green")
	made := h.post("/api/tasks", nick.Token, obj{"title": "Pay the bill", "assigneeId": nick.ID, "stake": 15,
		"deadline": "2026-11-02"}).expect(http.StatusCreated)
	if made.str("task.status") != "agreed" || made.num("task.daysLeft") != 0 {
		t.Fatalf("made = %s", made.Body)
	}
	h.post("/api/tasks", nick.Token, obj{"title": "Pay the bill", "assigneeId": 9999, "stake": 15,
		"deadline": "2026-11-02"}).expect(http.StatusUnprocessableEntity)
	h.post(taskPath(made.num("task.id"), "/done"), nick.Token, nil).expect(http.StatusOK)
}

func TestRacingFinishAndSettlementDecideOnce(t *testing.T) {
	h := newHarness(t)
	nick, nadia := h.pair()
	h.gems(nadia, "2026-10-30", 100)
	id := h.proposeRisky(nadia, "Edge case", 40, "2026-11-02")
	h.post(taskPath(id, "/agree"), nick.Token, nil).expect(http.StatusOK)
	h.clock.Set(ny(2026, time.November, 3, 0, 1))

	var wg sync.WaitGroup
	for range 4 {
		wg.Add(2)
		go func() { defer wg.Done(); _ = h.srv.together.Settle(context.Background()) }()
		go func() { defer wg.Done(); _, _ = h.call(http.MethodPost, taskPath(id, "/done"), nadia.Token, nil) }()
	}
	wg.Wait()
	list := h.get("/api/tasks", nadia.Token).expect(http.StatusOK)
	if _, tasks, _ := balanceOf(list, nadia); tasks != -40 || list.length("history") != 1 {
		t.Fatalf("after the day ended the loss is taken exactly once: %s", list.Body)
	}
}
