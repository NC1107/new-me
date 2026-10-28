package api

import (
	"fmt"
	"net/http"
	"sync"
	"testing"
	"time"

	"github.com/nc1107/new-me/server/internal/together"
)

func rewardPath(id int, tail string) string { return fmt.Sprintf("/api/rewards/%d%s", id, tail) }

// gems puts a finished day with exactly n gems on the person's score table.
func (h *harness) gems(p person, date string, n int) {
	h.t.Helper()
	h.storeScore(p, date, n, 0, n)
}

func (h *harness) propose(p person, name string, price int) int {
	h.t.Helper()
	return h.post("/api/rewards", p.Token, obj{"name": name, "price": price}).expect(http.StatusCreated).num("reward.id")
}

func (h *harness) approve(p person, id int) *response {
	h.t.Helper()
	return h.post(rewardPath(id, "/approve"), p.Token, nil).expect(http.StatusOK)
}

func TestRewardProposalNeedsThePartnersAnswer(t *testing.T) {
	n := &capture{}
	h := newHarness(t, withPush(n))
	nick, nadia := h.pair()

	if empty := h.get("/api/rewards", nick.Token).expect(http.StatusOK); !empty.isNull("reward") ||
		empty.length("rewards") != 0 || empty.length("history") != 0 || empty.num("bank") != 0 || !empty.isNull("priceHelp") {
		t.Fatalf("empty = %s", empty.Body)
	}
	for _, bad := range []obj{{"name": " ", "price": 100}, {"name": "Trip", "price": 0}, {"name": "Trip", "price": 100001},
		{"price": 100}, {"name": "Trip"}} {
		h.post("/api/rewards", nick.Token, bad).expect(http.StatusUnprocessableEntity).code("invalid_request")
	}

	made := h.post("/api/rewards", nick.Token, obj{"name": "Date night", "price": 2000}).expect(http.StatusCreated)
	id := made.num("reward.id")
	if made.str("reward.status") != "pending" || made.flag("reward.focus") || made.num("reward.price") != 2000 ||
		made.num("reward.target") != 2000 || made.num("reward.proposedBy") != int(nick.ID) || made.str("reward.proposedByName") != "Nick" {
		t.Fatalf("created = %s", made.Body)
	}
	if got := n.of(together.EventRewardProposal, nadia.ID); len(got) != 1 || got[0].Body != "Nick wants Date night for 2000 gems" ||
		len(n.of(together.EventRewardProposal, nick.ID)) != 0 {
		t.Fatalf("pushes = %+v", n.msgs)
	}
	if !h.get("/api/board", nick.Token).expect(http.StatusOK).isNull("reward") {
		t.Fatal("a pending reward must not be the focus")
	}

	// Only the other person answers; the proposer edits or withdraws.
	h.post(rewardPath(id, "/approve"), nick.Token, nil).expect(http.StatusForbidden)
	h.patch(rewardPath(id, ""), nadia.Token, obj{"price": 10}).expect(http.StatusForbidden)
	h.delete(rewardPath(id, ""), nadia.Token).expect(http.StatusForbidden)
	renamed := h.patch(rewardPath(id, ""), nick.Token, obj{"name": "Dinner in"}).expect(http.StatusOK)
	if renamed.str("reward.name") != "Dinner in" || len(n.of(together.EventRewardProposal, nadia.ID)) != 1 {
		t.Fatalf("a rename must not push again: %s %+v", renamed.Body, n.msgs)
	}
	edited := h.patch(rewardPath(id, ""), nick.Token, obj{"name": "Dinner out", "price": 1500}).expect(http.StatusOK)
	if edited.str("reward.name") != "Dinner out" || edited.num("reward.price") != 1500 || edited.str("reward.status") != "pending" {
		t.Fatalf("edited = %s", edited.Body)
	}

	h.post(rewardPath(id, "/decline"), nadia.Token, nil).expect(http.StatusOK)
	list := h.get("/api/rewards", nick.Token).expect(http.StatusOK)
	if list.str("rewards.0.status") != "declined" {
		t.Fatalf("declined = %s", list.Body)
	}
	h.post(rewardPath(id, "/decline"), nadia.Token, nil).expect(http.StatusConflict).code("reward_state")

	// Editing a declined reward proposes it again, with another push.
	h.patch(rewardPath(id, ""), nick.Token, obj{"price": 1200}).expect(http.StatusOK)
	if got := n.of(together.EventRewardProposal, nadia.ID); len(got) != 3 {
		t.Fatalf("pushes after re-proposing = %+v", n.msgs)
	}
	approved := h.approve(nadia, id)
	if approved.str("reward.status") != "approved" || !approved.flag("reward.focus") {
		t.Fatalf("approved = %s", approved.Body)
	}
	if board := h.get("/api/board", nick.Token).expect(http.StatusOK); board.num("reward.id") != id || board.num("reward.price") != 1200 {
		t.Fatalf("board = %s", board.Body)
	}
	// An approved reward cannot be withdrawn, only cancelled.
	h.delete(rewardPath(id, ""), nick.Token).expect(http.StatusConflict).code("reward_state")

	gone := h.propose(nick, "Spare", 300)
	h.delete(rewardPath(gone, ""), nick.Token).expect(http.StatusNoContent)
	h.post(rewardPath(gone, "/approve"), nadia.Token, nil).expect(http.StatusNotFound)
	h.post("/api/rewards/999/approve", nadia.Token, nil).expect(http.StatusNotFound)
}

