package api

import (
	"net/http"
	"testing"
	"time"

	"github.com/nc1107/new-me/server/internal/db"
	"github.com/nc1107/new-me/server/internal/engine"
)

func TestTodayReportsFreezesRepairAndAway(t *testing.T) {
	h := newHarness(t)
	nick := h.joinAdmin("Nick", "green")
	got := h.get("/api/today", nick.Token).expect(http.StatusOK)
	if got.num("freezes.held") != 2 || got.num("freezes.earnedTowardNext") != 0 || !got.isNull("repair") ||
		got.flag("away.today") || got.length("away.upcoming") != 0 || !got.isNull("away.current") ||
		got.length("newMilestones") != 0 {
		t.Fatalf("today = %s", got.Body)
	}
}

func TestAwayRules(t *testing.T) {
	h := newHarness(t)
	nick, nadia := h.pair()
	day := func(offset int) string { return ny(2026, time.November, 2+offset, 12, 0).Format(time.DateOnly) }
	create := func(from, to string) *response {
		return h.post("/api/away", nick.Token, obj{"from": from, "to": to, "note": "trip"})
	}

	created := create(day(0), day(2)).expect(http.StatusCreated)
	if created.str("away.from") != day(0) || created.str("away.to") != day(2) || created.str("away.note") != "trip" ||
		!created.flag("state.today") || created.num("state.current.id") != created.num("away.id") {
		t.Fatalf("created = %s", created.Body)
	}
	today := h.get("/api/today", nick.Token).expect(http.StatusOK)
	if !today.flag("away.today") || today.str("away.current.to") != day(2) {
		t.Fatalf("today = %s", today.Body)
	}

	h.post("/api/away", nick.Token, obj{"from": day(2), "to": day(4)}).expect(http.StatusConflict).code("away_overlap")
	later := create(day(5), day(6)).expect(http.StatusCreated)
	if got := h.get("/api/today", nick.Token).expect(http.StatusOK); got.length("away.upcoming") != 1 ||
		got.str("away.upcoming.0.from") != day(5) {
		t.Fatalf("upcoming = %s", got.Body)
	}

	// The bounds: today to 14 days ahead, 1 to 14 days long.
	h.post("/api/away", nadia.Token, obj{"from": day(-1), "to": day(0)}).expect(http.StatusUnprocessableEntity).code("invalid_request")
	h.post("/api/away", nadia.Token, obj{"from": day(15), "to": day(15)}).expect(http.StatusUnprocessableEntity).code("invalid_request")
	h.post("/api/away", nadia.Token, obj{"from": day(0), "to": day(14)}).expect(http.StatusUnprocessableEntity).code("invalid_request")
	h.post("/api/away", nadia.Token, obj{"from": day(3), "to": day(2)}).expect(http.StatusUnprocessableEntity).code("invalid_request")
	h.post("/api/away", nadia.Token, obj{"from": "soon", "to": day(2)}).expect(http.StatusUnprocessableEntity).code("invalid_request")
	h.post("/api/away", nadia.Token, obj{"from": day(0), "to": day(2), "note": string(make([]byte, 201))}).expect(http.StatusUnprocessableEntity)
	h.post("/api/away", nadia.Token, obj{"from": day(14), "to": day(14)}).expect(http.StatusCreated)
	h.post("/api/away", nadia.Token, obj{"from": day(1), "to": day(14)}).expect(http.StatusConflict)
	h.post("/api/away", nick.Token, obj{"from": day(7), "to": day(7), "extra": 1}).expect(http.StatusBadRequest)

	// Spans are the caller's own.
	h.delete("/api/away/"+itoa(later.num("away.id")), nadia.Token).expect(http.StatusNotFound)
	h.delete("/api/away/"+itoa(later.num("away.id")), nick.Token).expect(http.StatusNoContent)
	h.delete("/api/away/"+itoa(later.num("away.id")), nick.Token).expect(http.StatusNotFound)
	h.delete("/api/away/abc", nick.Token).expect(http.StatusNotFound)
	if got := h.get("/api/today", nick.Token).expect(http.StatusOK); got.length("away.upcoming") != 0 {
		t.Fatalf("upcoming after delete = %s", got.Body)
	}
}

