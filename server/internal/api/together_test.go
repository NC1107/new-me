package api

import (
	"context"
	"fmt"
	"net/http"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/nc1107/new-me/server/internal/db"
	"github.com/nc1107/new-me/server/internal/push"
	"github.com/nc1107/new-me/server/internal/score"
	"github.com/nc1107/new-me/server/internal/together"
)

// capture records queued pushes, standing in for the APNs dispatcher.
type capture struct {
	mu   sync.Mutex
	msgs []push.Message
}

func (c *capture) Enqueue(m push.Message) bool {
	c.mu.Lock()
	defer c.mu.Unlock()
	c.msgs = append(c.msgs, m)
	return true
}

func (c *capture) of(kind string, user int64) []push.Message {
	c.mu.Lock()
	defer c.mu.Unlock()
	var out []push.Message
	for _, m := range c.msgs {
		if m.Kind == kind && m.UserID == user {
			out = append(out, m)
		}
	}
	return out
}

func withPush(c *capture) func(*Server) { return func(s *Server) { s.WithNotifier(c) } }

func (h *harness) cheer(from person, to person, kind string) *response {
	h.t.Helper()
	return h.post("/api/cheers", from.Token, obj{"to": to.ID, "kind": kind})
}

func TestCheerRules(t *testing.T) {
	h := newHarness(t)
	nick, nadia := h.pair()

	first := h.cheer(nick, nadia, "fire").expect(http.StatusCreated)
	if first.num("cheer.from") != int(nick.ID) || first.str("cheer.kind") != "fire" || first.str("cheer.fromName") != "Nick" {
		t.Fatalf("cheer = %s", first.Body)
	}
	repeat := h.cheer(nick, nadia, "fire").expect(http.StatusOK)
	if repeat.str("cheer.at") != first.str("cheer.at") {
		t.Fatalf("a repeat must answer the stored cheer: %s vs %s", repeat.Body, first.Body)
	}
	h.cheer(nick, nadia, "clap").expect(http.StatusCreated)
	h.cheer(nadia, nick, "fire").expect(http.StatusCreated)

	h.cheer(nick, nick, "fire").expect(http.StatusUnprocessableEntity).code("invalid_request")
	h.cheer(nick, nadia, "party").expect(http.StatusUnprocessableEntity).code("invalid_request")
	h.post("/api/cheers", nick.Token, obj{"to": 9999, "kind": "fire"}).expect(http.StatusNotFound)
	h.post("/api/cheers", "", obj{"to": nadia.ID, "kind": "fire"}).expect(http.StatusUnauthorized)

	// The next sender-local day allows the same kind again.
	h.clock.Set(ny(2026, time.November, 3, 12, 0))
	h.cheer(nick, nadia, "fire").expect(http.StatusCreated)
}

func TestCheersReceivedAppearOnTheRecipientsToday(t *testing.T) {
	h := newHarness(t)
	nick, nadia := h.pair()
	h.cheer(nick, nadia, "fire").expect(http.StatusCreated)
	h.clock.Set(ny(2026, time.November, 2, 13, 0))
	h.cheer(nick, nadia, "heart").expect(http.StatusCreated)

	got := h.get("/api/today", nadia.Token).expect(http.StatusOK)
	if got.length("cheers") != 2 || got.str("cheers.0.kind") != "heart" || got.str("cheers.1.kind") != "fire" ||
		got.num("cheers.0.from") != int(nick.ID) || got.str("cheers.0.fromName") != "Nick" ||
		got.str("cheers.0.at") == "" {
		t.Fatalf("cheers = %s", got.Body)
	}
	if mine := h.get("/api/today", nick.Token).expect(http.StatusOK); mine.length("cheers") != 0 {
		t.Fatalf("the sender sees %s", mine.Body)
	}
	h.clock.Set(ny(2026, time.November, 3, 0, 30))
	if next := h.get("/api/today", nadia.Token).expect(http.StatusOK); next.length("cheers") != 0 {
		t.Fatalf("yesterday's cheers leaked into today: %s", next.Body)
	}
}

