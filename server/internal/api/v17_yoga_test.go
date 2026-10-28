package api

import (
	"fmt"
	"net/http"
	"slices"
	"strings"
	"testing"
	"time"
)

func TestYogaPosesAreCatalogHoldsWithCreditedPhotos(t *testing.T) {
	h := newHarness(t)
	nick := h.joinAdmin("Nick", "green")
	got := h.get("/api/exercises", nick.Token).expect(http.StatusOK)
	poses, groups := 0, map[string]int{}
	for i := 0; i < got.length("exercises"); i++ {
		p := fmt.Sprintf("exercises.%d.", i)
		if got.str(p+"kind") != "yoga" {
			if !got.isNull(p + "pose") {
				t.Errorf("%s is not yoga but has a pose", got.str(p+"key"))
			}
			continue
		}
		poses++
		key := got.str(p + "key")
		if got.str(p+"measure") != "seconds" || got.str(p+"load") != "bodyweight" || got.length(p+"equipment") != 0 {
			t.Errorf("%s must be a bodyweight hold: %s", key, got.Body)
		}
		if !strings.HasPrefix(key, "yoga_") || got.str(p+"pose.sanskrit") == "" || got.str(p+"pose.effect") == "" || got.str(p+"pose.holdNote") == "" {
			t.Errorf("%s is missing pose fields", key)
		}
		if n := got.length(p + "imageUrls"); n == 0 || n != got.length(p+"pose.imageCredits") {
			t.Errorf("%s has %d photos and %d credits", key, n, got.length(p+"pose.imageCredits"))
		}
		for j := 0; j < got.length(p+"pose.imageCredits"); j++ {
			c := fmt.Sprintf("%spose.imageCredits.%d.", p, j)
			if got.str(c+"author") == "" || got.str(c+"license") == "" || !strings.HasPrefix(got.str(c+"sourceUrl"), "https://commons.wikimedia.org/wiki/File:") {
				t.Errorf("%s credit %d incomplete: %s", key, j, got.Body)
			}
		}
		if n := got.length(p + "steps"); n < 3 || n > 6 {
			t.Errorf("%s has %d steps", key, n)
		}
		if got.length(p+"pose.cautions") == 0 {
			t.Errorf("%s has no caution", key)
		}
		groups[got.str(p+"pose.group")]++
	}
	if poses != 25 {
		t.Fatalf("%d poses, want 25", poses)
	}
	for _, g := range []string{"standing", "kneeling", "seated", "prone", "supine"} {
		if groups[g] == 0 {
			t.Errorf("no %s pose", g)
		}
	}
	if i := exerciseIndex(t, got, "yoga_warrior_i"); !got.flag(fmt.Sprintf("exercises.%d.perSide", i)) {
		t.Errorf("warrior I is done on each side")
	}
}

func TestYogaPhotosAreServedWithTheirCredit(t *testing.T) {
	h := newHarness(t)
	nick := h.joinAdmin("Nick", "green")
	for _, key := range []string{"yoga_mountain", "yoga_cat_cow"} {
		path := "/api/exercises/" + key + "/images/0"
		r := h.get(path, nick.Token).expect(http.StatusOK)
		if len(r.Body) < 1000 {
			t.Errorf("%s served %d bytes", path, len(r.Body))
		}
	}
	h.get("/api/exercises/yoga_mountain/images/1", nick.Token).expect(http.StatusNotFound)
	h.get("/api/exercises/yoga_cat_cow/images/1", nick.Token).expect(http.StatusOK)
}

func TestYogaPosesStayOutOfStrengthCounts(t *testing.T) {
	h := newHarness(t)
	nick := h.joinAdmin("Nick", "green")
	h.put("/api/training/profile", nick.Token, obj{"equipment": []string{}, "daysPerWeek": 3, "sessionMinutes": 45,
		"experience": "experienced", "focus": ""}).expect(http.StatusOK)
	h.post("/api/sets", nick.Token, obj{"clientOpId": h.nextOp(), "exercise": "yoga_bridge", "seconds": 30}).expect(http.StatusCreated)
	got := h.get("/api/training/progress", nick.Token).expect(http.StatusOK)
	for i := 0; i < got.length("muscles"); i++ {
		if n := got.num(fmt.Sprintf("muscles.%d.weeks.3", i)); n != 0 {
			t.Fatalf("%s counts %d sets after only a yoga pose: %s", got.str(fmt.Sprintf("muscles.%d.muscle", i)), n, got.Body)
		}
	}
}

