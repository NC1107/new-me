package api

import (
	"context"
	"net/http"
	"testing"
	"time"
)

func TestStrengthWorkoutCompletesThePushupsQuestWithoutLoggedReps(t *testing.T) {
	h := newHarness(t)
	nick := h.joinAdmin("Nick", "green")

	before := h.get("/api/today", nick.Token).expect(http.StatusOK)
	if before.flag("quests.1.done") || !before.isNull("quests.1.doneBy") {
		t.Fatalf("push-ups before any workout = %s", before.Body)
	}

	putWorkouts(h, nick, workout("w1", "strength", ny(2026, time.November, 2, 8, 0), 42)).expect(http.StatusOK)
	got := h.get("/api/today", nick.Token).expect(http.StatusOK)
	if got.str("quests.1.key") != "pushups" || !got.flag("quests.1.done") || got.num("quests.1.actual") != 0 ||
		got.num("quests.1.basePoints") != 100 || got.num("quests.1.bonusPoints") != 20 ||
		got.str("quests.1.doneBy.kind") != "workout" || got.str("quests.1.doneBy.type") != "strength" ||
		got.num("quests.1.doneBy.minutes") != 42 {
		t.Fatalf("push-ups after a strength workout = %s", got.Body)
	}
	if got.num("day.basePoints") != 100 {
		t.Fatalf("day = %s", got.Body)
	}
}

func TestWorkoutPutRescoresTheStoredDayWithoutAnyRead(t *testing.T) {
	h := newHarness(t)
	nick := h.joinAdmin("Nick", "green")
	h.get("/api/today", nick.Token).expect(http.StatusOK)

	putWorkouts(h, nick, workout("w1", "hiit", ny(2026, time.November, 2, 7, 0), 20)).expect(http.StatusOK)
	var base int
	err := h.db.Pool.QueryRow(context.Background(),
		`SELECT base_points FROM day_scores WHERE user_id = $1 AND local_date = '2026-11-02'`, nick.ID).Scan(&base)
	if err != nil || base != 100 {
		t.Fatalf("stored base points = %d, %v; the PUT must rescore", base, err)
	}
}

func TestWorkoutsThatDoNotQualifyChangeNothing(t *testing.T) {
	h := newHarness(t)
	nick := h.joinAdmin("Nick", "green")
	putWorkouts(h, nick,
		workout("short", "strength", ny(2026, time.November, 2, 7, 0), 19.9),
		workout("run", "running", ny(2026, time.November, 2, 8, 0), 90)).expect(http.StatusOK)
	got := h.get("/api/today", nick.Token).expect(http.StatusOK)
	if got.flag("quests.1.done") || got.num("day.basePoints") != 0 {
		t.Fatalf("today = %s", got.Body)
	}
}

func TestLoggedRepsStillCompleteWithoutDoneBy(t *testing.T) {
	h := newHarness(t)
	nick := h.joinAdmin("Nick", "green")
	putWorkouts(h, nick, workout("w1", "strength", ny(2026, time.November, 2, 8, 0), 40)).expect(http.StatusOK)
	h.logActivity(nick, "pushups", "reps", 35).expect(http.StatusCreated)
	got := h.get("/api/today", nick.Token).expect(http.StatusOK)
	if !got.flag("quests.1.done") || got.num("quests.1.actual") != 35 || !got.isNull("quests.1.doneBy") {
		t.Fatalf("push-ups = %s", got.Body)
	}
}

func TestEditingAWorkoutDownRemovesTheCredit(t *testing.T) {
	h := newHarness(t)
	nick := h.joinAdmin("Nick", "green")
	putWorkouts(h, nick, workout("w1", "strength", ny(2026, time.November, 2, 8, 0), 40)).expect(http.StatusOK)
	if !h.get("/api/today", nick.Token).flag("quests.1.done") {
		t.Fatal("expected credit")
	}
	putWorkouts(h, nick, workout("w1", "strength", ny(2026, time.November, 2, 8, 0), 10)).expect(http.StatusOK)
	if got := h.get("/api/today", nick.Token); got.flag("quests.1.done") || got.num("day.basePoints") != 0 {
		t.Fatalf("today = %s", got.Body)
	}
}

func TestYogaWorkoutMinutesAddToTheYogaQuest(t *testing.T) {
	h := newHarness(t)
	nick := h.joinAdmin("Nick", "green")
	h.patch("/api/me", nick.Token, obj{"questTemplates": []obj{{"key": "yoga", "enabled": true}}}).expect(http.StatusOK)
	h.logActivity(nick, "yoga", "minutes", 5).expect(http.StatusCreated)

	putWorkouts(h, nick, workout("y1", "yoga", ny(2026, time.November, 2, 7, 0), 12.4)).expect(http.StatusOK)
	got := h.get("/api/today", nick.Token).expect(http.StatusOK)
	var yoga int = -1
	for i := range 8 {
		if got.str("quests."+itoa(i)+".key") == "yoga" {
			yoga = i
			break
		}
	}
	if yoga < 0 {
		t.Fatalf("no yoga quest: %s", got.Body)
	}
	p := "quests." + itoa(yoga)
	if got.num(p+".actual") != 17 || got.flag(p+".done") || !got.isNull(p+".doneBy") {
		t.Fatalf("yoga with 5 logged + 12 from workout = %s", got.Body)
	}

	putWorkouts(h, nick, workout("y2", "yoga", ny(2026, time.November, 2, 9, 0), 10)).expect(http.StatusOK)
	got = h.get("/api/today", nick.Token).expect(http.StatusOK)
	if got.num(p+".actual") != 27 || !got.flag(p+".done") || got.str(p+".doneBy.type") != "yoga" ||
		got.num(p+".doneBy.minutes") != 22 {
		t.Fatalf("yoga after the second workout = %s", got.Body)
	}
}

func TestHIITNeedsIntensityWhenAgeAndRestingHeartRateAreKnown(t *testing.T) {
	h := newHarness(t)
	nick := h.joinAdmin("Nick", "green")
	h.patch("/api/me", nick.Token, obj{"birthYear": 1986}).expect(http.StatusOK) // age 40
	h.putHealth(nick, "2026-11-02", "resting_hr", 60).expect(http.StatusOK)

	easy := workout("easy", "hiit", ny(2026, time.November, 2, 7, 0), 30)
	easy["avgHr"] = 120.0
	putWorkouts(h, nick, easy).expect(http.StatusOK)
	if h.get("/api/today", nick.Token).flag("quests.1.done") {
		t.Fatal("a 30 minute HIIT below 60% of heart-rate reserve (132 bpm) must not count")
	}
	hard := workout("hard", "hiit", ny(2026, time.November, 2, 9, 0), 15)
	hard["avgHr"] = 140.0
	putWorkouts(h, nick, hard).expect(http.StatusOK)
	got := h.get("/api/today", nick.Token).expect(http.StatusOK)
	if !got.flag("quests.1.done") || got.str("quests.1.doneBy.type") != "hiit" || got.num("quests.1.doneBy.minutes") != 15 {
		t.Fatalf("today = %s", got.Body)
	}
}
