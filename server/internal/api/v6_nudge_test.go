package api

import (
	"context"
	"net/http"
	"strings"
	"testing"
	"time"

	"github.com/nc1107/new-me/server/internal/nudge"
	"github.com/nc1107/new-me/server/internal/recap"
	"github.com/nc1107/new-me/server/internal/together"
)

func (h *harness) nudges() *nudge.Service {
	return &nudge.Service{DB: h.db, Together: h.srv.together, Polisher: h.srv.polisher, Now: h.clock.Now}
}

// enableAllNudges switches on the two kinds that start off.
func (h *harness) enableAllNudges(p person) {
	h.t.Helper()
	h.patch("/api/me", p.Token, obj{"notifications": obj{"behindPace": true, "windDown": true}}).expect(http.StatusOK)
}

func (h *harness) runNudges(at time.Time) {
	h.t.Helper()
	h.clock.Set(at)
	if err := h.nudges().Run(context.Background()); err != nil {
		h.t.Fatalf("nudges at %s: %v", at, err)
	}
}

func (c *capture) count() int {
	c.mu.Lock()
	defer c.mu.Unlock()
	return len(c.msgs)
}

func TestBehindPaceNudgesOncePerWindowAndOnlyWhenBehind(t *testing.T) {
	push := &capture{}
	h := newHarness(t, withPush(push))
	nick, nadia := h.pair()
	h.enableAllNudges(nick)
	h.enableAllNudges(nadia)
	h.seedSteps(nick, 1, steady(8000, 14)...)
	h.seedSteps(nadia, 1, steady(8000, 14)...)

	h.putHealth(nick, "2026-11-02", "steps", 1000).expect(http.StatusOK)
	h.putHealth(nadia, "2026-11-02", "steps", 4000).expect(http.StatusOK)
	h.runNudges(ny(2026, time.November, 2, 13, 55))
	if push.count() != 0 {
		t.Fatalf("nothing is due before 14:00: %+v", push.msgs)
	}

	h.runNudges(ny(2026, time.November, 2, 14, 5))
	got := push.of(together.EventBehindPaceAfternoon, nick.ID)
	if len(got) != 1 || got[0].Title != "Steps to go" ||
		got[0].Body != "7,000 steps to go. Even a 30-minute walk gets you most of the way." {
		t.Fatalf("Nick's nudge = %+v", got)
	}
	if len(push.of(together.EventBehindPaceAfternoon, nadia.ID)) != 0 {
		t.Fatal("Nadia is on pace and must not be nudged")
	}

	h.runNudges(ny(2026, time.November, 2, 14, 10))
	h.runNudges(ny(2026, time.November, 2, 15, 50))
	if len(push.of(together.EventBehindPaceAfternoon, nick.ID)) != 1 {
		t.Fatal("the window sends once")
	}

	h.putHealth(nick, "2026-11-02", "steps", 3000).expect(http.StatusOK)
	h.putHealth(nadia, "2026-11-02", "steps", 8100).expect(http.StatusOK)
	h.runNudges(ny(2026, time.November, 2, 18, 35))
	evening := push.of(together.EventBehindPaceEvening, nick.ID)
	if len(evening) != 1 || evening[0].Body != "5,000 steps to go. Even a 30-minute walk gets you most of the way." {
		t.Fatalf("evening = %+v", evening)
	}

	// Done means no nudge in any window.
	if len(push.of(together.EventBehindPaceEvening, nadia.ID)) != 0 {
		t.Fatal("never after the steps quest is done")
	}
}

func TestBehindPaceNudgeRespectsThePreferenceAndQuietHours(t *testing.T) {
	push := &capture{}
	h := newHarness(t, withPush(push))
	nick := h.joinAdmin("Nick", "green")
	h.seedSteps(nick, 1, steady(8000, 14)...)
	h.putHealth(nick, "2026-11-02", "steps", 100).expect(http.StatusOK)

	h.runNudges(ny(2026, time.November, 2, 14, 5))
	if push.count() != 0 {
		t.Fatalf("behind pace starts off: %+v", push.msgs)
	}
	h.patch("/api/me", nick.Token, obj{"notifications": obj{"behindPace": false}}).expect(http.StatusOK)
	h.runNudges(ny(2026, time.November, 2, 14, 5))
	if push.count() != 0 {
		t.Fatalf("preference off: %+v", push.msgs)
	}

	h.patch("/api/me", nick.Token, obj{"notifications": obj{"behindPace": true}}).expect(http.StatusOK)
	h.runNudges(ny(2026, time.November, 2, 22, 0))
	h.runNudges(ny(2026, time.November, 3, 5, 0))
	if push.count() != 0 {
		t.Fatalf("quiet hours: %+v", push.msgs)
	}
	// The day the window was missed in does not carry over.
	h.runNudges(ny(2026, time.November, 3, 14, 5))
	if push.count() != 0 {
		t.Fatalf("a new day with no steps yet synced must stay quiet: %+v", push.msgs)
	}
}

