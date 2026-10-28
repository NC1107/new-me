package score

import "math/bits"

const (
	// ChallengeBonusPoints is what each person earns when the weekly couple challenge completes.
	ChallengeBonusPoints = 50
	// AllWeekdays is the weekdays mask of a habit that applies every day.
	AllWeekdays = 0b1111111
)

// WeekdayBit is the bit of a date's weekday in a weekdays mask: bit 0 is Monday, bit 6 Sunday.
func WeekdayBit(d Date) int { return 1 << ((int(d.Weekday()) + 6) % 7) }

// HabitDue reports whether a habit with the weekdays mask applies on the date.
func HabitDue(weekdays int, d Date) bool { return weekdays&WeekdayBit(d) != 0 }

// WeekdaysFromISO builds a mask from ISO weekday numbers, Monday 1 to Sunday 7. Duplicates are
// harmless; ok is false for a number out of range or an empty list.
func WeekdaysFromISO(days []int) (mask int, ok bool) {
	for _, d := range days {
		if d < 1 || d > 7 {
			return 0, false
		}
		mask |= 1 << (d - 1)
	}
	return mask, mask != 0
}

// ISOWeekdays lists the ISO weekday numbers set in a mask, in order.
func ISOWeekdays(mask int) []int {
	out := make([]int, 0, bits.OnesCount(uint(mask)))
	for d := 1; d <= 7; d++ {
		if mask&(1<<(d-1)) != 0 {
			out = append(out, d)
		}
	}
	return out
}

// HabitDay is one due habit and how far the person got on it that day. A check habit carries
// its slot count and how many are done; a count habit carries a target and the count.
type HabitDay struct {
	Check     bool
	Slots     int
	SlotsDone int
	Target    int
	Count     int
	// Points is the habit's worth toward the day.
	Points int
}

// Habit worths a person can choose; quests are worth 50 or 100.
var HabitWorths = []int{0, 10, 25, 50}

// HabitGemsPerMinute and HabitGemsCap are the v11 rate: the timed quests' own, rounded down so
// habits never outpay them.
const (
	HabitGemsPerMinute = 3
	HabitGemsCap       = 100
	HabitMaxMinutes    = 30
)

// HabitGems is what a habit that takes the given minutes is worth; a habit that is only
// tracked (zero minutes) is worth nothing.
func HabitGems(minutes int) int {
	if minutes <= 0 {
		return 0
	}
	return min(HabitGemsCap, HabitGemsPerMinute*minutes)
}

// HabitWorthDefault is the worth of a habit created without one.
const HabitWorthDefault = 25

// HabitScore is what the day's due habits add: their worth to the possible points, and the
// share of it completed (check slots done over slots, or count over target, capped at the whole)
// to the earned points.
func HabitScore(days []HabitDay) (earned, possible int) {
	for _, h := range days {
		if h.Points <= 0 {
			continue
		}
		possible += h.Points
		switch {
		case h.Check && h.Slots > 0:
			earned += h.Points * min(max(h.SlotsDone, 0), h.Slots) / h.Slots
		case !h.Check && h.Target > 0:
			earned += h.Points * min(max(h.Count, 0), h.Target) / h.Target
		}
	}
	return earned, possible
}

// WithBonus returns the day with extra bonus points added. Percent, Counted and MaxBase are
// base-only, so they are left alone.
func (d DayScore) WithBonus(extra int) DayScore {
	d.BonusPoints += extra
	return d
}

// WithHabits adds the day's habits to its base points and maximum and recomputes the percent and
// whether the day counts, so habits count toward the daily goal like quests.
func (d DayScore) WithHabits(earned, possible int) DayScore {
	if possible <= 0 {
		return d
	}
	d.BasePoints += earned
	d.MaxBase += possible
	d.Percent = min(100, d.BasePoints*100/d.MaxBase)
	d.Counted = d.BasePoints*100 >= CountedPercent*d.MaxBase
	return d
}