func TestAwayDaysKeepTheStreakAndSpendNoFreeze(t *testing.T) {
	h := newHarness(t)
	h.clock.Set(ny(2026, time.November, 2, 9, 0))
	nick := h.joinAdmin("Nick", "green")
	h.storeScore(nick, "2026-11-02", 300, 0, 400)
	h.post("/api/away", nick.Token, obj{"from": "2026-11-03", "to": "2026-11-05"}).expect(http.StatusCreated)
	// The away days are unscored: no rows were written for them.
	h.storeScore(nick, "2026-11-06", 300, 0, 400)

	h.clock.Set(ny(2026, time.November, 7, 15, 0))
	got := h.get("/api/today", nick.Token).expect(http.StatusOK)
	if got.num("streak.current") != 2 || got.num("freezes.held") != 2 {
		t.Fatalf("today = %s", got.Body)
	}
	board := h.get("/api/board", nick.Token).expect(http.StatusOK)
	away := map[string]bool{}
	for i := range board.length("users.0.last7") {
		p := "users.0.last7." + itoa(i) + "."
		away[board.str(p+"date")] = board.flag(p + "away")
	}
	if !away["2026-11-03"] || !away["2026-11-05"] || away["2026-11-06"] || away["2026-11-02"] {
		t.Fatalf("away marks = %v", away)
	}
}

// brokenWeek stores Monday counted, Tuesday and Wednesday missed (both freezes), Thursday
// counted and Friday missed, so Friday breaks the streak. The clock ends on Friday evening.
func brokenWeek(h *harness, p person) {
	h.storeScore(p, "2026-11-02", 300, 0, 400)
	h.storeScore(p, "2026-11-05", 300, 0, 400)
}

func TestRepairWindowAndRepairByReachingOneHundredPercent(t *testing.T) {
	h := newHarness(t)
	nick := h.joinAdmin("Nick", "green")
	brokenWeek(h, nick)
	h.storeScore(nick, "2026-11-06", 0, 0, 400)

	h.clock.Set(ny(2026, time.November, 7, 12, 0))
	got := h.get("/api/today", nick.Token).expect(http.StatusOK)
	if got.num("streak.current") != 0 || got.num("freezes.held") != 0 {
		t.Fatalf("before the repair = %s", got.Body)
	}
	if got.str("repair.date") != "2026-11-06" || got.str("repair.until") != "2026-11-08T03:00:00Z" || got.num("repair.progressPercent") != 0 {
		t.Fatalf("repair window = %s", got.Body)
	}

	h.logActivity(nick, "pushups", "reps", 30).expect(http.StatusCreated)
	if p := h.get("/api/today", nick.Token).expect(http.StatusOK); p.num("repair.progressPercent") != 33 {
		t.Fatalf("progress = %s", p.Body)
	}
	h.logActivity(nick, "reading", "minutes", 20).expect(http.StatusCreated)
	h.logActivity(nick, "reading", "pages", 15).expect(http.StatusCreated)
	h.logMeal(nick, "Eggs", 300, 50).expect(http.StatusCreated)
	if p := h.get("/api/today", nick.Token).expect(http.StatusOK); p.isNull("repair") || p.num("day.percent") >= 100 {
		t.Fatalf("not at 100%% yet: %s", p.Body)
	}
	// Steps are not in the day until Health has reported them, so the rest is all there is.
	h.logMeal(nick, "Steak", 500, 50).expect(http.StatusCreated)

	done := h.get("/api/today", nick.Token).expect(http.StatusOK)
	if done.num("day.percent") != 100 || !done.isNull("repair") {
		t.Fatalf("repaired = %s", done.Body)
	}
	// Mon counted, Tue and Wed frozen, Thu counted, Fri repaired, Sat counted.
	if done.num("streak.current") != 3 || done.num("freezes.held") != 0 {
		t.Fatalf("streak after repair = %s", done.Body)
	}
	board := h.get("/api/board", nick.Token).expect(http.StatusOK)
	flags := map[string][2]bool{}
	for i := range board.length("users.0.last7") {
		p := "users.0.last7." + itoa(i) + "."
		flags[board.str(p+"date")] = [2]bool{board.flag(p + "frozen"), board.flag(p + "repaired")}
	}
	if flags["2026-11-06"] != [2]bool{true, true} || flags["2026-11-04"] != [2]bool{true, false} || flags["2026-11-05"] != [2]bool{false, false} {
		t.Fatalf("flags = %v", flags)
	}
}

func TestRepairClosesAtTenInTheEvening(t *testing.T) {
	h := newHarness(t)
	nick := h.joinAdmin("Nick", "green")
	brokenWeek(h, nick)
	h.storeScore(nick, "2026-11-06", 0, 0, 400)
	h.clock.Set(ny(2026, time.November, 7, 21, 59))
	if got := h.get("/api/today", nick.Token).expect(http.StatusOK); got.isNull("repair") {
		t.Fatalf("still open at 21:59: %s", got.Body)
	}
	h.clock.Set(ny(2026, time.November, 7, 22, 0))
	if got := h.get("/api/today", nick.Token).expect(http.StatusOK); !got.isNull("repair") {
		t.Fatalf("closed at 22:00: %s", got.Body)
	}
	// Finishing everything now is too late.
	h.logActivity(nick, "pushups", "reps", 30).expect(http.StatusCreated)
	h.logActivity(nick, "reading", "minutes", 20).expect(http.StatusCreated)
	h.logActivity(nick, "reading", "pages", 15).expect(http.StatusCreated)
	h.logMeal(nick, "Eggs", 300, 100).expect(http.StatusCreated)
	h.logMeal(nick, "Steak", 500, 20).expect(http.StatusCreated)
	got := h.get("/api/today", nick.Token).expect(http.StatusOK)
	if got.num("day.percent") != 100 || got.num("streak.current") != 1 {
		t.Fatalf("a late finish repairs nothing: %s", got.Body)
	}
}

