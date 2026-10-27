package api

import (
	"fmt"
	"net/http"
	"strings"
	"testing"
	"time"
)

// planReply is a two-day plan (Monday and Thursday) inside the beginner limits, with the given
// sets on every exercise.
func planReply(sets int) obj {
	ex := func(key string, lo, hi int) obj {
		return obj{"exercise": key, "sets": sets, "min": lo, "max": hi, "rir": 2, "restSec": 90}
	}
	day := func(label string, weekday int) obj {
		return obj{"label": label, "weekday": weekday, "exercises": []obj{ex("push_up", 6, 12), ex("pull_up", 3, 8),
			ex("db_row", 6, 10), ex("db_overhead_press", 6, 10), ex("split_squat", 8, 12)}}
	}
	return obj{"weeks": 4, "notes": "Two full-body days.", "days": []obj{day("Full body A", 1), day("Full body B", 4)}}
}

// plansFrom answers submit_plan calls with the queued plans in order, repeating the last.
func plansFrom(plans ...obj) func(map[string]any) any {
	n := 0
	return func(map[string]any) any {
		p := plans[min(n, len(plans)-1)]
		n++
		return obj{"id": "msg_1", "type": "message", "role": "assistant", "stop_reason": "tool_use",
			"content": []obj{{"type": "tool_use", "id": "tu_1", "name": "submit_plan", "input": p}}}
	}
}

var beginnerProfile = obj{"equipment": []string{"pullup_bar", "dumbbells"}, "dumbbellMaxKg": 30, "daysPerWeek": 2,
	"sessionMinutes": 40, "experience": "new", "focus": "first set of 10 pull-ups"}

func trainingHarness(t *testing.T, plans ...obj) (*harness, *fakeClaude, person) {
	t.Helper()
	f, srv := newFakeClaude(t)
	f.reply = plansFrom(plans...)
	h := newHarness(t, withClaude(srv), withPlannerClient(srv.URL))
	nick := h.joinAdmin("Nick", "green")
	return h, f, nick
}

func exerciseAt(t *testing.T, r *response, key string) string {
	t.Helper()
	for i := 0; i < r.length("session.exercises"); i++ {
		p := fmt.Sprintf("session.exercises.%d.", i)
		if r.str(p+"plan.exercise") == key {
			return p
		}
	}
	t.Fatalf("no %s in session: %s", key, r.Body)
	return ""
}

func TestTrainingIsOffWithoutAKey(t *testing.T) {
	h := newHarness(t)
	nick := h.joinAdmin("Nick", "green")
	h.put("/api/training/profile", nick.Token, beginnerProfile).expect(http.StatusOK)
	h.post("/api/training/plan", nick.Token, obj{}).code("training_disabled")
	got := h.get("/api/training/today", nick.Token).expect(http.StatusOK)
	if !got.isNull("plan") || !got.isNull("session") {
		t.Fatalf("today without a plan = %s", got.Body)
	}
}

func TestTrainingProfileValidation(t *testing.T) {
	h := newHarness(t)
	nick := h.joinAdmin("Nick", "green")
	if !h.get("/api/training/profile", nick.Token).expect(http.StatusOK).isNull("profile") {
		t.Fatal("no profile before the first save")
	}
	bad := func(field string, value any) {
		body := obj{}
		for k, v := range beginnerProfile {
			body[k] = v
		}
		body[field] = value
		h.put("/api/training/profile", nick.Token, body).expect(http.StatusUnprocessableEntity)
	}
	bad("equipment", []string{"kettlebell"})
	bad("daysPerWeek", 7)
	bad("sessionMinutes", 10)
	bad("experience", "pro")
	bad("dumbbellMaxKg", 0)
	bad("focus", strings.Repeat("x", 301))
	got := h.put("/api/training/profile", nick.Token, beginnerProfile).expect(http.StatusOK)
	if got.num("profile.daysPerWeek") != 2 || got.str("profile.equipment.1") != "dumbbells" ||
		got.str("profile.focus") != "first set of 10 pull-ups" {
		t.Fatalf("profile = %s", got.Body)
	}
}

func TestPlanNeedsAProfile(t *testing.T) {
	h, f, nick := trainingHarness(t, planReply(2))
	h.post("/api/training/plan", nick.Token, obj{}).code("no_training_profile")
	if f.count() != 0 {
		t.Fatal("no Claude call without a profile")
	}
}

