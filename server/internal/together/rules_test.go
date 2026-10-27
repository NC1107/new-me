package together

import (
	"testing"

	"github.com/nc1107/new-me/server/internal/score"
)

func TestKindRotatesByISOWeekNumber(t *testing.T) {
	// 2026-11-02 is Monday of ISO week 45, and 2026-12-28 starts week 53.
	cases := []struct {
		monday string
		kind   string
	}{
		{"2026-11-02", KindWorkouts},    // 45 % 4 = 1
		{"2026-11-09", KindCountedDays}, // 46 % 4 = 2
		{"2026-11-16", KindReading},     // 47 % 4 = 3
		{"2026-11-23", KindSteps},       // 48 % 4 = 0
		{"2026-12-28", KindWorkouts},    // 53 % 4 = 1
		{"2027-01-04", KindWorkouts},    // ISO week 1 of 2027: 1 % 4 = 1
	}
	for _, tc := range cases {
		if got := KindFor(score.MustDate(tc.monday)); got != tc.kind {
			t.Errorf("%s: kind = %s, want %s", tc.monday, got, tc.kind)
		}
	}
	seen := map[string]bool{}
	for d := score.MustDate("2026-11-02"); len(seen) < 4; d = d.AddDays(7) {
		seen[KindFor(d)] = true
	}
}

func TestStepsShareIsTenPercentAboveTheWeeklyAverageRoundedToAThousand(t *testing.T) {
	cases := []struct {
		avg  float64
		want int
	}{
		{0, defaultSteps},
		{-5, defaultSteps},
		{10000, 77000},
		{12000, 92000},  // 92,400
		{15250, 117000}, // 117,425
		{500, minSteps}, // 3,850 -> floor
		{6000, 46000},   // 46,200
	}
	for _, tc := range cases {
		if got := StepsShare(tc.avg); got != tc.want {
			t.Errorf("StepsShare(%v) = %d, want %d", tc.avg, got, tc.want)
		}
	}
}

func TestWorkoutsShareIsLastWeekPlusOneAtLeastTwo(t *testing.T) {
	for last, want := range map[int]int{0: 2, 1: 2, 2: 3, 3: 4, 6: 7} {
		if got := WorkoutsShare(last); got != want {
			t.Errorf("WorkoutsShare(%d) = %d, want %d", last, got, want)
		}
	}
}

func TestReadingShareSizesFromTheWeeklyAverage(t *testing.T) {
	for in, want := range map[int]int{0: defaultReading, 50: minReading, 200: 110, 333: 180} {
		if got := ReadingShare(in); got != want {
			t.Errorf("ReadingShare(%d) = %d, want %d", in, got, want)
		}
	}
}

func TestSharesAreSizedFromEachPersonsOwnHistory(t *testing.T) {
	heavy := Sizing{StepsDailyAverage: 12000, WorkoutsLastWeek: 4, ReadingLastTwoWeeks: 400}
	light := Sizing{StepsDailyAverage: 5000, WorkoutsLastWeek: 1, ReadingLastTwoWeeks: 60}
	cases := []struct {
		kind         string
		heavy, light int
	}{
		{KindSteps, 92000, 39000},
		{KindWorkouts, 5, 2},
		{KindCountedDays, 5, 5},
		{KindReading, 220, minReading},
	}
	for _, tc := range cases {
		if got := Share(tc.kind, heavy); got != tc.heavy {
			t.Errorf("%s heavy = %d, want %d", tc.kind, got, tc.heavy)
		}
		if got := Share(tc.kind, light); got != tc.light {
			t.Errorf("%s light = %d, want %d", tc.kind, got, tc.light)
		}
	}
}

func TestGenerateTitlesAndTargetsPerKind(t *testing.T) {
	cases := []struct {
		monday string
		shares []int
		want   Spec
	}{
		{"2026-11-23", []int{92000, 39000}, Spec{KindSteps, "Walk 131,000 steps together", 131000}},
		{"2026-11-02", []int{5, 2}, Spec{KindWorkouts, "Do 7 workouts together", 7}},
		{"2026-11-09", []int{5, 5}, Spec{KindCountedDays, "Both count on 5 of 7 days", 10}},
		{"2026-11-16", []int{220, 30}, Spec{KindReading, "Read 250 minutes together", 250}},
	}
	for _, tc := range cases {
		if got := Generate(score.MustDate(tc.monday), tc.shares); got != tc.want {
			t.Errorf("%s: %+v, want %+v", tc.monday, got, tc.want)
		}
	}
}

func TestCombinedCompletesOnlyWhenEveryoneReachedTheirOwnShare(t *testing.T) {
	cases := []struct {
		name     string
		people   []Standing
		progress int
		target   int
		complete bool
	}{
		{"nobody", nil, 0, 0, false},
		{"both short", []Standing{{1, 100, 40}, {2, 60, 10}}, 50, 160, false},
		{"one carries the other: still not complete", []Standing{{1, 100, 300}, {2, 60, 10}}, 110, 160, false},
		{"both reached", []Standing{{1, 100, 100}, {2, 60, 90}}, 160, 160, true},
		{"exactly on the share", []Standing{{1, 100, 100}, {2, 60, 60}}, 160, 160, true},
		{"a single person", []Standing{{1, 5, 5}}, 5, 5, true},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			progress, target, complete := Combined(tc.people)
			if progress != tc.progress || target != tc.target || complete != tc.complete {
				t.Fatalf("got %d/%d %v, want %d/%d %v", progress, target, complete, tc.progress, tc.target, tc.complete)
			}
		})
	}
}

func TestWithThousands(t *testing.T) {
	for in, want := range map[int]string{5: "5", 999: "999", 1000: "1,000", 75000: "75,000", 1234567: "1,234,567"} {
		if got := withThousands(in); got != want {
			t.Errorf("withThousands(%d) = %q, want %q", in, got, want)
		}
	}
}

func TestBothCountedDaysNeedsEveryMemberOnTheSameDay(t *testing.T) {
	d := score.MustDate("2026-11-02")
	counted := []Counted{
		{1, d}, {2, d}, // both
		{1, d.AddDays(1)},                    // only one
		{2, d.AddDays(2)},                    // only the other
		{1, d.AddDays(3)}, {2, d.AddDays(3)}, // both
		{3, d.AddDays(4)}, // a stranger
	}
	if got := BothCountedDays(counted, []int64{1, 2}); got != 2 {
		t.Fatalf("both = %d, want 2", got)
	}
	if got := BothCountedDays(counted, []int64{1}); got != 3 {
		t.Fatalf("alone = %d, want 3", got)
	}
	if got := BothCountedDays(counted, nil); got != 0 {
		t.Fatalf("nobody = %d, want 0", got)
	}
}

func TestRewardProgressIsClampedAndReachedAtTheTarget(t *testing.T) {
	if got := RewardProgress(900, 1000, 500); got != 0 {
		t.Errorf("below baseline = %d, want 0", got)
	}
	if got := RewardProgress(1300, 1000, 500); got != 300 {
		t.Errorf("progress = %d, want 300", got)
	}
	if got := RewardProgress(2000, 1000, 500); got != 500 {
		t.Errorf("past target = %d, want 500", got)
	}
	if RewardReached(1499, 1000, 500) || !RewardReached(1500, 1000, 500) {
		t.Error("reached should flip exactly at baseline + target")
	}
}
