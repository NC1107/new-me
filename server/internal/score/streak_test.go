package score

import (
	"reflect"
	"testing"
	"time"
)

// pattern turns "xx.x" into consecutive day flags from start: x counted, . missed, _ absent.
func pattern(start Date, p string) []DayFlag {
	var days []DayFlag
	for i, c := range p {
		if c == '_' {
			continue
		}
		days = append(days, DayFlag{Date: start.AddDays(i), Counted: c == 'x'})
	}
	return days
}

func TestStreak(t *testing.T) {
	monday := MustDate("2026-10-26")
	tests := []struct {
		name     string
		start    Date
		days     string
		todayIdx int
		want     int
		rest     []int
	}{
		{name: "no days", start: monday, days: "", todayIdx: 0, want: 0},
		{name: "first week all counted", start: monday, days: "xxx", todayIdx: 3, want: 3},
		{name: "today counted adds one", start: monday, days: "xxxx", todayIdx: 3, want: 4},
		{name: "today not counted is excluded", start: monday, days: "xxx.", todayIdx: 3, want: 3},
		{name: "first miss in a week is forgiven", start: monday, days: "xx.x", todayIdx: 4, want: 3, rest: []int{2}},
		{name: "miss at zero streak consumes nothing", start: monday, days: ".xx.x", todayIdx: 5, want: 3, rest: []int{3}},
		{name: "second miss in the same week breaks", start: monday, days: "xx.x.x", todayIdx: 6, want: 1, rest: []int{2}},
		{name: "two consecutive misses break", start: monday, days: "xxx..x", todayIdx: 6, want: 1, rest: []int{3}},
		{name: "three day gap breaks and restarts", start: monday, days: "xxx...xx", todayIdx: 8, want: 2, rest: []int{3}},
		{name: "sunday and monday misses break", start: monday, days: "xxxxxx..xx", todayIdx: 10, want: 2, rest: []int{6}},
		{name: "rest resets each week", start: monday, days: "xx.xxxxx.xx", todayIdx: 11, want: 9, rest: []int{2, 8}},
		{name: "miss right after a rest breaks", start: monday, days: "xx..x", todayIdx: 5, want: 1, rest: []int{2}},
		{name: "unused rest does not carry over", start: monday, days: "xxxxxxxx..x", todayIdx: 11, want: 1, rest: []int{8}},
		{name: "missing dates are misses", start: monday, days: "xx__x", todayIdx: 5, want: 1, rest: []int{2}},
		{name: "backdated fill rescues a gap", start: monday, days: "xxxxxxx", todayIdx: 7, want: 7},
		{name: "unfilled gap before the fill", start: monday, days: "xxx..xx", todayIdx: 7, want: 2, rest: []int{3}},
		{name: "days before join are skipped", start: monday.AddDays(3), days: "xx", todayIdx: 2, want: 2},
		{name: "trailing absent days up to yesterday are misses", start: monday, days: "xxxx", todayIdx: 7, want: 0, rest: []int{4}},
	}
	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			got := Streak(pattern(tc.start, tc.days), tc.start.AddDays(tc.todayIdx))
			if got.Count != tc.want {
				t.Fatalf("count = %d, want %d", got.Count, tc.want)
			}
			var wantRest []Date
			for _, i := range tc.rest {
				wantRest = append(wantRest, tc.start.AddDays(i))
			}
			if !reflect.DeepEqual(got.RestDays, wantRest) {
				t.Fatalf("rest days = %v, want %v", got.RestDays, wantRest)
			}
		})
	}
}

func TestStreakBackdatedFillRescuesGap(t *testing.T) {
	start := MustDate("2026-10-26")
	today := start.AddDays(6)
	gap := Streak(pattern(start, "xx..xx"), today)
	if gap.Count != 2 {
		t.Fatalf("with the gap: count = %d, want 2", gap.Count)
	}
	filled := Streak(pattern(start, "xx.xxx"), today)
	if filled.Count != 5 {
		t.Fatalf("after the backdated fill: count = %d, want 5", filled.Count)
	}
}