func TestPlanSessionProgressionAndQuest(t *testing.T) {
	h, f, nick := trainingHarness(t, planReply(2))
	h.put("/api/training/profile", nick.Token, beginnerProfile).expect(http.StatusOK)
	created := h.post("/api/training/plan", nick.Token, obj{}).expect(http.StatusCreated)
	if created.str("plan.startsOn") != "2026-11-02" || created.str("plan.endsOn") != "2026-11-29" ||
		created.length("plan.days") != 2 || created.str("plan.days.0.exercises.2.exercise") != "db_row" {
		t.Fatalf("plan = %s", created.Body)
	}
	prompt := fmt.Sprint(f.requests[0]["messages"])
	if !strings.Contains(prompt, "first set of 10 pull-ups") || strings.Contains(prompt, "back_squat") {
		t.Fatalf("the prompt should carry the focus and only equipped exercises: %s", prompt)
	}

	monday := h.get("/api/training/today", nick.Token).expect(http.StatusOK)
	if monday.flag("restDay") || monday.str("session.label") != "Full body A" || monday.length("session.exercises") != 5 {
		t.Fatalf("monday = %s", monday.Body)
	}
	row := exerciseAt(t, monday, "db_row")
	if monday.num(row+"target.amount") != 6 || !strings.Contains(monday.str(row+"reason"), "First time") {
		t.Fatalf("first db row target = %s", monday.Body)
	}
	sessionID := monday.num("session.id")
	for range 2 {
		h.post("/api/sets", nick.Token, obj{"clientOpId": h.nextOp(), "exercise": "db_row", "reps": 10, "loadKg": 20, "rir": 2}).
			expect(http.StatusCreated)
	}
	h.post("/api/sets", nick.Token, obj{"clientOpId": h.nextOp(), "exercise": "push_up", "reps": 8, "sessionId": sessionID}).
		expect(http.StatusCreated)
	h.post("/api/sets", nick.Token, obj{"clientOpId": h.nextOp(), "exercise": "push_up", "reps": 8, "sessionId": 999}).
		expect(http.StatusNotFound)
	nadia := h.joinMember(h.invite(nick), "Nadia", "violet")
	h.post("/api/sets", nadia.Token, obj{"clientOpId": h.nextOp(), "exercise": "push_up", "reps": 8, "sessionId": sessionID}).
		expect(http.StatusNotFound)
	again := h.get("/api/training/today", nick.Token).expect(http.StatusOK)
	if again.num("session.id") != sessionID || again.length(exerciseAt(t, again, "db_row")+"logged") != 2 {
		t.Fatalf("logged sets should show on the session: %s", again.Body)
	}

	done := h.post(fmt.Sprintf("/api/training/sessions/%d/complete", sessionID), nick.Token, obj{}).expect(http.StatusOK)
	if !done.flag("session.completed") {
		t.Fatalf("complete = %s", done.Body)
	}
	for i := 0; i < done.length("day.quests"); i++ {
		p := fmt.Sprintf("day.quests.%d.", i)
		if done.str(p+"key") == "pushups" {
			// Like a qualifying workout, the session completes the quest while the shown reps stay
			// what was logged.
			if !done.flag(p+"done") || done.str(p+"doneBy.kind") != "session" || done.str(p+"doneBy.type") != "Full body A" {
				t.Fatalf("the session should complete the strength quest: %s", done.Body)
			}
		}
	}
	h.post(fmt.Sprintf("/api/training/sessions/%d/complete", sessionID), nick.Token, obj{}).expect(http.StatusOK)
	h.post("/api/training/sessions/999/complete", nick.Token, obj{}).expect(http.StatusNotFound)

	h.clock.Set(ny(2026, time.November, 3, 12, 0))
	if !h.get("/api/training/today", nick.Token).expect(http.StatusOK).flag("restDay") {
		t.Fatal("Tuesday is a rest day")
	}
	h.post("/api/sets", nick.Token, obj{"clientOpId": h.nextOp(), "exercise": "decline_push_up", "reps": 7}).
		expect(http.StatusCreated)

	h.clock.Set(ny(2026, time.November, 5, 12, 0))
	thursday := h.get("/api/training/today", nick.Token).expect(http.StatusOK)
	row = exerciseAt(t, thursday, "db_row")
	if thursday.str("session.label") != "Full body B" || thursday.num(row+"target.amount") != 6 ||
		thursday.at(row+"target.loadKg").(float64) != 22 || !strings.Contains(thursday.str(row+"reason"), "22 kg") {
		t.Fatalf("both sets at the top should add 2%% rounded to one dumbbell step: %s", thursday.Body)
	}
	push := exerciseAt(t, thursday, "push_up")
	if thursday.str(push+"exercise") != "decline_push_up" || thursday.str(push+"target.exercise") != "decline_push_up" ||
		thursday.num(push+"target.amount") != 8 || thursday.str(push+"planName") != "Push-up" {
		t.Fatalf("after logging the harder variation, the session should follow it: %s", thursday.Body)
	}

	h.clock.Set(ny(2026, time.November, 30, 12, 0))
	if !h.get("/api/training/today", nick.Token).expect(http.StatusOK).flag("blockEnded") {
		t.Fatal("the block ends after four weeks")
	}
}

func TestPlanRepairAndRejection(t *testing.T) {
	h, f, nick := trainingHarness(t, planReply(1), planReply(2))
	h.put("/api/training/profile", nick.Token, beginnerProfile).expect(http.StatusOK)
	h.post("/api/training/plan", nick.Token, obj{}).expect(http.StatusCreated)
	if f.count() != 2 {
		t.Fatalf("one repair round expected, got %d calls", f.count())
	}

	h2, _, nadia := trainingHarness(t, planReply(1))
	h2.put("/api/training/profile", nadia.Token, beginnerProfile).expect(http.StatusOK)
	bad := h2.post("/api/training/plan", nadia.Token, obj{}).code("plan_invalid")
	if bad.length("violations") == 0 || !h2.get("/api/training/plan", nadia.Token).isNull("plan") {
		t.Fatalf("a rejected plan must not save: %s", bad.Body)
	}
}

