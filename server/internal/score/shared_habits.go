package score

// Shared household habits (chores) are scheduled by when they were last done, not by a fixed
// calendar, so the due date is a pure function of the schedule, the last time it was done and the
// viewer's own today.

// The schedule kinds of a shared habit.
const (
	SharedDaily    = "daily"
	SharedWeekdays = "weekdays"
	SharedWeekly   = "weekly"
	SharedEveryN   = "every_n"
)

// SharedHabitGems is what the person who did a chore earns, the same as a personal habit created
// without a worth. It is a bonus, so it never moves the daily percent or the streak.
const SharedHabitGems = HabitWorthDefault

// Bounds of an every-N-days schedule.
const (
	SharedMinEveryDays = 2
	SharedMaxEveryDays = 365
)

// The states of a shared habit on a day.
const (
	SharedOverdue  = "overdue"
	SharedDueToday = "today"
	SharedUpcoming = "upcoming"
)

// SharedSchedule is how often a shared habit comes round. Weekdays is the mask of WeekdayBit and
// is used by the weekdays kind only; EveryDays by every_n only.
type SharedSchedule struct {
	Kind      string
	Weekdays  int
	EveryDays int
}

// SharedStatus is where a shared habit stands for one viewer. Days is how far DueOn is from the
// viewer's today: negative when overdue, positive when upcoming.
type SharedStatus struct {
	State string
	DueOn Date
	Days  int
}

// ValidSharedSchedule reports whether the schedule is one a shared habit may have.
func ValidSharedSchedule(s SharedSchedule) bool {
	switch s.Kind {
	case SharedDaily, SharedWeekly:
		return true
	case SharedWeekdays:
		return s.Weekdays > 0 && s.Weekdays <= AllWeekdays
	case SharedEveryN:
		return s.EveryDays >= SharedMinEveryDays && s.EveryDays <= SharedMaxEveryDays
	}
	return false
}

// DaysBetween is the number of calendar days from a to b, negative when b is earlier.
func DaysBetween(a, b Date) int {
	return int(b.Time().Sub(a.Time()).Hours() / 24)
}

// SharedDue works out when the habit is next due. lastDone is the local day (in the viewer's zone)
// it was last done, nil if never; startOn is where a never-done habit becomes due.
// A daily habit is never overdue, it is just due today until it is done.
func SharedDue(s SharedSchedule, startOn Date, lastDone *Date, today Date) SharedStatus {
	base := startOn
	if lastDone != nil {
		base = lastDone.AddDays(1)
	}
	var due Date
	switch s.Kind {
	case SharedDaily:
		due = base
		if lastDone != nil && !lastDone.Before(today) {
			due = lastDone.AddDays(1)
		} else if due.Before(today) {
			due = today
		}
	case SharedWeekdays:
		due = nextScheduledDay(s.Weekdays, base)
	case SharedWeekly:
		due = everyN(startOn, lastDone, 7)
	default:
		due = everyN(startOn, lastDone, s.EveryDays)
	}
	days := DaysBetween(today, due)
	state := SharedUpcoming
	switch {
	case days < 0:
		state = SharedOverdue
	case days == 0:
		state = SharedDueToday
	}
	return SharedStatus{State: state, DueOn: due, Days: days}
}

func everyN(startOn Date, lastDone *Date, n int) Date {
	if lastDone == nil {
		return startOn
	}
	return lastDone.AddDays(n)
}

// nextScheduledDay is the first day on or after from whose weekday is in the mask.
func nextScheduledDay(mask int, from Date) Date {
	for i := 0; i < 7; i++ {
		if d := from.AddDays(i); HabitDue(mask, d) {
			return d
		}
	}
	return from
}
