package score

import "fmt"

// What a quest is worth follows the deliberate effort its target asks, so a long walk is worth
// more than a glass of water. One point is one MET-minute above rest: minutes times (MET - 1),
// with MET values from the 2024 Adult Compendium of Physical Activities, where 1 MET is rest.
// The floor, the cap, the rounding step, the default strength session length and the least a
// seated minute counts for are game design choices, not research, and the app says so.
const (
	// PointsFloor is what a quest with no measured effort, or a very short one, is worth.
	PointsFloor = 20
	// PointsCap keeps one long target, such as steps, from deciding the whole day.
	PointsCap = 100
	// PointsStep is the rounding step, so a worth reads as a plain number.
	PointsStep = 5
	// DefaultStrengthMinutes is the strength session length assumed until the person plans one.
	DefaultStrengthMinutes = 30
	// StepsPerMinute is the walking cadence Marshall et al. 2009 call moderate.
	StepsPerMinute = 100
)

// MET values in tenths, with the Compendium code they come from.
const (
	metModerateWalk = 38 // 17190, walking 2.8 to 3.4 mph, level, moderate pace
	metResistance   = 35 // 02054, resistance (weight) training, multiple exercises, 8-15 reps at varied resistance
	metYogaHatha    = 23 // 02150, yoga, Hatha
	metSeated       = 10 // 07075, meditating; sitting quietly (07021) is also 1.0
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
	// BasisStrength is the strength session the quest also accepts.
	BasisStrength EffortBasis = "strength"
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
	// Planned is true when the strength session length came from the person's own plan.
	Planned bool
}

// EffortPoints is the worth of a quest with the given target. The strength quest (key pushups)
// ignores its target and is priced as the person's planned strength session, strengthMinutes
// long, or DefaultStrengthMinutes when they have not planned one (zero). Quests the Compendium
// has nothing for are worth the floor.
func EffortPoints(key string, target, strengthMinutes int) Effort {
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
		planned := strengthMinutes > 0
		if !planned {
			strengthMinutes = DefaultStrengthMinutes
		}
		e := priced(BasisStrength, strengthMinutes*10, metResistance)
		e.Planned = planned
		return e
	case "yoga":
		basis, minutesX10, met = BasisYoga, target*10, metYogaHatha
	case "breathing", "reading":
		basis, minutesX10, met = BasisFocus, target*10, metSeated
	}
	if basis == BasisNone || target <= 0 {
		return Effort{Points: PointsFloor, Basis: BasisNone, Floored: true}
	}
	return priced(basis, minutesX10, met)
}

// priced turns minutes (in tenths) at a MET value (in tenths) into points.
func priced(basis EffortBasis, minutesX10, met int) Effort {
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
	case BasisStrength:
		if e.Planned {
			what = fmt.Sprintf("priced as your %d min strength session, which this quest also accepts", e.Minutes)
		} else {
			what = fmt.Sprintf("priced as a %d min strength session (a game default), which this quest also accepts", e.Minutes)
		}
	case BasisYoga:
		what = fmt.Sprintf("about %d min of yoga", e.Minutes)
	case BasisFocus:
		what = fmt.Sprintf("about %d min of focused time", e.Minutes)
	default:
		return fmt.Sprintf("Worth %d, the least any goal earns: no measured effort.", e.Points)
	}
	switch {
	case e.Floored:
		return fmt.Sprintf("Worth %d, the least any goal earns: %s.", e.Points, what)
	case e.Capped:
		return fmt.Sprintf("Worth %d, the most any goal earns: %s.", e.Points, what)
	}
	return fmt.Sprintf("Worth %d: %s.", e.Points, what)
}
