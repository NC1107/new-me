package api

import (
	"net/http"
	"testing"
	"time"

	"github.com/nc1107/new-me/server/internal/together"
)

func (h *harness) proposeTreat(p person, name string, price int) int {
	h.t.Helper()
	return h.post("/api/rewards", p.Token, obj{"name": name, "price": price, "treat": true}).
		expect(http.StatusCreated).num("reward.id")
}

func (h *harness) redeem(p person, id int, requestID string) *response {
	h.t.Helper()
	return h.post(rewardPath(id, "/redeem"), p.Token, obj{"requestId": requestID})
}

func (h *harness) balances(p person) (nick, nadia, bank int) {
	h.t.Helper()
	list := h.get("/api/rewards", p.Token).expect(http.StatusOK)
	return list.num("balances.0.balance"), list.num("balances.1.balance"), list.num("bank")
}

func TestATreatIsPricedByBothAndStaysOffTheSharedWishlist(t *testing.T) {
	n := &capture{}
	h := newHarness(t, withPush(n))
	nick, nadia := h.pair()

	id := h.proposeTreat(nick, "Monster energy drink", 1000)
	if got := n.of(together.EventRewardProposal, nadia.ID); len(got) != 1 || got[0].Title != "Treat to approve" ||
		got[0].Body != "Nick wants Monster energy drink as a treat for 1000 gems" {
		t.Fatalf("pushes = %+v", n.msgs)
	}
	list := h.get("/api/rewards", nick.Token).expect(http.StatusOK)
	if list.length("rewards") != 0 || list.length("treats") != 1 || list.num("treats.0.ownerId") != int(nick.ID) ||
		list.str("treats.0.ownerName") != "Nick" || list.str("treats.0.status") != "pending" || list.flag("treats.0.focus") {
		t.Fatalf("list = %s", list.Body)
	}

	// The owner cannot price their own treat; the partner answers and may counter.
	h.post(rewardPath(id, "/approve"), nick.Token, nil).expect(http.StatusForbidden)
	h.redeem(nick, id, "request-000001").expect(http.StatusConflict).code("reward_state")
	h.approve(nadia, id)
	if !h.get("/api/board", nick.Token).expect(http.StatusOK).isNull("reward") {
		t.Fatal("a treat must never be the board focus")
	}

	h.patch(rewardPath(id, ""), nadia.Token, obj{"name": "Free drink"}).expect(http.StatusForbidden)
	counter := h.patch(rewardPath(id, ""), nadia.Token, obj{"price": 1500}).expect(http.StatusOK)
	if counter.str("reward.status") != "pending" || counter.num("reward.price") != 1500 {
		t.Fatalf("counter = %s", counter.Body)
	}
	h.post(rewardPath(id, "/approve"), nadia.Token, nil).expect(http.StatusForbidden)
	h.post(rewardPath(id, "/decline"), nick.Token, nil).expect(http.StatusOK)
	if back := h.get("/api/rewards", nick.Token).expect(http.StatusOK); back.str("treats.0.status") != "approved" ||
		back.num("treats.0.price") != 1000 {
		t.Fatalf("a declined counter must restore the agreed price: %s", back.Body)
	}
	h.patch(rewardPath(id, ""), nick.Token, obj{"price": 0}).expect(http.StatusUnprocessableEntity)
	h.patch(rewardPath(id, ""), nick.Token, obj{"price": 800}).expect(http.StatusOK)
	h.approve(nadia, id)
	if got := h.get("/api/rewards", nadia.Token).expect(http.StatusOK); got.num("treats.0.price") != 800 || got.str("treats.0.status") != "approved" {
		t.Fatalf("agreed = %s", got.Body)
	}

	h.post(rewardPath(id, "/claim"), nick.Token, nil).expect(http.StatusConflict).code("reward_state")
	h.post(rewardPath(id, "/focus"), nick.Token, nil).expect(http.StatusConflict).code("reward_state")
	h.post(rewardPath(id, "/cancel"), nadia.Token, nil).expect(http.StatusForbidden)
}

