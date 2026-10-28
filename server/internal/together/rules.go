// Package together holds what the two people share: the weekly challenge, the shared reward
// and the notifications about them. This file is the pure part; service.go wires it to data.
package together

import (
	"fmt"
	"math"
	"strconv"

	"github.com/nc1107/new-me/server/internal/score"
)

// Challenge kinds. The first four predate v13 and are always eligible; the rest are measured
// from stored data and need history, see kinds.go.
const (
	KindSteps       = "steps"
	KindWorkouts    = "workouts"
	KindCountedDays = "counted_days"
	KindReading     = "reading"
)

const (
	// stretch is how far above recent form a share is set: reachable, but a push.
	stretch = 1.1

	stepsRound        = 1000
	minSteps          = 10000
	defaultSteps      = 35000
	minWorkouts       = 2
	countedDaysTarget = 5
	readingRound      = 10
	minReading        = 30
	defaultReading    = 75
	weeksOfHistory    = 2
	daysInWeek        = 7
)

// Sizing is one person's own recent history, which their share of the challenge is sized from.
type Sizing struct {
	// StepsDailyAverage is the person's average daily steps over the last two weeks.
	StepsDailyAverage float64
	// WorkoutsLastWeek is the person's workouts in the week before the challenge.
	WorkoutsLastWeek int
	// ReadingLastTwoWeeks is the person's reading plus listening minutes over the two weeks before.
	ReadingLastTwoWeeks int
	// Recent holds the person's last two weeks of each measured kind (see kinds.go).
	Recent map[string]Recent
	// AwayDays is how many days of the challenge week the person has marked away.
	AwayDays int
}

// Spec is a generated challenge before it is stored. Target is the sum of the people's shares.
type Spec struct {
	Kind   string
	Title  string
	Target int
}

// Share is one person's share of a challenge of the kind, sized from their own history.
func Share(kind string, in Sizing) int {
	switch kind {
	case KindSteps:
		return StepsShare(in.StepsDailyAverage)
	case KindWorkouts:
		return WorkoutsShare(in.WorkoutsLastWeek)
	case KindCountedDays:
		return countedDaysTarget
	case KindReading:
		return ReadingShare(in.ReadingLastTwoWeeks)
	}
	return MeasuredShare(kind, in.Recent[kind], in.AwayDays)
}

// Generate words the challenge from the shares of the people taking part.
func Generate(kind string, shares []int) Spec {
	total := 0
	for _, share := range shares {
		total += share
	}
	return Spec{Kind: kind, Title: Title(kind, total), Target: total}
}

// Title words a challenge of the kind and combined target.
func Title(kind string, combined int) string {
	switch kind {
	case KindSteps:
		return "Walk " + withThousands(combined) + " steps together"
	case KindWorkouts:
		return fmt.Sprintf("Do %d workouts together", combined)
	case KindCountedDays:
		return fmt.Sprintf("Both count on %d of 7 days", countedDaysTarget)
	case KindReading:
		return fmt.Sprintf("Read %d minutes together", combined)
	}
	return measuredTitle(kind, combined)
}

// StepsShare is 110 percent of the person's weekly steps over the last two weeks, rounded to the
// nearest 1,000. Without history it falls back to a default rather than a trivial goal.
func StepsShare(dailyAverage float64) int {
	if dailyAverage <= 0 {
		return defaultSteps
	}
	raw := dailyAverage * daysInWeek * stretch
	rounded := int(math.Round(raw/stepsRound)) * stepsRound
	return max(rounded, minSteps)
}

// WorkoutsShare is the person's workouts of last week plus one, and never under two.
func WorkoutsShare(lastWeek int) int { return max(lastWeek+1, minWorkouts) }

// ReadingShare is 110 percent of the person's weekly minutes over the last two weeks, rounded to
// the nearest ten, with a floor and a default for someone with no history.
func ReadingShare(lastTwoWeeks int) int {
	if lastTwoWeeks <= 0 {
		return defaultReading
	}
	weekly := float64(lastTwoWeeks) / weeksOfHistory * stretch
	return max(int(math.Round(weekly/readingRound))*readingRound, minReading)
}

// Standing is one person's progress on their own share.
type Standing struct {
	UserID   int64
	Target   int
	Progress int
}

// Done reports whether the person reached their share.
func (s Standing) Done() bool { return s.Progress >= s.Target }

// Combined adds the people's progress, each capped at their own share so that one person
// cannot carry the other, and reports whether everyone reached their share. The challenge
// completes exactly when it does.
func Combined(people []Standing) (progress, target int, complete bool) {
	complete = len(people) > 0
	for _, p := range people {
		progress += min(p.Progress, p.Target)
		target += p.Target
		complete = complete && p.Done()
	}
	return progress, target, complete
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