func TestNoRepairWhenYesterdayWasFrozenOrCounted(t *testing.T) {
	h := newHarness(t)
	nick := h.joinAdmin("Nick", "green")
	h.storeScore(nick, "2026-11-02", 300, 0, 400)
	h.storeScore(nick, "2026-11-03", 0, 0, 400)
	h.clock.Set(ny(2026, time.November, 4, 12, 0))
	if got := h.get("/api/today", nick.Token).expect(http.StatusOK); !got.isNull("repair") {
		t.Fatalf("a freeze covered it: %s", got.Body)
	}
	h.storeScore(nick, "2026-11-04", 300, 0, 400)
	h.clock.Set(ny(2026, time.November, 5, 12, 0))
	if got := h.get("/api/today", nick.Token).expect(http.StatusOK); !got.isNull("repair") {
		t.Fatalf("it counted: %s", got.Body)
	}
}

// coverScene is Saturday 09:00 with Nick counted all week and Nadia out of freezes with
// yesterday (Friday) still open.
func coverScene(t *testing.T) (*harness, person, person) {
	h := newHarness(t)
	nick, nadia := h.pair()
	for _, d := range []string{"2026-11-02", "2026-11-03", "2026-11-04", "2026-11-05", "2026-11-06"} {
		h.storeScore(nick, d, 300, 0, 400)
	}
	h.storeScore(nadia, "2026-11-02", 300, 0, 400)
	h.storeScore(nadia, "2026-11-05", 300, 0, 400)
	h.clock.Set(ny(2026, time.November, 7, 9, 0))
	return h, nick, nadia
}

func TestPartnerCoverSpendsTheCoverersFreezeAndKeepsBothStreaks(t *testing.T) {
	n := &capture{}
	h := newHarness(t, withPush(n))
	nick, nadia := h.pair()
	for _, d := range []string{"2026-11-02", "2026-11-03", "2026-11-04", "2026-11-05", "2026-11-06"} {
		h.storeScore(nick, d, 300, 0, 400)
	}
	h.storeScore(nadia, "2026-11-02", 300, 0, 400)
	h.storeScore(nadia, "2026-11-05", 300, 0, 400)
	h.clock.Set(ny(2026, time.November, 7, 9, 0))

	before := h.get("/api/board", nick.Token).expect(http.StatusOK)
	if before.num("sharedStreak.current") != 4 || before.num("users.1.freezes.held") != 0 || before.num("users.0.freezes.held") != 2 {
		t.Fatalf("before = %s", before.Body)
	}
	// Today (Saturday) and two days ago cannot be covered, nor a day that counted.
	h.post("/api/streak/cover", nick.Token, obj{"date": "2026-11-07"}).expect(http.StatusUnprocessableEntity).code("cover_closed")
	h.post("/api/streak/cover", nick.Token, obj{"date": "2026-11-05"}).expect(http.StatusUnprocessableEntity).code("cover_closed")
	h.post("/api/streak/cover", nick.Token, obj{"date": "someday"}).expect(http.StatusUnprocessableEntity).code("invalid_request")
	h.post("/api/streak/cover", nadia.Token, obj{"date": "2026-11-06"}).expect(http.StatusUnprocessableEntity).code("cover_closed")

	covered := h.post("/api/streak/cover", nick.Token, obj{"date": "2026-11-06"}).expect(http.StatusCreated)
	if int64(covered.num("covered")) != nadia.ID || covered.str("date") != "2026-11-06" || covered.num("freezes.held") != 1 {
		t.Fatalf("covered = %s", covered.Body)
	}
	if got := n.of("cover", nadia.ID); len(got) != 1 || got[0].Title != "Nick covered your day" {
		t.Fatalf("push = %+v", n.msgs)
	}
	h.post("/api/streak/cover", nick.Token, obj{"date": "2026-11-06"}).expect(http.StatusConflict)

	nadiaToday := h.get("/api/today", nadia.Token).expect(http.StatusOK)
	if nadiaToday.num("streak.current") != 2 || nadiaToday.num("freezes.held") != 0 {
		t.Fatalf("nadia = %s", nadiaToday.Body)
	}
	after := h.get("/api/board", nick.Token).expect(http.StatusOK)
	if after.num("users.0.freezes.held") != 1 || after.num("users.0.streak.current") != 5 {
		t.Fatalf("nick = %s", after.Body)
	}
	// Friday is frozen for Nadia and Nick counted, so it is a fifth day for the couple.
	if after.num("sharedStreak.current") != 5 {
		t.Fatalf("shared = %s", after.Body)
	}
	flags := map[string]bool{}
	for i := range after.length("users.1.last7") {
		p := "users.1.last7." + itoa(i) + "."
		flags[after.str(p+"date")] = after.flag(p + "frozen")
	}
	if !flags["2026-11-06"] {
		t.Fatalf("Nadia's Friday is frozen: %v", flags)
	}
}

