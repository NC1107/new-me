package api

import (
	"context"
	"net/http"
	"testing"
	"time"

	"github.com/nc1107/new-me/server/internal/db"
	"github.com/nc1107/new-me/server/internal/push"
	"github.com/nc1107/new-me/server/internal/together"
)

func (h *harness) deliverHeld() {
	h.t.Helper()
	if err := h.srv.together.DeliverHeld(context.Background()); err != nil {
		h.t.Fatalf("deliver held: %v", err)
	}
}

func (h *harness) holdCount() int {
	h.t.Helper()
	var n int
	err := h.db.Pool.QueryRow(context.Background(), `SELECT count(*)::int FROM held_pushes WHERE delivered_at IS NULL`).Scan(&n)
	if err != nil {
		h.t.Fatal(err)
	}
	return n
}

func TestAPushHeldInQuietHoursIsDeliveredAfterWakeNotBefore(t *testing.T) {
	n := &capture{}
	h := newHarness(t, withPush(n))
	nick, nadia := h.pair()

	h.clock.Set(ny(2026, time.November, 3, 3, 0))
	h.cheer(nadia, nick, "fire").expect(http.StatusCreated)
	h.srv.together.Notify(h.user(nick), push.Message{Kind: together.EventChallenge, Title: "Challenge complete", Body: "Walk"})
	if n.count() != 0 || h.holdCount() != 2 {
		t.Fatalf("held = %d, sent = %+v", h.holdCount(), n.msgs)
	}

	// Wake is 07:00 and the first notification 07:10.
	h.clock.Set(ny(2026, time.November, 3, 7, 5))
	h.deliverHeld()
	if n.count() != 0 {
		t.Fatalf("delivered before the first notification: %+v", n.msgs)
	}

	h.clock.Set(ny(2026, time.November, 3, 7, 10))
	h.deliverHeld()
	if len(n.of(together.EventCheer, nick.ID)) != 1 || len(n.of(together.EventChallenge, nick.ID)) != 1 {
		t.Fatalf("after wake: %+v", n.msgs)
	}
	h.deliverHeld()
	if n.count() != 2 || h.holdCount() != 0 {
		t.Fatalf("a delivered push must not repeat: %+v", n.msgs)
	}
}

func TestAHeldPushIsDroppedWhenItsSwitchIsTurnedOffMeanwhile(t *testing.T) {
	n := &capture{}
	h := newHarness(t, withPush(n))
	nick, nadia := h.pair()

	h.clock.Set(ny(2026, time.November, 3, 3, 0))
	h.cheer(nadia, nick, "fire").expect(http.StatusCreated)
	h.srv.together.Notify(h.user(nick), push.Message{Kind: together.EventReward, Title: "Reward ready", Body: "Trip"})
	h.patch("/api/me", nick.Token, obj{"notifications": obj{"cheers": false}}).expect(http.StatusOK)

	h.clock.Set(ny(2026, time.November, 3, 9, 0))
	h.deliverHeld()
	if len(n.of(together.EventCheer, nick.ID)) != 0 || len(n.of(together.EventReward, nick.ID)) != 1 || h.holdCount() != 0 {
		t.Fatalf("only the switched-off kind is dropped: %+v", n.msgs)
	}
}

func TestHeldDuplicatesOfTheSameKindAndSubjectCollapse(t *testing.T) {
	n := &capture{}
	h := newHarness(t, withPush(n))
	nick, _ := h.pair()
	svc := h.srv.together

	h.clock.Set(ny(2026, time.November, 3, 2, 0))
	svc.Notify(h.user(nick), push.Message{Kind: together.EventReward, Title: "Reward ready", Body: "Trip"})
	h.clock.Set(ny(2026, time.November, 3, 4, 0))
	svc.Notify(h.user(nick), push.Message{Kind: together.EventReward, Title: "Reward ready", Body: "Trip"})
	svc.Notify(h.user(nick), push.Message{Kind: together.EventReward, Title: "Reward ready", Body: "Movie night"})

	h.clock.Set(ny(2026, time.November, 3, 8, 0))
	h.deliverHeld()
	got := n.of(together.EventReward, nick.ID)
	if len(got) != 2 || got[0].Body != "Trip" || got[1].Body != "Movie night" || h.holdCount() != 0 {
		t.Fatalf("collapse: %+v", n.msgs)
	}
}

