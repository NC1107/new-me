package api

import (
	"net/http"
	"strings"
	"testing"
	"time"
)

func todayQuest(t *testing.T, h *harness, p person, key string) string {
	t.Helper()
	got := h.get("/api/today", p.Token).expect(http.StatusOK)
	for i := range got.length("quests") {
		if got.str("quests."+itoa(i)+".key") == key {
			return "quests." + itoa(i)
		}
	}
	t.Fatalf("no quest %s: %s", key, got.Body)
	return ""
}

func dailyRepsEntry(t *testing.T, r *response, key string) string {
	t.Helper()
	for i := range r.length("exercises") {
		if r.str("exercises."+itoa(i)+".key") == key {
			return "exercises." + itoa(i)
		}
	}
	t.Fatalf("no exercise %s: %s", key, r.Body)
	return ""
}

func TestDailyRepsDefaultsToPushupsAndLegacyLogsCountForThem(t *testing.T) {
	h := newHarness(t)
	nick := h.joinAdmin("Nick", "green")
	got := h.get("/api/daily-reps", nick.Token).expect(http.StatusOK)
	if got.str("exercise") != "push_up" || got.num("target") != 30 || got.str("dayExercise") != "push_up" || got.num("sets") != 3 {
		t.Fatalf("default = %s", got.Body)
	}
	if got.length("exercises") != 8 || got.length("sources") != 3 {
		t.Fatalf("choices = %s", got.Body)
	}
	q := todayQuest(t, h, nick, "pushups")
	today := h.get("/api/today", nick.Token).expect(http.StatusOK)
	if today.str(q+".title") != "Push-ups" || today.str(q+".exercise") != "push_up" {
		t.Fatalf("title = %s", today.Body)
	}

	// A client that predates the exercise field logs without it.
	logged := h.logActivity(nick, "pushups", "reps", 12).expect(http.StatusCreated)
	if logged.str("log.exercise") != "push_up" {
		t.Fatalf("log = %s", logged.Body)
	}
	if today = h.get("/api/today", nick.Token).expect(http.StatusOK); today.num(q+".actual") != 12 {
		t.Fatalf("actual = %s", today.Body)
	}
}

func TestDailyRepsPreviewSizesThreeSetsAtThreeQuartersOfTheMax(t *testing.T) {
	h := newHarness(t)
	nick := h.joinAdmin("Nick", "green")
	got := h.get("/api/daily-reps/preview?exercise=air_squat&max=20", nick.Token).expect(http.StatusOK)
	if got.num("repsPerSet") != 15 || got.num("low") != 14 || got.num("high") != 16 || got.num("daily") != 45 ||
		got.num("sets") != 3 || !strings.Contains(got.str("formula"), "squats") || got.length("sources") != 3 {
		t.Fatalf("preview = %s", got.Body)
	}
	if got = h.get("/api/daily-reps/preview?exercise=push_up&max=7", nick.Token).expect(http.StatusOK); got.num("repsPerSet") != 5 || got.num("daily") != 15 {
		t.Fatalf("push-up preview = %s", got.Body)
	}
	for _, path := range []string{
		"/api/daily-reps/preview?exercise=air_squat&max=0",
		"/api/daily-reps/preview?exercise=air_squat&max=201",
		"/api/daily-reps/preview?exercise=air_squat",
		"/api/daily-reps/preview?exercise=deadlift&max=10",
	} {
		h.get(path, nick.Token).expect(http.StatusUnprocessableEntity)
	}
	h.get("/api/daily-reps/preview?exercise=air_squat&max=20", "").expect(http.StatusUnauthorized)
}