func TestCloseToDoneNudgeOnceADay(t *testing.T) {
	push := &capture{}
	h := newHarness(t, withPush(push))
	nick := h.joinAdmin("Nick", "green")
	h.putHealth(nick, "2026-11-02", "steps", 8200).expect(http.StatusOK)
	h.logActivity(nick, "reading", "minutes", 20).expect(http.StatusCreated)
	h.logMeal(nick, "Eggs", 300, 20).expect(http.StatusCreated)
	h.logMeal(nick, "Rice", 400, 10).expect(http.StatusCreated)

	h.runNudges(ny(2026, time.November, 2, 16, 0))
	got := push.of(together.EventCloseToDone, nick.ID)
	if len(got) != 1 || got[0].Title != "Almost there" || got[0].Body != "70 g more protein would make today count." {
		t.Fatalf("close to done = %+v", got)
	}
	h.runNudges(ny(2026, time.November, 2, 16, 5))
	if len(push.of(together.EventCloseToDone, nick.ID)) != 1 {
		t.Fatal("once a day")
	}

	h.logMeal(nick, "Steak", 500, 75).expect(http.StatusCreated)
	h.runNudges(ny(2026, time.November, 3, 16, 0))
	if len(push.of(together.EventCloseToDone, nick.ID)) != 1 {
		t.Fatal("a new day starts from nothing and is far from done")
	}
}

func TestMorningPlanPushCarriesReadinessAndThePlan(t *testing.T) {
	push := &capture{}
	h := newHarness(t, withPush(push))
	nick := h.joinAdmin("Nick", "green")
	putSleep(h, nick, sleepNight(2, time.November, 330)).expect(http.StatusOK)

	h.runNudges(ny(2026, time.November, 2, 7, 59))
	if push.count() != 0 {
		t.Fatal("too early")
	}
	h.runNudges(ny(2026, time.November, 2, 8, 0))
	got := push.of(together.EventMorningPlan, nick.ID)
	if len(got) != 1 || got[0].Title != "Take it easy today" ||
		!strings.HasPrefix(got[0].Body, "Slept 5 h 30, 1 h 30 under your target. 0 of 4 quests done.") {
		t.Fatalf("morning plan = %+v", got)
	}
	h.runNudges(ny(2026, time.November, 2, 8, 5))
	if len(push.of(together.EventMorningPlan, nick.ID)) != 1 {
		t.Fatal("once a day")
	}

	h.patch("/api/me", nick.Token, obj{"notifications": obj{"morningPlan": false}}).expect(http.StatusOK)
	h.runNudges(ny(2026, time.November, 3, 8, 0))
	if len(push.of(together.EventMorningPlan, nick.ID)) != 1 {
		t.Fatal("preference off")
	}
}

func TestMorningPlanWaitsForTheUsualWakeTime(t *testing.T) {
	push := &capture{}
	h := newHarness(t, withPush(push))
	nick := h.joinAdmin("Nick", "green")
	// In bed at 23:00 for 9 h 30 asleep, so awake at 09:00 every morning: the push is due at 09:30.
	var nights []obj
	for day := 28; day <= 31; day++ {
		nights = append(nights, sleepNight(day, time.October, 570))
	}
	// The night of November 1 is skipped: the clocks went back that night, which moves its wake time.
	nights = append(nights, sleepNight(2, time.November, 570))
	putSleep(h, nick, nights...).expect(http.StatusOK)

	h.runNudges(ny(2026, time.November, 2, 9, 29))
	if push.count() != 0 {
		t.Fatalf("before wake plus 30: %+v", push.msgs)
	}
	h.runNudges(ny(2026, time.November, 2, 9, 30))
	if len(push.of(together.EventMorningPlan, nick.ID)) != 1 {
		t.Fatalf("at wake plus 30: %+v", push.msgs)
	}
}

