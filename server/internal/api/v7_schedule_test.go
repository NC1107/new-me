package api

import (
	"net/http"
	"testing"
	"time"
)

func TestMeHasTheDefaultScheduleAndProteinState(t *testing.T) {
	h := newHarness(t)
	nick := h.joinAdmin("Nick", "green")
	got := h.get("/api/me", nick.Token).expect(http.StatusOK)
	if got.length("schedule.workdays") != 5 || got.num("schedule.workdays.0") != 1 || got.num("schedule.workdays.4") != 5 ||
		got.str("schedule.workday.wake") != "07:00" || got.str("schedule.workday.bed") != "23:00" ||
		got.str("schedule.dayOff.wake") != "07:00" || got.str("schedule.dayOff.bed") != "23:00" ||
		got.num("schedule.firstNotificationOffsetMin") != 10 {
		t.Fatalf("schedule = %s", got.Body)
	}
	if !got.flag("protein.auto") || got.num("protein.effective") != 100 || !got.isNull("protein.weightKg") ||
		!got.isNull("protein.suggested") {
		t.Fatalf("protein = %s", got.Body)
	}
	if !got.flag("notifications.milestones") || !got.flag("notifications.lookback") {
		t.Fatalf("notifications = %s", got.Body)
	}
}

func TestPatchScheduleIsPartialAndValidated(t *testing.T) {
	h := newHarness(t)
	nick := h.joinAdmin("Nick", "green")
	got := h.patch("/api/me", nick.Token, obj{"schedule": obj{
		"workdays":                   []int{1, 2, 3, 4},
		"workday":                    obj{"wake": "06:30"},
		"dayOff":                     obj{"wake": "09:15", "bed": "00:30"},
		"firstNotificationOffsetMin": 0,
	}}).expect(http.StatusOK)
	if got.length("schedule.workdays") != 4 || got.str("schedule.workday.wake") != "06:30" || got.str("schedule.workday.bed") != "23:00" ||
		got.str("schedule.dayOff.wake") != "09:15" || got.str("schedule.dayOff.bed") != "00:30" ||
		got.num("schedule.firstNotificationOffsetMin") != 0 {
		t.Fatalf("patched = %s", got.Body)
	}
	if again := h.get("/api/me", nick.Token).expect(http.StatusOK); again.str("schedule.dayOff.bed") != "00:30" {
		t.Fatalf("not persisted: %s", again.Body)
	}
	// An unrelated patch leaves the schedule alone, and an empty workday list means every day is off.
	if kept := h.patch("/api/me", nick.Token, obj{"name": "Nicholas"}).expect(http.StatusOK); kept.str("schedule.workday.wake") != "06:30" {
		t.Fatalf("an unrelated patch reset the schedule: %s", kept.Body)
	}
	if none := h.patch("/api/me", nick.Token, obj{"schedule": obj{"workdays": []int{}}}).expect(http.StatusOK); none.length("schedule.workdays") != 0 {
		t.Fatalf("workdays = %s", none.Body)
	}

	for name, body := range map[string]obj{
		"bad time":         {"workday": obj{"wake": "7am"}},
		"hour 24":          {"workday": obj{"bed": "24:00"}},
		"equal wake / bed": {"dayOff": obj{"wake": "08:00", "bed": "08:00"}},
		"offset too big":   {"firstNotificationOffsetMin": 361},
		"offset negative":  {"firstNotificationOffsetMin": -1},
		"weekday 8":        {"workdays": []int{1, 8}},
		"weekday 0":        {"workdays": []int{0}},
	} {
		got := h.patch("/api/me", nick.Token, obj{"schedule": body})
		if got.Status != http.StatusUnprocessableEntity {
			t.Errorf("%s: status %d, body %s", name, got.Status, got.Body)
		}
	}
	h.patch("/api/me", nick.Token, obj{"schedule": obj{"nonsense": 1}}).expect(http.StatusBadRequest)
	if bad := h.get("/api/me", nick.Token).expect(http.StatusOK); bad.str("schedule.workday.bed") != "23:00" {
		t.Fatalf("a refused patch changed something: %s", bad.Body)
	}
}

