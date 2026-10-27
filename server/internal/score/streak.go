package score

import "time"

// DayFlag is whether one local day counted toward the streak.
type DayFlag struct {
	Date    Date
	Counted bool
}

// StreakResult is the current streak and the days a weekly rest allowance was spent on.
type StreakResult struct {
	Count    int
	RestDays []Date
}

// RestUsedIn returns the rest day spent in the ISO week starting on weekStart.
func (r StreakResult) RestUsedIn(weekStart Date) (Date, bool) {
	for _, d := range r.RestDays {
		if WeekStart(d) == weekStart {
			return d, true
		}
	}
	return "", false
}

// Streak derives the current streak from per-day flags. It walks from the earliest given day
// up to yesterday: a counted day adds one, and a missing date is a miss. A miss is forgiven
// once per ISO week while a streak is running, but never right after another miss or rest,
// so two consecutive misses always break it, across a week boundary too. Today is left out
// until it has counted.
func Streak(days []DayFlag, today Date) StreakResult {
	counted := make(map[Date]bool, len(days))
	var first Date
	for _, d := range days {
		counted[d.Date] = d.Counted
		if first == "" || d.Date.Before(first) {
			first = d.Date
		}
	}

	var result StreakResult
	restWeeks := map[Date]bool{}
	previousMissed := false
	for d := first; first != "" && d.Before(today); d = d.AddDays(1) {
		if counted[d] {
			result.Count++
			previousMissed = false
			continue
		}
		week := WeekStart(d)
		if result.Count > 0 && !restWeeks[week] && !previousMissed {
			restWeeks[week] = true
			result.RestDays = append(result.RestDays, d)
		} else {
			result.Count = 0
		}
		previousMissed = true
	}
	if counted[today] {
		result.Count++
	}
	return result
}

// StreakNow is Streak for a wall-clock moment. While yesterday's grace window is open and it
// has not counted yet, it is treated as still in progress like today, so a user is not shown
// a broken streak at breakfast for a day they can still fill in.
func StreakNow(days []DayFlag, now time.Time, loc *time.Location) StreakResult {
	today := LocalToday(now, loc)
	yesterday := today.AddDays(-1)
	if _, open := BackdateUntil(now, loc); open {
		yesterdayCounted := false
		for _, d := range days {
			if d.Date == yesterday && d.Counted {
				yesterdayCounted = true
			}
		}
		if !yesterdayCounted {
			today = yesterday
		}
	}
	return Streak(days, today)
}
