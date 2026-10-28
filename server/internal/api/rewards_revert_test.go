package api

import (
	"context"
	"fmt"
	"net/http"
	"testing"
	"time"

	"github.com/nc1107/new-me/server/internal/db"
	"github.com/nc1107/new-me/server/internal/together"
)

func TestWithdrawingOrDecliningAPriceChangeRestoresTheApprovedReward(t *testing.T) {
	h := newHarness(t)
	nick, nadia := h.pair()
	first := h.propose(nick, "Date night", 500)
	h.approve(nadia, first)

	// Nick proposes a new price and then withdraws it: the reward stays approved at 500, in focus.
	h.patch(rewardPath(first, ""), nick.Token, obj{"price": 900}).expect(http.StatusOK)
	h.delete(rewardPath(first, ""), nick.Token).expect(http.StatusNoContent)
	back := h.get("/api/rewards", nick.Token).expect(http.StatusOK)
	if back.length("rewards") != 1 || back.num("rewards.0.price") != 500 || back.str("rewards.0.status") != "approved" ||
		!back.flag("rewards.0.focus") {
		t.Fatalf("after withdraw = %s", back.Body)
	}

	// Declining restores it too, and the focus goes back only while the slot is free.
	h.patch(rewardPath(first, ""), nick.Token, obj{"price": 900}).expect(http.StatusOK)
	other := h.propose(nadia, "Weekend away", 3000)
	h.approve(nick, other)
	h.post(rewardPath(first, "/decline"), nadia.Token, nil).expect(http.StatusOK)
	list := h.get("/api/rewards", nick.Token).expect(http.StatusOK)
	if list.length("rewards") != 2 || list.num("reward.id") != other {
		t.Fatalf("after decline = %s", list.Body)
	}
	for i := 0; i < 2; i++ {
		at := func(f string) string { return fmt.Sprintf("rewards.%d.%s", i, f) }
		if list.num(at("id")) == first &&
			(list.num(at("price")) != 500 || list.str(at("status")) != "approved" || list.flag(at("focus"))) {
			t.Fatalf("restored reward = %s", list.Body)
		}
	}

	// Approving the change keeps the new price and ends the revert path.
	h.patch(rewardPath(first, ""), nick.Token, obj{"price": 700}).expect(http.StatusOK)
	h.approve(nadia, first)
	h.delete(rewardPath(first, ""), nick.Token).expect(http.StatusConflict).code("reward_state")
}

func TestAnOldBuildsRewardIsApprovedAtOnceWithAPartnerAndNotDuplicated(t *testing.T) {
	n := &capture{}
	h := newHarness(t, withPush(n))
	nick, _ := h.pair()
	made := h.post("/api/rewards", nick.Token, obj{"name": "Treat", "target": 100}).expect(http.StatusCreated)
	if made.str("reward.status") != "approved" || !made.flag("reward.focus") || made.num("reward.price") != 100 {
		t.Fatalf("legacy create = %s", made.Body)
	}
	if got := n.of(together.EventRewardProposal, nick.ID); len(got) != 0 {
		t.Fatalf("an auto-approved reward needs no proposal push: %+v", n.msgs)
	}

	// A repeated pending proposal under the same name is the same proposal.
	id := h.propose(nick, "Spa", 300)
	again := h.post("/api/rewards", nick.Token, obj{"name": "spa", "price": 300}).expect(http.StatusOK)
	if again.num("reward.id") != id || h.get("/api/rewards", nick.Token).expect(http.StatusOK).length("rewards") != 2 {
		t.Fatalf("duplicate create = %s", again.Body)
	}
}

func TestSettlingRewardsWaitsForTheWishlistLock(t *testing.T) {
	h := newHarness(t)
	nick, nadia := h.pair()
	h.clock.Set(ny(2026, time.November, 16, 12, 0))
	id := h.propose(nick, "Movie", 600)
	h.approve(nadia, id)
	h.gems(nick, "2026-11-10", 700)

	ctx := t.Context()
	tx, err := h.db.Pool.Begin(ctx)
	if err != nil {
		t.Fatal(err)
	}
	defer tx.Rollback(ctx)
	if err := db.LockRewards(ctx, tx); err != nil {
		t.Fatal(err)
	}
	done := make(chan struct{})
	go func() {
		h.srv.together.SettleQuietly(context.Background())
		close(done)
	}()
	select {
	case <-done:
		t.Fatal("settling stamped rewards ready without the wishlist lock, so a claim could race it")
	case <-time.After(300 * time.Millisecond):
	}
	if err := tx.Commit(ctx); err != nil {
		t.Fatal(err)
	}
	<-done
}
