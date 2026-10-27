// Package together holds what the two people share: the weekly challenge, the shared reward
// and the notifications about them. This file is the pure part; service.go wires it to data.
package together

import (
	"fmt"
	"math"
	"strconv"

	"github.com/nc1107/new-me/server/internal/score"
)

// Challenge kinds, in rotation order.
const (
	KindSteps       = "steps"
	KindWorkouts    = "workouts"
	KindCountedDays = "counted_days"
	KindReading     = "reading"
)

var rotation = []string{KindSteps, KindWorkouts, KindCountedDays, KindReading}

const (
	// stretch is how far above recent form a target is set: reachable, but a push.
	stretch = 1.1

	stepsRound        = 5000
	minSteps          = 5000
	defaultSteps      = 70000
	minWorkouts       = 3
	countedDaysTarget = 5
	readingRound      = 10
	minReading        = 60
	defaultReading    = 150
	weeksOfHistory    = 2
	daysInWeek        = 7
)

// Sizing is the recent history a target is sized from. Everything is combined across the pair.
type Sizing struct {
	// StepsDailyAverage is the sum of each person's average daily steps over the last two weeks.
	StepsDailyAverage float64
	// WorkoutsLastWeek is the number of workouts in the week before the challenge.
	WorkoutsLastWeek int
	// ReadingLastTwoWeeks is reading plus listening minutes over the two weeks before.
	ReadingLastTwoWeeks int
}

// Spec is a generated challenge before it is stored.
type Spec struct {
	Kind   string
	Title  string
	Target int
}

// KindFor rotates through the kinds by ISO week number of the week starting on the Monday.
func KindFor(weekStart score.Date) string {
	_, week := weekStart.Time().ISOWeek()
	return rotation[week%len(rotation)]
}

// Generate picks the week's challenge and sizes it.
func Generate(weekStart score.Date, in Sizing) Spec {
	kind := KindFor(weekStart)
	spec := Spec{Kind: kind}
	switch kind {
	case KindSteps:
		spec.Target = StepsTarget(in.StepsDailyAverage)
		spec.Title = "Walk " + withThousands(spec.Target) + " steps together"
	case KindWorkouts:
		spec.Target = WorkoutsTarget(in.WorkoutsLastWeek)
		spec.Title = fmt.Sprintf("Do %d workouts together", spec.Target)
	case KindCountedDays:
		spec.Target = countedDaysTarget
		spec.Title = fmt.Sprintf("Both count on %d of 7 days", spec.Target)
	default:
		spec.Target = ReadingTarget(in.ReadingLastTwoWeeks)
		spec.Title = fmt.Sprintf("Read %d minutes together", spec.Target)
	}
	return spec
}

// StepsTarget is 110 percent of the pair's combined daily average over a week, rounded to the
// nearest 5,000. Without history it falls back to a default rather than a trivial goal.
func StepsTarget(combinedDailyAverage float64) int {
	if combinedDailyAverage <= 0 {
		return defaultSteps
	}
	raw := combinedDailyAverage * daysInWeek * stretch
	rounded := int(math.Round(raw/stepsRound)) * stepsRound
	return max(rounded, minSteps)
}

// WorkoutsTarget is last week's combined workouts plus one, and never under three.
func WorkoutsTarget(lastWeek int) int { return max(lastWeek+1, minWorkouts) }

// ReadingTarget is 110 percent of the combined weekly minutes over the last two weeks, rounded
// to the nearest ten, with a floor and a default for a pair with no history.
func ReadingTarget(lastTwoWeeks int) int {
	if lastTwoWeeks <= 0 {
		return defaultReading
	}
	weekly := float64(lastTwoWeeks) / weeksOfHistory * stretch
	return max(int(math.Round(weekly/readingRound))*readingRound, minReading)
}

// Counted is a day on which one person's day counted.
type Counted struct {
	UserID int64
	Date   score.Date
}

// BothCountedDays is how many days every member counted on.
func BothCountedDays(counted []Counted, members []int64) int {
	if len(members) == 0 {
		return 0
	}
	perDay := map[score.Date]map[int64]bool{}
	for _, c := range counted {
		if perDay[c.Date] == nil {
			perDay[c.Date] = map[int64]bool{}
		}
		perDay[c.Date][c.UserID] = true
	}
	days := 0
	for _, who := range perDay {
		all := true
		for _, m := range members {
			all = all && who[m]
		}
		if all {
			days++
		}
	}
	return days
}

// RewardProgress is the combined points earned since the reward started, never below zero and
// never above the target it is shown against.
func RewardProgress(total, baseline, target int) int {
	return min(max(total-baseline, 0), target)
}

// RewardReached reports whether the combined points since the start cover the target.
func RewardReached(total, baseline, target int) bool { return total-baseline >= target }

// withThousands writes 120000 as "120,000".
func withThousands(n int) string {
	s := strconv.Itoa(n)
	for i := len(s) - 3; i > 0; i -= 3 {
		s = s[:i] + "," + s[i:]
	}
	return s
}