func TestApprovedRewardsQueueBehindOneFocusAndPriceChangesAreProposedAgain(t *testing.T) {
	n := &capture{}
	h := newHarness(t, withPush(n))
	nick, nadia := h.pair()

	first := h.propose(nick, "Date night", 500)
	second := h.propose(nadia, "Weekend away", 3000)
	h.approve(nadia, first)
	if got := h.approve(nick, second); got.flag("reward.focus") {
		t.Fatalf("a second approved reward waits in the list: %s", got.Body)
	}

	// A new price on an approved reward is proposed again and the focus moves on.
	changed := h.patch(rewardPath(first, ""), nadia.Token, obj{"price": 800}).expect(http.StatusOK)
	if changed.str("reward.status") != "pending" || changed.flag("reward.focus") || changed.num("reward.proposedBy") != int(nadia.ID) {
		t.Fatalf("price change = %s", changed.Body)
	}
	if got := n.of(together.EventRewardProposal, nick.ID); len(got) != 2 || got[1].Body != "Nadia wants Date night for 800 gems" {
		t.Fatalf("pushes = %+v", n.msgs)
	}
	if board := h.get("/api/board", nick.Token).expect(http.StatusOK); board.num("reward.id") != second {
		t.Fatalf("board = %s", board.Body)
	}
	// A rename is not a price change and needs no answer.
	renamed := h.patch(rewardPath(second, ""), nick.Token, obj{"name": "Cabin weekend"}).expect(http.StatusOK)
	if renamed.str("reward.status") != "approved" || renamed.str("reward.name") != "Cabin weekend" || !renamed.flag("reward.focus") {
		t.Fatalf("rename = %s", renamed.Body)
	}
	h.approve(nick, first)

	// Focus is chosen by hand, and cancelling the focus hands it to the next approved one.
	h.post(rewardPath(first, "/focus"), nick.Token, nil).expect(http.StatusOK)
	if board := h.get("/api/board", nick.Token).expect(http.StatusOK); board.num("reward.id") != first {
		t.Fatalf("board after choosing = %s", board.Body)
	}
	h.post(rewardPath(first, "/cancel"), nadia.Token, nil).expect(http.StatusOK)
	list := h.get("/api/rewards", nick.Token).expect(http.StatusOK)
	if list.length("rewards") != 1 || list.num("reward.id") != second || !list.flag("rewards.0.focus") {
		t.Fatalf("after cancel = %s", list.Body)
	}
	h.post(rewardPath(first, "/focus"), nick.Token, nil).expect(http.StatusConflict).code("reward_state")
	h.post(rewardPath(first, "/cancel"), nick.Token, nil).expect(http.StatusConflict).code("reward_state")
}

