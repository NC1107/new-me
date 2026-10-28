// Package recap computes the weekly recap: each person's and the pair's week against the week
// before, the best day, the challenge result and one suggestion. This file is the pure part;
// service.go reads the data.
package recap

import (
	"fmt"
	"math"

	"github.com/nc1107/new-me/server/internal/plan"
	"github.com/nc1107/new-me/server/internal/readiness"
	"github.com/nc1107/new-me/server/internal/score"
)

// Thresholds of the suggestion rules.
const (
	// CountedDaysGoal is the number of counted days a week should reach.
	CountedDaysGoal = 5
	// stepsSlipFraction is how far steps must fall from the week before to be called out.
	stepsSlipFraction = 0.10
	// sleepGoalMin is the average sleep below which the recap suggests an earlier bedtime.
	sleepGoalMin = 420
	// minSleepNights is how many nights an average needs.
	minSleepNights = 3
)

// DayPoints is one day's stored score.
type DayPoints struct {
	Date    score.Date
	Points  int
	Counted bool
}

// Week is one person's raw numbers for one ISO week.
type Week struct {
	Days           []DayPoints
	Steps          int
	AsleepNights   []int
	Workouts       int
	ReadingMinutes int
}

// Stats are the numbers the recap compares between weeks.
type Stats struct {
	Points         int `json:"points"`
	CountedDays    int `json:"countedDays"`
	Steps          int `json:"steps"`
	SleepAvgMin    int `json:"sleepAvgMin"`
	SleepNights    int `json:"sleepNights"`
	Workouts       int `json:"workouts"`
	ReadingMinutes int `json:"readingMinutes"`
}

// BestDay is the day with the most points.
type BestDay struct {
	Date   score.Date `json:"date"`
	Points int        `json:"points"`
}

// StatsOf totals one person's week.
func StatsOf(w Week) Stats {
	s := Stats{Steps: w.Steps, Workouts: w.Workouts, ReadingMinutes: w.ReadingMinutes, SleepNights: len(w.AsleepNights)}
	for _, d := range w.Days {
		s.Points += d.Points
		if d.Counted {
			s.CountedDays++
		}
	}
	if n := len(w.AsleepNights); n > 0 {
		sum := 0
		for _, m := range w.AsleepNights {
			sum += m
		}
		s.SleepAvgMin = int(math.Round(float64(sum) / float64(n)))
	}
	return s
}

// PairStats combines two people's stats. The sleep average is weighted by nights.
func PairStats(all ...Stats) Stats {
	var out Stats
	weighted := 0
	for _, s := range all {
		out.Points += s.Points
		out.CountedDays += s.CountedDays
		out.Steps += s.Steps
		out.Workouts += s.Workouts
		out.ReadingMinutes += s.ReadingMinutes
		out.SleepNights += s.SleepNights
		weighted += s.SleepAvgMin * s.SleepNights
	}
	if out.SleepNights > 0 {
		out.SleepAvgMin = int(math.Round(float64(weighted) / float64(out.SleepNights)))
	}
	return out
}

// Best returns the highest-scoring day, the earliest on a tie, or nil when no day scored.
func Best(days []DayPoints) *BestDay {
	var best *BestDay
	for _, d := range days {
		if d.Points > 0 && (best == nil || d.Points > best.Points || (d.Points == best.Points && d.Date.Before(best.Date))) {
			best = &BestDay{Date: d.Date, Points: d.Points}
		}
	}
	return best
}

// CombineDays adds several people's days date by date, for the pair's best day.
func CombineDays(people ...[]DayPoints) []DayPoints {
	byDate := map[score.Date]int{}
	var order []score.Date
	for _, days := range people {
		for _, d := range days {
			if _, seen := byDate[d.Date]; !seen {
				order = append(order, d.Date)
			}
			byDate[d.Date] += d.Points
		}
	}
	out := make([]DayPoints, len(order))
	for i, date := range order {
		out[i] = DayPoints{Date: date, Points: byDate[date]}
	}
	return out
}

// Suggest picks the one thing most worth changing next week, first match wins. A week that is
// not over yet gets an encouragement instead, since its numbers cannot be compared yet.
func Suggest(cur, prev Stats, complete bool) string {
	if !complete {
		// A partial week against a full one would always look like a slump.
		return "The week is still running. Keep going to make it a good one."
	}
	switch {
	case cur.CountedDays < CountedDaysGoal-1:
		return fmt.Sprintf("Aim for %d counted days next week. You had %d.", CountedDaysGoal, cur.CountedDays)
	case prev.Steps > 0 && float64(cur.Steps) < float64(prev.Steps)*(1-stepsSlipFraction):
		drop := int(math.Round((1 - float64(cur.Steps)/float64(prev.Steps)) * 100))
		return fmt.Sprintf("Steps slipped %d%% from the week before. One extra 20-minute walk a day gets them back.", drop)
	case cur.SleepNights >= minSleepNights && cur.SleepAvgMin < sleepGoalMin:
		return fmt.Sprintf("You averaged %s of sleep. Aim for an earlier bedtime on two nights.", readiness.Duration(cur.SleepAvgMin))
	case cur.Workouts == 0:
		return "No workouts this week. Plan two for next week."
	case prev.Points > 0 && cur.Points < prev.Points:
		return "Points dipped. Pick one quest to do first thing each day next week."
	}
	return fmt.Sprintf("Solid week. Keep the routine and try to beat %s points.", plan.Thousands(cur.Points))
}

// SummaryLine is the one-sentence push for a person: their week against the one before, plus the pair.
func SummaryLine(cur, prev, pair Stats) string {
	days := "counted days"
	if cur.CountedDays == 1 {
		days = "counted day"
	}
	line := fmt.Sprintf("%s points, %d %s, %s steps.", plan.Thousands(cur.Points), cur.CountedDays, days, plan.Thousands(cur.Steps))
	if prev.Points > 0 {
		change := int(math.Round((float64(cur.Points)/float64(prev.Points) - 1) * 100))
		switch {
		case change > 0:
			line += fmt.Sprintf(" Up %d%% on last week.", change)
		case change < 0:
			line += fmt.Sprintf(" Down %d%% on last week.", -change)
		default:
			line += " Level with last week."
		}
	}
	return line + fmt.Sprintf(" Together: %s points.", plan.Thousands(pair.Points))
}

// ScoredRange is the part of the week from monday that the board counts for a person whose local
// day is today: it stops at today, and stays inside the season the week's last counted day
// belongs to. The recap adds points over the same days, so the two always agree.
func ScoredRange(monday, today score.Date, seasons []score.Season) (from, to score.Date) {
	from, to = monday, monday.AddDays(6)
	if today.Before(monday) {
		return from, monday.AddDays(-1)
	}
	if today.Before(to) {
		to = today
	}
	if season, ok := score.SeasonFor(to, seasons); ok {
		if from.Before(season.StartsOn) {
			from = season.StartsOn
		}
		if season.EndsOn != nil && to.After(*season.EndsOn) {
			to = *season.EndsOn
		}
	}
	return from, to
}
