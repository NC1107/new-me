// Package regularity judges one night of sleep against the person's own recent routine, which
// is what the steady-bedtime quest scores. It is pure: nights in, a verdict out.
//
// The research behind it is the Sleep Regularity Index (Phillips et al., Sci Rep 2017;7:3216),
// used by Windred et al. (Sleep 2024;47:zsad253) to show that regular timing predicts mortality
// beyond duration. Neither paper gives a per-night window a person can act on, so the window
// here is a product choice, set by the person; see docs/design-v17-quests.md.
package regularity

import (
	"math"
	"slices"
	"time"

	"github.com/nc1107/new-me/server/internal/score"
)

const (
	// BaselineDays is how many mornings before the night make up the usual bed and wake times.
	BaselineDays = 7
	// MinBaseline is the fewest earlier nights a usual time can be taken from; with fewer the
	// night is not judged, because a median of one or two nights is the night before, not a routine.
	MinBaseline = 3
	// Anchors is the number of times the quest checks: bedtime and wake time.
	Anchors = 2

	minutesPerDay = 24 * 60
)

// Night is one night by the morning it ends, with the instants the person went to bed and woke.
type Night struct {
	Date          score.Date
	BedAt, WakeAt time.Time
}

// Check is the verdict on one night.
type Check struct {
	// Measurable is false until the night exists and at least MinBaseline earlier nights do.
	Measurable     bool
	BaselineNights int
	WindowMin      int
	// BedMedian and WakeMedian are the usual times, as minutes after midnight in the person's zone.
	BedMedian, WakeMedian int
	// BedOffset and WakeOffset are minutes later (positive) or earlier (negative) than usual.
	BedOffset, WakeOffset int
	BedOK, WakeOK         bool
	// Hits is how many of the two times fell inside the window.
	Hits int
}

// Evaluate checks the night ending on date against the median bed and wake times of the nights
// in the seven mornings before it. Times are read on the wall clock of loc and compared round the
// clock, so 23:50 and 00:10 are 20 minutes apart.
func Evaluate(nights []Night, date score.Date, windowMin int, loc *time.Location) Check {
	out := Check{WindowMin: windowMin}
	var tonight *Night
	var beds, wakes []float64
	for i := range nights {
		n := nights[i]
		switch {
		case n.Date == date:
			tonight = &nights[i]
		case !n.Date.Before(date.AddDays(-BaselineDays)) && n.Date.Before(date):
			beds = append(beds, score.MinuteOfDay(n.BedAt, loc))
			wakes = append(wakes, score.MinuteOfDay(n.WakeAt, loc))
		}
	}
	out.BaselineNights = len(beds)
	if tonight == nil || len(beds) < MinBaseline {
		return out
	}
	out.Measurable = true
	bed, wake := circularMedian(beds), circularMedian(wakes)
	out.BedMedian, out.WakeMedian = int(math.Round(bed)), int(math.Round(wake))
	out.BedOffset = int(math.Round(signedGap(score.MinuteOfDay(tonight.BedAt, loc), bed)))
	out.WakeOffset = int(math.Round(signedGap(score.MinuteOfDay(tonight.WakeAt, loc), wake)))
	out.BedOK = abs(out.BedOffset) <= windowMin
	out.WakeOK = abs(out.WakeOffset) <= windowMin
	if out.BedOK {
		out.Hits++
	}
	if out.WakeOK {
		out.Hits++
	}
	return out
}

func abs(n int) int {
	if n < 0 {
		return -n
	}
	return n
}

// signedGap is how far a is from b on the clock, in (-720, 720]; positive means a is later.
func signedGap(a, b float64) float64 {
	d := math.Mod(a-b, minutesPerDay)
	if d > minutesPerDay/2 {
		d -= minutesPerDay
	}
	if d <= -minutesPerDay/2 {
		d += minutesPerDay
	}
	return d
}

// circularMedian is the median of times of day. It measures every time from the circular mean,
// takes the median of those signed gaps and adds it back, so a routine that straddles midnight
// has a usual time that is not noon.
func circularMedian(minutes []float64) float64 {
	var sin, cos float64
	for _, m := range minutes {
		angle := m / minutesPerDay * 2 * math.Pi
		sin += math.Sin(angle)
		cos += math.Cos(angle)
	}
	ref := math.Atan2(sin, cos) / (2 * math.Pi) * minutesPerDay
	gaps := make([]float64, len(minutes))
	for i, m := range minutes {
		gaps[i] = signedGap(m, ref)
	}
	slices.Sort(gaps)
	mid := len(gaps) / 2
	median := gaps[mid]
	if len(gaps)%2 == 0 {
		median = (gaps[mid-1] + gaps[mid]) / 2
	}
	out := math.Mod(ref+median, minutesPerDay)
	if out < 0 {
		out += minutesPerDay
	}
	return out
}