func TestDailyRepsSquatsOnTheJoinDayRetitleAndRetargetTheQuest(t *testing.T) {
	h := newHarness(t)
	nick := h.joinAdmin("Nick", "green")
	put := h.put("/api/daily-reps", nick.Token, obj{"exercise": "air_squat", "max": 20}).expect(http.StatusOK)
	if put.str("exercise") != "air_squat" || put.num("target") != 45 || put.str("dayExercise") != "air_squat" {
		t.Fatalf("put = %s", put.Body)
	}
	if m := put.str(dailyRepsEntry(t, put, "air_squat") + ".latestMax.date"); m != "2026-11-02" {
		t.Fatalf("max date = %s", m)
	}
	if put.num(dailyRepsEntry(t, put, "air_squat")+".latestMax.reps") != 20 || !put.isNull(dailyRepsEntry(t, put, "push_up")+".latestMax") {
		t.Fatalf("max tests are per exercise: %s", put.Body)
	}

	me := h.get("/api/me", nick.Token).expect(http.StatusOK)
	var seen bool
	for i := range me.length("questTemplates") {
		p := "questTemplates." + itoa(i)
		if me.str(p+".key") == "pushups" {
			seen = true
			if me.str(p+".exercise") != "air_squat" || me.str(p+".title") != "Squats" || me.num(p+".target") != 45 {
				t.Fatalf("template = %s", me.Body)
			}
		}
	}
	if !seen {
		t.Fatalf("no template: %s", me.Body)
	}
	today := h.get("/api/today", nick.Token).expect(http.StatusOK)
	q := todayQuest(t, h, nick, "pushups")
	if today.str(q+".title") != "Squats" || today.str(q+".exercise") != "air_squat" || today.num(q+".target") != 45 {
		t.Fatalf("today = %s", today.Body)
	}
}

func TestRepsOfAnotherExerciseDoNotCount(t *testing.T) {
	h := newHarness(t)
	nick := h.joinAdmin("Nick", "green")
	h.put("/api/daily-reps", nick.Token, obj{"exercise": "air_squat", "max": 20}).expect(http.StatusOK)
	q := todayQuest(t, h, nick, "pushups")

	h.logActivity(nick, "pushups", "reps", 40, obj{"exercise": "push_up"}).expect(http.StatusCreated)
	if got := h.get("/api/today", nick.Token).expect(http.StatusOK); got.num(q+".actual") != 0 || got.flag(q+".done") {
		t.Fatalf("push-ups counted toward squats: %s", got.Body)
	}
	h.post("/api/sets", nick.Token, obj{"clientOpId": h.nextOp(), "exercise": "push_up", "reps": 50}).expect(http.StatusCreated)
	if got := h.get("/api/today", nick.Token).expect(http.StatusOK); got.num(q+".actual") != 0 {
		t.Fatalf("push-up sets counted toward squats: %s", got.Body)
	}

	h.logActivity(nick, "pushups", "reps", 15).expect(http.StatusCreated)
	h.logActivity(nick, "pushups", "reps", 10, obj{"exercise": "air_squat"}).expect(http.StatusCreated)
	h.post("/api/sets", nick.Token, obj{"clientOpId": h.nextOp(), "exercise": "air_squat", "reps": 20}).expect(http.StatusCreated)
	got := h.get("/api/today", nick.Token).expect(http.StatusOK)
	if got.num(q+".actual") != 45 || !got.flag(q+".done") {
		t.Fatalf("squats = %s", got.Body)
	}

	h.logActivity(nick, "pushups", "reps", 5, obj{"exercise": "deadlift"}).expect(http.StatusUnprocessableEntity)
	h.logActivity(nick, "reading", "minutes", 5, obj{"exercise": "air_squat"}).expect(http.StatusUnprocessableEntity)
}

func TestPushupSetsStillCountForPushups(t *testing.T) {
	h := newHarness(t)
	nick := h.joinAdmin("Nick", "green")
	q := todayQuest(t, h, nick, "pushups")
	h.post("/api/sets", nick.Token, obj{"clientOpId": h.nextOp(), "exercise": "incline_push_up", "reps": 12}).expect(http.StatusCreated)
	h.post("/api/sets", nick.Token, obj{"clientOpId": h.nextOp(), "exercise": "air_squat", "reps": 50}).expect(http.StatusCreated)
	if got := h.get("/api/today", nick.Token).expect(http.StatusOK); got.num(q+".actual") != 12 {
		t.Fatalf("actual = %s", got.Body)
	}
}