func TestCheerPushesOncePerCheerAndRespectsThePreference(t *testing.T) {
	n := &capture{}
	h := newHarness(t, withPush(n))
	nick, nadia := h.pair()

	h.cheer(nick, nadia, "flex").expect(http.StatusCreated)
	h.cheer(nick, nadia, "flex").expect(http.StatusOK)
	got := n.of("cheer", nadia.ID)
	if len(got) != 1 || got[0].Title != "Nick cheered your day" {
		t.Fatalf("pushes = %+v", got)
	}

	h.patch("/api/me", nadia.Token, obj{"notifications": obj{"cheers": false}}).expect(http.StatusOK)
	h.cheer(nick, nadia, "heart").expect(http.StatusCreated)
	if got := n.of("cheer", nadia.ID); len(got) != 1 {
		t.Fatalf("a muted cheer still pushed: %+v", got)
	}
}

func TestNotificationPreferencesDefaultOnAndPatchPartially(t *testing.T) {
	h := newHarness(t)
	nick := h.joinAdmin("Nick", "green")
	me := h.get("/api/me", nick.Token).expect(http.StatusOK)
	for _, k := range []string{"partnerDone", "cheers", "challenge", "reward"} {
		if !me.flag("notifications." + k) {
			t.Fatalf("%s should default on: %s", k, me.Body)
		}
	}
	got := h.patch("/api/me", nick.Token, obj{"notifications": obj{"partnerDone": false, "reward": false}}).
		expect(http.StatusOK)
	if got.flag("notifications.partnerDone") || got.flag("notifications.reward") ||
		!got.flag("notifications.cheers") || !got.flag("notifications.challenge") {
		t.Fatalf("patched = %s", got.Body)
	}
	if again := h.get("/api/me", nick.Token).expect(http.StatusOK); again.flag("notifications.partnerDone") {
		t.Fatalf("not persisted: %s", again.Body)
	}
	h.patch("/api/me", nick.Token, obj{"notifications": obj{"nope": true}}).expect(http.StatusBadRequest)
	if kept := h.patch("/api/me", nick.Token, obj{"name": "Nicholas"}).expect(http.StatusOK); kept.flag("notifications.partnerDone") {
		t.Fatalf("an unrelated patch reset the switches: %s", kept.Body)
	}
}

func TestBoardCreatesTheWeeksChallengeLazilyWithAFrozenTarget(t *testing.T) {
	h := newHarness(t)
	nick, _ := h.pair()
	h.seedChallenge(together.KindWorkouts)
	ctx := context.Background()
	// Nick had four workouts last week, so his share is five; Nadia had none, so hers is two.
	for i, day := range []string{"2026-10-26", "2026-10-27", "2026-10-28", "2026-10-30"} {
		start := ny(2026, time.October, 26+i, 8, 0)
		if err := db.UpsertWorkout(ctx, h.db.Pool, nick.ID, db.Workout{HealthID: "old-" + day, Type: "running",
			LocalDate: score.MustDate(day), StartedAt: start, EndedAt: start.Add(30 * time.Minute),
			DurationMin: 30, Source: "test"}); err != nil {
			t.Fatal(err)
		}
	}

	got := h.get("/api/board", nick.Token).expect(http.StatusOK)
	if got.str("challenge.kind") != "workouts" || got.num("challenge.target") != 7 || got.num("challenge.progress") != 0 ||
		got.flag("challenge.done") || got.str("challenge.endsOn") != "2026-11-08" ||
		got.str("challenge.title") != "Do 7 workouts together" {
		t.Fatalf("challenge = %s", got.Body)
	}
	if int64(got.num("challenge.people.0.userId")) != nick.ID || got.num("challenge.people.0.target") != 5 ||
		got.num("challenge.people.1.target") != 2 || got.length("challenge.people") != 2 {
		t.Fatalf("shares = %s", got.Body)
	}
	// More history arriving later must not move a target that has been shown.
	start := ny(2026, time.October, 31, 8, 0)
	if err := db.UpsertWorkout(ctx, h.db.Pool, nick.ID, db.Workout{HealthID: "late", Type: "yoga",
		LocalDate: "2026-10-31", StartedAt: start, EndedAt: start.Add(time.Hour), DurationMin: 60, Source: "test"}); err != nil {
		t.Fatal(err)
	}
	if again := h.get("/api/board", nick.Token).expect(http.StatusOK); again.num("challenge.target") != 7 {
		t.Fatalf("target moved: %s", again.Body)
	}
	var rows int
	if err := h.db.Pool.QueryRow(ctx, `SELECT count(*) FROM challenges`).Scan(&rows); err != nil || rows != 1 {
		t.Fatalf("challenges = %d, %v", rows, err)
	}
}

