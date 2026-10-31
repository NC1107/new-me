package api

import (
	"net/http"
	"strconv"
	"testing"
	"time"
)

func questPath(t *testing.T, r *response, key string) string {
	t.Helper()
	for i := 0; i < r.length("quests"); i++ {
		if r.str("quests."+strconv.Itoa(i)+".key") == key {
			return "quests." + strconv.Itoa(i)
		}
	}
	t.Fatalf("no %s quest in %s", key, r.Body)
	return ""
}

// enableExerciseQuest turns the exercise quest on and moves to the next day, because quest
// edits apply from the next day.
func enableExerciseQuest(h *harness, nick person) {
	h.patch("/api/me", nick.Token, obj{"questTemplates": []obj{{"key": "exercise", "enabled": true, "target": 30}}}).
		expect(http.StatusOK)
	h.clock.Set(ny(2026, time.November, 3, 12, 0))
}

func TestLongCalisthenicsSessionIsAStrengthWorkoutAndExerciseMinutes(t *testing.T) {
	h := newHarness(t)
	nick := h.joinAdmin("Nick", "green")
	enableExerciseQuest(h, nick)

	h.logActivity(nick, "calisthenics", "minutes", 24).expect(http.StatusCreated)
	got := h.get("/api/today", nick.Token).expect(http.StatusOK)
	push := questPath(t, got, "pushups")
	if !got.flag(push+".done") || got.str(push+".doneBy.kind") != "workout" || got.str(push+".doneBy.type") != "strength" ||
		got.num(push+".doneBy.minutes") != 24 || got.num(push+".actual") != 0 {
		t.Fatalf("push-ups after 24 minutes of calisthenics = %s", got.Body)
	}
	if got.num(questPath(t, got, "exercise")+".actual") != 24 {
		t.Fatalf("exercise minutes = %s", got.Body)
	}
}

func TestShortCalisthenicsSessionOnlyAddsExerciseMinutes(t *testing.T) {
	h := newHarness(t)
	nick := h.joinAdmin("Nick", "green")
	enableExerciseQuest(h, nick)

	h.logActivity(nick, "calisthenics", "minutes", 12).expect(http.StatusCreated)
	got := h.get("/api/today", nick.Token).expect(http.StatusOK)
	if got.flag(questPath(t, got, "pushups")+".done") || got.num(questPath(t, got, "exercise")+".actual") != 12 {
		t.Fatalf("today after 12 minutes of calisthenics = %s", got.Body)
	}
}

func TestCalisthenicsRepsCountTowardTheDailyRepsQuestByExercise(t *testing.T) {
	h := newHarness(t)
	nick := h.joinAdmin("Nick", "green")
	h.logActivity(nick, "calisthenics", "minutes", 10).expect(http.StatusCreated)
	h.logActivity(nick, "pushups", "reps", 22, obj{"exercise": "push_up"}).expect(http.StatusCreated)
	h.logActivity(nick, "pushups", "reps", 30, obj{"exercise": "air_squat"}).expect(http.StatusCreated)
	got := h.get("/api/today", nick.Token).expect(http.StatusOK)
	if got.num(questPath(t, got, "pushups")+".actual") != 22 {
		t.Fatalf("only the quest's own exercise counts: %s", got.Body)
	}
}

func TestCalisthenicsLogRejectsBadAmounts(t *testing.T) {
	h := newHarness(t)
	nick := h.joinAdmin("Nick", "green")
	h.logActivity(nick, "calisthenics", "minutes", 0).expect(http.StatusUnprocessableEntity)
	h.logActivity(nick, "calisthenics", "reps", 10).expect(http.StatusUnprocessableEntity)
	h.logActivity(nick, "calisthenics", "minutes", 1441).expect(http.StatusUnprocessableEntity)
}

func TestCalisthenicsCatalogEntriesHaveHowTo(t *testing.T) {
	h := newHarness(t)
	nick := h.joinAdmin("Nick", "green")
	got := h.get("/api/exercises", nick.Token).expect(http.StatusOK)
	for _, key := range []string{"jumping_jack", "mountain_climber", "wall_sit", "pike_push_up", "jump_squat"} {
		p := "exercises." + strconv.Itoa(exerciseIndex(t, got, key)) + "."
		if got.length(p+"steps") < 3 || got.length(p+"cues") < 1 || got.flag(p+"custom") {
			t.Fatalf("%s = %s", key, got.Body)
		}
	}
}
