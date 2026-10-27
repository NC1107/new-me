package score

import (
	"fmt"
	"strconv"
	"strings"
)

// Schedule bounds.
const (
	// MaxFirstOffsetMin is the longest wait after waking before the first notification.
	MaxFirstOffsetMin = 120
	// DefaultFirstOffsetMin is how long after waking the first notification comes by default.
	DefaultFirstOffsetMin = 10
	minutesPerDay         = 1440
	// WorkdaysMonToFri is the default workdays mask.
	WorkdaysMonToFri = 0b0011111
)

// DaySchedule is when a person wakes and goes to bed, in minutes after local midnight. A bedtime
// earlier than the wake time is after midnight.
type DaySchedule struct {
	WakeMin int
	BedMin  int
}

// Schedule is a person's general weekly rhythm; everything time-based follows it.
type Schedule struct {
	// Workdays is a weekdays mask: bit 0 is Monday.
	Workdays int
	Workday  DaySchedule
	DayOff   DaySchedule
	// FirstOffsetMin is how long after waking the first notification of the day may come.
	FirstOffsetMin int
}

// DefaultSchedule wakes at 07:00 and sleeps at 23:00 on every day, working Monday to Friday.
func DefaultSchedule() Schedule {
	day := DaySchedule{WakeMin: 7 * 60, BedMin: 23 * 60}
	return Schedule{Workdays: WorkdaysMonToFri, Workday: day, DayOff: day, FirstOffsetMin: DefaultFirstOffsetMin}
}

// On is the schedule that applies to the date.
func (s Schedule) On(d Date) DaySchedule {
	if HabitDue(s.Workdays, d) {
		return s.Workday
	}
	return s.DayOff
}

// Window is the stretch of the date in which automatic notifications may arrive: from the first
// notification (wake plus the offset) to bedtime. A bedtime after midnight ends the window at
// midnight, since the hours after belong to the next date. First is capped to the last minute
// of the day.
func (s Schedule) Window(d Date) (first, end int) {
	day := s.On(d)
	first = min(day.WakeMin+s.FirstOffsetMin, minutesPerDay-1)
	end = day.BedMin
	if end <= day.WakeMin {
		end = minutesPerDay
	}
	return first, end
}

// Quiet reports whether the minute of the date lies outside the notification window, which is
// from bedtime until the first notification of the day.
func (s Schedule) Quiet(d Date, minute int) bool {
	first, end := s.Window(d)
	return minute < first || minute >= end
}

// FormatClock writes minutes after midnight as HH:MM.
func FormatClock(minutes int) string { return fmt.Sprintf("%02d:%02d", minutes/60, minutes%60) }

// ParseClock reads HH:MM as minutes after midnight.
func ParseClock(s string) (int, error) {
	h, m, ok := strings.Cut(s, ":")
	if !ok || len(h) != 2 || len(m) != 2 {
		return 0, fmt.Errorf("time %q is not HH:MM", s)
	}
	hours, errH := strconv.Atoi(h)
	minutes, errM := strconv.Atoi(m)
	if errH != nil || errM != nil || hours < 0 || hours > 23 || minutes < 0 || minutes > 59 {
		return 0, fmt.Errorf("time %q is not HH:MM", s)
	}
	return hours*60 + minutes, nil
}

// Validate checks the schedule against the stored bounds.
func (s Schedule) Validate() error {
	if s.Workdays < 0 || s.Workdays > AllWeekdays {
		return fmt.Errorf("workdays must be weekdays 1 to 7")
	}
	if s.FirstOffsetMin < 0 || s.FirstOffsetMin > MaxFirstOffsetMin {
		return fmt.Errorf("firstNotificationOffsetMin must be between 0 and %d", MaxFirstOffsetMin)
	}
	for _, d := range []struct {
		name string
		day  DaySchedule
	}{{"workday", s.Workday}, {"dayOff", s.DayOff}} {
		for _, m := range []int{d.day.WakeMin, d.day.BedMin} {
			if m < 0 || m >= minutesPerDay {
				return fmt.Errorf("%s times must be within the day", d.name)
			}
		}
		if d.day.WakeMin == d.day.BedMin {
			return fmt.Errorf("%s wake and bed must differ", d.name)
		}
	}
	return nil
}
