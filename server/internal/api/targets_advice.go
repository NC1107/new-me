package api

import (
	"fmt"

	"github.com/nc1107/new-me/server/internal/insights"
	"github.com/nc1107/new-me/server/internal/plan"
	"github.com/nc1107/new-me/server/internal/readiness"
	"github.com/nc1107/new-me/server/internal/targets"
)

// addAdvice fills the plain line, the short citation and the other published figures for the
// targets a person sets as a daily goal. Targets without a value get none.
func (d targetData) addAdvice(t *targetJSON) {
	if t.Value == nil {
		return
	}
	v := *t.Value
	switch t.Key {
	case tgtSteps:
		low, high := insights.Band(d.Age)
		t.Cite = "Paluch 2022, Ding 2025"
		t.Why = "Around where the benefit of walking starts to level off, 5,000 to 7,000 steps."
		if v > targets.DefaultSteps {
			t.Why = fmt.Sprintf("You already walk more than 7,000, so this is the next step toward %s to %s for your age.", plan.Thousands(low), plan.Thousands(high))
		}
		t.Alternatives = targets.StepAlternatives(low, high, v)
	case tgtSleep:
		t.Cite = "AASM and SRS 2015"
		t.Why = fmt.Sprintf("Adults need 7 to 9 hours, and %s is the middle of that range.", readiness.Duration(v))
		t.Alternatives = targets.SleepAlternatives()
	case tgtWater:
		t.Cite = "National Academies 2005"
		who := "women"
		if d.Sex != nil && *d.Sex == targets.Male {
			who = "men"
		}
		t.Why = fmt.Sprintf("The adequate intake of drinks for %s, about 81%% of total water. Needs rise with activity and heat.", who)
		if d.Sex == nil {
			t.Why = "The adequate intake of drinks for women, the lower figure. Set your sex in About you for yours."
		}
		t.Alternatives = targets.WaterAlternatives(d.Sex)
	case tgtProtein:
		t.Cite = "ISSN 2017"
		t.Alternatives = nil
		if d.WeightKg != nil {
			p := targets.ComputeProtein(d.User.GoalKind, *d.WeightKg, d.HeightCm)
			purpose := map[string]string{targets.Lose: "to keep muscle while you lose weight", targets.Gain: "to build muscle while you gain"}[d.User.GoalKind]
			if purpose == "" {
				purpose = "to maintain muscle"
			}
			t.Why = fmt.Sprintf("%s of your %s, %s.", d.perKg(p.PerKg, "g"), d.kg(*d.WeightKg, 1), purpose)
			t.Alternatives = targets.ProteinAlternatives(*d.WeightKg, v)
		}
	case tgtProduce:
		t.Cite = "WHO, NHS 5 A Day"
		t.Why = fmt.Sprintf("WHO advises at least %d g a day. One serving is %d g, so %d servings.", targets.ProduceWHOGrams, targets.ProduceServingGrams, targets.ProduceServings)
		t.Alternatives = targets.ProduceAlternatives()
	case tgtBreathing:
		t.Cite = "Balban 2023"
		t.Why = "Five minutes a day of cyclic sighing lifted mood in a month-long trial."
	case tgtExercise:
		t.Cite = "WHO 2020"
		t.Why = fmt.Sprintf("WHO advises 150 to 300 minutes of moderate activity a week. Spread over the week that is about %d minutes a day.", v)
		t.Alternatives = targets.ExerciseAlternatives()
	}
}