func TestOtherActivityLogsCountTowardExerciseMinutes(t *testing.T) {
	h := newHarness(t)
	nick := h.joinAdmin("Nick", "green")
	other := func(name string, minutes int, intensity string) *response {
		return h.post("/api/logs", nick.Token, obj{"clientOpId": h.nextOp(), "kind": "activity", "type": "other",
			"name": name, "minutes": minutes, "intensity": intensity})
	}
	created := other("Horse riding", 40, "easy").expect(http.StatusCreated)
	if created.str("log.type") != "other" || created.str("log.name") != "Horse riding" || created.str("log.intensity") != "easy" ||
		created.num("log.quantity") != 40 || created.str("log.unit") != "minutes" {
		t.Fatalf("log = %s", created.Body)
	}
	if ex := questsByKey(dayOf(created))["exercise"]; ex.actual != 20 {
		t.Fatalf("easy counts half: %+v", ex)
	}
	moderate := other("Rowing", 10, "moderate").expect(http.StatusCreated)
	if ex := questsByKey(dayOf(moderate))["exercise"]; ex.actual != 30 || !ex.done {
		t.Fatalf("moderate counts fully: %+v", ex)
	}
	hard := other("Sprints", 5, "hard").expect(http.StatusCreated)
	if ex := questsByKey(dayOf(hard))["exercise"]; ex.actual != 35 {
		t.Fatalf("hard counts fully: %+v", ex)
	}

	listed := h.get("/api/logs", nick.Token).expect(http.StatusOK)
	if listed.length("logs") != 3 || listed.str("logs.0.name") != "Horse riding" {
		t.Fatalf("logs = %s", listed.Body)
	}
	// Quantity works as a synonym for minutes, and deleting rescores.
	viaQuantity := h.post("/api/logs", nick.Token, obj{"clientOpId": h.nextOp(), "kind": "activity", "type": "other",
		"name": "Gardening", "quantity": 20, "intensity": "hard"}).expect(http.StatusCreated)
	if viaQuantity.num("log.quantity") != 20 {
		t.Fatalf("quantity = %s", viaQuantity.Body)
	}
	deleted := h.delete("/api/logs/"+itoa(viaQuantity.num("log.id")), nick.Token).expect(http.StatusOK)
	if ex := questsByKey(dayOf(deleted))["exercise"]; ex.actual != 35 {
		t.Fatalf("after delete: %+v", ex)
	}

	bad := map[string]*response{
		"no name":       other("", 10, "easy"),
		"blank name":    other("   ", 10, "easy"),
		"long name":     other(string(make([]byte, 61)), 10, "easy"),
		"no intensity":  other("Walk", 10, ""),
		"bad intensity": other("Walk", 10, "brutal"),
		"zero minutes":  other("Walk", 0, "easy"),
		"too long":      other("Walk", 1441, "easy"),
		"both fields": h.post("/api/logs", nick.Token, obj{"clientOpId": h.nextOp(), "kind": "activity", "type": "other",
			"name": "Walk", "minutes": 10, "quantity": 20, "intensity": "easy"}),
		"intensity on a pushup": h.logActivity(nick, "pushups", "reps", 10, obj{"intensity": "easy"}),
		"minutes on a pushup":   h.logActivity(nick, "pushups", "reps", 10, obj{"minutes": 5}),
	}
	for name, r := range bad {
		if r.Status != http.StatusUnprocessableEntity {
			t.Errorf("%s: status %d, body %s", name, r.Status, r.Body)
		}
	}
}

// dayOf reads the day inside a log response, for questsByKey.
func dayOf(r *response) *response {
	return &response{t: r.t, Status: r.Status, Header: r.Header, Body: r.Body, parsed: r.at("day")}
}

func TestManualActivityStartsTheExerciseQuestBeforeHealthDoes(t *testing.T) {
	h := newHarness(t)
	nick := h.joinAdmin("Nick", "green")
	before := h.get("/api/today", nick.Token).expect(http.StatusOK)
	if before.num("day.maxBase") != 300 {
		t.Fatalf("exercise waits for data: %s", before.Body)
	}
	h.post("/api/logs", nick.Token, obj{"clientOpId": h.nextOp(), "kind": "activity", "type": "other",
		"name": "Run", "minutes": 30, "intensity": "hard"}).expect(http.StatusCreated)
	after := h.get("/api/today", nick.Token).expect(http.StatusOK)
	if after.num("day.maxBase") != 400 || after.num("day.basePoints") != 100 {
		t.Fatalf("a logged run connects the exercise quest: %s", after.Body)
	}
}

func TestNewPeopleStartWithSleepAndExerciseOn(t *testing.T) {
	h := newHarness(t)
	nick := h.joinAdmin("Nick", "green")
	me := h.get("/api/me", nick.Token).expect(http.StatusOK)
	for _, key := range []string{"questTemplates.6.", "questTemplates.7."} {
		if !me.flag(key + "enabled") {
			t.Fatalf("%s off: %s", key, me.Body)
		}
	}
	if me.flag("questTemplates.5.enabled") {
		t.Fatal("yoga stays off")
	}
}