func TestClaimingSpendsThePriceOnceAndTheReadyPushComesOnce(t *testing.T) {
	n := &capture{}
	h := newHarness(t, withPush(n))
	nick, nadia := h.pair()
	h.clock.Set(ny(2026, time.November, 16, 12, 0))

	id := h.propose(nick, "Date night", 1000)
	h.approve(nadia, id)
	h.gems(nick, "2026-11-10", 400)
	h.gems(nadia, "2026-11-10", 300)
	list := h.get("/api/rewards", nick.Token).expect(http.StatusOK)
	if list.num("bank") != 700 || list.num("reward.progress") != 700 || list.flag("reward.ready") || !list.isNull("reward.reachedAt") {
		t.Fatalf("midway = %s", list.Body)
	}
	h.post(rewardPath(id, "/claim"), nick.Token, nil).expect(http.StatusConflict).code("reward_not_reached")
	if len(n.of("reward", nick.ID)) != 0 {
		t.Fatalf("pushed too early: %+v", n.msgs)
	}

	h.gems(nadia, "2026-11-11", 450)
	ready := h.get("/api/rewards", nadia.Token).expect(http.StatusOK)
	if ready.num("bank") != 1150 || ready.num("reward.progress") != 1000 || !ready.flag("reward.ready") || ready.str("reward.reachedAt") == "" {
		t.Fatalf("ready = %s", ready.Body)
	}
	h.get("/api/rewards", nick.Token).expect(http.StatusOK)
	for _, p := range []person{nick, nadia} {
		if got := n.of("reward", p.ID); len(got) != 1 || got[0].Body != "Date night" || got[0].Title != "Reward ready" {
			t.Fatalf("%s ready pushes = %+v", p.Name, got)
		}
	}

	claimed := h.post(rewardPath(id, "/claim"), nick.Token, nil).expect(http.StatusOK)
	stamp := claimed.str("reward.claimedAt")
	if stamp == "" || claimed.str("reward.status") != "claimed" || claimed.num("bank") != 150 {
		t.Fatalf("claimed = %s", claimed.Body)
	}
	h.clock.Set(h.clock.Now().Add(time.Hour))
	again := h.post(rewardPath(id, "/claim"), nadia.Token, nil).expect(http.StatusOK)
	if again.str("reward.claimedAt") != stamp || again.num("bank") != 150 {
		t.Fatalf("a repeat claim spent again: %s", again.Body)
	}
	after := h.get("/api/rewards", nick.Token).expect(http.StatusOK)
	if after.num("bank") != 150 || !after.isNull("reward") || after.length("history") != 1 || after.num("history.0.progress") != 1000 {
		t.Fatalf("after = %s", after.Body)
	}
	if !h.get("/api/board", nick.Token).isNull("reward") {
		t.Fatal("a claimed reward is still on the board")
	}
	if len(n.of("reward", nick.ID)) != 1 {
		t.Fatalf("ready pushed more than once: %+v", n.msgs)
	}
	h.post(rewardPath(id, "/cancel"), nick.Token, nil).expect(http.StatusConflict)
}

