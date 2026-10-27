package score

import "math"

const (
	// StrengthCreditMinutes is how long a strength workout must run to count as the day's
	// push-ups quest, whatever number of reps was logged. A HIIT workout without a known
	// heart-rate threshold needs the same.
	StrengthCreditMinutes = 20
	// HIITCreditMinutes is how long a HIIT workout must run when its average heart rate reaches
	// the intensity threshold.
	HIITCreditMinutes = 15
	// HIITReserveFraction is the share of heart-rate reserve a HIIT workout's average heart
	// rate must reach to count at HIITCreditMinutes.
	HIITReserveFraction = 0.6
)

// HIITMinHR is the average heart rate a HIIT workout needs: resting heart rate plus 60% of the
// reserve up to the age-estimated maximum (220 minus age). Nil when age or resting heart rate
// is unknown, which makes HIIT count like strength.
func HIITMinHR(age *int, restingHR *float64) *float64 {
	if age == nil || restingHR == nil || *age < 0 || *age > 120 {
		return nil
	}
	reserve := float64(220-*age) - *restingHR
	if reserve <= 0 {
		return nil
	}
	v := *restingHR + HIITReserveFraction*reserve
	return &v
}

// Workout types that feed quests. The strings are the workout types stored from Apple Health,
// where pilates and flexibility sessions already arrive as yoga.
const (
	WorkoutStrength = "strength"
	WorkoutHIIT     = "hiit"
	WorkoutYoga     = "yoga"
)

// WorkoutSpan is one Health workout of the day as scoring sees it.
type WorkoutSpan struct {
	Type        string
	DurationMin float64
	// AvgHR is nil when Health had no heart rate for the workout.
	AvgHR *float64
}

// DoneBy names the data that completed a quest on its own.
type DoneBy struct {
	Kind    string `json:"kind"`
	Type    string `json:"type"`
	Minutes int    `json:"minutes"`
}

// DoneByWorkout is the kind of a quest finished by Health data.
const DoneByWorkout = "workout"

// qualifies applies the credit rules to one workout: strength needs 20 minutes; HIIT needs 15
// at the heart-rate threshold when it is known and the workout has a heart rate, 20 when the
// threshold is unknown, and never counts below the threshold.
func qualifies(w WorkoutSpan, hiitMinHR *float64) bool {
	switch w.Type {
	case WorkoutStrength:
		return w.DurationMin >= StrengthCreditMinutes
	case WorkoutHIIT:
		if hiitMinHR == nil || w.AvgHR == nil {
			return w.DurationMin >= StrengthCreditMinutes
		}
		return w.DurationMin >= HIITCreditMinutes && *w.AvgHR >= *hiitMinHR
	}
	return false
}

// StrengthCredit returns the longest qualifying strength or HIIT workout, or nil.
func StrengthCredit(workouts []WorkoutSpan, hiitMinHR *float64) *DoneBy {
	var best *WorkoutSpan
	for i, w := range workouts {
		if !qualifies(w, hiitMinHR) {
			continue
		}
		if best == nil || w.DurationMin > best.DurationMin {
			best = &workouts[i]
		}
	}
	if best == nil {
		return nil
	}
	return &DoneBy{Kind: DoneByWorkout, Type: best.Type, Minutes: wholeMinutes(best.DurationMin)}
}

// PushupsProgress is the push-ups quest's actual against its target. A qualifying workout
// completes the quest outright, so it earns full base points and the completion bonus; logged
// reps still count when they alone get there. DoneBy is set only when the workout is what
// completed it.
func PushupsProgress(reps, target int, workouts []WorkoutSpan, hiitMinHR *float64) (actual int, doneBy *DoneBy) {
	if reps >= target {
		return reps, nil
	}
	if credit := StrengthCredit(workouts, hiitMinHR); credit != nil {
		return target, credit
	}
	return reps, nil
}

// DoneBySession is the kind of a quest finished by completing the day's planned training
// session.
const DoneBySession = "session"

// StrengthProgress is the push-ups ("Get stronger") quest with v9 training: logged reps count
// first, then a completed planned session (named by its plan-day label) completes the quest,
// then a qualifying Health workout does, as in PushupsProgress.
func StrengthProgress(reps, target int, sessionLabel string, workouts []WorkoutSpan, hiitMinHR *float64) (actual int, doneBy *DoneBy) {
	if reps >= target {
		return reps, nil
	}
	if sessionLabel != "" {
		return target, &DoneBy{Kind: DoneBySession, Type: sessionLabel}
	}
	return PushupsProgress(reps, target, workouts, hiitMinHR)
}

// YogaWorkoutMinutes is the whole minutes of yoga workouts, which add to logged yoga minutes.
func YogaWorkoutMinutes(workouts []WorkoutSpan) int {
	total := 0.0
	for _, w := range workouts {
		if w.Type == WorkoutYoga {
			total += w.DurationMin
		}
	}
	return wholeMinutes(total)
}

// YogaProgress is the yoga quest's actual: logged minutes plus yoga workout minutes. DoneBy is
// set when workouts contribute, so the card can say where the minutes came from.
func YogaProgress(logged int, workouts []WorkoutSpan) (actual int, doneBy *DoneBy) {
	fromWorkouts := YogaWorkoutMinutes(workouts)
	if fromWorkouts <= 0 {
		return logged, nil
	}
	return logged + fromWorkouts, &DoneBy{Kind: DoneByWorkout, Type: WorkoutYoga, Minutes: fromWorkouts}
}

func wholeMinutes(v float64) int { return int(math.Floor(v + 1e-9)) }