func TestRedeemingSpendsOnlyTheOwnersGemsAndRepeats(t *testing.T) {
	n := &capture{}
	h := newHarness(t, withPush(n))
	nick, nadia := h.pair()
	h.clock.Set(ny(2026, time.November, 16, 12, 0))

	id := h.proposeTreat(nick, "Monster energy drink", 1000)
	h.approve(nadia, id)
	h.gems(nick, "2026-11-10", 700)
	h.gems(nadia, "2026-11-10", 2000)

	// Nadia's gems do not count toward Nick's treat even though the bank would cover it.
	list := h.get("/api/rewards", nick.Token).expect(http.StatusOK)
	if list.num("bank") != 2700 || list.num("treats.0.progress") != 700 || list.flag("treats.0.ready") {
		t.Fatalf("before = %s", list.Body)
	}
	h.redeem(nick, id, "request-000001").expect(http.StatusConflict).code("insufficient_gems")
	if len(n.of(together.EventTreat, nadia.ID)) != 0 {
		t.Fatalf("pushed without a redemption: %+v", n.msgs)
	}

	h.gems(nick, "2026-11-11", 1500)
	h.redeem(nadia, id, "request-000002").expect(http.StatusForbidden)
	h.redeem(nick, id, "short").expect(http.StatusUnprocessableEntity)
	h.post(rewardPath(id, "/redeem"), nick.Token, nil).expect(http.StatusUnprocessableEntity)

	first := h.redeem(nick, id, "request-000003").expect(http.StatusCreated)
	if first.num("redemption.price") != 1000 || first.str("redemption.name") != "Monster energy drink" ||
		first.str("redemption.userName") != "Nick" || first.num("balances.0.balance") != 1200 ||
		first.num("balances.1.balance") != 2000 || first.num("bank") != 3200 {
		t.Fatalf("first = %s", first.Body)
	}
	if got := n.of(together.EventTreat, nadia.ID); len(got) != 1 || got[0].Body != "Nick redeemed Monster energy drink" ||
		len(n.of(together.EventTreat, nick.ID)) != 0 {
		t.Fatalf("pushes = %+v", n.msgs)
	}

	// A double tap carries the same request id and spends nothing more.
	again := h.redeem(nick, id, "request-000003").expect(http.StatusOK)
	if again.num("redemption.id") != first.num("redemption.id") || again.num("balances.0.balance") != 1200 ||
		len(n.of(together.EventTreat, nadia.ID)) != 1 {
		t.Fatalf("a double tap spent again: %s", again.Body)
	}

	// Treats repeat: another request is another redemption, until the gems run out.
	h.redeem(nick, id, "request-000004").expect(http.StatusCreated)
	h.redeem(nick, id, "request-000005").expect(http.StatusConflict).code("insufficient_gems")
	nickBal, nadiaBal, bank := h.balances(nadia)
	if nickBal != 200 || nadiaBal != 2000 || bank != 2200 {
		t.Fatalf("balances = %d %d %d", nickBal, nadiaBal, bank)
	}
	hist := h.get("/api/rewards", nadia.Token).expect(http.StatusOK)
	if hist.length("treatHistory") != 2 || hist.str("treatHistory.0.userName") != "Nick" || hist.num("treatHistory.0.price") != 1000 {
		t.Fatalf("history = %s", hist.Body)
	}

	// A later price change does not rewrite what was already bought.
	h.patch(rewardPath(id, ""), nadia.Token, obj{"price": 5}).expect(http.StatusOK)
	if later := h.get("/api/rewards", nick.Token).expect(http.StatusOK); later.num("treatHistory.1.price") != 1000 {
		t.Fatalf("history repriced: %s", later.Body)
	}
	h.redeem(nick, id, "request-000006").expect(http.StatusConflict).code("reward_state")
}

func TestSharedRewardsArePaidInProportionToWhatEachHoldsAndTheBankStaysConsistent(t *testing.T) {
	h := newHarness(t)
	nick, nadia := h.pair()
	h.clock.Set(ny(2026, time.November, 16, 12, 0))

	treat := h.proposeTreat(nick, "Big Gulp", 600)
	h.approve(nadia, treat)
	h.gems(nick, "2026-11-10", 1000)
	h.gems(nadia, "2026-11-10", 400)
	h.redeem(nick, treat, "request-000001").expect(http.StatusCreated)
	if a, b, bank := h.balances(nick); a != 400 || b != 400 || bank != 800 {
		t.Fatalf("after treat = %d %d %d", a, b, bank)
	}

	trip := h.propose(nick, "Date night", 300)
	h.approve(nadia, trip)
	h.post(rewardPath(trip, "/claim"), nick.Token, nil).expect(http.StatusOK)
	a, b, bank := h.balances(nick)
	if a != 250 || b != 250 || bank != 500 || a+b != bank {
		t.Fatalf("after shared claim = %d %d %d", a, b, bank)
	}

	// The bank covers a 400 treat for Nadia, but her own 250 does not.
	mine := h.proposeTreat(nadia, "Latte", 400)
	h.approve(nick, mine)
	h.redeem(nadia, mine, "request-000002").expect(http.StatusConflict).code("insufficient_gems")
	h.gems(nadia, "2026-11-11", 150)
	h.redeem(nadia, mine, "request-000003").expect(http.StatusCreated)
	if a, b, bank := h.balances(nick); a != 250 || b != 0 || bank != 250 {
		t.Fatalf("after Nadia's treat = %d %d %d", a, b, bank)
	}

	// A shared reward the bank covers is refused when it would need gems nobody has.
	big := h.propose(nick, "Trip", 300)
	h.approve(nadia, big)
	h.post(rewardPath(big, "/claim"), nick.Token, nil).expect(http.StatusConflict).code("reward_not_reached")
}
