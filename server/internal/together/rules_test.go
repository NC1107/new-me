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

func TestStepsTargetIsTenPercentAboveTheWeeklyAverageRoundedToFiveThousand(t *testing.T) {
	cases := []struct {
		avg  float64
		want int
	}{
		{0, defaultSteps},
		{-5, defaultSteps},
		{10000, 75000},  // 77,000
		{12000, 90000},  // 92,400
		{15250, 115000}, // 117,425
		{500, 5000},     // 3,850 -> floor
	}
	for _, tc := range cases {
		if got := StepsTarget(tc.avg); got != tc.want {
			t.Errorf("StepsTarget(%v) = %d, want %d", tc.avg, got, tc.want)
		}
	}
}

func TestWorkoutsTargetIsLastWeekPlusOneAtLeastThree(t *testing.T) {
	for last, want := range map[int]int{0: 3, 1: 3, 2: 3, 3: 4, 6: 7} {
		if got := WorkoutsTarget(last); got != want {
			t.Errorf("WorkoutsTarget(%d) = %d, want %d", last, got, want)
		}
	}
}

func TestReadingTargetSizesFromTheWeeklyAverage(t *testing.T) {
	for in, want := range map[int]int{0: defaultReading, 100: 60, 400: 220, 333: 180} {
		if got := ReadingTarget(in); got != want {
			t.Errorf("ReadingTarget(%d) = %d, want %d", in, got, want)
		}
	}
}

func TestGenerateTitlesAndTargetsPerKind(t *testing.T) {
	in := Sizing{StepsDailyAverage: 10000, WorkoutsLastWeek: 4, ReadingLastTwoWeeks: 400}
	cases := []struct {
		monday string
		want   Spec
	}{
		{"2026-11-23", Spec{KindSteps, "Walk 75,000 steps together", 75000}},
		{"2026-11-02", Spec{KindWorkouts, "Do 5 workouts together", 5}},
		{"2026-11-09", Spec{KindCountedDays, "Both count on 5 of 7 days", 5}},
		{"2026-11-16", Spec{KindReading, "Read 220 minutes together", 220}},
	}
	for _, tc := range cases {
		if got := Generate(score.MustDate(tc.monday), in); got != tc.want {
			t.Errorf("%s: %+v, want %+v", tc.monday, got, tc.want)
		}
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
