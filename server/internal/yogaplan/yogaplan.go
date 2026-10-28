// Package yogaplan places a person's weekly yoga days and decides when to offer a longer flow.
// It is pure, so the rules are unit tested without a database.
package yogaplan

import (
	"math/bits"
	"slices"

	"github.com/nc1107/new-me/server/internal/score"
)

// Flows are the flow lengths in minutes, shortest first.
var Flows = []int{10, 20, 30}

// DefaultDays is the starting weekly count. ACSM advises flexibility exercise on at least 2 to 3
// days a week, with more benefit from daily practice (Garber et al., Med Sci Sports Exerc
// 2011;43:1334); 3 is the top of that minimum range.
const DefaultDays = 3

// ProgressionWeeks is how many full weeks of finishing the plan precede the offer of a longer
// flow. It is New Me's own rule, not a trial result.
const ProgressionWeeks = 2

// lowerBody are the muscles whose work makes a strength day a lower-body day.
var lowerBody = []string{"quads", "hamstrings", "glutes"}

// Day is a strength plan day as placement reads it: its ISO weekday and exercise keys.
type Day struct {
	Weekday   int
	Exercises []string
}

// LowerBodyDays returns the ISO weekdays (1 is Monday) of strength days with at least two
// exercises whose primary muscle is a leg muscle: New Me's reading of a heavy lower-body day.
// primary maps an exercise key to its primary muscles.
func LowerBodyDays(days []Day, primary map[string][]string) map[int]bool {
	out := map[int]bool{}
	for _, d := range days {
		n := 0
		for _, key := range d.Exercises {
			if slices.ContainsFunc(primary[key], func(m string) bool { return slices.Contains(lowerBody, m) }) {
				n++
			}
		}
		if n >= 2 {
			out[d.Weekday] = true
		}
	}
	return out
}

// Place picks [days] ISO weekdays. It first avoids the weekdays in [avoid], as far as enough
// other days remain, then spreads the days as evenly as possible around the week, and prefers
// earlier weekdays on a tie. The result is sorted.
func Place(days int, avoid map[int]bool) []int {
	if days < 1 {
		return nil
	}
	days = min(days, 7)
	var best []int
	bestConflicts, bestGap := 8, -1
	for mask := 1; mask < 1<<7; mask++ {
		if bits.OnesCount(uint(mask)) != days {
			continue
		}
		var chosen []int
		conflicts := 0
		for d := 1; d <= 7; d++ {
			if mask&(1<<(d-1)) != 0 {
				chosen = append(chosen, d)
				if avoid[d] {
					conflicts++
				}
			}
		}
		gap := minGap(chosen)
		if conflicts < bestConflicts || (conflicts == bestConflicts && gap > bestGap) {
			best, bestConflicts, bestGap = chosen, conflicts, gap
		}
	}
	return best
}

// minGap is the smallest distance between neighbouring days, wrapping around the week.
func minGap(days []int) int {
	if len(days) == 1 {
		return 7
	}
	smallest := 7
	for i, d := range days {
		next := days[(i+1)%len(days)]
		smallest = min(smallest, (next-d+7)%7)
	}
	return smallest
}

// NextFlow is the next longer flow after [minutes], or 0 at the longest.
func NextFlow(minutes int) int {
	i := slices.Index(Flows, minutes)
	if i < 0 || i+1 >= len(Flows) {
		return 0
	}
	return Flows[i+1]
}

// Count is the number of days of the week starting at [week], up to and including [upTo], with
// yoga logged.
func Count(week score.Date, yogaDays map[score.Date]bool, upTo score.Date) int {
	n := 0
	for i := 0; i < 7; i++ {
		d := week.AddDays(i)
		if !d.After(upTo) && yogaDays[d] {
			n++
		}
	}
	return n
}

// OfferLonger reports whether the person finished the plan in each of the last
// [ProgressionWeeks] full weeks before the current one, all of them starting on or after [level]
// (when the current flow length began), and a longer flow exists. Finishing means yoga on at
// least as many days as the plan asks for.
func OfferLonger(today, level score.Date, daysPerWeek, flowMinutes int, yogaDays map[score.Date]bool) bool {
	if NextFlow(flowMinutes) == 0 {
		return false
	}
	thisWeek := score.WeekStart(today)
	for i := 1; i <= ProgressionWeeks; i++ {
		week := thisWeek.AddDays(-7 * i)
		if week.Before(level) || Count(week, yogaDays, week.AddDays(6)) < daysPerWeek {
			return false
		}
	}
	return true
}
