package insights

import (
	"cmp"
	"math"
	"slices"

	"github.com/nc1107/new-me/server/internal/score"
)

// Workout is one workout on a local date.
type Workout struct {
	Type        string
	Date        score.Date
	DurationMin float64
}

// Summary is a count of workouts and their total minutes.
type Summary struct {
	Count   int `json:"count"`
	Minutes int `json:"minutes"`
}

// TypeSummary is a Summary for one workout type.
type TypeSummary struct {
	Type    string `json:"type"`
	Count   int    `json:"count"`
	Minutes int    `json:"minutes"`
}

// Last30 is the 30 day summary with its split by type.
type Last30 struct {
	Count   int           `json:"count"`
	Minutes int           `json:"minutes"`
	ByType  []TypeSummary `json:"byType"`
}

// Workouts is the workout part of the insights answer.
type Workouts struct {
	Week   Summary `json:"week"`
	Last30 Last30  `json:"last30"`
}

// WeekSummary totals the workouts on or after from, up to and including to.
func WeekSummary(workouts []Workout, from, to score.Date) Summary {
	var s Summary
	var minutes float64
	for _, w := range workouts {
		if !w.Date.Before(from) && !w.Date.After(to) {
			s.Count++
			minutes += w.DurationMin
		}
	}
	s.Minutes = int(math.Round(minutes))
	return s
}

// ComputeWorkouts summarizes this ISO week (Monday to today) and the last 30 days.
func ComputeWorkouts(workouts []Workout, today score.Date) Workouts {
	out := Workouts{
		Week:   WeekSummary(workouts, score.WeekStart(today), today),
		Last30: Last30{ByType: []TypeSummary{}},
	}
	from := today.AddDays(-29)
	minutes := map[string]float64{}
	counts := map[string]int{}
	var total float64
	for _, w := range workouts {
		if w.Date.Before(from) || w.Date.After(today) {
			continue
		}
		out.Last30.Count++
		total += w.DurationMin
		counts[w.Type]++
		minutes[w.Type] += w.DurationMin
	}
	out.Last30.Minutes = int(math.Round(total))
	for typ, n := range counts {
		out.Last30.ByType = append(out.Last30.ByType, TypeSummary{Type: typ, Count: n, Minutes: int(math.Round(minutes[typ]))})
	}
	slices.SortFunc(out.Last30.ByType, func(a, b TypeSummary) int {
		return cmp.Or(cmp.Compare(b.Minutes, a.Minutes), cmp.Compare(b.Count, a.Count), cmp.Compare(a.Type, b.Type))
	})
	return out
}