func TestDailyRepsChangeReachesTodayEvenAfterReps(t *testing.T) {
	h := newHarness(t)
	nick := h.joinAdmin("Nick", "green")
	h.clock.Set(ny(2026, time.November, 3, 9, 0))
	q := todayQuest(t, h, nick, "pushups")

	// Today follows the new choice.
	put := h.put("/api/daily-reps", nick.Token, obj{"exercise": "lunge", "repsPerSet": 6}).expect(http.StatusOK)
	if put.str("dayExercise") != "lunge" || put.num("target") != 18 {
		t.Fatalf("put = %s", put.Body)
	}
	if got := h.get("/api/today", nick.Token).expect(http.StatusOK); got.str(q+".title") != "Lunges" || got.num(q+".target") != 18 {
		t.Fatalf("today = %s", got.Body)
	}

	// Logged reps do not hold the day back: like every goal edit, a switch applies today, and the
	// lunges already logged stop counting toward the new exercise.
	h.logActivity(nick, "pushups", "reps", 6).expect(http.StatusCreated)
	put = h.put("/api/daily-reps", nick.Token, obj{"exercise": "glute_bridge", "repsPerSet": 8}).expect(http.StatusOK)
	if put.str("exercise") != "glute_bridge" || put.str("dayExercise") != "glute_bridge" {
		t.Fatalf("put = %s", put.Body)
	}
	got := h.get("/api/today", nick.Token).expect(http.StatusOK)
	if got.str(q+".title") != "Glute bridges" || got.num(q+".target") != 24 || got.num(q+".actual") != 0 {
		t.Fatalf("today = %s", got.Body)
	}
}

func TestDailyRepsStartingSetWithoutAMaxRecordsNoTest(t *testing.T) {
	h := newHarness(t)
	nick := h.joinAdmin("Nick", "green")
	put := h.put("/api/daily-reps", nick.Token, obj{"exercise": "knee_push_up", "repsPerSet": 4}).expect(http.StatusOK)
	if put.num("target") != 12 || !put.isNull(dailyRepsEntry(t, put, "knee_push_up")+".latestMax") {
		t.Fatalf("put = %s", put.Body)
	}
	got := h.get("/api/targets", nick.Token).expect(http.StatusOK)
	p := targetPath(t, got, "pushups")
	if got.str(p+".details.exercise") != "knee_push_up" || got.length(p+".missing") != 1 ||
		!strings.Contains(got.str(p+".formula"), "knee push-ups") {
		t.Fatalf("target = %s", got.Body)
	}
}

func TestDailyRepsValidation(t *testing.T) {
	h := newHarness(t)
	nick := h.joinAdmin("Nick", "green")
	for name, body := range map[string]obj{
		"unknown exercise":      {"exercise": "deadlift", "max": 10},
		"no amount":             {"exercise": "air_squat"},
		"both amounts":          {"exercise": "air_squat", "max": 10, "repsPerSet": 5},
		"max too high":          {"exercise": "air_squat", "max": 201},
		"max zero":              {"exercise": "air_squat", "max": 0},
		"reps per set too high": {"exercise": "air_squat", "repsPerSet": 151},
		"reps per set zero":     {"exercise": "air_squat", "repsPerSet": 0},
		"missing exercise":      {"max": 10},
		"pull-up without a bar": {"exercise": "pull_up", "max": 5},
	} {
		if r := h.put("/api/daily-reps", nick.Token, body); r.Status != http.StatusUnprocessableEntity {
			t.Errorf("%s: status %d: %s", name, r.Status, r.Body)
		}
	}
	h.patch("/api/me", nick.Token, obj{"questTemplates": []obj{{"key": "steps", "exercise": "air_squat"}}}).expect(http.StatusUnprocessableEntity)
	if got := h.get("/api/daily-reps", nick.Token).expect(http.StatusOK); got.str("exercise") != "push_up" || got.num("target") != 30 {
		t.Fatalf("rejected requests changed the quest: %s", got.Body)
	}
}

