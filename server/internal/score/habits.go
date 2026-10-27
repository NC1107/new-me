package score

import "math/bits"

const (
	// HabitPoints is the bonus for one completed check slot, or a count habit at its target.
	HabitPoints = 5
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
}

// HabitBonus is the bonus points the day's habits earn: HabitPoints per completed check slot
// and per count habit at its target. It is added to a day's bonus and never to its maximum,
// so habits can only help and never move whether a day counts.
func HabitBonus(days []HabitDay) int {
	total := 0
	for _, h := range days {
		switch {
		case h.Check:
			total += HabitPoints * min(max(h.SlotsDone, 0), h.Slots)
		case h.Target > 0 && h.Count >= h.Target:
			total += HabitPoints
		}
	}
	return total
}

// WithBonus returns the day with extra bonus points added. Percent, Counted and MaxBase are
// base-only, so they are left alone.
func (d DayScore) WithBonus(extra int) DayScore {
	d.BonusPoints += extra
	return d
}