func TestWorkoutChallengeCompletesOnceAndPaysBothFiftyPoints(t *testing.T) {
	n := &capture{}
	h := newHarness(t, withPush(n))
	nick, nadia := h.pair()
	h.seedChallenge(together.KindWorkouts)
	h.get("/api/board", nick.Token).expect(http.StatusOK)

	start := ny(2026, time.November, 2, 8, 0)
	putWorkouts(h, nick, workout("a", "running", start, 30), workout("b", "yoga", start.Add(time.Hour), 30)).expect(http.StatusOK)
	mid := h.get("/api/board", nadia.Token).expect(http.StatusOK)
	if mid.num("challenge.progress") != 2 || mid.num("challenge.target") != 4 || mid.flag("challenge.done") ||
		!mid.flag("challenge.people.0.done") || mid.flag("challenge.people.1.done") {
		t.Fatalf("midway = %s", mid.Body)
	}
	if h.get("/api/today", nick.Token).expect(http.StatusOK).num("day.bonusPoints") != 0 {
		t.Fatal("bonus paid early")
	}

	// Nick doing far more than his share does not carry Nadia: it completes when she reaches hers.
	putWorkouts(h, nick, workout("x1", "running", start.Add(150*time.Minute), 20), workout("x2", "running", start.Add(180*time.Minute), 20)).expect(http.StatusOK)
	short := h.get("/api/board", nick.Token).expect(http.StatusOK)
	if short.flag("challenge.done") || short.num("challenge.progress") != 2 || short.num("challenge.people.0.progress") != 4 {
		t.Fatalf("one person carried the challenge: %s", short.Body)
	}
	putWorkouts(h, nadia, workout("c", "cycling", start, 45), workout("c2", "cycling", start.Add(time.Hour), 45)).expect(http.StatusOK)
	done := h.get("/api/board", nick.Token).expect(http.StatusOK)
	if !done.flag("challenge.done") || done.num("challenge.progress") != 4 {
		t.Fatalf("done = %s", done.Body)
	}
	for _, p := range []person{nick, nadia} {
		today := h.get("/api/today", p.Token).expect(http.StatusOK)
		if today.num("day.bonusPoints") != 50 || today.num("day.points") != 50 {
			t.Fatalf("%s today = %s", p.Name, today.Body)
		}
		if got := n.of("challenge", p.ID); len(got) != 1 || got[0].Body != "Do 4 workouts together" {
			t.Fatalf("%s pushes = %+v", p.Name, got)
		}
		if week := h.get("/api/board", p.Token).expect(http.StatusOK); week.num("users.0.week.points") != 50 {
			t.Fatalf("%s week points = %s", p.Name, week.Body)
		}
	}

	// Further workouts, rescoring and settling never pay it twice.
	putWorkouts(h, nick, workout("d", "hiit", start.Add(2*time.Hour), 20)).expect(http.StatusOK)
	h.logActivity(nick, "pushups", "reps", 30).expect(http.StatusCreated)
	h.get("/api/board", nadia.Token).expect(http.StatusOK)
	if err := h.srv.together.Settle(context.Background()); err != nil {
		t.Fatal(err)
	}
	if today := h.get("/api/today", nick.Token).expect(http.StatusOK); today.num("day.bonusPoints") != 70 {
		t.Fatalf("Nick bonus = %s", today.Body)
	}
	if today := h.get("/api/today", nadia.Token).expect(http.StatusOK); today.num("day.bonusPoints") != 50 {
		t.Fatalf("Nadia bonus = %s", today.Body)
	}
	var awards int
	if err := h.db.Pool.QueryRow(context.Background(), `SELECT count(*) FROM challenge_awards`).Scan(&awards); err != nil || awards != 2 {
		t.Fatalf("awards = %d, %v", awards, err)
	}
	if len(n.of("challenge", nick.ID)) != 1 {
		t.Fatalf("challenge pushed again: %+v", n.msgs)
	}

	// Deleting what completed it does not take the challenge back.
	if after := h.get("/api/board", nick.Token).expect(http.StatusOK); !after.flag("challenge.done") {
		t.Fatalf("challenge reopened: %s", after.Body)
	}
}

