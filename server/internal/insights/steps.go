// Package insights holds the pure math behind GET /api/insights: step averages and the step
// goal suggestion, sleep statistics and workout summaries. It touches no database and no clock;
// the caller passes the person's local today.
package insights

import (
	"math"
	"slices"
	"strconv"

	"github.com/nc1107/new-me/server/internal/score"
)

const (
	// MinSuggestionDays is how many of the last 14 days need steps before a goal is suggested.
	MinSuggestionDays = 5
	// FloorTarget is the lowest step goal ever suggested.
	FloorTarget = 3000
	// trendThreshold is how far the last week must move from the one before to count as a trend.
	trendThreshold = 0.05
	// roundTo is the granularity of a suggested goal.
	roundTo = 500
	// raiseBy is how far above the person's own baseline a suggestion reaches.
	raiseBy = 1000

	TrendUp   = "up"
	TrendFlat = "flat"
	TrendDown = "down"
)

// StepDay is one day's step count.
type StepDay struct {
	Date  score.Date
	Steps float64
}

// BestDay is the day with the most steps.
type BestDay struct {
	Date  score.Date `json:"date"`
	Value int        `json:"value"`
}

// Suggestion is the step goal New Me proposes and what it was derived from.
type Suggestion struct {
	Target   int  `json:"target"`
	Median14 int  `json:"median14"`
	BandLow  int  `json:"bandLow"`
	BandHigh int  `json:"bandHigh"`
	AgeKnown bool `json:"ageKnown"`
}

// Steps is the step part of the insights answer.
type Steps struct {
	Avg7         int         `json:"avg7"`
	Avg30        int         `json:"avg30"`
	Median14     int         `json:"median14"`
	Trend        string      `json:"trend"`
	Best         *BestDay    `json:"best"`
	DaysAtGoal30 int         `json:"daysAtGoal30"`
	Goal         int         `json:"goal"`
	Suggestion   *Suggestion `json:"suggestion"`
}

// StepInput is everything the step insights read.
type StepInput struct {
	Days []StepDay
	// Today is the person's local today. Averages, the median, the trend and the suggestion
	// use the complete days before it, so a morning with few steps so far never drags them
	// down; the best day and the days at goal include today.
	Today score.Date
	Goal  int
	// BirthYear is nil while unknown.
	BirthYear *int
}

// ComputeSteps derives the step insights.
func ComputeSteps(in StepInput) Steps {
	byDate := make(map[score.Date]float64, len(in.Days))
	for _, d := range in.Days {
		if d.Steps > 0 {
			byDate[d.Date] = d.Steps
		}
	}
	window := func(from, to score.Date) []float64 {
		var out []float64
		for d := from; !d.After(to); d = d.AddDays(1) {
			if v, ok := byDate[d]; ok {
				out = append(out, v)
			}
		}
		return out
	}

	yesterday := in.Today.AddDays(-1)
	last7 := window(yesterday.AddDays(-6), yesterday)
	prev7 := window(yesterday.AddDays(-13), yesterday.AddDays(-7))
	last14 := window(yesterday.AddDays(-13), yesterday)
	last30 := window(yesterday.AddDays(-29), yesterday)

	out := Steps{
		Avg7:     int(math.Round(mean(last7))),
		Avg30:    int(math.Round(mean(last30))),
		Median14: int(math.Round(median(last14))),
		Trend:    trend(mean(last7), mean(prev7), len(last7) > 0 && len(prev7) > 0),
		Goal:     in.Goal,
	}
	for d := in.Today.AddDays(-29); !d.After(in.Today); d = d.AddDays(1) {
		v, ok := byDate[d]
		if !ok {
			continue
		}
		if out.Best == nil || int(math.Round(v)) >= out.Best.Value {
			out.Best = &BestDay{Date: d, Value: int(math.Round(v))}
		}
		if in.Goal > 0 && v >= float64(in.Goal) {
			out.DaysAtGoal30++
		}
	}
	if len(last14) >= MinSuggestionDays {
		s := Suggest(out.Median14, ageOn(in.Today, in.BirthYear))
		out.Suggestion = &s
	}
	return out
}

// ageOn is the age by calendar year, or nil when the birth year is unknown or in the future.
func ageOn(today score.Date, birthYear *int) *int {
	if birthYear == nil {
		return nil
	}
	year, err := strconv.Atoi(string(today)[:4])
	if err != nil || year < *birthYear {
		return nil
	}
	age := year - *birthYear
	return &age
}

// Band is the range of daily steps where most of the benefit is reached. Age is the only
// factor that moves it; body size does not.
func Band(age *int) (low, high int) {
	switch {
	case age == nil:
		return 7000, 10000
	case *age >= 60:
		return 6000, 8000
	default:
		return 8000, 10000
	}
}

// Suggest proposes a step goal from the median of the last two weeks and the age.
func Suggest(median14 int, age *int) Suggestion {
	low, high := Band(age)
	var target int
	switch {
	case median14 < low:
		target = min(ceilTo(median14+raiseBy, roundTo), low)
	case median14 < high:
		target = min(roundHalfUpTo(median14+raiseBy, roundTo), high)
	default:
		target = median14 / roundTo * roundTo
	}
	return Suggestion{Target: max(target, FloorTarget), Median14: median14, BandLow: low, BandHigh: high, AgeKnown: age != nil}
}

func ceilTo(n, step int) int { return (n + step - 1) / step * step }

func roundHalfUpTo(n, step int) int { return (n + step/2) / step * step }

func trend(recent, before float64, both bool) string {
	switch {
	case !both || before == 0:
		return TrendFlat
	case recent > before*(1+trendThreshold):
		return TrendUp
	case recent < before*(1-trendThreshold):
		return TrendDown
	}
	return TrendFlat
}

func mean(v []float64) float64 {
	if len(v) == 0 {
		return 0
	}
	var sum float64
	for _, x := range v {
		sum += x
	}
	return sum / float64(len(v))
}

func median(v []float64) float64 {
	if len(v) == 0 {
		return 0
	}
	s := slices.Clone(v)
	slices.Sort(s)
	if mid := len(s) / 2; len(s)%2 == 1 {
		return s[mid]
	}
	return (s[len(s)/2-1] + s[len(s)/2]) / 2
}
