package api

import (
	"fmt"
	"net/http"
	"testing"
)

func TestCatalogCarriesKindAndPerSide(t *testing.T) {
	h := newHarness(t)
	nick := h.joinAdmin("Nick", "green")
	got := h.get("/api/exercises", nick.Token).expect(http.StatusOK)
	stretches := 0
	for i := 0; i < got.length("exercises"); i++ {
		p := fmt.Sprintf("exercises.%d.", i)
		kind := got.str(p + "kind")
		if kind != "strength" && kind != "stretch" && kind != "yoga" {
			t.Fatalf("%s has kind %q", got.str(p+"key"), kind)
		}
		if kind == "stretch" {
			stretches++
			if got.str(p+"measure") != "seconds" || got.str(p+"load") != "bodyweight" || got.length(p+"equipment") != 0 {
				t.Errorf("%s must be a bodyweight hold without equipment: %s", got.str(p+"key"), got.Body)
			}
		} else if got.flag(p + "perSide") {
			t.Errorf("%s is strength but perSide", got.str(p+"key"))
		}
	}
	if stretches != 12 {
		t.Fatalf("%d stretches, want 12", stretches)
	}
	i := exerciseIndex(t, got, "kneeling_hip_flexor_stretch")
	if got.str(fmt.Sprintf("exercises.%d.kind", i)) != "stretch" || !got.flag(fmt.Sprintf("exercises.%d.perSide", i)) {
		t.Fatalf("hip flexor stretch = %s", got.Body)
	}
	if j := exerciseIndex(t, got, "cat_stretch"); got.flag(fmt.Sprintf("exercises.%d.perSide", j)) {
		t.Fatalf("cat stretch is not per side")
	}
	if j := exerciseIndex(t, got, "push_up"); got.str(fmt.Sprintf("exercises.%d.kind", j)) != "strength" {
		t.Fatalf("push-up kind: %s", got.Body)
	}
}

func TestStretchSetsDoNotCountInWeeklyMuscleSets(t *testing.T) {
	h := newHarness(t)
	nick := h.joinAdmin("Nick", "green")
	h.put("/api/training/profile", nick.Token, obj{"equipment": []string{}, "daysPerWeek": 3, "sessionMinutes": 45,
		"experience": "experienced", "focus": ""}).expect(http.StatusOK)
	h.post("/api/sets", nick.Token, obj{"clientOpId": h.nextOp(), "exercise": "triceps_stretch", "seconds": 30}).expect(http.StatusCreated)
	h.post("/api/sets", nick.Token, obj{"clientOpId": h.nextOp(), "exercise": "cat_stretch", "seconds": 30}).expect(http.StatusCreated)
	got := h.get("/api/training/progress", nick.Token).expect(http.StatusOK)
	for i := 0; i < got.length("muscles"); i++ {
		if n := got.num(fmt.Sprintf("muscles.%d.weeks.3", i)); n != 0 {
			t.Fatalf("%s counts %d sets after only stretches: %s", got.str(fmt.Sprintf("muscles.%d.muscle", i)), n, got.Body)
		}
	}
}
