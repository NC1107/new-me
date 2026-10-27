package api

import (
	"net/http"
	"testing"
	"time"
)

func TestBoardListsTheCallerFirstAndOnlyThemUntilAPartnerJoins(t *testing.T) {
	h := newHarness(t)
	nick := h.joinAdmin("Nick", "green")
	alone := h.get("/api/board", nick.Token).expect(http.StatusOK)
	if alone.length("users") != 1 || alone.str("users.0.name") != "Nick" || alone.str("season.name") != "Season 0" {
		t.Fatalf("board alone = %s", alone.Body)
	}

	nadia := h.joinMember(h.invite(nick), "Nadia", "violet")
	if got := h.get("/api/board", nadia.Token).expect(http.StatusOK); got.str("users.0.name") != "Nadia" ||
		got.str("users.1.name") != "Nick" || got.str("users.1.color") != "green" {
		t.Fatalf("board for Nadia = %s", got.Body)
	}
	if got := h.get("/api/board", nick.Token).expect(http.StatusOK); got.str("users.0.name") != "Nick" {
		t.Fatalf("board for Nick = %s", got.Body)
	}
}

func TestBoardShowsTodayStreakAndSyncForEachPerson(t *testing.T) {
	h := newHarness(t)
	nick, nadia := h.pair()
	fixtureDay(h, nick)
	h.logActivity(nadia, "pushups", "reps", 15).expect(http.StatusCreated)

	got := h.get("/api/board", nadia.Token).expect(http.StatusOK)
	if got.num("users.0.today.points") != 50 || got.num("users.0.today.percent") != 16 || got.flag("users.0.today.counted") ||
		!got.isNull("users.0.syncedAt") || got.num("users.0.streak.current") != 0 {
		t.Fatalf("Nadia = %s", got.Body)
	}
	if got.num("users.1.today.points") != 336 || got.num("users.1.today.percent") != 76 || !got.flag("users.1.today.counted") ||
		got.isNull("users.1.syncedAt") || got.num("users.1.streak.current") != 1 {
		t.Fatalf("Nick = %s", got.Body)
	}
	if got.num("users.1.week.points") != 336 || got.num("users.1.season.points") != 336 {
		t.Fatalf("Nick totals = %s", got.Body)
	}

	if got.length("users.1.last7") != 7 || got.str("users.1.last7.0.date") != "2026-10-27" ||
		got.str("users.1.last7.6.date") != "2026-11-02" || got.num("users.1.last7.6.percent") != 76 ||
		!got.flag("users.1.last7.6.counted") || got.flag("users.1.last7.6.rest") || got.num("users.1.last7.0.percent") != 0 {
		t.Fatalf("Nick last7 = %s", got.Body)
	}
}

func TestBoardWeekAndSeasonMathAcrossNewYear(t *testing.T) {
	h := newHarness(t)
	h.clock.Set(ny(2026, time.December, 20, 12, 0))
	nick := h.joinAdmin("Nick", "green")

	// Mon 2026-12-28 .. Sun 2027-01-03 is one ISO week that straddles the season change.
	h.storeScore(nick, "2026-12-14", 400, 40, 400)
	h.storeScore(nick, "2026-12-28", 300, 30, 400)
	h.storeScore(nick, "2026-12-29", 200, 0, 400)
	h.storeScore(nick, "2026-12-31", 100, 0, 400)
	h.storeScore(nick, "2027-01-01", 360, 20, 400)
	h.storeScore(nick, "2027-01-02", 280, 0, 400)

	type totals struct{ week, season int }
	check := func(label string, at time.Time, season string, startsOn string, want totals) {
		t.Helper()
		h.clock.Set(at)
		got := h.get("/api/board", nick.Token).expect(http.StatusOK)
		if got.str("season.name") != season || got.str("season.startsOn") != startsOn {
			t.Fatalf("%s: season = %s", label, got.Body)
		}
		have := totals{got.num("users.0.week.points"), got.num("users.0.season.points")}
		if have != want {
			t.Fatalf("%s: week/season = %v, want %v; body: %s", label, have, want, got.Body)
		}
	}

	// Season 0 on Dec 31: the week so far is Mon-Thu, and the season holds everything since 1 Jan 2026.
	check("Dec 31", ny(2026, time.December, 31, 12, 0), "Season 0", "2026-01-01",
		totals{week: 330 + 200 + 100, season: 440 + 330 + 200 + 100})
	// Season 1 on Jan 1: the week shows only the 2027 days, and everyone starts at zero.
	check("Jan 1", ny(2027, time.January, 1, 12, 0), "Season 1", "2027-01-01",
		totals{week: 380, season: 380})
	check("Jan 2", ny(2027, time.January, 2, 12, 0), "Season 1", "2027-01-01",
		totals{week: 380 + 280, season: 380 + 280})
	check("Jan 4", ny(2027, time.January, 4, 12, 0), "Season 1", "2027-01-01",
		totals{week: 0, season: 380 + 280})
}

func TestBoardSeasonEndIsNullOnlyForTheOpenSeason(t *testing.T) {
	h := newHarness(t)
	nick := h.joinAdmin("Nick", "green")
	got := h.get("/api/board", nick.Token).expect(http.StatusOK)
	if got.str("season.endsOn") != "2026-12-31" {
		t.Fatalf("season 0 = %s", got.Body)
	}
	h.clock.Set(ny(2027, time.January, 2, 12, 0))
	if !h.get("/api/board", nick.Token).isNull("season.endsOn") {
		t.Fatal("season 1 is open ended")
	}
}

func TestBoardBeforeTheFirstSeasonShowsTheUpcomingOne(t *testing.T) {
	h := newHarness(t)
	nick := h.joinAdmin("Nick", "green")
	h.sql(`UPDATE seasons SET starts_on = '2026-11-03' WHERE name = 'Season 0'`)
	got := h.get("/api/board", nick.Token).expect(http.StatusOK)
	if got.str("season.name") != "Season 0" || got.num("users.0.season.points") != 0 || got.num("users.0.week.points") != 0 {
		t.Fatalf("board before the season = %s", got.Body)
	}
}

func TestBoardMarksTheFrozenDay(t *testing.T) {
	h := newHarness(t)
	h.clock.Set(ny(2026, time.November, 2, 9, 0))
	nick := h.joinAdmin("Nick", "green")
	h.storeScore(nick, "2026-11-02", 300, 0, 400)
	h.storeScore(nick, "2026-11-03", 300, 0, 400)
	h.storeScore(nick, "2026-11-05", 300, 0, 400)

	h.clock.Set(ny(2026, time.November, 6, 15, 0))
	got := h.get("/api/board", nick.Token).expect(http.StatusOK)
	if got.num("users.0.streak.current") != 3 {
		t.Fatalf("board = %s", got.Body)
	}
	marks := map[string]bool{}
	for i := range got.length("users.0.last7") {
		p := "users.0.last7." + itoa(i) + "."
		marks[got.str(p+"date")] = got.flag(p + "frozen")
	}
	if !marks["2026-11-04"] || marks["2026-11-05"] || marks["2026-11-03"] {
		t.Fatalf("frozen marks = %v; the missed Wednesday is the frozen day", marks)
	}
}