func TestStreakAcrossDSTTransitions(t *testing.T) {
	for _, start := range []Date{MustDate("2026-03-06"), MustDate("2026-11-01")} {
		days := pattern(start, "xxxxx")
		if got := Streak(days, start.AddDays(5)).Count; got != 5 {
			t.Fatalf("from %s: count = %d, want 5 across the clock change", start, got)
		}
	}
}

func TestStreakIgnoresInputOrderAndFutureDays(t *testing.T) {
	start := MustDate("2026-10-26")
	days := pattern(start, "xxxxx")
	days[0], days[4] = days[4], days[0]
	if got := Streak(days, start.AddDays(3)).Count; got != 4 {
		t.Fatalf("count = %d, want 4 (three past days, today counted, the later day ignored)", got)
	}
}

func TestRestUsedIn(t *testing.T) {
	start := MustDate("2026-10-26")
	r := Streak(pattern(start, "xx.xx"), start.AddDays(5))
	if d, ok := r.RestUsedIn(start); !ok || d != start.AddDays(2) {
		t.Fatalf("RestUsedIn = %v %v", d, ok)
	}
	if _, ok := r.RestUsedIn(start.AddDays(7)); ok {
		t.Fatal("next week must still have its rest available")
	}
}

func TestStreakNowTreatsOpenYesterdayAsPending(t *testing.T) {
	loc := mustLoc(t, "America/New_York")
	start := MustDate("2026-10-26")
	days := pattern(start, "xxx.")
	morning := time.Date(2026, 10, 30, 9, 0, 0, 0, loc)
	if got := StreakNow(days, morning, loc).Count; got != 3 {
		t.Fatalf("before the grace hour: count = %d, want 3", got)
	}
	if got := StreakNow(days, morning, loc).RestDays; len(got) != 0 {
		t.Fatalf("a pending day must not spend the rest: %v", got)
	}
	afternoon := time.Date(2026, 10, 30, 11, 0, 0, 0, loc)
	if got := StreakNow(days, afternoon, loc); got.Count != 3 || len(got.RestDays) != 1 {
		t.Fatalf("after the grace hour: %+v, want count 3 with the rest spent", got)
	}
}

func TestStreakNowCountsYesterdayOnceFilled(t *testing.T) {
	loc := mustLoc(t, "America/New_York")
	start := MustDate("2026-10-26")
	days := pattern(start, "xxxx")
	morning := time.Date(2026, 10, 30, 9, 0, 0, 0, loc)
	if got := StreakNow(days, morning, loc).Count; got != 4 {
		t.Fatalf("count = %d, want 4", got)
	}
}

func TestStreakNowCountsTodayWhileYesterdayIsPending(t *testing.T) {
	loc := mustLoc(t, "America/New_York")
	start := MustDate("2026-10-26")
	morning := time.Date(2026, 10, 30, 9, 0, 0, 0, loc)

	// Join day: only today exists and it already counted.
	joined := pattern(MustDate("2026-10-30"), "x")
	if got := StreakNow(joined, morning, loc); got.Count != 1 || len(got.RestDays) != 0 {
		t.Fatalf("join day counted before the grace hour: %+v, want count 1", got)
	}

	// Three counted days, yesterday still open, today counted.
	days := pattern(start, "xxx.x")
	if got := StreakNow(days, morning, loc); got.Count != 4 || len(got.RestDays) != 0 {
		t.Fatalf("pending yesterday with today counted: %+v, want count 4 and no rest spent", got)
	}
}

func mustLoc(t *testing.T, name string) *time.Location {
	t.Helper()
	loc, err := time.LoadLocation(name)
	if err != nil {
		t.Fatalf("load %s: %v", name, err)
	}
	return loc
}
