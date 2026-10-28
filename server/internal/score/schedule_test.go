package score

import (
	"testing"
	"time"
)

func TestDefaultScheduleIsValid(t *testing.T) {
	s := DefaultSchedule()
	if err := s.Validate(); err != nil {
		t.Fatal(err)
	}
	if s.Workday.WakeMin != 420 || s.Workday.BedMin != 1380 || s.FirstOffsetMin != 10 {
		t.Fatalf("defaults = %+v", s)
	}
	// 2026-10-26 is a Monday, 2026-10-31 a Saturday.
	if !s.On(MustDate("2026-10-26")).equal(s.Workday) || !s.On(MustDate("2026-10-31")).equal(s.DayOff) {
		t.Fatal("On picked the wrong day type")
	}
}

func (d DaySchedule) equal(o DaySchedule) bool { return d == o }

func TestScheduleWindow(t *testing.T) {
	workday, dayOff := MustDate("2026-10-26"), MustDate("2026-10-31")
	s := DefaultSchedule()
	s.DayOff = DaySchedule{WakeMin: 9 * 60, BedMin: 30}
	tests := []struct {
		name       string
		s          Schedule
		date       Date
		first, end int
	}{
		{name: "default workday", s: DefaultSchedule(), date: workday, first: 7*60 + 10, end: 23 * 60},
		{name: "day off after midnight ends at midnight", s: s, date: dayOff, first: 9*60 + 10, end: 1440},
		{name: "offset zero", s: Schedule{Workdays: 31, Workday: DaySchedule{WakeMin: 360, BedMin: 1320}, FirstOffsetMin: 0}, date: workday, first: 360, end: 1320},
		{name: "offset is capped to the day", s: Schedule{Workdays: 31, Workday: DaySchedule{WakeMin: 1430, BedMin: 100}, FirstOffsetMin: 120}, date: workday, first: 1439, end: 1440},
	}
	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			first, end := tc.s.Window(tc.date)
			if first != tc.first || end != tc.end {
				t.Fatalf("window = %d..%d, want %d..%d", first, end, tc.first, tc.end)
			}
		})
	}
}

func TestScheduleQuiet(t *testing.T) {
	s := DefaultSchedule()
	d := MustDate("2026-10-26")
	for minute, want := range map[int]bool{0: true, 7*60 + 9: true, 7*60 + 10: false, 12 * 60: false, 22*60 + 59: false, 23 * 60: true, 1439: true} {
		if got := s.Quiet(d, minute); got != want {
			t.Errorf("minute %d: quiet = %v, want %v", minute, got, want)
		}
	}
}

func TestScheduleValidate(t *testing.T) {
	bad := []func(*Schedule){
		func(s *Schedule) { s.Workdays = 128 },
		func(s *Schedule) { s.Workdays = -1 },
		func(s *Schedule) { s.FirstOffsetMin = 361 },
		func(s *Schedule) { s.FirstOffsetMin = -1 },
		func(s *Schedule) { s.Workday.WakeMin = 1440 },
		func(s *Schedule) { s.DayOff.BedMin = -1 },
		func(s *Schedule) { s.Workday.BedMin = s.Workday.WakeMin },
		func(s *Schedule) { s.DayOff.BedMin = s.DayOff.WakeMin },
	}
	for i, mutate := range bad {
		s := DefaultSchedule()
		mutate(&s)
		if s.Validate() == nil {
			t.Errorf("case %d: expected an error", i)
		}
	}
	s := DefaultSchedule()
	s.Workdays = 0
	if err := s.Validate(); err != nil {
		t.Errorf("no workdays is allowed: %v", err)
	}
}

func TestClock(t *testing.T) {
	for in, want := range map[string]int{"00:00": 0, "07:05": 425, "23:59": 1439} {
		got, err := ParseClock(in)
		if err != nil || got != want || FormatClock(got) != in {
			t.Errorf("%s: %d %v", in, got, err)
		}
	}
	for _, in := range []string{"", "7:00", "24:00", "07:60", "0700", "ab:cd", "07:0"} {
		if _, err := ParseClock(in); err == nil {
			t.Errorf("%q should not parse", in)
		}
	}
}

func TestRepairWindow(t *testing.T) {
	loc := mustLoc(t, "America/New_York")
	missed := MustDate("2026-10-28")
	if got := RepairUntil(missed, loc); !got.Equal(time.Date(2026, 10, 29, 22, 0, 0, 0, loc)) {
		t.Fatalf("until = %v", got)
	}
	cases := map[string]struct {
		now  time.Time
		open bool
	}{
		"grace window still open": {time.Date(2026, 10, 29, 9, 59, 0, 0, loc), false},
		"just finalized":          {time.Date(2026, 10, 29, 10, 0, 0, 0, loc), true},
		"evening":                 {time.Date(2026, 10, 29, 21, 59, 0, 0, loc), true},
		"closed at 22:00":         {time.Date(2026, 10, 29, 22, 0, 0, 0, loc), false},
		"two days later":          {time.Date(2026, 10, 30, 12, 0, 0, 0, loc), false},
	}
	for name, tc := range cases {
		if got := RepairOpen(missed, tc.now, loc); got != tc.open {
			t.Errorf("%s: open = %v, want %v", name, got, tc.open)
		}
	}
}
