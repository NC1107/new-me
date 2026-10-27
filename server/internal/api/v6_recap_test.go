package api

import (
	"context"
	"net/http"
	"testing"
	"time"

	"github.com/nc1107/new-me/server/internal/db"
	"github.com/nc1107/new-me/server/internal/score"
)

// recapPair joins the pair on Monday 2026-10-19 and moves the clock to Monday 2026-11-02, so
// the last completed week (2026-W44) lies after they joined.
func recapPair(t *testing.T) (*harness, person, person) {
	h := newHarness(t)
	h.clock.Set(ny(2026, time.October, 19, 12, 0))
	nick, nadia := h.pair()
	h.clock.Set(ny(2026, time.November, 2, 12, 0))

	// W44 is Oct 26 to Nov 1; W43 is Oct 19 to 25.
	h.storeScore(nick, "2026-10-26", 300, 40, 400)
	h.storeScore(nick, "2026-10-27", 100, 0, 400)
	h.storeScore(nick, "2026-10-29", 380, 20, 400)
	h.storeScore(nick, "2026-10-21", 200, 0, 400)
	h.storeScore(nadia, "2026-10-29", 390, 60, 400)
	h.seedSteps(nick, 1, steady(8000, 7)...)
	h.seedSteps(nick, 8, steady(6000, 7)...)
	h.seedSteps(nadia, 1, steady(5000, 7)...)
	putSleep(h, nick,
		sleepNight(27, time.October, 400), sleepNight(28, time.October, 430), sleepNight(29, time.October, 460)).expect(http.StatusOK)
	putWorkouts(h, nick, workout("w1", "strength", ny(2026, time.October, 28, 7, 0), 30)).expect(http.StatusOK)
	_, err := h.db.Pool.Exec(context.Background(),
		`INSERT INTO listening_daily (user_id, local_date, minutes, synced_at) VALUES ($1, '2026-10-30', 45, now())`, nick.ID)
	if err != nil {
		t.Fatal(err)
	}
	if _, err := db.InsertChallenge(context.Background(), h.db.Pool, db.Challenge{
		WeekStart: score.MustDate("2026-10-26"), Kind: "steps", Title: "Walk 90,000 steps together", Target: 90000}); err != nil {
		t.Fatal(err)
	}
	return h, nick, nadia
}

func TestRecapDefaultsToTheLastCompletedWeekForBothPeople(t *testing.T) {
	h, nick, nadia := recapPair(t)
	got := h.get("/api/recap", nick.Token).expect(http.StatusOK)
	if got.str("week") != "2026-W44" || got.str("from") != "2026-10-26" || got.str("to") != "2026-11-01" || !got.flag("complete") {
		t.Fatalf("recap = %s", got.Body)
	}
	if got.length("people") != 2 || int64(got.num("people.0.userId")) != nick.ID || int64(got.num("people.1.userId")) != nadia.ID {
		t.Fatalf("people = %s", got.Body)
	}
	nickThis, nickPrev := "people.0.this.", "people.0.previous."
	if got.num(nickThis+"points") != 840 || got.num(nickThis+"countedDays") != 2 || got.num(nickThis+"steps") != 56000 ||
		got.num(nickThis+"sleepAvgMin") != 430 || got.num(nickThis+"sleepNights") != 3 || got.num(nickThis+"workouts") != 1 ||
		got.num(nickThis+"readingMinutes") != 45 {
		t.Fatalf("Nick this week = %s", got.Body)
	}
	if got.num(nickPrev+"points") != 200 || got.num(nickPrev+"steps") != 42000 || got.num(nickPrev+"countedDays") != 0 {
		t.Fatalf("Nick previous week = %s", got.Body)
	}
	if got.str("people.0.bestDay.date") != "2026-10-29" || got.num("people.0.bestDay.points") != 400 ||
		got.str("people.0.suggestion") == "" {
		t.Fatalf("best day / suggestion = %s", got.Body)
	}
	if got.num("people.1.this.points") != 450 || got.num("people.1.this.steps") != 35000 {
		t.Fatalf("Nadia this week = %s", got.Body)
	}
	if got.num("pair.this.points") != 1290 || got.num("pair.this.steps") != 91000 || got.num("pair.previous.points") != 200 ||
		got.str("pair.bestDay.date") != "2026-10-29" || got.num("pair.bestDay.points") != 850 {
		t.Fatalf("pair = %s", got.Body)
	}
	if got.str("challenge.kind") != "steps" || got.num("challenge.target") != 90000 || got.num("challenge.progress") != 91000 {
		t.Fatalf("challenge = %s", got.Body)
	}

	same := h.get("/api/recap?week=2026-W44", nadia.Token).expect(http.StatusOK)
	if same.num("pair.this.points") != 1290 {
		t.Fatalf("explicit week = %s", same.Body)
	}
}

func TestRecapHasNoChallengeWhenTheWeekHadNone(t *testing.T) {
	h, nick, _ := recapPair(t)
	got := h.get("/api/recap?week=2026-W43", nick.Token).expect(http.StatusOK)
	if !got.isNull("challenge") || got.num("people.0.this.points") != 200 || got.num("pair.previous.points") != 0 {
		t.Fatalf("recap = %s", got.Body)
	}
}

func TestRecapWeekParameterAndTheSundayEveningDefault(t *testing.T) {
	h, nick, _ := recapPair(t)
	for _, bad := range []string{"2026-44", "W44", "2026-W00", "2026-W54", "2026-W46", "2026-W41", "yesterday"} {
		h.get("/api/recap?week="+bad, nick.Token).expect(http.StatusUnprocessableEntity).code("invalid_request")
	}

	h.clock.Set(ny(2026, time.November, 8, 18, 59))
	if got := h.get("/api/recap", nick.Token).expect(http.StatusOK); got.str("week") != "2026-W44" {
		t.Fatalf("Sunday 18:59 = %s", got.Body)
	}
	h.clock.Set(ny(2026, time.November, 8, 19, 0))
	got := h.get("/api/recap", nick.Token).expect(http.StatusOK)
	if got.str("week") != "2026-W45" || got.flag("complete") {
		t.Fatalf("Sunday 19:00 = %s", got.Body)
	}
	if got.num("people.0.previous.points") != 840 {
		t.Fatalf("W45 previous = %s", got.Body)
	}
}

func TestRecapForABrandNewPairFallsBackToThisWeek(t *testing.T) {
	h := newHarness(t)
	nick := h.joinAdmin("Nick", "green")
	got := h.get("/api/recap", nick.Token).expect(http.StatusOK)
	if got.str("week") != "2026-W45" || got.flag("complete") || got.num("pair.this.points") != 0 || !got.isNull("people.0.bestDay") {
		t.Fatalf("recap = %s", got.Body)
	}
	h.get("/api/recap", "").expect(http.StatusUnauthorized)
}
