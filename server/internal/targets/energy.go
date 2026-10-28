// Package targets holds the formulas behind GET /api/targets: published equations, ratios and
// guideline values applied to a person's measurements. It is pure: no database and no clock.
// A measurement is only ever an input to a cited formula; nothing here is tuned to anyone's data.
package targets

import (
	"math"

	"github.com/nc1107/new-me/server/internal/insights"
	"github.com/nc1107/new-me/server/internal/score"
)

// Sex is the value the resting energy equation and the calorie floor and fiber tables need.
type Sex string

const (
	Male   Sex = "male"
	Female Sex = "female"
)

// Goal kinds.
const (
	Lose     = "lose"
	Maintain = "maintain"
	Gain     = "gain"
)

// Energy constants.
const (
	// KcalPerKg is the energy of a kilogram of body weight change (Hall et al., Lancet 2011).
	KcalPerKg = 7700
	// MaxLosePerWeekFraction is the most body weight to lose in a week (Helms 2014; Jensen 2014).
	MaxLosePerWeekFraction = 0.01
	// MaxGainPerWeekFraction is the most body weight to gain in a week (Helms 2014).
	MaxGainPerWeekFraction = 0.005
	// PaceStepKg is the granularity of a gain pace.
	PaceStepKg = 0.05
	// FloorKcalFemale and FloorKcalMale are the least daily energy (Jensen 2014).
	FloorKcalFemale = 1200
	FloorKcalMale   = 1500
	// kcalRound is the granularity of a calorie target.
	kcalRound = 50
	// DefaultSteps is the default daily step target (Ding 2025).
	DefaultSteps = 7000
)

// LosePaces are the paces offered for losing weight, in kg a week; imperial people are offered
// 0.5 and 1 lb (0.23 and 0.45 kg), so any pace in MinLosePace..MaxLosePace is accepted.
var LosePaces = []float64{0.25, 0.5}

// Accepted pace bounds, kg a week.
const (
	MinLosePace = 0.2
	MaxLosePace = 0.5
	MinGainPace = 0.05
)

// RestingEnergy is the Mifflin-St Jeor equation in kcal a day.
func RestingEnergy(kg, cm float64, age int, sex Sex) float64 {
	base := 10*kg + 6.25*cm - 5*float64(age)
	if sex == Male {
		return base + 5
	}
	return base - 161
}

// PAL is a physical activity level picked from the step band.
type PAL struct {
	Value float64
	// Band names the Tudor-Locke and Bassett step category in steps a day.
	Band string
}

// PALForSteps maps the 14-day average step count to a PAL. The step categories are Tudor-Locke
// and Bassett's; the PAL value inside each FAO/WHO/UNU 2004 range is our convention.
func PALForSteps(avgSteps float64) PAL {
	switch {
	case avgSteps < 7500:
		return PAL{1.4, "under 7,500"}
	case avgSteps < 10000:
		return PAL{1.55, "7,500 to 9,999"}
	case avgSteps < 12500:
		return PAL{1.7, "10,000 to 12,499"}
	}
	return PAL{1.85, "12,500 or more"}
}

// AverageSteps is the mean of the days with steps in the 14 complete days before today and how
// many days that is.
func AverageSteps(days []insights.StepDay, today score.Date) (avg float64, n int) {
	from, to := today.AddDays(-14), today.AddDays(-1)
	var sum float64
	for _, d := range days {
		if d.Steps > 0 && !d.Date.Before(from) && !d.Date.After(to) {
			sum += d.Steps
			n++
		}
	}
	if n == 0 {
		return 0, 0
	}
	return sum / float64(n), n
}

// MaxGainPace is 0.5% of body weight a week in kg, rounded to 0.05.
func MaxGainPace(weightKg float64) float64 {
	return math.Round(MaxGainPerWeekFraction*weightKg/PaceStepKg) * PaceStepKg
}

// CalorieInput is what the calorie target is derived from.
type CalorieInput struct {
	Resting  float64
	PAL      float64
	WeightKg float64
	Sex      Sex
	Kind     string
	// PaceKg is the chosen pace in kg a week; ignored for maintain.
	PaceKg float64
}

// Calories is the goal-adjusted daily energy and how it was reached.
type Calories struct {
	Maintenance float64
	// PaceKg is the pace actually used, after the body-weight cap.
	PaceKg     float64
	PaceCapped bool
	// PaceCapKg is the cap that applied to the goal kind, 0 for maintain.
	PaceCapKg float64
	// DeltaKcal is the daily energy added (gain) or removed (lose), before rounding.
	DeltaKcal float64
	Target    int
	Floor     int
	Floored   bool
}