func TestTheBankCannotGoNegativeAcrossRewardsOrConcurrentClaims(t *testing.T) {
	h := newHarness(t)
	nick, nadia := h.pair()
	h.clock.Set(ny(2026, time.November, 16, 12, 0))
	a := h.propose(nick, "Movie", 600)
	b := h.propose(nick, "Dinner", 600)
	h.approve(nadia, a)
	h.approve(nadia, b)
	h.gems(nick, "2026-11-10", 700)
	h.gems(nadia, "2026-11-10", 300)

	// Each price is covered alone, both together are not: exactly one claim can win.
	var wg sync.WaitGroup
	statuses := make([]int, 4)
	for i := range statuses {
		wg.Add(1)
		go func() {
			defer wg.Done()
			id, who := a, nick
			if i%2 == 1 {
				id, who = b, nadia
			}
			statuses[i], _ = h.call(http.MethodPost, rewardPath(id, "/claim"), who.Token, nil)
		}()
	}
	wg.Wait()
	ok, notReady := 0, 0
	for _, s := range statuses {
		switch s {
		case http.StatusOK:
			ok++
		case http.StatusConflict:
			notReady++
		default:
			t.Fatalf("statuses = %v", statuses)
		}
	}
	// Two taps on the same reward both answer 200 without spending twice; the other reward loses.
	if ok != 2 || notReady != 2 {
		t.Fatalf("statuses = %v", statuses)
	}
	if bank := h.get("/api/rewards", nick.Token).expect(http.StatusOK).num("bank"); bank != 400 {
		t.Fatalf("bank = %d, want 400", bank)
	}
}

func TestAloneARewardIsApprovedAtOnceAndOldBuildsStillWork(t *testing.T) {
	h := newHarness(t)
	nick := h.joinAdmin("Nick", "green")
	h.clock.Set(ny(2026, time.November, 16, 12, 0))

	// Builds from before shared rewards send target and read target, progress and history.
	made := h.post("/api/rewards", nick.Token, obj{"name": "Treat", "target": 100}).expect(http.StatusCreated)
	if made.str("reward.status") != "approved" || !made.flag("reward.focus") || made.num("reward.target") != 100 ||
		made.num("reward.progress") != 0 || !made.isNull("reward.claimedAt") {
		t.Fatalf("created = %s", made.Body)
	}
	id := made.num("reward.id")
	h.gems(nick, "2026-11-10", 120)
	if board := h.get("/api/board", nick.Token).expect(http.StatusOK); board.num("reward.progress") != 100 || board.str("reward.reachedAt") == "" {
		t.Fatalf("board = %s", board.Body)
	}
	h.post(rewardPath(id, "/claim"), nick.Token, nil).expect(http.StatusOK)
	// The leftover 20 gems start the next one.
	next := h.post("/api/rewards", nick.Token, obj{"name": "Next", "target": 100}).expect(http.StatusCreated)
	if next.num("reward.progress") != 20 || next.num("bank") != 20 {
		t.Fatalf("next = %s", next.Body)
	}
}

func TestThePriceHelperUsesThePairsMedianDay(t *testing.T) {
	h := newHarness(t)
	nick, nadia := h.pair()
	h.clock.Set(ny(2026, time.November, 16, 12, 0))
	if got := h.get("/api/rewards", nick.Token).expect(http.StatusOK); !got.isNull("priceHelp") {
		t.Fatalf("no history must give no figures: %s", got.Body)
	}

	// The 14 full days before today: Nov 2 to Nov 15. Today's partial gems are not counted.
	for day := 2; day <= 15; day++ {
		date := fmt.Sprintf("2026-11-%02d", day)
		h.gems(nick, date, 60)
		h.gems(nadia, date, 40)
	}
	h.gems(nick, "2026-11-16", 5)
	h.gems(nadia, "2026-11-01", 9000)
	got := h.get("/api/rewards", nick.Token).expect(http.StatusOK)
	if got.num("priceHelp.medianDaily") != 100 || got.num("priceHelp.sampleDays") != 14 ||
		got.length("priceHelp.options") != 3 || got.num("priceHelp.options.0.days") != 7 || got.num("priceHelp.options.0.price") != 700 ||
		got.num("priceHelp.options.1.price") != 1400 || got.num("priceHelp.options.2.days") != 30 || got.num("priceHelp.options.2.price") != 3000 {
		t.Fatalf("priceHelp = %s", got.Body)
	}
}
