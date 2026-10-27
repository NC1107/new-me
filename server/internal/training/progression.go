package training

import (
	"fmt"
	"math"
)

// Prescription is how a plan asks for one exercise on a training day.
type Prescription struct {
	Exercise string
	Sets     int
	// Min and Max are the rep range, or the seconds range for a timed exercise.
	Min int
	Max int
	// RIR is the target reps in reserve on each set.
	RIR     int
	RestSec int
}

// ExerciseInfo is what progression needs to know about an exercise.
type ExerciseInfo struct {
	Key       string
	Name      string
	Timed     bool
	Loaded    bool
	Lower     bool
	EasierKey string
	HarderKey string
}

// Equipment describes the load steps available to a person.
type Equipment struct {
	// DumbbellMaxKg caps dumbbell loads; 0 means unknown, so no cap.
	DumbbellMaxKg float64
	// Barbell is true when barbell work is possible, which rounds loads to 2.5 kg plates.
	Barbell bool
}

// SessionResult is one earlier session's logged sets of an exercise, newest session first in
// the history slices below.
type SessionResult struct {
	Exercise string
	Sets     []Set
	// RIRs are the reps in reserve logged per set, -1 where none was logged.
	RIRs []int
}

// Target is what the next session asks for, and why.
type Target struct {
	Exercise string
	Sets     int
	// Amount is the reps (or seconds) to aim for on each set.
	Amount int
	// LoadKg is the load for loaded work, 0 when unknown or bodyweight.
	LoadKg float64
	Reason string
}

// acsm is the source line every progression reason ends with.
const acsm = "ACSM progression models in resistance training, 2009"

// Load steps from the ACSM position stand: 2 to 5% for upper-body and 5 to 10% for lower-body
// exercises. The lower bound is the step; rounding up to the equipment increment makes the real
// step at least that.
const (
	upperStep = 0.02
	lowerStep = 0.05
	// deloadStep backs load off after repeated misses, within the 5 to 10% the stand uses for
	// reducing load.
	deloadStep       = 0.10
	timedStep        = 5
	repStep          = 1
	sessionsToMoveUp = 2
)

// Next decides the next session's target from the history of this exercise, newest first.
// It is the double progression model: add reps within the range, and add load (or move to the
// harder variation) once every set reaches the top of the range at the target reps in reserve;
// back off after two sessions below the bottom of the range.
func Next(p Prescription, info ExerciseInfo, history []SessionResult, eq Equipment) Target {
	unit := "reps"
	step := repStep
	if info.Timed {
		unit, step = "seconds", timedStep
	}
	t := Target{Exercise: p.Exercise, Sets: p.Sets, Amount: p.Min}
	if len(history) == 0 || len(history[0].Sets) == 0 {
		t.Reason = fmt.Sprintf("First time in this plan: start at %d %s, the bottom of the range.", p.Min, unit)
		return t
	}
	last := history[0]
	lastLoad := maxLoad(last.Sets)
	t.LoadKg = lastLoad

	if missedBottom(last, p) && len(history) > 1 && missedBottom(history[1], p) {
		return deload(t, p, info, lastLoad, eq, unit)
	}
	if hitTop(last, p) {
		if info.Loaded && lastLoad > 0 {
			t.LoadKg = stepLoad(lastLoad, info.Lower, eq, +1)
			t.Amount = p.Min
			t.Reason = fmt.Sprintf("All %d sets reached %d %s last time, so the load goes up to %s and back to %d %s (%s).",
				len(last.Sets), p.Max, unit, kg(t.LoadKg), p.Min, unit, acsm)
			return t
		}
		if !info.Loaded && info.HarderKey != "" && len(history) >= sessionsToMoveUp && hitTop(history[1], p) {
			t.Exercise = info.HarderKey
			t.Amount = p.Min
			t.Reason = fmt.Sprintf("The top of the range two sessions in a row, so move to the harder variation at %d %s (%s).",
				p.Min, unit, acsm)
			return t
		}
		t.Amount = p.Max
		t.Reason = fmt.Sprintf("You reached the top of the range; hold %d %s once more before moving on (%s).", p.Max, unit, acsm)
		return t
	}
	t.Amount = clamp(minAmount(last.Sets)+step, p.Min, p.Max)
	t.Reason = fmt.Sprintf("Last time your lowest set was %d %s, so aim for %d (%s).", minAmount(last.Sets), unit, t.Amount, acsm)
	return t
}

