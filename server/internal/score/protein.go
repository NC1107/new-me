package score

import "math"

const (
	// ProteinPerKg is the default daily protein, in grams per kilogram of body weight.
	ProteinPerKg = 1.6
	proteinRound = 5
	// ProteinOffFraction is how far the current target may be from the per-kilogram one before
	// a change is proposed.
	ProteinOffFraction = 0.20
)

// ProteinTarget is the per-kilogram protein target for a body weight, rounded to 5 g.
func ProteinTarget(weightKg float64) int {
	return int(math.Round(weightKg*ProteinPerKg/proteinRound)) * proteinRound
}

// ProteinOff reports whether a target is at least 20% away from the per-kilogram one.
func ProteinOff(current, suggested int) bool {
	if suggested <= 0 {
		return false
	}
	return math.Abs(float64(current-suggested)) >= ProteinOffFraction*float64(suggested)
}