func TestYogaPlanStartsWithTheACSMDefault(t *testing.T) {
	h := newHarness(t)
	nick := h.joinAdmin("Nick", "green")
	got := h.get("/api/yoga/plan", nick.Token).expect(http.StatusOK)
	if !got.isNull("plan") || got.num("suggested.daysPerWeek") != 3 || got.num("suggested.flowMinutes") != 10 ||
		got.length("suggested.weekdays") != 3 || !strings.Contains(got.str("citation"), "Garber") {
		t.Fatalf("no plan yet = %s", got.Body)
	}
}

func TestYogaPlanIsSavedPerPersonAndCounted(t *testing.T) {
	h := newHarness(t)
	nick, nadia := h.pair()
	h.put("/api/yoga/plan", nick.Token, obj{"daysPerWeek": 0, "flowMinutes": 10}).expect(http.StatusUnprocessableEntity)
	h.put("/api/yoga/plan", nick.Token, obj{"daysPerWeek": 8, "flowMinutes": 10}).expect(http.StatusUnprocessableEntity)
	h.put("/api/yoga/plan", nick.Token, obj{"daysPerWeek": 3, "flowMinutes": 15}).expect(http.StatusUnprocessableEntity)
	h.put("/api/yoga/plan", "", obj{"daysPerWeek": 3, "flowMinutes": 10}).expect(http.StatusUnauthorized)

	saved := h.put("/api/yoga/plan", nick.Token, obj{"daysPerWeek": 3, "flowMinutes": 10}).expect(http.StatusOK)
	if saved.num("plan.daysPerWeek") != 3 || saved.length("plan.weekdays") != 3 || saved.num("week.planned") != 3 || saved.num("week.done") != 0 {
		t.Fatalf("saved = %s", saved.Body)
	}
	if !h.get("/api/yoga/plan", nadia.Token).expect(http.StatusOK).isNull("plan") {
		t.Fatal("Nadia sees Nick's plan")
	}

	// 2026-11-02 is a Monday; the plan's first day is Monday with three evenly spread days.
	h.logActivity(nick, "yoga", "minutes", 12)
	got := h.get("/api/yoga/plan", nick.Token).expect(http.StatusOK)
	if got.num("week.done") != 1 || got.str("week.start") != "2026-11-02" || !got.flag("today.planned") || !got.flag("today.done") || got.num("today.flowMinutes") != 10 {
		t.Fatalf("after one flow = %s", got.Body)
	}

	h.put("/api/yoga/plan", nick.Token, obj{"daysPerWeek": 2, "flowMinutes": 20}).expect(http.StatusOK)
	if r := h.get("/api/yoga/plan", nick.Token).expect(http.StatusOK); r.num("plan.daysPerWeek") != 2 || r.num("plan.flowMinutes") != 20 || r.length("plan.weekdays") != 2 {
		t.Fatalf("replaced = %s", r.Body)
	}
}

func TestYogaDaysAvoidAHeavyLowerBodyDay(t *testing.T) {
	legDay := obj{"label": "Legs", "weekday": 1, "exercises": []obj{
		{"exercise": "push_up", "sets": 2, "min": 6, "max": 12, "rir": 2, "restSec": 90},
		{"exercise": "pull_up", "sets": 2, "min": 3, "max": 8, "rir": 2, "restSec": 90},
		{"exercise": "split_squat", "sets": 2, "min": 8, "max": 12, "rir": 2, "restSec": 90},
		{"exercise": "goblet_squat", "sets": 2, "min": 8, "max": 12, "rir": 2, "restSec": 90},
		{"exercise": "db_romanian_deadlift", "sets": 2, "min": 8, "max": 12, "rir": 2, "restSec": 90}}}
	upper := obj{"label": "Upper", "weekday": 4, "exercises": []obj{
		{"exercise": "push_up", "sets": 2, "min": 6, "max": 12, "rir": 2, "restSec": 90},
		{"exercise": "pull_up", "sets": 2, "min": 3, "max": 8, "rir": 2, "restSec": 90},
		{"exercise": "db_row", "sets": 2, "min": 6, "max": 10, "rir": 2, "restSec": 90},
		{"exercise": "db_overhead_press", "sets": 2, "min": 6, "max": 10, "rir": 2, "restSec": 90}}}
	h, _, nick := trainingHarness(t, obj{"weeks": 4, "notes": "Legs then upper.", "days": []obj{legDay, upper}})
	h.put("/api/training/profile", nick.Token, beginnerProfile).expect(http.StatusOK)
	h.post("/api/training/plan", nick.Token, obj{}).expect(http.StatusCreated)

	got := h.get("/api/yoga/plan", nick.Token).expect(http.StatusOK)
	if got.length("avoidedDays") != 1 || got.num("avoidedDays.0") != 1 {
		t.Fatalf("only Monday is a heavy lower-body day: %s", got.Body)
	}
	for _, days := range []int{1, 2, 3, 4, 5, 6} {
		saved := h.put("/api/yoga/plan", nick.Token, obj{"daysPerWeek": days, "flowMinutes": 10}).expect(http.StatusOK)
		var weekdays []int
		for i := 0; i < saved.length("plan.weekdays"); i++ {
			weekdays = append(weekdays, saved.num(fmt.Sprintf("plan.weekdays.%d", i)))
		}
		if slices.Contains(weekdays, 1) || len(weekdays) != days {
			t.Errorf("%d days placed on %v, which includes the leg day", days, weekdays)
		}
	}
}

