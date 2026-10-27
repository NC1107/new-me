// Package training holds the pure rules for exercises, sets, plans and progression.
package training

import "math"

// Set is the part of a logged set the rules read.
type Set struct {
	Date    string
	Reps    int
	Seconds int
	LoadKg  float64
}

// Best is the strongest set of an exercise: the most reps (or seconds) for bodyweight work,
// the highest estimated one-rep max for loaded work.
type Best struct {
	Set
	// E1RMKg is the Epley estimate for a loaded set, 0 for bodyweight work.
	E1RMKg float64
}

// Epley estimates a one-rep max from a set: load x (1 + reps / 30) (Epley 1985). It is an
// estimate that loses accuracy past about 10 reps, so callers label it as one. A single rep is
// the load itself.
func Epley(loadKg float64, reps int) float64 {
	if loadKg <= 0 || reps < 1 {
		return 0
	}
	if reps == 1 {
		return loadKg
	}
	return math.Round(loadKg*(1+float64(reps)/30)*10) / 10
}

// BestSet picks the strongest set. Ties go to the newest, so a matched best reads as recent.
// ok is false when there are no sets.
func BestSet(sets []Set, loaded bool) (best Best, ok bool) {
	for _, s := range sets {
		candidate := Best{Set: s}
		if loaded {
			candidate.E1RMKg = Epley(s.LoadKg, s.Reps)
		}
		if !ok || better(candidate, best, loaded) {
			best, ok = candidate, true
		}
	}
	return best, ok
}

func better(a, b Best, loaded bool) bool {
	if loaded {
		if a.E1RMKg != b.E1RMKg {
			return a.E1RMKg > b.E1RMKg
		}
	} else if amount(a.Set) != amount(b.Set) {
		return amount(a.Set) > amount(b.Set)
	}
	return a.Date >= b.Date
}

// amount is the reps or seconds of a set, whichever its exercise measures.
func amount(s Set) int {
	if s.Seconds > 0 {
		return s.Seconds
	}
	return s.Reps
}