func TestPullUpsNeedTheBarInTheTrainingProfile(t *testing.T) {
	h := newHarness(t)
	nick := h.joinAdmin("Nick", "green")
	got := h.get("/api/daily-reps", nick.Token).expect(http.StatusOK)
	if p := dailyRepsEntry(t, got, "pull_up"); got.flag(p+".available") || got.str(p+".needs") != "pullup_bar" {
		t.Fatalf("pull-up before the bar = %s", got.Body)
	}
	h.put("/api/daily-reps", nick.Token, obj{"exercise": "pull_up", "max": 5}).expect(http.StatusUnprocessableEntity)

	h.put("/api/training/profile", nick.Token, obj{"equipment": []string{"pullup_bar"}, "daysPerWeek": 3, "sessionMinutes": 45,
		"experience": "new", "focus": ""}).expect(http.StatusOK)
	got = h.get("/api/daily-reps", nick.Token).expect(http.StatusOK)
	if !got.flag(dailyRepsEntry(t, got, "pull_up") + ".available") {
		t.Fatalf("pull-up with the bar = %s", got.Body)
	}
	put := h.put("/api/daily-reps", nick.Token, obj{"exercise": "pull_up", "max": 5}).expect(http.StatusOK)
	if put.num("target") != 12 {
		t.Fatalf("pull-up target = %s", put.Body)
	}
}

func TestDailyRepsMaxTestSeedsTheDerivedTargetPerExercise(t *testing.T) {
	h := newHarness(t)
	nick := h.joinAdmin("Nick", "green")
	h.put("/api/daily-reps", nick.Token, obj{"exercise": "air_squat", "max": 20}).expect(http.StatusOK)
	got := h.get("/api/targets", nick.Token).expect(http.StatusOK)
	if p := targetPath(t, got, "pushups"); got.num(p+".value") != 45 || got.num(p+".details.latestMax") != 20 ||
		got.str(p+".details.exercise") != "air_squat" {
		t.Fatalf("squat target = %s", got.Body)
	}

	// A push-up max does not move the squat target, and the push-up max is its own.
	h.post("/api/pushups/max", nick.Token, obj{"reps": 40}).expect(http.StatusCreated)
	got = h.get("/api/targets", nick.Token).expect(http.StatusOK)
	if targetValue(t, got, "pushups") != 45 {
		t.Fatalf("squat target moved by a push-up max: %s", got.Body)
	}
	h.put("/api/daily-reps", nick.Token, obj{"exercise": "push_up", "repsPerSet": 10}).expect(http.StatusOK)
	got = h.get("/api/targets", nick.Token).expect(http.StatusOK)
	if p := targetPath(t, got, "pushups"); got.num(p+".details.latestMax") != 40 || got.num(p+".value") != 90 {
		t.Fatalf("push-up target = %s", got.Body)
	}
}

func TestProgressionAppliesPerExercise(t *testing.T) {
	h := newHarness(t)
	nick := h.joinAdmin("Nick", "green")
	h.put("/api/daily-reps", nick.Token, obj{"exercise": "air_squat", "max": 20}).expect(http.StatusOK)
	h.post("/api/pushups/max", nick.Token, obj{"reps": 40}).expect(http.StatusCreated)

	// Five full days of three sets of 15 squats, and every day three sets of 30 push-ups that
	// must not count toward the squat progression.
	for day := 3; day <= 7; day++ {
		h.clock.Set(ny(2026, time.November, day, 12, 0))
		for range 3 {
			h.logActivity(nick, "pushups", "reps", 15, obj{"exercise": "air_squat"}).expect(http.StatusCreated)
			h.logActivity(nick, "pushups", "reps", 30, obj{"exercise": "push_up"}).expect(http.StatusCreated)
		}
	}
	h.clock.Set(ny(2026, time.November, 9, 12, 0))
	got := h.get("/api/targets", nick.Token).expect(http.StatusOK)
	p := targetPath(t, got, "pushups")
	// 15 reps a set + 5% (0.75 -> 1) = 16 a set.
	if got.num(p+".details.repsPerSet") != 16 || got.num(p+".value") != 48 || !got.flag(p+".details.progressed") ||
		got.num(p+".details.daysCompleted7") != 5 {
		t.Fatalf("squat progression = %s", got.Body)
	}

	// The same week of push-ups would not have progressed squats the other way round: with the
	// push-up exercise chosen, its own 30 rep sets drive its progression from a max of 40.
	h.put("/api/daily-reps", nick.Token, obj{"exercise": "push_up", "repsPerSet": 30}).expect(http.StatusOK)
	got = h.get("/api/targets", nick.Token).expect(http.StatusOK)
	p = targetPath(t, got, "pushups")
	if got.num(p+".details.repsPerSet") != 32 || got.num(p+".details.daysCompleted7") != 5 {
		t.Fatalf("push-up progression = %s", got.Body)
	}
}