func TestPlanChangesReplaceTheActivePlan(t *testing.T) {
	h, f, nick := trainingHarness(t, planReply(2))
	h.put("/api/training/profile", nick.Token, beginnerProfile).expect(http.StatusOK)
	h.post("/api/training/plan/change", nick.Token, obj{"kind": "swap", "detail": "pull-ups"}).code("no_plan")
	first := h.post("/api/training/plan", nick.Token, obj{"weeks": 6}).expect(http.StatusCreated)
	h.post("/api/training/plan", nick.Token, obj{"weeks": 9}).expect(http.StatusUnprocessableEntity)
	h.post("/api/training/plan/change", nick.Token, obj{"kind": "teleport"}).expect(http.StatusUnprocessableEntity)
	changed := h.post("/api/training/plan/change", nick.Token, obj{"kind": "pain", "detail": "left elbow"}).
		expect(http.StatusCreated)
	if changed.num("plan.id") == first.num("plan.id") {
		t.Fatal("a change saves a new plan")
	}
	last := fmt.Sprint(f.requests[len(f.requests)-1]["messages"])
	if !strings.Contains(last, "Current plan:") || !strings.Contains(last, "left elbow") {
		t.Fatalf("the change prompt should carry the plan and the detail: %s", last)
	}
	if h.get("/api/training/plan", nick.Token).num("plan.id") != changed.num("plan.id") {
		t.Fatal("the changed plan should be active")
	}
	h.delete("/api/training/plan", nick.Token).expect(http.StatusNoContent)
	if !h.get("/api/training/plan", nick.Token).isNull("plan") {
		t.Fatal("deleting ends the plan")
	}
}

func TestTrainingProgressCountsWeeklySetsPerMuscle(t *testing.T) {
	h := newHarness(t)
	nick := h.joinAdmin("Nick", "green")
	h.put("/api/training/profile", nick.Token, obj{"equipment": []string{}, "daysPerWeek": 3, "sessionMinutes": 45,
		"experience": "experienced", "focus": ""}).expect(http.StatusOK)
	for _, key := range []string{"push_up", "push_up", "split_squat"} {
		h.post("/api/sets", nick.Token, obj{"clientOpId": h.nextOp(), "exercise": key, "reps": 10}).expect(http.StatusCreated)
	}
	got := h.get("/api/training/progress", nick.Token).expect(http.StatusOK)
	if got.num("range.min") != 10 || got.num("range.max") != 20 || got.str("weeksStart") != "2026-10-12" {
		t.Fatalf("progress = %s", got.Body)
	}
	weeks := map[string]int{}
	for i := 0; i < got.length("muscles"); i++ {
		weeks[got.str(fmt.Sprintf("muscles.%d.muscle", i))] = got.num(fmt.Sprintf("muscles.%d.weeks.3", i))
	}
	if weeks["chest"] != 2 || weeks["quads"] != 1 || weeks["glutes"] != 1 || weeks["back"] != 0 {
		t.Fatalf("this week = %v", weeks)
	}
}

func TestATodaySessionWithSetsSurvivesAPlanChange(t *testing.T) {
	// The new plan lists its days the other way round, so index 1 is now Monday's day.
	reordered := planReply(2)
	days := reordered["days"].([]obj)
	days[0]["label"], days[1]["label"] = "New A", "New B"
	reordered["days"] = []obj{days[1], days[0]}
	h, _, nick := trainingHarness(t, planReply(2), reordered)
	profile := obj{}
	for k, v := range beginnerProfile {
		profile[k] = v
	}
	h.put("/api/training/profile", nick.Token, profile).expect(http.StatusOK)
	h.post("/api/training/plan", nick.Token, obj{}).expect(http.StatusCreated)

	// Thursday is day index 1 of the first plan.
	h.clock.Set(ny(2026, time.November, 5, 12, 0))
	thursday := h.get("/api/training/today", nick.Token).expect(http.StatusOK)
	h.post("/api/sets", nick.Token, obj{"clientOpId": h.nextOp(), "exercise": "push_up", "reps": 8,
		"sessionId": thursday.num("session.id")}).expect(http.StatusCreated)

	h.post("/api/training/plan/change", nick.Token, obj{"kind": "shorter"}).expect(http.StatusCreated)
	after := h.get("/api/training/today", nick.Token).expect(http.StatusOK)
	if after.num("session.id") != thursday.num("session.id") || after.str("session.label") != "Full body B" ||
		after.length(exerciseAt(t, after, "push_up")+"logged") != 1 {
		t.Fatalf("the started session should keep its own plan day: %s", after.Body)
	}
}
