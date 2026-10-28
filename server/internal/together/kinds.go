package together

import (
	"fmt"
	"hash/fnv"
	"math"
	"slices"

	"github.com/nc1107/new-me/server/internal/score"
)

// The v13 challenge kinds, all measured from stored data.
const (
	KindSleepNights = "sleep_nights"
	KindMealDays    = "meal_days"
	KindProteinDays = "protein_days"
	KindPushupReps  = "pushup_reps"
	KindYogaMinutes = "yoga_minutes"
	KindHabitMarks  = "habit_marks"
	KindActiveDays  = "active_days"
)

const (
	// bestWeekCap keeps a share within reach of what the person has really done: no more than
	// 125 percent of their best recent week.
	bestWeekCap = 1.25
	// MinHistoryDays is how many days with data a kind needs, in the two weeks before the
	// challenge, from each person before it can be picked.
	MinHistoryDays = 7
	// minOpenDays is how many days of the week a person must be home for a day-count kind.
	minOpenDays = 3
	// tieMargin is how close two attainments must be (in percent) to count as a tie.
	tieMargin = 1
)

// measured describes how a new kind is sized and worded.
type measured struct {
	kind string
	// dayCount kinds count days, are capped at 7 minus away days, and need open days.
	dayCount bool
	// round is what the share is rounded to; it is also the smallest share.
	round int
	// area names the part of life the kind is about, for the stored reason.
	area string
	// noun words an amount: "nights", "push-ups".
	noun  string
	title func(combined int) string
}

var measuredKinds = []measured{
	{KindSleepNights, true, 1, "Sleep", "nights", func(n int) string {
		return fmt.Sprintf("Sleep your target on %d nights together", n)
	}},
	{KindMealDays, true, 1, "Meal logging", "days", func(n int) string {
		return fmt.Sprintf("Log your meals on %d days together", n)
	}},
	{KindProteinDays, true, 1, "Protein", "days", func(n int) string {
		return fmt.Sprintf("Hit your protein on %d days together", n)
	}},
	{KindPushupReps, false, 5, "Push-ups", "push-ups", func(n int) string {
		return fmt.Sprintf("Do %d push-ups together", n)
	}},
	{KindYogaMinutes, false, 5, "Yoga", "min of yoga", func(n int) string {
		return fmt.Sprintf("Do %d minutes of yoga together", n)
	}},
	{KindHabitMarks, false, 1, "Habits", "habit marks", func(n int) string {
		return fmt.Sprintf("Mark %d habits together", n)
	}},
	{KindActiveDays, true, 1, "Activity", "days", func(n int) string {
		return fmt.Sprintf("Be active on %d days together", n)
	}},
}

func measuredFor(kind string) (measured, bool) {
	for _, m := range measuredKinds {
		if m.kind == kind {
			return m, true
		}
	}
	return measured{}, false
}

// AllKinds lists every challenge kind, the measured ones after the four older ones.
func AllKinds() []string {
	out := []string{KindSteps, KindWorkouts, KindCountedDays, KindReading}
	for _, m := range measuredKinds {
		out = append(out, m.kind)
	}
	return out
}

// IsMeasured reports whether the kind is one of the v13 kinds that need history to be picked.
func IsMeasured(kind string) bool { _, ok := measuredFor(kind); return ok }

func measuredTitle(kind string, combined int) string {
	if m, ok := measuredFor(kind); ok {
		return m.title(combined)
	}
	return fmt.Sprintf("Reach %d together", combined)
}

// Recent is one person's own history of a measured kind in the two weeks before the challenge.
type Recent struct {
	// Last is the amount in the week just before, Before the week earlier.
	Last, Before int
	// HistoryDays is how many of those 14 days had any data of the kind.
	HistoryDays int
}

// Best is the larger of the two weeks.
func (r Recent) Best() int { return max(r.Last, r.Before) }

// MeasuredShare is the person's share of a measured kind: 110 percent of the average of their
// last two weeks, never over 125 percent of their best of those weeks, rounded to the kind's
// unit, at least one unit, and for day-count kinds never more than the days they are home.
func MeasuredShare(kind string, r Recent, awayDays int) int {
	m, ok := measuredFor(kind)
	if !ok {
		return 1
	}
	average := float64(r.Last+r.Before) / weeksOfHistory
	rounded := int(math.Round(average*stretch/float64(m.round))) * m.round
	// Rounding can lift a share over the cap, so the cap is applied to the rounded figure.
	if ceiling := float64(r.Best()) * bestWeekCap; float64(rounded) > ceiling {
		rounded = int(ceiling/float64(m.round)) * m.round
	}
	if m.dayCount {
		rounded = min(rounded, OpenDays(awayDays))
	}
	return max(rounded, m.round)
}

