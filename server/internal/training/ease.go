package training

import "fmt"

// Ease is the target for a session on an Easy readiness morning: one set fewer than prescribed
// (never below one), and the load and reps held where the last session left them instead of
// progressing. With no history it asks for the bottom of the range, as Next does.
func Ease(p Prescription, history []SessionResult) Target {
	t := Target{Exercise: p.Exercise, Sets: max(1, p.Sets-1), Amount: p.Min}
	if len(history) == 0 || len(history[0].Sets) == 0 {
		t.Reason = fmt.Sprintf("First time in this plan: start at %d, the bottom of the range, one set lighter today.", p.Min)
		return t
	}
	last := history[0]
	t.LoadKg = maxLoad(last.Sets)
	t.Amount = clamp(minAmount(last.Sets), p.Min, p.Max)
	t.Reason = fmt.Sprintf("Held at last time's %d with one set fewer while you recover; progression resumes next session.", t.Amount)
	return t
}

// EasedReason is the one line that says why a session is eased, from the kinds of the readiness
// reasons that pulled the level down, naming the most telling one.
func EasedReason(strainKinds []string) string {
	lines := []struct{ kind, line string }{
		{"hrv", "Your HRV is below its usual level, so today is one set lighter."},
		{"resting_hr", "Your resting heart rate is above its usual level, so today is one set lighter."},
		{"sleep", "You slept less than your target, so today is one set lighter."},
	}
	for _, l := range lines {
		for _, k := range strainKinds {
			if k == l.kind {
				return l.line
			}
		}
	}
	return "You look under-recovered this morning, so today is one set lighter."
}