func deload(t Target, p Prescription, info ExerciseInfo, lastLoad float64, eq Equipment, unit string) Target {
	t.Amount = p.Min
	switch {
	case info.Loaded && lastLoad > 0:
		t.LoadKg = stepLoad(lastLoad, info.Lower, eq, -1)
		t.Reason = fmt.Sprintf("Two sessions below %d %s, so the load comes down to %s (%s).", p.Min, unit, kg(t.LoadKg), acsm)
	case !info.Loaded && info.EasierKey != "":
		t.Exercise = info.EasierKey
		t.Reason = fmt.Sprintf("Two sessions below %d %s, so step back to the easier variation (%s).", p.Min, unit, acsm)
	default:
		t.Reason = fmt.Sprintf("Two sessions below %d %s; aim for %d again (%s).", p.Min, unit, p.Min, acsm)
	}
	return t
}

// hitTop is true when the session logged at least the prescribed sets, each at the top of the
// range, without going under the target reps in reserve where it was logged.
func hitTop(r SessionResult, p Prescription) bool {
	if len(r.Sets) < p.Sets {
		return false
	}
	for i, s := range r.Sets[:p.Sets] {
		if amount(s) < p.Max {
			return false
		}
		if i < len(r.RIRs) && r.RIRs[i] >= 0 && r.RIRs[i] < p.RIR {
			return false
		}
	}
	return true
}

// missedBottom is true when any logged set fell below the bottom of the range.
func missedBottom(r SessionResult, p Prescription) bool {
	for _, s := range r.Sets {
		if amount(s) < p.Min {
			return true
		}
	}
	return false
}

func minAmount(sets []Set) int {
	low := math.MaxInt
	for _, s := range sets {
		low = min(low, amount(s))
	}
	return low
}

func maxLoad(sets []Set) float64 {
	high := 0.0
	for _, s := range sets {
		high = math.Max(high, s.LoadKg)
	}
	return high
}

// stepLoad moves a load one step up (dir 1) or down (dir -1): at least the ACSM percentage,
// rounded to the equipment increment, and never by less than one increment.
func stepLoad(load float64, lower bool, eq Equipment, dir int) float64 {
	pct := upperStep
	if lower {
		pct = lowerStep
	}
	if dir < 0 {
		pct = deloadStep
	}
	inc := Increment(load, eq)
	change := math.Max(inc, math.Ceil(load*pct/inc)*inc)
	next := load + float64(dir)*change
	if dir > 0 && eq.DumbbellMaxKg > 0 && !eq.Barbell && next > eq.DumbbellMaxKg {
		next = eq.DumbbellMaxKg
	}
	if next < inc {
		next = inc
	}
	return math.Round(next*100) / 100
}

// Increment is the smallest load change available: 2.5 kg plates with a barbell, otherwise
// dumbbells that go up 1 kg below 10 kg and 2 kg from there (a common fixed-dumbbell series,
// labelled as our convention).
func Increment(load float64, eq Equipment) float64 {
	if eq.Barbell {
		return 2.5
	}
	if load < 10 {
		return 1
	}
	return 2
}

func clamp(v, lo, hi int) int { return max(lo, min(hi, v)) }

func kg(v float64) string {
	if v == math.Trunc(v) {
		return fmt.Sprintf("%.0f kg", v)
	}
	return fmt.Sprintf("%g kg", v)
}
