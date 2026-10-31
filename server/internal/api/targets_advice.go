package api

import (
	"fmt"

	"github.com/nc1107/new-me/server/internal/insights"
	"github.com/nc1107/new-me/server/internal/plan"
	"github.com/nc1107/new-me/server/internal/readiness"
	"github.com/nc1107/new-me/server/internal/score"
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
		t.Why = "The health benefit of walking starts to level off between 5,000 and 7,000 steps a day, so 7,000 is a solid daily aim."
		if v > targets.DefaultSteps {
			t.Why = fmt.Sprintf("You already walk more than 7,000 a day, so this is the next step toward %s to %s, where the benefit levels off for your age.", plan.Thousands(low), plan.Thousands(high))
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
		t.Why = fmt.Sprintf("About what health bodies say is enough drinks a day for %s: 81%% of the water you need, the rest comes from food. You need more with activity and heat.", who)
		if d.Sex == nil {
			t.Why = "About what health bodies say is enough drinks a day for women, the lower figure. Set your sex in About you for yours."
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
		t.Why = fmt.Sprintf("WHO advises at least %d g of fruit and vegetables a day. One serving is %d g, so that is %d servings.", targets.ProduceWHOGrams, targets.ProduceServingGrams, targets.ProduceServings)
		t.Alternatives = targets.ProduceAlternatives()
	case tgtPushups:
		t.Cite = "Zourdos 2016"
	case tgtBreathing:
		t.Cite = "Balban 2023"
		t.Why = "Five minutes a day of cyclic sighing lifted mood in a month-long trial."
	case tgtReading:
		t.Cite = "Brysbaert 2019"
		t.Why = fmt.Sprintf("About %d pages: the time you chose, at the %d words a minute an adult reads and about %d words a page. No study sets how long to read, so the minutes are your call.",
			v, score.ReadingWPM, score.WordsPerPage)
	case tgtExercise:
		t.Cite = "WHO 2020"
		t.Why = fmt.Sprintf("WHO advises 150 to 300 minutes of moderate activity a week. Spread over the week that is about %d minutes a day.", v)
		t.Alternatives = targets.ExerciseAlternatives()
	}
}