// ComputeCalories applies the goal to maintenance: minus or plus the pace x 7,700 / 7, rounded
// to 50 kcal and never below the floor.
func ComputeCalories(in CalorieInput) Calories {
	out := Calories{Maintenance: in.Resting * in.PAL, PaceKg: in.PaceKg}
	switch in.Kind {
	case Lose:
		out.PaceCapKg = MaxLosePerWeekFraction * in.WeightKg
		out.DeltaKcal = -paceKcal(&out, in.PaceKg)
	case Gain:
		out.PaceCapKg = MaxGainPace(in.WeightKg)
		out.DeltaKcal = paceKcal(&out, in.PaceKg)
	default:
		out.PaceKg = 0
	}
	out.Target = roundTo(out.Maintenance+out.DeltaKcal, kcalRound)
	floor := FloorKcalFemale
	if in.Sex == Male {
		floor = FloorKcalMale
	}
	out.Floor = ceilTo(math.Max(in.Resting, float64(floor)), kcalRound)
	if out.Target < out.Floor {
		out.Target, out.Floored = out.Floor, true
	}
	return out
}

func paceKcal(c *Calories, pace float64) float64 {
	if pace > c.PaceCapKg {
		pace, c.PaceCapped = c.PaceCapKg, true
	}
	c.PaceKg = pace
	return pace * KcalPerKg / 7
}

func roundTo(v float64, step int) int { return int(math.Round(v/float64(step))) * step }

func ceilTo(v float64, step int) int { return int(math.Ceil(v/float64(step))) * step }

// Balance windows and data requirements for the estimate from logs.
const (
	BalanceMinSpanDays = 14
	BalanceMaxSpanDays = 28
	BalanceMinLogged   = 10
	BalanceMinWeighIns = 8
)

// BalanceInput is the history the energy balance reads.
type BalanceInput struct {
	Today score.Date
	// Readings are every weigh-in, oldest first; the trend is the v7 smoothed weight.
	Readings []insights.Reading
	// IntakeKcal is the logged energy of each day that has any; today is left out as unfinished.
	IntakeKcal map[score.Date]float64
}

// Balance is maintenance estimated as intake minus the change in body energy stores.
type Balance struct {
	// Kcal is nil until the data requirements are met.
	Kcal         *int
	AvgIntake    float64
	TrendChgKg   float64
	SpanDays     int
	WeighIns     int
	LoggedDays   int
	Missing      []string
	FirstWeighIn score.Date
	LastWeighIn  score.Date
}

// EstimateFromLogs needs a 14 to 28 day window with 10 or more days of logged intake and 8 or
// more weigh-ins (Racette 2012 energy balance; 7,700 kcal per kg, Hall 2011).
func EstimateFromLogs(in BalanceInput) Balance {
	windowStart := in.Today.AddDays(-BalanceMaxSpanDays)
	smoothed := insights.Smooth(in.Readings)
	var window []insights.WeightPoint
	for _, p := range smoothed {
		if !p.Date.Before(windowStart) && !p.Date.After(in.Today) {
			window = append(window, p)
		}
	}
	out := Balance{WeighIns: len(window)}
	if len(window) > 0 {
		first, last := window[0], window[len(window)-1]
		out.FirstWeighIn, out.LastWeighIn = first.Date, last.Date
		out.SpanDays = int(last.Date.Time().Sub(first.Date.Time()).Hours() / 24)
		out.TrendChgKg = last.Smoothed - first.Smoothed
		var sum float64
		for d, kcal := range in.IntakeKcal {
			if kcal > 0 && !d.Before(first.Date) && !d.After(last.Date) && d.Before(in.Today) {
				sum += kcal
				out.LoggedDays++
			}
		}
		if out.LoggedDays > 0 {
			out.AvgIntake = sum / float64(out.LoggedDays)
		}
	}
	if out.WeighIns < BalanceMinWeighIns {
		out.Missing = append(out.Missing, "weighIns")
	}
	if out.SpanDays < BalanceMinSpanDays {
		out.Missing = append(out.Missing, "spanDays")
	}
	if out.LoggedDays < BalanceMinLogged {
		out.Missing = append(out.Missing, "loggedDays")
	}
	if len(out.Missing) == 0 {
		kcal := int(math.Round(out.AvgIntake - out.TrendChgKg*KcalPerKg/float64(out.SpanDays)))
		out.Kcal = &kcal
	}
	return out
}