func TestChallengePushRespectsThePreference(t *testing.T) {
	n := &capture{}
	h := newHarness(t, withPush(n))
	nick, nadia := h.pair()
	h.seedChallenge(together.KindWorkouts)
	h.patch("/api/me", nadia.Token, obj{"notifications": obj{"challenge": false}}).expect(http.StatusOK)
	start := ny(2026, time.November, 2, 8, 0)
	putWorkouts(h, nick, workout("a", "running", start, 30), workout("b", "yoga", start.Add(time.Hour), 30)).expect(http.StatusOK)
	putWorkouts(h, nadia, workout("c", "running", start.Add(2*time.Hour), 30), workout("d", "cycling", start.Add(3*time.Hour), 30)).expect(http.StatusOK)
	if len(n.of("challenge", nick.ID)) != 1 || len(n.of("challenge", nadia.ID)) != 0 {
		t.Fatalf("pushes = %+v", n.msgs)
	}
	// The bonus is paid whether or not the notification is wanted.
	if h.get("/api/today", nadia.Token).expect(http.StatusOK).num("day.bonusPoints") != 50 {
		t.Fatal("Nadia was not paid")
	}
}

func TestStepsChallengeIsSizedFromTheLastTwoWeeks(t *testing.T) {
	h := newHarness(t)
	h.clock.Set(ny(2026, time.November, 23, 12, 0))
	nick, nadia := h.pair()
	h.seedChallenge(together.KindSteps)
	for i := range 14 {
		date := score.MustDate("2026-11-09").AddDays(i)
		for _, row := range []struct {
			p     person
			steps float64
		}{{nick, 10000}, {nadia, 5000}} {
			if _, err := db.UpsertHealthDaily(context.Background(), h.db.Pool, row.p.ID, date, "steps", row.steps,
				"test", time.Now()); err != nil {
				t.Fatal(err)
			}
		}
	}
	got := h.get("/api/board", nick.Token).expect(http.StatusOK)
	// Each share is the person's own average * 7 * 1.1 rounded to a thousand: 77,000 and 38,500 -> 39,000.
	if got.str("challenge.kind") != "steps" || got.num("challenge.target") != 116000 ||
		got.str("challenge.title") != "Walk 116,000 steps together" ||
		got.num("challenge.people.0.target") != 77000 || got.num("challenge.people.1.target") != 39000 {
		t.Fatalf("challenge = %s", got.Body)
	}
	h.putHealth(nick, "2026-11-23", "steps", 12000).expect(http.StatusOK)
	h.putHealth(nadia, "2026-11-23", "steps", 6000).expect(http.StatusOK)
	if later := h.get("/api/board", nick.Token).expect(http.StatusOK); later.num("challenge.progress") != 18000 {
		t.Fatalf("progress = %s", later.Body)
	}
}

func TestReadingChallengeCountsLoggedMinutesAndListening(t *testing.T) {
	h := newHarness(t)
	h.clock.Set(ny(2026, time.November, 16, 12, 0))
	nick, nadia := h.pair()
	h.seedChallenge(together.KindReading)
	got := h.get("/api/board", nick.Token).expect(http.StatusOK)
	if got.str("challenge.kind") != "reading" || got.num("challenge.target") != 150 ||
		got.num("challenge.people.0.target") != 75 {
		t.Fatalf("challenge = %s", got.Body)
	}
	h.logActivity(nick, "reading", "minutes", 100).expect(http.StatusCreated)
	h.logActivity(nick, "reading", "pages", 40).expect(http.StatusCreated)
	// Nick's 100 minutes count 75 toward the combined progress: his own share is all he can add.
	if mid := h.get("/api/board", nick.Token).expect(http.StatusOK); mid.num("challenge.progress") != 75 ||
		mid.num("challenge.people.0.progress") != 100 {
		t.Fatalf("pages must not count as minutes: %s", mid.Body)
	}
	if err := db.UpsertListening(context.Background(), h.db.Pool, nadia.ID, "2026-11-16", 80, h.clock.Now()); err != nil {
		t.Fatal(err)
	}
	done := h.get("/api/board", nadia.Token).expect(http.StatusOK)
	if !done.flag("challenge.done") || done.num("challenge.progress") != 150 {
		t.Fatalf("done = %s", done.Body)
	}
}

