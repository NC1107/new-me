package score

import "time"

// RepairHour is the local hour the repair window of a missed day closes, on the day after it.
const RepairHour = 22

// RepairUntil is when the missed date can no longer be repaired: 22:00 the next local day.
func RepairUntil(missed Date, loc *time.Location) time.Time {
	t := missed.AddDays(1).Time()
	return time.Date(t.Year(), t.Month(), t.Day(), RepairHour, 0, 0, 0, loc)
}

// RepairOpen reports whether a missed, unfrozen day can be repaired right now: its grace window
// has closed, so it is final, and the repair window has not.
func RepairOpen(missed Date, now time.Time, loc *time.Location) bool {
	return !now.Before(FinalizeAt(missed, loc)) && now.Before(RepairUntil(missed, loc))
}