func TestAHeldPushOlderThanADayExpires(t *testing.T) {
	n := &capture{}
	h := newHarness(t, withPush(n))
	nick, _ := h.pair()
	if _, err := db.CreateAway(context.Background(), h.db.Pool, nick.ID, "2026-11-03", "2026-11-05", ""); err != nil {
		t.Fatal(err)
	}

	h.clock.Set(ny(2026, time.November, 3, 12, 0))
	h.srv.together.Notify(h.user(nick), push.Message{Kind: together.EventChallenge, Title: "Challenge complete", Body: "Walk"})
	if h.holdCount() != 1 {
		t.Fatalf("an away day should hold the push")
	}

	// Still away that evening: nothing is due yet.
	h.clock.Set(ny(2026, time.November, 3, 20, 0))
	h.deliverHeld()
	// The away span runs until the 5th, so by the 4th at 13:00 the push is over a day old.
	h.clock.Set(ny(2026, time.November, 4, 13, 0))
	h.deliverHeld()
	h.clock.Set(ny(2026, time.November, 6, 9, 0))
	h.deliverHeld()
	if n.count() != 0 || h.holdCount() != 0 {
		t.Fatalf("a stale push was sent: %+v", n.msgs)
	}
}

func TestAHeldPushWaitsOutAnAwayDay(t *testing.T) {
	n := &capture{}
	h := newHarness(t, withPush(n))
	nick, _ := h.pair()
	if _, err := db.CreateAway(context.Background(), h.db.Pool, nick.ID, "2026-11-03", "2026-11-03", ""); err != nil {
		t.Fatal(err)
	}

	h.clock.Set(ny(2026, time.November, 3, 12, 0))
	h.srv.together.Notify(h.user(nick), push.Message{Kind: together.EventChallenge, Title: "Challenge complete", Body: "Walk"})
	h.clock.Set(ny(2026, time.November, 3, 20, 0))
	h.deliverHeld()
	if n.count() != 0 {
		t.Fatalf("delivered on an away day: %+v", n.msgs)
	}
	h.clock.Set(ny(2026, time.November, 4, 8, 0))
	h.deliverHeld()
	if len(n.of(together.EventChallenge, nick.ID)) != 1 {
		t.Fatalf("next morning: %+v", n.msgs)
	}
}

func TestRewardProposalPushFollowsTheApprovalsSwitch(t *testing.T) {
	n := &capture{}
	h := newHarness(t, withPush(n))
	nick, nadia := h.pair()

	h.propose(nick, "Date night", 2000)
	if len(n.of(together.EventRewardProposal, nadia.ID)) != 1 {
		t.Fatalf("approvals on: %+v", n.msgs)
	}
	h.patch("/api/me", nadia.Token, obj{"notifications": obj{"approvals": false}}).expect(http.StatusOK)
	h.propose(nick, "Trip", 3000)
	if len(n.of(together.EventRewardProposal, nadia.ID)) != 1 {
		t.Fatalf("approvals off still pushed a reward proposal: %+v", n.msgs)
	}
	h.patch("/api/me", nadia.Token, obj{"notifications": obj{"approvals": true, "partnerNudges": false, "cheers": false}}).expect(http.StatusOK)
	h.propose(nick, "Spa", 1000)
	if len(n.of(together.EventRewardProposal, nadia.ID)) != 2 {
		t.Fatalf("only approvals gates proposals: %+v", n.msgs)
	}
}