func TestCountedDaysChallengeNeedsEachPersonsOwnDays(t *testing.T) {
	h := newHarness(t)
	h.clock.Set(ny(2026, time.November, 14, 12, 0))
	nick, nadia := h.pair()
	h.seedChallenge(together.KindCountedDays)
	for _, day := range []string{"2026-11-09", "2026-11-10", "2026-11-11", "2026-11-12"} {
		h.storeScore(nick, day, 300, 0, 400)
		h.storeScore(nadia, day, 300, 0, 400)
	}
	// Each needs five counted days of their own: Nick has five, Nadia four.
	h.storeScore(nick, "2026-11-13", 300, 0, 400)
	h.storeScore(nadia, "2026-11-13", 100, 0, 400)
	got := h.get("/api/board", nick.Token).expect(http.StatusOK)
	if got.str("challenge.kind") != "counted_days" || got.num("challenge.target") != 10 ||
		got.num("challenge.progress") != 9 || got.flag("challenge.done") {
		t.Fatalf("challenge = %s", got.Body)
	}
	h.storeScore(nadia, "2026-11-13", 300, 0, 400)
	if done := h.get("/api/board", nick.Token).expect(http.StatusOK); !done.flag("challenge.done") ||
		done.num("challenge.progress") != 10 {
		t.Fatalf("done = %s", done.Body)
	}
	// The award lands on the day it completed, not on the days that earned it.
	if today := h.get("/api/today", nick.Token).expect(http.StatusOK); today.str("date") != "2026-11-14" ||
		today.num("day.bonusPoints") != 50 {
		t.Fatalf("today = %s", today.Body)
	}
}

func TestSettleCompletesAChallengeWithoutAnyRequest(t *testing.T) {
	n := &capture{}
	h := newHarness(t, withPush(n))
	nick, nadia := h.pair()
	h.seedChallenge(together.KindWorkouts)
	start := ny(2026, time.November, 2, 8, 0)
	for i, id := range []string{"a", "b", "c", "d"} {
		who := []person{nick, nadia, nick, nadia}[i]
		if err := db.UpsertWorkout(context.Background(), h.db.Pool, who.ID, db.Workout{HealthID: id, Type: "running",
			LocalDate: "2026-11-02", StartedAt: start, EndedAt: start.Add(time.Hour), DurationMin: 60, Source: "test"}); err != nil {
			t.Fatal(err)
		}
	}
	if err := h.srv.together.Settle(context.Background()); err != nil {
		t.Fatal(err)
	}
	if len(n.of("challenge", nick.ID)) != 1 || len(n.of("challenge", nadia.ID)) != 1 {
		t.Fatalf("pushes = %+v", n.msgs)
	}
	if h.get("/api/today", nadia.Token).expect(http.StatusOK).num("day.bonusPoints") != 50 {
		t.Fatal("Nadia was not paid")
	}
}

