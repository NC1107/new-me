package targets

import "math"

// Push-up constants. The target is a derivation from reps-in-reserve guidance (Zourdos 2016) and
// hypertrophy evidence for sets near failure (Schoenfeld 2017), not a published constant.
const (
	PushupSets     = 3
	PushupLowFrac  = 0.70
	PushupHighFrac = 0.80
	// PushupMidFrac is the midpoint of the 70 to 80% range.
	PushupMidFrac = 0.75
	// ProgressionFrac is the 5% increase (ACSM 2009 allows 2 to 10%); at least one rep.
	ProgressionFrac = 0.05
	// ProgressionDays of ProgressionWindow days with every set completed earn an increase.
	ProgressionDays   = 5
	ProgressionWindow = 7
)

// Pushups is the daily push-up target.
type Pushups struct {
	RepsPerSet int
	Low, High  int
	Max        int
	// Progressed is true when the per-set reps were raised by the progression rule.
	Progressed bool
	// ProgressedFrom is the per-set reps the person had been working with.
	ProgressedFrom int
}

// Daily is the reps over all sets.
func (p Pushups) Daily() int { return p.RepsPerSet * PushupSets }

func fracReps(maxReps int, f float64) int { return max(1, int(math.Round(f*float64(maxReps)))) }

// ComputePushups is 3 sets at 75% (midpoint of 70 to 80%) of the latest max. When the person
// completed every set of their current target on 5 of the last 7 days, the per-set reps rise by
// 5% (at least one rep) instead, if that is more.
func ComputePushups(maxReps, currentPerSet int, daysCompleted int) Pushups {
	out := Pushups{Max: maxReps, RepsPerSet: fracReps(maxReps, PushupMidFrac),
		Low: fracReps(maxReps, PushupLowFrac), High: fracReps(maxReps, PushupHighFrac)}
	if currentPerSet > 0 && daysCompleted >= ProgressionDays {
		next := ProgressedReps(currentPerSet)
		if next > out.RepsPerSet {
			out.RepsPerSet, out.Progressed, out.ProgressedFrom = next, true, currentPerSet
		}
	}
	return out
}

// ProgressedReps raises reps by 5%, at least one rep.
func ProgressedReps(reps int) int {
	return reps + max(1, int(math.Round(ProgressionFrac*float64(reps))))
}

// DayCompleted reports whether the day's logged sets (one log entry each) include a full set of
// the target's reps PushupSets times.
func DayCompleted(sets []int, perSet int) bool {
	n := 0
	for _, reps := range sets {
		if reps >= perSet {
			n++
		}
	}
	return perSet > 0 && n >= PushupSets
}
