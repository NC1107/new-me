package targets

import (
	"fmt"
	"math"
)

// Alternative is another published figure a person can pick instead of the recommendation, with
// a label that says what the number is.
type Alternative struct {
	Value int    `json:"value"`
	Label string `json:"label"`
}

// Weekly activity guideline, minutes of moderate activity (WHO 2020; US Physical Activity
// Guidelines 2018).
const (
	ActivityWeekMinMin = 150
	ActivityWeekMaxMin = 300
)

// drinksShare is the part of total water that comes from drinks (National Academies 2005).
const drinksShare = 0.81

// DailyFromWeekly spreads a weekly figure over seven days, rounding up so a week of full days
// always reaches it.
func DailyFromWeekly(week int) int { return (week + 6) / 7 }

// ExerciseAlternatives is the top of the weekly guideline as daily minutes.
func ExerciseAlternatives() []Alternative {
	return []Alternative{
		{Value: DailyFromWeekly(ActivityWeekMaxMin), Label: "300 min a week, the top of the WHO range"},
	}
}

// WaterAlternatives is the EFSA adequate intake of total water for the sex, less the share that
// comes from food, so it is comparable with a count of drinks.
func WaterAlternatives(sex *Sex) []Alternative {
	totalL, who := 2.0, "women"
	if sex != nil && *sex == Male {
		totalL, who = 2.5, "men"
	}
	ml := int(math.Round(totalL*1000*drinksShare/100)) * 100
	return []Alternative{{Value: ml, Label: fmt.Sprintf("EFSA: %.1f L of total water for %s, the drinks part", totalL, who)}}
}

// SleepAlternatives are the ends of the 7 to 9 hours recommended for adults.
func SleepAlternatives() []Alternative {
	return []Alternative{
		{Value: MinSleepMin, Label: "The low end of the recommended 7 to 9 hours"},
		{Value: MaxSleepMin, Label: "The top of the recommended 7 to 9 hours"},
	}
}

// StepAlternatives are the ends of the age band where Paluch et al. 2022 found the benefit levels
// off, without the recommendation itself.
func StepAlternatives(low, high, recommended int) []Alternative {
	var out []Alternative
	if low != recommended {
		out = append(out, Alternative{Value: low, Label: "The low end of where the benefit levels off for your age"})
	}
	if high != recommended {
		out = append(out, Alternative{Value: high, Label: "The top of where the benefit levels off for your age"})
	}
	return out
}

// ProteinAlternatives are the RDA of 0.8 g/kg and the ISSN range of 1.4 to 2.0 g/kg (Jäger et al.
// 2017), each rounded to 5 g and left out when it equals the recommendation.
func ProteinAlternatives(weightKg float64, recommendedG int) []Alternative {
	round5 := func(perKg float64) int { return int(math.Round(perKg*weightKg/proteinRound)) * proteinRound }
	all := []Alternative{
		{Value: round5(0.8), Label: "0.8 g per kg, the RDA for adults who do not train"},
		{Value: round5(1.4), Label: "1.4 g per kg, the low end of the range for training"},
		{Value: round5(2.0), Label: "2.0 g per kg, the top of the range for training"},
	}
	var out []Alternative
	for _, a := range all {
		if a.Value != recommendedG && a.Value > 0 {
			out = append(out, a)
		}
	}
	return out
}

// ProduceAlternatives is the intake where Aune et al. 2017 found risk still falling.
func ProduceAlternatives() []Alternative {
	return []Alternative{{Value: ProduceLowestRiskGrams / ProduceServingGrams, Label: "800 g, where risk was still falling (Aune 2017)"}}
}

// ProduceExamples are single servings from the NHS 5 A Day guide.
var ProduceExamples = []string{
	"1 medium apple, banana, pear or orange",
	"2 plums, kiwis or satsumas",
	"3 heaped tablespoons of cooked vegetables",
	"1 cereal bowl of salad",
}