func TestRewardLifecycle(t *testing.T) {
	n := &capture{}
	h := newHarness(t, withPush(n))
	nick, nadia := h.pair()

	if empty := h.get("/api/rewards", nick.Token).expect(http.StatusOK); !empty.isNull("reward") || empty.length("history") != 0 {
		t.Fatalf("empty = %s", empty.Body)
	}
	if board := h.get("/api/board", nick.Token).expect(http.StatusOK); !board.isNull("reward") {
		t.Fatalf("board reward = %s", board.Body)
	}

	// Points earned before the reward starts do not count towards it.
	h.logActivity(nick, "pushups", "reps", 30).expect(http.StatusCreated)
	for _, bad := range []obj{{"name": " ", "target": 100}, {"name": strings.Repeat("x", 41), "target": 100},
		{"name": "Trip", "target": 0}, {"name": "Trip", "target": 100001}} {
		h.post("/api/rewards", nick.Token, bad).expect(http.StatusUnprocessableEntity).code("invalid_request")
	}
	made := h.post("/api/rewards", nick.Token, obj{"name": "Date night", "target": 200}).expect(http.StatusCreated)
	if made.str("reward.name") != "Date night" || made.num("reward.target") != 200 || made.num("reward.progress") != 0 ||
		!made.isNull("reward.reachedAt") || !made.isNull("reward.claimedAt") {
		t.Fatalf("created = %s", made.Body)
	}
	id := made.num("reward.id")
	h.post("/api/rewards", nadia.Token, obj{"name": "Second", "target": 50}).expect(http.StatusConflict).code("reward_active")
	h.post(fmt.Sprintf("/api/rewards/%d/claim", id), nick.Token, nil).expect(http.StatusConflict).code("reward_not_reached")
	h.post("/api/rewards/999/claim", nick.Token, nil).expect(http.StatusNotFound)

	h.logActivity(nadia, "pushups", "reps", 30).expect(http.StatusCreated)
	mid := h.get("/api/board", nick.Token).expect(http.StatusOK)
	if mid.num("reward.progress") != 120 || !mid.isNull("reward.reachedAt") || mid.num("reward.id") != id {
		t.Fatalf("midway = %s", mid.Body)
	}

	h.logActivity(nick, "reading", "minutes", 20).expect(http.StatusCreated)
	reached := h.get("/api/rewards", nadia.Token).expect(http.StatusOK)
	if !reached.isNull("reward") || reached.length("history") != 1 || reached.str("history.0.reachedAt") == "" ||
		reached.num("history.0.progress") != 200 {
		t.Fatalf("reached = %s", reached.Body)
	}
	for _, p := range []person{nick, nadia} {
		if got := n.of("reward", p.ID); len(got) != 1 || got[0].Body != "Date night" {
			t.Fatalf("%s reward pushes = %+v", p.Name, got)
		}
	}
	board := h.get("/api/board", nick.Token).expect(http.StatusOK)
	if board.num("reward.id") != id || board.str("reward.reachedAt") == "" {
		t.Fatalf("board after reaching = %s", board.Body)
	}

	claimed := h.post(fmt.Sprintf("/api/rewards/%d/claim", id), nick.Token, nil).expect(http.StatusOK)
	stamp := claimed.str("reward.claimedAt")
	if stamp == "" {
		t.Fatalf("claimed = %s", claimed.Body)
	}
	h.clock.Set(h.clock.Now().Add(time.Hour))
	if again := h.post(fmt.Sprintf("/api/rewards/%d/claim", id), nadia.Token, nil).expect(http.StatusOK); again.str("reward.claimedAt") != stamp {
		t.Fatalf("a repeat claim moved the time: %s", again.Body)
	}
	if after := h.get("/api/board", nick.Token).expect(http.StatusOK); !after.isNull("reward") {
		t.Fatalf("a claimed reward still on the board: %s", after.Body)
	}

	// The next one starts from the points at that moment.
	next := h.post("/api/rewards", nadia.Token, obj{"name": "Trip", "target": 500}).expect(http.StatusCreated)
	if next.num("reward.progress") != 0 || next.num("reward.createdBy") != int(nadia.ID) {
		t.Fatalf("next = %s", next.Body)
	}
	if len(n.of("reward", nick.ID)) != 1 {
		t.Fatalf("reward pushed more than once: %+v", n.msgs)
	}
}

func TestStartingARewardRightAfterReachingOneIsAllowed(t *testing.T) {
	h := newHarness(t)
	nick := h.joinAdmin("Nick", "green")
	h.post("/api/rewards", nick.Token, obj{"name": "Treat", "target": 100}).expect(http.StatusCreated)
	h.logActivity(nick, "pushups", "reps", 30).expect(http.StatusCreated)
	// No read happened in between: creating the next one settles the first.
	h.post("/api/rewards", nick.Token, obj{"name": "Next", "target": 100}).expect(http.StatusCreated)
	if list := h.get("/api/rewards", nick.Token).expect(http.StatusOK); list.str("reward.name") != "Next" ||
		list.length("history") != 1 {
		t.Fatalf("list = %s", list.Body)
	}
}