// OpenDays is how many days of a week are left once the away days are taken out.
func OpenDays(awayDays int) int { return max(daysInWeek-awayDays, 0) }

// Candidate is one kind the picker may choose, with what is known about the pair.
type Candidate struct {
	Kind string
	// People holds each person's recent history of the kind (measured kinds only).
	People []Recent
	// AwayDays is each person's away days of the challenge week, in the same order.
	AwayDays []int
	// Attainment is how much of their own targets the pair met over the last two weeks, in
	// percent, or -1 when the kind has no target to measure against.
	Attainment int
}

// Eligible reports whether the kind may be picked. The older kinds always may. A measured kind
// needs MinHistoryDays of data from everyone, and for day-count kinds enough days at home.
func (c Candidate) Eligible() bool {
	m, measuredKind := measuredFor(c.Kind)
	if !measuredKind {
		return true
	}
	if len(c.People) == 0 {
		return false
	}
	for i, p := range c.People {
		if p.HistoryDays < MinHistoryDays {
			return false
		}
		if m.dayCount && i < len(c.AwayDays) && OpenDays(c.AwayDays[i]) < minOpenDays {
			return false
		}
	}
	return true
}

// Pick is the chosen kind and why, in words the app can show.
type Pick struct {
	Kind   string
	Reason string
}

// PickKind chooses the week's kind among the eligible ones, never one used in the last two
// weeks (unless nothing else is eligible), favouring the area the pair has done least against
// their own targets. Kinds within a percentage point of each other are tied, and a hash of the
// week and kind breaks the tie, so the pick is stable for a week and varies between weeks.
func PickKind(week score.Date, recentKinds []string, cands []Candidate) Pick {
	var pool []Candidate
	for _, c := range cands {
		if c.Eligible() && !slices.Contains(recentKinds, c.Kind) {
			pool = append(pool, c)
		}
	}
	if len(pool) == 0 {
		for _, c := range cands {
			if c.Eligible() {
				pool = append(pool, c)
			}
		}
	}
	if len(pool) == 0 {
		return Pick{Kind: KindCountedDays, Reason: "Not enough history for another kind yet, so you count days together."}
	}
	lowest := math.MaxInt
	for _, c := range pool {
		lowest = min(lowest, rank(c))
	}
	var tied []Candidate
	for _, c := range pool {
		if rank(c) <= lowest+tieMargin {
			tied = append(tied, c)
		}
	}
	best := tied[0]
	for _, c := range tied[1:] {
		if weekHash(week, c.Kind) < weekHash(week, best.Kind) {
			best = c
		}
	}
	return Pick{Kind: best.Kind, Reason: reasonFor(best, len(tied) > 1)}
}

// rank orders candidates: a kind with no target to measure sorts after all that have one.
func rank(c Candidate) int {
	if c.Attainment < 0 {
		return 1000
	}
	return c.Attainment
}

func weekHash(week score.Date, kind string) uint32 {
	h := fnv.New32a()
	_, _ = h.Write([]byte(string(week) + "/" + kind))
	return h.Sum32()
}

func reasonFor(c Candidate, tie bool) string {
	area := areaOf(c.Kind)
	switch {
	case c.Attainment < 0:
		return fmt.Sprintf("%s was not used in the last two weeks, so it is next.", area)
	case tie:
		return fmt.Sprintf("%s is among your lowest areas against your own targets: %d%% lately.", area, c.Attainment)
	}
	return fmt.Sprintf("%s was your lowest area against your own targets: %d%% lately.", area, c.Attainment)
}

func areaOf(kind string) string {
	if m, ok := measuredFor(kind); ok {
		return m.area
	}
	switch kind {
	case KindSteps:
		return "Steps"
	case KindWorkouts:
		return "Workouts"
	case KindReading:
		return "Reading"
	}
	return "Counting days"
}

// Phrase words an amount of the kind with its unit, e.g. "12,000 steps" or "3 nights".
func Phrase(kind string, n int) string {
	switch kind {
	case KindSteps:
		return withThousands(n) + " steps"
	case KindWorkouts:
		if n == 1 {
			return "1 workout"
		}
		return fmt.Sprintf("%d workouts", n)
	case KindCountedDays:
		return dayWord(n)
	case KindReading:
		return fmt.Sprintf("%d min of reading", n)
	}
	if m, ok := measuredFor(kind); ok {
		if n == 1 && m.noun == "nights" {
			return "1 night"
		}
		if n == 1 && m.noun == "days" {
			return "1 day"
		}
		return fmt.Sprintf("%d %s", n, m.noun)
	}
	return fmt.Sprintf("%d", n)
}

func dayWord(n int) string {
	if n == 1 {
		return "1 day"
	}
	return fmt.Sprintf("%d days", n)
}
