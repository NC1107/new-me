package score

import "fmt"

// What a quest is worth follows the deliberate effort its target asks, so a long walk is worth
// more than a glass of water. One point is one MET-minute above rest: minutes times (MET - 1),
// with MET values from the 2024 Adult Compendium of Physical Activities. The floor, the cap, the
// rounding step, the rep tempo and the least a quiet minute counts for are game design choices,
// not research, and the app says so.
const (
	// PointsFloor is what a quest with no measured effort, or a very short one, is worth.
	PointsFloor = 20
	// PointsCap keeps one long target from deciding the whole day.
	PointsCap = 150
	// PointsStep is the rounding step, so a worth reads as a plain number.
	PointsStep = 5
	// SecondsPerRep is the tempo of a daily-reps set, resting between sets included.
	SecondsPerRep = 10
	// StepsPerMinute is the walking cadence Marshall et al. 2009 call moderate.
	StepsPerMinute = 100
)

// MET values in tenths, with the Compendium code they come from.
const (
	metModerateWalk     = 38 // 17190, walking 2.8 to 3.4 mph, level, moderate pace
	metCalisthenicsMod  = 38 // 02022, calisthenics (push-ups, pull-ups, lunges), moderate effort
	metCalisthenicsLite = 28 // 02024, calisthenics (curl ups, crunches, plank), light effort
	metBodyweightGen    = 30 // 02056, body weight resistance exercises, general
	metYogaHatha        = 23 // 02150, yoga, Hatha
	metSeated           = 10 // 07075, meditating; sitting quietly is also 1.0
)

// leastAboveRest is the least a deliberate minute counts for, in tenths of a MET above rest, so
// a seated quest such as reading still counts the time it takes.
const leastAboveRest = 10

// EffortBasis says how a quest's worth was reached.
type EffortBasis string

const (
	// BasisWalk is minutes of walking at the moderate cadence.
	BasisWalk EffortBasis = "walk"
	// BasisModerate is minutes of moderate exercise.
	BasisModerate EffortBasis = "moderate"
	// BasisReps is the time a set of reps takes at the game tempo.
	BasisReps EffortBasis = "reps"
	// BasisYoga is minutes of Hatha yoga.
	BasisYoga EffortBasis = "yoga"
	// BasisFocus is minutes of seated, deliberate time (reading, breathing).
	BasisFocus EffortBasis = "focus"
	// BasisNone is a quest with no measured effort.
	BasisNone EffortBasis = "none"
)

// Effort is the worth of one quest and where it came from.
type Effort struct {
	Points int
	Basis  EffortBasis
	// Minutes is the deliberate time the target asks, rounded; zero for BasisNone.
	Minutes int
	// Raw is the points before the floor, cap and rounding.
	Raw int
	// Floored and Capped say the floor or the cap decided the worth.
	Floored, Capped bool
}

// repsMET is the Compendium value of a daily-reps exercise, in tenths of a MET.
func repsMET(exercise string) int {
	switch exercise {
	case "crunch":
		return metCalisthenicsLite
	case "glute_bridge":
		return metBodyweightGen
	default:
		return metCalisthenicsMod
	}
}

// EffortPoints is the worth of a quest with the given target. exercise only matters for the
// pushups quest. Quests the Compendium has nothing for are worth the floor.
func EffortPoints(key string, target int, exercise string) Effort {
	var (
		basis      = BasisNone
		minutesX10 int // minutes in tenths so rounding happens once
		met        int
	)
	switch key {
	case "steps":
		basis, minutesX10, met = BasisWalk, target*10/StepsPerMinute, metModerateWalk
	case "exercise":
		basis, minutesX10, met = BasisModerate, target*10, metModerateWalk
	case "pushups":
		basis, minutesX10, met = BasisReps, target*SecondsPerRep*10/60, repsMET(exercise)
	case "yoga":
		basis, minutesX10, met = BasisYoga, target*10, metYogaHatha
	case "breathing", "reading":
		basis, minutesX10, met = BasisFocus, target*10, metSeated
	}
	if basis == BasisNone || target <= 0 {
		return Effort{Points: PointsFloor, Basis: BasisNone, Floored: true}
	}
	raw := (minutesX10*max(met-10, leastAboveRest) + 50) / 100
	e := Effort{Basis: basis, Minutes: (minutesX10 + 5) / 10, Raw: raw}
	rounded := (raw + PointsStep/2) / PointsStep * PointsStep
	switch {
	case rounded < PointsFloor:
		e.Points, e.Floored = PointsFloor, true
	case rounded > PointsCap:
		e.Points, e.Capped = PointsCap, true
	default:
		e.Points = rounded
	}
	return e
}

// Reason is the one line that says why a quest is worth what it is. The floor and the cap are
// named as design choices, never as research.
func (e Effort) Reason() string {
	var what string
	switch e.Basis {
	case BasisWalk:
		what = fmt.Sprintf("about %d min of walking at a moderate pace", e.Minutes)
	case BasisModerate:
		what = fmt.Sprintf("about %d min of moderate effort", e.Minutes)
	case BasisReps:
		what = fmt.Sprintf("about %d min of effort, counting %d seconds a rep with rests", e.Minutes, SecondsPerRep)
	case BasisYoga:
		what = fmt.Sprintf("about %d min of yoga", e.Minutes)
	case BasisFocus:
		what = fmt.Sprintf("about %d min of focused time", e.Minutes)
	default:
		return fmt.Sprintf("Worth %d, the game's minimum: no measured effort.", e.Points)
	}
	switch {
	case e.Floored:
		return fmt.Sprintf("Worth %d, the game's minimum: %s.", e.Points, what)
	case e.Capped:
		return fmt.Sprintf("Worth %d, the game's maximum: %s.", e.Points, what)
	}
	return fmt.Sprintf("Worth %d: %s.", e.Points, what)
}