func TestExistingPeopleGetProposalsToSwitchSleepAndExerciseOn(t *testing.T) {
	h := newHarness(t)
	nick := h.joinAdmin("Nick", "green")
	// Existing people have both quests off.
	h.patch("/api/me", nick.Token, obj{"questTemplates": []obj{
		{"key": "sleep", "enabled": false}, {"key": "exercise", "enabled": false}}}).expect(http.StatusOK)
	got := h.get("/api/goals/proposals", nick.Token).expect(http.StatusOK)
	kinds := map[string]string{}
	for i := range got.length("proposals") {
		kinds[got.str("proposals."+itoa(i)+".key")] = got.str("proposals." + itoa(i) + ".kind")
	}
	if len(kinds) != 2 || kinds["sleep"] != "enable" || kinds["exercise"] != "enable" {
		t.Fatalf("proposals = %s", got.Body)
	}

	me := h.post("/api/goals/proposals/exercise/accept", nick.Token, nil).expect(http.StatusOK)
	if !me.flag("questTemplates.6.enabled") || me.num("questTemplates.6.target") != 30 {
		t.Fatalf("accept = %s", me.Body)
	}
	h.post("/api/goals/proposals/sleep/dismiss", nick.Token, nil).expect(http.StatusNoContent)
	if left := h.get("/api/goals/proposals", nick.Token).expect(http.StatusOK); left.length("proposals") != 0 {
		t.Fatalf("decided proposals stay decided this week: %s", left.Body)
	}
	// Next week the dismissed offer stays quiet for four weeks.
	h.clock.Set(ny(2026, time.November, 9, 12, 0))
	if next := h.get("/api/goals/proposals", nick.Token).expect(http.StatusOK); next.length("proposals") != 0 {
		t.Fatalf("a dismissed offer came back after a week: %s", next.Body)
	}
	h.clock.Set(ny(2026, time.December, 7, 12, 0))
	if later := h.get("/api/goals/proposals", nick.Token).expect(http.StatusOK); later.length("proposals") != 1 ||
		later.str("proposals.0.key") != "sleep" {
		t.Fatalf("after four weeks: %s", later.Body)
	}
}

func TestProteinTargetFollowsWeightAndProposesWhenFarOff(t *testing.T) {
	h := newHarness(t)
	nick := h.joinAdmin("Nick", "green")
	h.putHealth(nick, "2026-11-02", "weight_kg", 82).expect(http.StatusOK)
	// 82 kg x 1.6 = 131.2 g, rounded to 130.
	me := h.get("/api/me", nick.Token).expect(http.StatusOK)
	if !me.flag("protein.auto") || me.num("protein.suggested") != 130 || me.num("protein.effective") != 130 ||
		me.num("protein.weightKg") != 82 {
		t.Fatalf("protein = %s", me.Body)
	}
	h.clock.Set(ny(2026, time.November, 3, 12, 0))
	if q := questsByKey(h.get("/api/today", nick.Token).expect(http.StatusOK))["protein"]; q.target != 130 {
		t.Fatalf("tomorrow's protein quest = %+v", q)
	}
	if got := h.get("/api/goals/proposals", nick.Token).expect(http.StatusOK); got.length("proposals") != 0 {
		t.Fatalf("the target is the per-kilogram one: %s", got.Body)
	}

	// A chosen target 20% or more away gets a proposal; 106 g (18%) does not.
	h.patch("/api/me", nick.Token, obj{"targets": obj{"protein": 100}}).expect(http.StatusOK)
	got := h.get("/api/goals/proposals", nick.Token).expect(http.StatusOK)
	if got.length("proposals") != 1 || got.str("proposals.0.key") != "protein" || got.num("proposals.0.current") != 100 ||
		got.num("proposals.0.proposed") != 130 || got.str("proposals.0.kind") != "target" || got.str("proposals.0.unit") != "g" {
		t.Fatalf("proposals = %s", got.Body)
	}
	accepted := h.post("/api/goals/proposals/protein/accept", nick.Token, nil).expect(http.StatusOK)
	if accepted.num("targets.protein") != 130 {
		t.Fatalf("accept = %s", accepted.Body)
	}
	h.clock.Set(ny(2026, time.November, 10, 12, 0))
	h.patch("/api/me", nick.Token, obj{"targets": obj{"protein": 106}}).expect(http.StatusOK)
	if got := h.get("/api/goals/proposals", nick.Token).expect(http.StatusOK); got.length("proposals") != 0 {
		t.Fatalf("106 g is within 20%% of 130 g: %s", got.Body)
	}
}
