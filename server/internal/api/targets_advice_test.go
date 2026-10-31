package api

import (
	"net/http"
	"strings"
	"testing"
)

func TestGoalTargetsCarryAPlainWhyACitationAndNamedAlternatives(t *testing.T) {
	h := newHarness(t)
	nick := h.joinAdmin("Nick", "green")
	h.bodyProfile(nick)
	got := h.get("/api/targets", nick.Token).expect(http.StatusOK)

	for _, key := range []string{"steps", "sleep", "water", "protein", "produce", "breathing", "exercise"} {
		p := targetPath(t, got, key)
		if got.str(p+".why") == "" || got.str(p+".cite") == "" {
			t.Errorf("%s has no why or cite: %s", key, got.Body)
		}
	}
	// 150 minutes a week spread over 7 days, rounded up.
	ex := targetPath(t, got, "exercise")
	if got.num(ex+".value") != 22 || got.str(ex+".unit") != "min" {
		t.Errorf("exercise = %s", got.Body)
	}
	if got.num(ex+".alternatives.0.value") != 43 {
		t.Errorf("exercise alternatives = %s", got.Body)
	}
	// EFSA: 2.5 L of total water for men, 81% of it from drinks.
	water := targetPath(t, got, "water")
	if got.num(water+".alternatives.0.value") != 2050 || !strings.Contains(got.str(water+".alternatives.0.label"), "EFSA") {
		t.Errorf("water alternatives = %s", got.Body)
	}
	protein := targetPath(t, got, "protein")
	if !strings.Contains(got.str(protein+".why"), "1.6 g per kg") || !strings.Contains(got.str(protein+".why"), "80 kg") {
		t.Errorf("protein why = %s", got.str(protein+".why"))
	}
	produce := targetPath(t, got, "produce")
	if !strings.Contains(got.str(produce+".formula"), "5 servings = 400 g") || got.length(produce+".details.servingExamples") != 4 {
		t.Errorf("produce = %s", got.Body)
	}
	resting, _ := got.at(targetPath(t, got, "restingEnergy")).(map[string]any)
	if _, has := resting["why"]; has {
		t.Errorf("resting energy should carry no why: %v", resting)
	}
}

func TestApplyingTheExerciseTargetSetsTheQuestGoal(t *testing.T) {
	h := newHarness(t)
	nick := h.joinAdmin("Nick", "green")
	h.bodyProfile(nick)
	h.post("/api/targets/apply", nick.Token, obj{"keys": []string{"exercise"}}).expect(http.StatusOK)
	got := h.get("/api/targets", nick.Token).expect(http.StatusOK)
	if p := targetPath(t, got, "exercise"); got.num(p+".current") != 22 {
		t.Errorf("exercise = %s", got.Body)
	}
}