func TestWindDownNudgeOnlyAfterAShortNightAndEvenInQuietHours(t *testing.T) {
	push := &capture{}
	h := newHarness(t, withPush(push))
	nick := h.joinAdmin("Nick", "green")
	h.enableAllNudges(nick)
	h.patch("/api/me", nick.Token, obj{"questTemplates": []obj{{"key": "sleep", "enabled": true, "target": 450}}}).expect(http.StatusOK)
	// Every night is 6 h 20 asleep, in bed at 23:00 and awake at 05:50: the target of 7 h 30
	// means bed by 22:20, so the nudge comes at 21:35.
	var nights []obj
	for day := 28; day <= 31; day++ {
		nights = append(nights, sleepNight(day, time.October, 380))
	}
	nights = append(nights, sleepNight(2, time.November, 380))
	putSleep(h, nick, nights...).expect(http.StatusOK)

	h.runNudges(ny(2026, time.November, 2, 21, 34))
	if len(push.of(together.EventWindDown, nick.ID)) != 0 {
		t.Fatal("before the nudge time")
	}
	h.runNudges(ny(2026, time.November, 2, 21, 40))
	got := push.of(together.EventWindDown, nick.ID)
	if len(got) != 1 || got[0].Title != "Wind down" || got[0].Body != "Bed by 22:20 for 7 h 30." {
		t.Fatalf("wind down = %+v", got)
	}
	h.runNudges(ny(2026, time.November, 2, 21, 50))
	if len(push.of(together.EventWindDown, nick.ID)) != 1 {
		t.Fatal("once a day")
	}

	// A good night means no wind down the next evening.
	h.clock.Set(ny(2026, time.November, 3, 8, 0))
	putSleep(h, nick, sleepNight(3, time.November, 470)).expect(http.StatusOK)
	h.runNudges(ny(2026, time.November, 3, 21, 40))
	if len(push.of(together.EventWindDown, nick.ID)) != 1 {
		t.Fatalf("last night met the target: %+v", push.msgs)
	}
}

func TestNudgesDoNothingWithoutPush(t *testing.T) {
	h := newHarness(t)
	nick := h.joinAdmin("Nick", "green")
	h.enableAllNudges(nick)
	h.seedSteps(nick, 1, steady(8000, 14)...)
	h.putHealth(nick, "2026-11-02", "steps", 100).expect(http.StatusOK)
	h.runNudges(ny(2026, time.November, 2, 14, 5))
	var claimed int
	if err := h.db.Pool.QueryRow(context.Background(), `SELECT count(*) FROM notice_log WHERE kind LIKE 'nudge_%'`).Scan(&claimed); err != nil || claimed != 0 {
		t.Fatalf("with push off nothing may be claimed: %d, %v", claimed, err)
	}
}

func TestWeeklyRecapPushOnSundayEveningOnce(t *testing.T) {
	push := &capture{}
	h := newHarness(t, withPush(push))
	h.clock.Set(ny(2026, time.October, 26, 12, 0))
	nick, nadia := h.pair()
	h.storeScore(nick, "2026-10-26", 300, 40, 400)
	h.storeScore(nadia, "2026-10-27", 200, 0, 400)
	h.clock.Set(ny(2026, time.November, 2, 12, 0))
	h.seedSteps(nick, 1, steady(6000, 6)...)

	svc := &recap.Service{DB: h.db, Together: h.srv.together, Now: h.clock.Now}
	run := func(at time.Time) {
		h.clock.Set(at)
		if err := svc.PushDue(context.Background(), at); err != nil {
			t.Fatal(err)
		}
	}
	run(ny(2026, time.November, 1, 18, 59))
	if push.count() != 0 {
		t.Fatal("before 19:00")
	}
	run(ny(2026, time.October, 31, 19, 0))
	if push.count() != 0 {
		t.Fatal("not Sunday")
	}
	run(ny(2026, time.November, 1, 19, 0))
	run(ny(2026, time.November, 1, 20, 0))
	mine, hers := push.of(together.EventWeeklyRecap, nick.ID), push.of(together.EventWeeklyRecap, nadia.ID)
	if len(mine) != 1 || len(hers) != 1 || mine[0].Title != "Your week" {
		t.Fatalf("pushes = %+v", push.msgs)
	}
	if !strings.HasPrefix(mine[0].Body, "340 points, 1 counted day, 36,000 steps.") || !strings.HasSuffix(mine[0].Body, "Together: 540 points.") {
		t.Fatalf("Nick's line = %q", mine[0].Body)
	}
	if !strings.HasPrefix(hers[0].Body, "200 points, 0 counted days, 0 steps.") {
		t.Fatalf("Nadia's line = %q", hers[0].Body)
	}

	h.patch("/api/me", nick.Token, obj{"notifications": obj{"weeklyRecap": false}}).expect(http.StatusOK)
	run(ny(2026, time.November, 8, 19, 0))
	if len(push.of(together.EventWeeklyRecap, nick.ID)) != 1 || len(push.of(together.EventWeeklyRecap, nadia.ID)) != 2 {
		t.Fatalf("the preference is per person: %+v", push.msgs)
	}
}