func TestALongerFlowIsOfferedAfterTwoFinishedWeeks(t *testing.T) {
	h := newHarness(t)
	// Joining first at the plan's start, because days before an account are closed.
	h.clock.Set(ny(2026, time.October, 19, 12, 0))
	nick := h.joinAdmin("Nick", "green")
	// The plan starts two Mondays back, so the two weeks before this one began at this level.
	h.clock.Set(ny(2026, time.October, 19, 12, 0))
	h.put("/api/yoga/plan", nick.Token, obj{"daysPerWeek": 2, "flowMinutes": 10}).expect(http.StatusOK)
	logOn := func(day int, month time.Month) {
		h.clock.Set(ny(2026, month, day, 12, 0))
		h.logActivity(nick, "yoga", "minutes", 10).expect(http.StatusCreated)
	}
	logOn(19, time.October)
	logOn(22, time.October)
	logOn(26, time.October)
	logOn(29, time.October)

	h.clock.Set(ny(2026, time.November, 2, 12, 0))
	got := h.get("/api/yoga/plan", nick.Token).expect(http.StatusOK)
	if !got.flag("progression.offer") || got.num("progression.nextMinutes") != 20 {
		t.Fatalf("two finished weeks should offer 20 minutes: %s", got.Body)
	}

	// Declining restarts the count at the same length.
	h.put("/api/yoga/plan", nick.Token, obj{"daysPerWeek": 2, "flowMinutes": 10, "restartLevel": true}).expect(http.StatusOK)
	if r := h.get("/api/yoga/plan", nick.Token).expect(http.StatusOK); r.flag("progression.offer") {
		t.Fatalf("declined offer came back at once: %s", r.Body)
	}

	// Accepting changes the flow and starts the count again.
	h.put("/api/yoga/plan", nick.Token, obj{"daysPerWeek": 2, "flowMinutes": 20}).expect(http.StatusOK)
	if r := h.get("/api/yoga/plan", nick.Token).expect(http.StatusOK); r.flag("progression.offer") || r.num("plan.flowMinutes") != 20 {
		t.Fatalf("after accepting = %s", r.Body)
	}
}

func TestNoOfferAfterOneShortWeek(t *testing.T) {
	h := newHarness(t)
	// Joining first at the plan's start, because days before an account are closed.
	h.clock.Set(ny(2026, time.October, 19, 12, 0))
	nick := h.joinAdmin("Nick", "green")
	h.clock.Set(ny(2026, time.October, 19, 12, 0))
	h.put("/api/yoga/plan", nick.Token, obj{"daysPerWeek": 2, "flowMinutes": 10}).expect(http.StatusOK)
	for _, day := range []int{19, 22, 26} {
		h.clock.Set(ny(2026, time.October, day, 12, 0))
		h.logActivity(nick, "yoga", "minutes", 10).expect(http.StatusCreated)
	}
	h.clock.Set(ny(2026, time.November, 2, 12, 0))
	if r := h.get("/api/yoga/plan", nick.Token).expect(http.StatusOK); r.flag("progression.offer") {
		t.Fatalf("a week with one flow must not offer: %s", r.Body)
	}
}
