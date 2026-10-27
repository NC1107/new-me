package recap

import (
	"strings"
	"testing"

	"github.com/nc1107/new-me/server/internal/score"
)

func d(date string, points int, counted bool) DayPoints {
	return DayPoints{Date: score.MustDate(date), Points: points, Counted: counted}
}

func TestStatsOf(t *testing.T) {
	got := StatsOf(Week{
		Days:  []DayPoints{d("2026-10-26", 300, true), d("2026-10-27", 120, false), d("2026-10-28", 280, true)},
		Steps: 51234, AsleepNights: []int{400, 421, 430}, Workouts: 2, ReadingMinutes: 95,
	})
	want := Stats{Points: 700, CountedDays: 2, Steps: 51234, SleepAvgMin: 417, SleepNights: 3, Workouts: 2, ReadingMinutes: 95}
	if got != want {
		t.Fatalf("got %+v, want %+v", got, want)
	}
	if empty := StatsOf(Week{}); empty != (Stats{}) {
		t.Fatalf("empty week = %+v", empty)
	}
}

func TestPairStatsWeightsSleepByNights(t *testing.T) {
	a := Stats{Points: 100, SleepAvgMin: 400, SleepNights: 6, Steps: 10}
	b := Stats{Points: 50, SleepAvgMin: 460, SleepNights: 2, Steps: 5, Workouts: 1}
	got := PairStats(a, b)
	if got.Points != 150 || got.Steps != 15 || got.Workouts != 1 || got.SleepNights != 8 || got.SleepAvgMin != 415 {
		t.Fatalf("pair = %+v", got)
	}
}

func TestBestDay(t *testing.T) {
	days := []DayPoints{d("2026-10-27", 200, true), d("2026-10-26", 200, true), d("2026-10-28", 150, false)}
	if b := Best(days); b == nil || b.Date != "2026-10-26" || b.Points != 200 {
		t.Fatalf("best = %+v", b)
	}
	if Best([]DayPoints{d("2026-10-26", 0, false)}) != nil || Best(nil) != nil {
		t.Fatal("a week with no points has no best day")
	}
	pair := CombineDays(
		[]DayPoints{d("2026-10-26", 100, true), d("2026-10-27", 50, false)},
		[]DayPoints{d("2026-10-26", 10, false), d("2026-10-27", 120, true)})
	if b := Best(pair); b.Date != "2026-10-27" || b.Points != 170 {
		t.Fatalf("pair best = %+v", b)
	}
}

func TestSuggestFirstMatchingRuleWins(t *testing.T) {
	good := Stats{Points: 2000, CountedDays: 6, Steps: 60000, SleepAvgMin: 450, SleepNights: 7, Workouts: 3}
	cases := []struct {
		name      string
		cur, prev Stats
		complete  bool
		wantHas   string
	}{
		{"few counted days", with(good, func(s *Stats) { s.CountedDays = 3 }), good, true, "Aim for 5 counted days next week. You had 3."},
		{"a running week is not judged", with(good, func(s *Stats) { s.CountedDays = 1; s.Steps = 40000 }), good, false, "still running"},
		{"steps slipped", with(good, func(s *Stats) { s.Steps = 50000 }), good, true, "Steps slipped 17%"},
		{"steps within 10 percent", with(good, func(s *Stats) { s.Steps = 54500 }), good, true, "Solid week"},
		{"short sleep", with(good, func(s *Stats) { s.SleepAvgMin = 385 }), good, true, "averaged 6 h 25 of sleep"},
		{"sleep needs three nights", with(good, func(s *Stats) { s.SleepAvgMin = 300; s.SleepNights = 2 }), good, true, "Solid week"},
		{"no workouts", with(good, func(s *Stats) { s.Workouts = 0 }), good, true, "No workouts this week"},
		{"points dipped", with(good, func(s *Stats) { s.Points = 1800 }), good, true, "Points dipped"},
		{"solid", good, good, true, "try to beat 2,000 points"},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			if got := Suggest(tc.cur, tc.prev, tc.complete); !strings.Contains(got, tc.wantHas) {
				t.Fatalf("got %q, want it to contain %q", got, tc.wantHas)
			}
		})
	}
}

func with(s Stats, edit func(*Stats)) Stats {
	edit(&s)
	return s
}

func TestSummaryLineSingularDay(t *testing.T) {
	got := SummaryLine(Stats{Points: 10, CountedDays: 1}, Stats{}, Stats{Points: 10})
	if got != "10 points, 1 counted day, 0 steps. Together: 10 points." {
		t.Fatalf("got %q", got)
	}
}

func TestSummaryLine(t *testing.T) {
	cur := Stats{Points: 1820, CountedDays: 5, Steps: 61200}
	pair := Stats{Points: 3410}
	cases := []struct {
		prev Stats
		want string
	}{
		{Stats{Points: 1625}, "1,820 points, 5 counted days, 61,200 steps. Up 12% on last week. Together: 3,410 points."},
		{Stats{Points: 2000}, "1,820 points, 5 counted days, 61,200 steps. Down 9% on last week. Together: 3,410 points."},
		{Stats{Points: 1820}, "1,820 points, 5 counted days, 61,200 steps. Level with last week. Together: 3,410 points."},
		{Stats{}, "1,820 points, 5 counted days, 61,200 steps. Together: 3,410 points."},
	}
	for _, tc := range cases {
		if got := SummaryLine(cur, tc.prev, pair); got != tc.want {
			t.Errorf("got %q, want %q", got, tc.want)
		}
	}
}