func TestDailyBudgetIsTwoAndPrioritizesCloseToDoneThenBehindPaceThenWindDown(t *testing.T) {
	push := &capture{}
	h := newHarness(t, withPush(push))
	nick := h.joinAdmin("Nick", "green")
	h.enableAllNudges(nick)
	h.seedSteps(nick, 1, steady(8000, 14)...)
	h.putHealth(nick, "2026-11-02", "steps", 1000).expect(http.StatusOK)

	h.runNudges(ny(2026, time.November, 2, 8, 0))
	if len(push.of(together.EventMorningPlan, nick.ID)) != 1 {
		t.Fatalf("morning plan is the first push: %+v", push.msgs)
	}
	h.runNudges(ny(2026, time.November, 2, 14, 5))
	if len(push.of(together.EventBehindPaceAfternoon, nick.ID)) != 1 {
		t.Fatal("second push of the day")
	}
	// The budget of two is spent: no evening steps push and no close to done.
	h.logActivity(nick, "reading", "minutes", 20).expect(http.StatusCreated)
	h.logMeal(nick, "Eggs", 300, 100).expect(http.StatusCreated)
	h.logMeal(nick, "Rice", 400, 10).expect(http.StatusCreated)
	h.putHealth(nick, "2026-11-02", "steps", 2000).expect(http.StatusOK)
	h.runNudges(ny(2026, time.November, 2, 18, 35))
	h.runNudges(ny(2026, time.November, 2, 19, 0))
	if push.count() != 2 {
		t.Fatalf("budget exceeded: %+v", push.msgs)
	}
}

func TestMorningPlanOnlyAsTheFirstPushAndCloseToDoneBeatsBehindPace(t *testing.T) {
	push := &capture{}
	h := newHarness(t, withPush(push))
	nick := h.joinAdmin("Nick", "green")
	h.enableAllNudges(nick)
	h.seedSteps(nick, 1, steady(8000, 14)...)
	// Close to done (reading, meals and protein done leaves steps and push-ups) and behind on steps.
	h.logActivity(nick, "reading", "minutes", 20).expect(http.StatusCreated)
	h.logMeal(nick, "Eggs", 300, 100).expect(http.StatusCreated)
	h.logMeal(nick, "Rice", 400, 10).expect(http.StatusCreated)
	h.putHealth(nick, "2026-11-02", "steps", 1000).expect(http.StatusOK)

	// 14:05 with only one slot left in the budget would pick close to done first; here both fit.
	h.runNudges(ny(2026, time.November, 2, 14, 5))
	if len(push.of(together.EventCloseToDone, nick.ID)) != 1 || len(push.of(together.EventBehindPaceAfternoon, nick.ID)) != 1 {
		t.Fatalf("both fit the budget: %+v", push.msgs)
	}
	// Morning plan is no longer allowed once a push went out.
	h.runNudges(ny(2026, time.November, 2, 10, 0))
	if len(push.of(together.EventMorningPlan, nick.ID)) != 0 {
		t.Fatal("morning plan must be the first push of the day")
	}
}

func TestEasyReadinessSilencesPushesToDoMore(t *testing.T) {
	push := &capture{}
	h := newHarness(t, withPush(push))
	nick := h.joinAdmin("Nick", "green")
	h.enableAllNudges(nick)
	h.seedSteps(nick, 1, steady(8000, 14)...)
	h.putHealth(nick, "2026-11-02", "steps", 100).expect(http.StatusOK)
	h.putHealth(nick, "2026-11-02", "sleep_minutes", 300).expect(http.StatusOK)
	if h.get("/api/today", nick.Token).str("readiness.level") != "easy" {
		t.Fatal("fixture should be an easy day")
	}
	h.runNudges(ny(2026, time.November, 2, 14, 5))
	h.runNudges(ny(2026, time.November, 2, 18, 35))
	if push.count() != 0 {
		t.Fatalf("easy day: %+v", push.msgs)
	}
}

func TestRecapPushSkippedWhenTheBudgetIsSpent(t *testing.T) {
	push := &capture{}
	h := newHarness(t, withPush(push))
	h.clock.Set(ny(2026, time.October, 26, 12, 0))
	nick := h.joinAdmin("Nick", "green")
	for _, kind := range []string{together.EventCloseToDone, together.EventMorningPlan} {
		if _, err := h.db.Pool.Exec(context.Background(),
			`INSERT INTO notice_log (kind, user_id, local_date) VALUES ($1, $2, '2026-11-01')`, kind, nick.ID); err != nil {
			t.Fatal(err)
		}
	}
	svc := &recap.Service{DB: h.db, Together: h.srv.together, Now: h.clock.Now}
	h.clock.Set(ny(2026, time.November, 1, 19, 0))
	if err := svc.PushDue(context.Background(), h.clock.Now()); err != nil {
		t.Fatal(err)
	}
	if push.count() != 0 {
		t.Fatalf("recap sent past the budget: %+v", push.msgs)
	}
}