func TestCoverNeedsAFreezeOfYourOwn(t *testing.T) {
	h, nick, _ := coverScene(t)
	// Two unscored days spend both of Nick's freezes.
	h.sql(`DELETE FROM day_scores WHERE user_id = $1 AND local_date IN ('2026-11-03', '2026-11-04')`, nick.ID)
	h.post("/api/streak/cover", nick.Token, obj{"date": "2026-11-06"}).expect(http.StatusUnprocessableEntity).code("no_freeze")
}

func TestCoverIsRefusedWhileThePartnerHasAFreeze(t *testing.T) {
	h, nick, nadia := coverScene(t)
	// Nadia counted Tuesday and Wednesday as well, so she still holds both freezes.
	h.storeScore(nadia, "2026-11-03", 300, 0, 400)
	h.storeScore(nadia, "2026-11-04", 300, 0, 400)
	h.post("/api/streak/cover", nick.Token, obj{"date": "2026-11-06"}).expect(http.StatusUnprocessableEntity).code("cover_closed")
}

func TestCoverClosesWithTheGraceWindow(t *testing.T) {
	h, nick, _ := coverScene(t)
	h.clock.Set(ny(2026, time.November, 7, 10, 0))
	h.post("/api/streak/cover", nick.Token, obj{"date": "2026-11-06"}).expect(http.StatusUnprocessableEntity).code("cover_closed")
}

func TestCoverIsRefundedWhenTheDayIsFilledIn(t *testing.T) {
	h, nick, nadia := coverScene(t)
	h.post("/api/streak/cover", nick.Token, obj{"date": "2026-11-06"}).expect(http.StatusCreated)
	// Nadia logs a full Friday before the window closes, so the cover was not needed.
	h.storeScore(nadia, "2026-11-06", 300, 0, 400)
	h.clock.Set(ny(2026, time.November, 7, 11, 0))
	nadiaStreak := func() *response { return h.get("/api/today", nadia.Token).expect(http.StatusOK) }
	if got := nadiaStreak(); got.num("streak.current") != 3 {
		t.Fatalf("nadia = %s", got.Body)
	}
	// Settling happens in the scheduler; run it for both people.
	for _, p := range []person{nick, nadia} {
		user, err := db.GetUser(t.Context(), h.db.Pool, p.ID)
		if err != nil {
			t.Fatal(err)
		}
		if err := engine.SettleStreaks(t.Context(), h.db.Pool, user, h.clock.Now(), newYork); err != nil {
			t.Fatal(err)
		}
	}
	if h.get("/api/board", nick.Token).expect(http.StatusOK).num("users.0.freezes.held") != 2 {
		t.Fatal("the unused cover must give the freeze back")
	}
}

func TestSharedStreakCountsDaysBothCountedFrozenOrAway(t *testing.T) {
	h := newHarness(t)
	nick, nadia := h.pair()
	for _, d := range []string{"2026-11-02", "2026-11-03", "2026-11-04"} {
		h.storeScore(nick, d, 300, 0, 400)
		h.storeScore(nadia, d, 300, 0, 400)
	}
	h.clock.Set(ny(2026, time.November, 5, 12, 0))
	got := h.get("/api/board", nick.Token).expect(http.StatusOK)
	if got.num("sharedStreak.current") != 3 || got.num("sharedStreak.best") != 3 {
		t.Fatalf("shared = %s", got.Body)
	}
	// Nadia misses Thursday and has a freeze, so the day still counts for the couple while Nick counts.
	h.storeScore(nick, "2026-11-05", 300, 0, 400)
	h.clock.Set(ny(2026, time.November, 6, 12, 0))
	got = h.get("/api/board", nick.Token).expect(http.StatusOK)
	if got.num("sharedStreak.current") != 4 || got.num("users.1.freezes.held") != 1 {
		t.Fatalf("a frozen day is kept: %s", got.Body)
	}
}