func TestPartnerDonePushesOncePerDayAndRespectsThePreference(t *testing.T) {
	n := &capture{}
	h := newHarness(t, withPush(n))
	nick, nadia := h.pair()

	fixtureDay(h, nick)
	h.logMeal(nick, "Snack", 100, 0).expect(http.StatusCreated)
	h.cheer(nick, nadia, "fire").expect(http.StatusCreated)
	got := n.of("partner_done", nadia.ID)
	if len(got) != 1 || got[0].Title != "Nick finished the day" || len(n.of("partner_done", nick.ID)) != 0 {
		t.Fatalf("pushes = %+v", n.msgs)
	}

	h.patch("/api/me", nadia.Token, obj{"notifications": obj{"partnerDone": false}}).expect(http.StatusOK)
	h.clock.Set(ny(2026, time.November, 3, 12, 0))
	countedDay := func(date string) {
		h.putHealth(nick, date, "steps", 8000).expect(http.StatusOK)
		h.logActivity(nick, "pushups", "reps", 30).expect(http.StatusCreated)
		h.logActivity(nick, "reading", "minutes", 20).expect(http.StatusCreated)
		h.logMeal(nick, "Oats", 400, 0).expect(http.StatusCreated)
		h.logMeal(nick, "Rice", 600, 0).expect(http.StatusCreated)
	}
	countedDay("2026-11-03")
	if !h.get("/api/today", nick.Token).expect(http.StatusOK).flag("day.counted") {
		t.Fatal("the fixture day should count")
	}
	if got := n.of("partner_done", nadia.ID); len(got) != 1 {
		t.Fatalf("a muted partner was notified: %+v", got)
	}
	h.patch("/api/me", nadia.Token, obj{"notifications": obj{"partnerDone": true}}).expect(http.StatusOK)
	h.clock.Set(ny(2026, time.November, 4, 12, 0))
	countedDay("2026-11-04")
	if got := n.of("partner_done", nadia.ID); len(got) != 2 {
		t.Fatalf("the new day should notify once more: %+v", got)
	}
}

func TestPushTokenRegistration(t *testing.T) {
	h := newHarness(t)
	nick, nadia := h.pair()
	token := strings.Repeat("ab12", 16)
	tokens := func(p person) []string {
		t.Helper()
		got, err := db.PushTokens(context.Background(), h.db.Pool, p.ID)
		if err != nil {
			t.Fatal(err)
		}
		return got
	}

	h.put("/api/devices/me/push", nick.Token, obj{"token": strings.ToUpper(token)}).expect(http.StatusNoContent)
	h.put("/api/devices/me/push", nick.Token, obj{"token": token}).expect(http.StatusNoContent)
	if got := tokens(nick); len(got) != 1 || got[0] != token {
		t.Fatalf("tokens = %v", got)
	}
	for _, bad := range []string{"", "short", strings.Repeat("zz", 32), strings.Repeat("a", 201)} {
		h.put("/api/devices/me/push", nick.Token, obj{"token": bad}).expect(http.StatusUnprocessableEntity).code("invalid_request")
	}
	h.put("/api/devices/me/push", "", obj{"token": token}).expect(http.StatusUnauthorized)

	// A token that shows up on another install moves there.
	h.put("/api/devices/me/push", nadia.Token, obj{"token": token}).expect(http.StatusNoContent)
	if len(tokens(nick)) != 0 || len(tokens(nadia)) != 1 {
		t.Fatalf("token did not move: %v / %v", tokens(nick), tokens(nadia))
	}

	h.delete("/api/devices/me/push", nadia.Token).expect(http.StatusNoContent)
	h.delete("/api/devices/me/push", nadia.Token).expect(http.StatusNoContent)
	if len(tokens(nadia)) != 0 {
		t.Fatal("token survived DELETE")
	}

	h.put("/api/devices/me/push", nick.Token, obj{"token": token}).expect(http.StatusNoContent)
	h.delete("/api/devices/me", nick.Token).expect(http.StatusNoContent)
	if len(tokens(nick)) != 0 {
		t.Fatal("signing out kept the push token")
	}
}

func TestPushIsOptionalEverywhere(t *testing.T) {
	h := newHarness(t)
	nick, nadia := h.pair()
	h.cheer(nick, nadia, "clap").expect(http.StatusCreated)
	fixtureDay(h, nick)
	var notices int
	if err := h.db.Pool.QueryRow(context.Background(), `SELECT count(*) FROM notice_log`).Scan(&notices); err != nil || notices != 0 {
		t.Fatalf("notice_log = %d, %v", notices, err)
	}
}