func TestEveryNotificationSwitchIsExposedAndPatchable(t *testing.T) {
	h := newHarness(t)
	nick := h.joinAdmin("Nick", "green")
	keys := []string{"partnerDone", "cheers", "challenge", "reward", "behindPace", "closeToDone", "windDown",
		"morningPlan", "weeklyRecap", "milestones", "lookback", "partnerNudges", "cover", "approvals"}
	me := h.get("/api/me", nick.Token).expect(http.StatusOK)
	for _, k := range keys {
		want := !me.flag("notifications." + k) // flag fails the test when the key is missing
		got := h.patch("/api/me", nick.Token, obj{"notifications": obj{k: want}}).expect(http.StatusOK)
		if got.flag("notifications."+k) != want {
			t.Errorf("PATCH %s=%v not applied: %s", k, want, got.Body)
		}
		if again := h.get("/api/me", nick.Token).expect(http.StatusOK); again.flag("notifications."+k) != want {
			t.Errorf("%s not persisted", k)
		}
	}
}

func TestFocusRewardProgressPushesAtFiftyAndNinetyPercentButNotAtReady(t *testing.T) {
	n := &capture{}
	h := newHarness(t, withPush(n))
	nick, nadia := h.pair()
	h.clock.Set(ny(2026, time.November, 16, 12, 0))
	id := h.propose(nick, "Date night", 1000)
	h.approve(nadia, id)
	settle := func() { h.srv.together.SettleQuietly(context.Background()) }

	h.gems(nick, "2026-11-10", 400)
	settle()
	if len(n.of(together.EventRewardProgress, nick.ID)) != 0 {
		t.Fatalf("40 percent: %+v", n.msgs)
	}
	h.gems(nadia, "2026-11-10", 150)
	settle()
	settle()
	for _, p := range []person{nick, nadia} {
		got := n.of(together.EventRewardProgress, p.ID)
		if len(got) != 1 || got[0].Body != "Date night is 50% of the way there." {
			t.Fatalf("%s at 55 percent: %+v", p.Name, n.msgs)
		}
	}

	h.clock.Set(ny(2026, time.November, 17, 12, 0))
	h.gems(nadia, "2026-11-11", 350)
	settle()
	settle()
	got := n.of(together.EventRewardProgress, nick.ID)
	if len(got) != 2 || got[1].Body != "Date night is 90% of the way there." {
		t.Fatalf("at 90 percent: %+v", n.msgs)
	}

	h.clock.Set(ny(2026, time.November, 18, 12, 0))
	h.gems(nick, "2026-11-12", 200)
	settle()
	if len(n.of(together.EventRewardProgress, nick.ID)) != 2 || len(n.of(together.EventReward, nick.ID)) != 1 {
		t.Fatalf("ready is the reward push alone: %+v", n.msgs)
	}
}

func TestRewardProgressInQuietHoursIsNotClaimedAndGoesOutLater(t *testing.T) {
	n := &capture{}
	h := newHarness(t, withPush(n))
	nick, nadia := h.pair()
	h.clock.Set(ny(2026, time.November, 16, 12, 0))
	id := h.propose(nick, "Date night", 1000)
	h.approve(nadia, id)
	h.gems(nick, "2026-11-10", 600)

	h.clock.Set(ny(2026, time.November, 17, 3, 0))
	h.srv.together.SettleQuietly(context.Background())
	if len(n.of(together.EventRewardProgress, nick.ID)) != 0 || h.holdCount() != 0 {
		t.Fatalf("a claim-based push must neither send nor be held: %+v", n.msgs)
	}
	h.clock.Set(ny(2026, time.November, 17, 9, 0))
	h.srv.together.SettleQuietly(context.Background())
	if len(n.of(together.EventRewardProgress, nick.ID)) != 1 {
		t.Fatalf("retry in the window: %+v", n.msgs)
	}
}
