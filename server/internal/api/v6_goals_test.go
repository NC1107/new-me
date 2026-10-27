package api

import (
	"fmt"
	"net/http"
	"testing"
	"time"
)

func templateTarget(me *response, key string) int {
	for i := range me.length("questTemplates") {
		if me.str(fmt.Sprintf("questTemplates.%d.key", i)) == key {
			return me.num(fmt.Sprintf("questTemplates.%d.target", i))
		}
	}
	me.t.Fatalf("no template %s: %s", key, me.Body)
	return 0
}

func TestNoProposalsWithoutHistory(t *testing.T) {
	h := newHarness(t)
	nick := h.joinAdmin("Nick", "green")
	got := h.get("/api/goals/proposals", nick.Token).expect(http.StatusOK)
	if got.str("week") != "2026-W45" || got.str("weekStart") != "2026-11-02" || got.length("proposals") != 0 {
		t.Fatalf("proposals = %s", got.Body)
	}
	h.get("/api/goals/proposals", "").expect(http.StatusUnauthorized)
}

func TestStepsProposalComesFromTheInsightsSuggestion(t *testing.T) {
	h := newHarness(t)
	nick := h.joinAdmin("Nick", "green")
	h.seedSteps(nick, 1, steady(5000, 14)...)

	got := h.get("/api/goals/proposals", nick.Token).expect(http.StatusOK)
	if got.length("proposals") != 1 || got.str("proposals.0.key") != "steps" || got.num("proposals.0.current") != 8000 ||
		got.num("proposals.0.proposed") != 6000 || got.str("proposals.0.title") != "Steps" || got.str("proposals.0.unit") != "steps" ||
		got.str("proposals.0.reason") != "You usually walk about 5,000 steps a day. 6,000 is a goal you can keep for now." {
		t.Fatalf("proposals = %s", got.Body)
	}
	insight := h.get("/api/insights", nick.Token).expect(http.StatusOK)
	if insight.num("steps.suggestion.target") != 6000 {
		t.Fatalf("the proposal must equal the insights suggestion: %s", insight.Body)
	}
}

func TestAProposalIsFrozenWhenFirstShownAndIgnoredOnceTheTargetMoves(t *testing.T) {
	h := newHarness(t)
	nick := h.joinAdmin("Nick", "green")
	h.seedSteps(nick, 1, steady(5000, 14)...)
	first := h.get("/api/goals/proposals", nick.Token).expect(http.StatusOK)
	if first.num("proposals.0.proposed") != 6000 {
		t.Fatalf("first = %s", first.Body)
	}
	// More walking changes the live suggestion, but the shown proposal stays put for the week.
	h.seedSteps(nick, 15, steady(9000, 14)...)
	h.putHealth(nick, "2026-11-02", "steps", 100).expect(http.StatusOK)
	if got := h.get("/api/goals/proposals", nick.Token); got.num("proposals.0.proposed") != 6000 {
		t.Fatalf("frozen proposal = %s", got.Body)
	}

	// Editing the target by hand makes the old proposal stale, so a fresh one is computed.
	h.patch("/api/me", nick.Token, obj{"questTemplates": []obj{{"key": "steps", "target": 6000}}}).expect(http.StatusOK)
	if got := h.get("/api/goals/proposals", nick.Token).expect(http.StatusOK); got.length("proposals") != 0 {
		t.Fatalf("after a manual edit to the suggestion = %s", got.Body)
	}
}

func TestDismissedProposalStaysGoneForTheWeekAndReturnsNextMonday(t *testing.T) {
	h := newHarness(t)
	nick := h.joinAdmin("Nick", "green")
	h.seedSteps(nick, 1, steady(5000, 14)...)
	h.get("/api/goals/proposals", nick.Token).expect(http.StatusOK)

	h.post("/api/goals/proposals/steps/dismiss", nick.Token, nil).expect(http.StatusNoContent)
	for range 2 {
		if got := h.get("/api/goals/proposals", nick.Token).expect(http.StatusOK); got.length("proposals") != 0 {
			t.Fatalf("dismissed proposal came back: %s", got.Body)
		}
	}
	h.post("/api/goals/proposals/steps/dismiss", nick.Token, nil).expect(http.StatusNotFound).code("not_found")
	h.post("/api/goals/proposals/steps/accept", nick.Token, nil).expect(http.StatusNotFound).code("not_found")

	h.clock.Set(ny(2026, time.November, 9, 8, 0))
	h.seedMetric(nick, "steps", 0, 5000)
	next := h.get("/api/goals/proposals", nick.Token).expect(http.StatusOK)
	if next.str("week") != "2026-W46" || next.length("proposals") != 1 {
		t.Fatalf("next week = %s", next.Body)
	}
}

func TestAcceptingAppliesFromTomorrowLikeAPatch(t *testing.T) {
	h := newHarness(t)
	nick := h.joinAdmin("Nick", "green")
	// A day after joining, so the join-day exception does not apply.
	h.clock.Set(ny(2026, time.November, 3, 12, 0))
	h.seedSteps(nick, 1, steady(5000, 14)...)

	h.get("/api/goals/proposals", nick.Token).expect(http.StatusOK)
	me := h.post("/api/goals/proposals/steps/accept", nick.Token, nil).expect(http.StatusOK)
	if templateTarget(me, "steps") != 6000 {
		t.Fatalf("template after accept = %s", me.Body)
	}
	today := h.get("/api/today", nick.Token).expect(http.StatusOK)
	if today.num("quests.0.target") != 8000 {
		t.Fatalf("today keeps its frozen target: %s", today.Body)
	}
	h.clock.Set(ny(2026, time.November, 4, 12, 0))
	if tomorrow := h.get("/api/today", nick.Token); tomorrow.num("quests.0.target") != 6000 {
		t.Fatalf("tomorrow = %s", tomorrow.Body)
	}

	if got := h.get("/api/goals/proposals", nick.Token); got.length("proposals") != 0 {
		t.Fatalf("accepted proposal listed again: %s", got.Body)
	}
	h.post("/api/goals/proposals/steps/accept", nick.Token, nil).expect(http.StatusNotFound)
	h.post("/api/goals/proposals/nonsense/accept", nick.Token, nil).expect(http.StatusNotFound)
}

func TestAcceptingOnTheJoinDayAppliesToday(t *testing.T) {
	h := newHarness(t)
	nick := h.joinAdmin("Nick", "green")
	h.seedSteps(nick, 1, steady(5000, 14)...)
	h.get("/api/goals/proposals", nick.Token).expect(http.StatusOK)
	h.post("/api/goals/proposals/steps/accept", nick.Token, nil).expect(http.StatusOK)
	if today := h.get("/api/today", nick.Token); today.num("quests.0.target") != 6000 {
		t.Fatalf("join day = %s", today.Body)
	}
}

func TestSleepProposalMovesTheTargetTowardTheAverage(t *testing.T) {
	h := newHarness(t)
	nick := h.joinAdmin("Nick", "green")
	h.patch("/api/me", nick.Token, obj{"questTemplates": []obj{{"key": "sleep", "enabled": true, "target": 480}}}).expect(http.StatusOK)
	var nights []obj
	for day := 20; day <= 31; day++ {
		nights = append(nights, sleepNight(day, time.October, 365))
	}
	nights = append(nights, sleepNight(1, time.November, 365), sleepNight(2, time.November, 365))
	putSleep(h, nick, nights...).expect(http.StatusOK)

	got := h.get("/api/goals/proposals", nick.Token).expect(http.StatusOK)
	var sleep int = -1
	for i := range got.length("proposals") {
		if got.str(fmt.Sprintf("proposals.%d.key", i)) == "sleep" {
			sleep = i
		}
	}
	if sleep < 0 {
		t.Fatalf("no sleep proposal: %s", got.Body)
	}
	p := fmt.Sprintf("proposals.%d.", sleep)
	if got.num(p+"current") != 480 || got.num(p+"proposed") != 420 ||
		got.str(p+"reason") != "You averaged 6 h 05 over the last 14 nights, 1 h 55 under your 8 h target. 7 h is a step toward it." {
		t.Fatalf("sleep proposal = %s", got.Body)
	}
	me := h.post("/api/goals/proposals/sleep/accept", nick.Token, nil).expect(http.StatusOK)
	if templateTarget(me, "sleep") != 420 {
		t.Fatalf("me = %s", me.Body)
	}
}

func TestNoProposalForAQuestThatIsOff(t *testing.T) {
	h := newHarness(t)
	nick := h.joinAdmin("Nick", "green")
	h.patch("/api/me", nick.Token, obj{"questTemplates": []obj{{"key": "steps", "enabled": false}}}).expect(http.StatusOK)
	h.seedSteps(nick, 1, steady(5000, 14)...)
	if got := h.get("/api/goals/proposals", nick.Token); got.length("proposals") != 0 {
		t.Fatalf("proposals = %s", got.Body)
	}
}

func TestNewNotificationPreferencesDefaultOnAndPatchIndependently(t *testing.T) {
	h := newHarness(t)
	nick, nadia := h.pair()
	me := h.get("/api/me", nick.Token).expect(http.StatusOK)
	for _, k := range []string{"closeToDone", "morningPlan", "weeklyRecap", "partnerDone"} {
		if !me.flag("notifications." + k) {
			t.Fatalf("%s should default on: %s", k, me.Body)
		}
	}
	for _, k := range []string{"behindPace", "windDown"} {
		if me.flag("notifications." + k) {
			t.Fatalf("%s should default off: %s", k, me.Body)
		}
	}
	got := h.patch("/api/me", nick.Token, obj{"notifications": obj{"windDown": true, "morningPlan": false}}).expect(http.StatusOK)
	if !got.flag("notifications.windDown") || got.flag("notifications.morningPlan") || got.flag("notifications.behindPace") ||
		!got.flag("notifications.closeToDone") || !got.flag("notifications.weeklyRecap") {
		t.Fatalf("notifications = %s", got.Body)
	}
	if other := h.get("/api/me", nadia.Token); other.flag("notifications.windDown") {
		t.Fatal("preferences are per person")
	}
	h.patch("/api/me", nick.Token, obj{"notifications": obj{"nope": true}}).expect(http.StatusBadRequest)
}

func TestStepsGoalIsOnlyRaisedAfterTenGoodDaysOfFourteen(t *testing.T) {
	h := newHarness(t)
	nick := h.joinAdmin("Nick", "green")
	// Walking 9,000 a day against an 8,000 goal: the suggestion is 10,000, but only 9 of the 14
	// days reached the goal (five were just under it), so no raise yet.
	days := append(steady(9000, 9), steady(7900, 5)...)
	h.seedSteps(nick, 1, days...)
	if got := h.get("/api/goals/proposals", nick.Token); got.length("proposals") != 0 {
		t.Fatalf("raise after 9 good days: %s", got.Body)
	}

	h2 := newHarness(t)
	nadia := h2.joinAdmin("Nadia", "violet")
	h2.seedSteps(nadia, 1, append(steady(9000, 10), steady(7900, 4)...)...)
	got := h2.get("/api/goals/proposals", nadia.Token).expect(http.StatusOK)
	if got.length("proposals") != 1 || got.num("proposals.0.proposed") <= got.num("proposals.0.current") {
		t.Fatalf("raise after 10 good days: %s", got.Body)
	}
}
