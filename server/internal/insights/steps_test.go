package insights

import (
	"testing"

	"github.com/nc1107/new-me/server/internal/score"
)

const today = score.Date("2026-11-02")

func ptr(n int) *int { return &n }

// daysBack builds one StepDay per value, the first value being yesterday and each next one a
// day earlier; a zero leaves that day without a reading.
func daysBack(values ...float64) []StepDay {
	var out []StepDay
	for i, v := range values {
		if v > 0 {
			out = append(out, StepDay{Date: today.AddDays(-(i + 1)), Steps: v})
		}
	}
	return out
}

func repeat(v float64, n int) []float64 {
	out := make([]float64, n)
	for i := range out {
		out[i] = v
	}
	return out
}

func TestSuggest(t *testing.T) {
	tests := []struct {
		name   string
		median int
		age    *int
		want   int
		low    int
		high   int
	}{
		{"under 60 below band rounds up to next 500", 6200, ptr(35), 7500, 8000, 10000},
		{"under 60 below band is capped at the low end", 7600, ptr(35), 8000, 8000, 10000},
		{"below band exact multiple stays", 6500, ptr(35), 7500, 8000, 10000},
		{"below band just over a multiple goes to the next", 6501, ptr(35), 8000, 8000, 10000},
		{"inside band rounds to nearest 500", 8200, ptr(35), 9000, 8000, 10000},
		{"inside band rounds half up", 8250, ptr(35), 9500, 8000, 10000},
		{"inside band at the low end", 8000, ptr(35), 9000, 8000, 10000},
		{"inside band is capped at the high end", 9400, ptr(35), 10000, 8000, 10000},
		{"at the high end keeps the median", 10000, ptr(35), 10000, 8000, 10000},
		{"above band rounds down to 500", 12345, ptr(35), 12000, 8000, 10000},
		{"above band exact", 11500, ptr(35), 11500, 8000, 10000},
		{"60 and over uses the older band", 6500, ptr(60), 7500, 6000, 8000},
		{"59 uses the younger band", 6500, ptr(59), 7500, 8000, 10000},
		{"older inside band capped", 7800, ptr(70), 8000, 6000, 8000},
		{"older above band", 9100, ptr(70), 9000, 6000, 8000},
		{"unknown age inside band", 7400, nil, 8500, 7000, 10000},
		{"unknown age below band", 5000, nil, 6000, 7000, 10000},
		{"unknown age above band", 10400, nil, 10000, 7000, 10000},
		{"floor applies to a very low median", 1000, ptr(35), 3000, 8000, 10000},
		{"floor applies at zero", 0, nil, 3000, 7000, 10000},
		{"just above the floor", 2200, nil, 3500, 7000, 10000},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got := Suggest(tt.median, tt.age)
			if got.Target != tt.want || got.BandLow != tt.low || got.BandHigh != tt.high ||
				got.Median14 != tt.median || got.AgeKnown != (tt.age != nil) {
				t.Fatalf("Suggest(%d) = %+v, want target %d band %d-%d", tt.median, got, tt.want, tt.low, tt.high)
			}
		})
	}
}

func TestAgeOnUsesCalendarYears(t *testing.T) {
	tests := []struct {
		birth *int
		want  *int
	}{
		{nil, nil},
		{ptr(1990), ptr(36)},
		{ptr(2026), ptr(0)},
		{ptr(2030), nil},
	}
	for _, tt := range tests {
		got := ageOn(today, tt.birth)
		if (got == nil) != (tt.want == nil) || (got != nil && *got != *tt.want) {
			t.Errorf("ageOn(%v) = %v, want %v", tt.birth, got, tt.want)
		}
	}
}

func TestStepsWindowsAndAverages(t *testing.T) {
	// Yesterday back 14 days: 7 days of 10000 then 7 days of 8000.
	vals := append(repeat(10000, 7), repeat(8000, 7)...)
	got := ComputeSteps(StepInput{Days: daysBack(vals...), Today: today, Goal: 9000})
	if got.Avg7 != 10000 || got.Avg30 != 9000 || got.Median14 != 9000 {
		t.Fatalf("averages = %+v", got)
	}
	if got.Trend != TrendUp {
		t.Fatalf("trend = %q, want up", got.Trend)
	}
	// 14 days at 10000 and 7 at 8000 -> only the first 7 are at goal 9000 or more.
	if got.DaysAtGoal30 != 7 {
		t.Fatalf("daysAtGoal30 = %d, want 7", got.DaysAtGoal30)
	}
}

func TestStepsExcludeTodayFromAveragesButNotBestOrGoal(t *testing.T) {
	days := append(daysBack(repeat(7000, 14)...), StepDay{Date: today, Steps: 20000})
	got := ComputeSteps(StepInput{Days: days, Today: today, Goal: 7000})
	if got.Avg7 != 7000 || got.Median14 != 7000 {
		t.Fatalf("a partial today must not move the averages: %+v", got)
	}
	if got.Best == nil || got.Best.Date != today || got.Best.Value != 20000 {
		t.Fatalf("best = %+v, want today at 20000", got.Best)
	}
	if got.DaysAtGoal30 != 15 {
		t.Fatalf("daysAtGoal30 = %d, want 15", got.DaysAtGoal30)
	}
}

func TestStepsTrend(t *testing.T) {
	tests := []struct {
		name         string
		recent, prev float64
		want         string
	}{
		{"just over 5 percent up", 10501, 10000, TrendUp},
		{"exactly 5 percent up is flat", 10500, 10000, TrendFlat},
		{"exactly 5 percent down is flat", 9500, 10000, TrendFlat},
		{"just under 5 percent down", 9499, 10000, TrendDown},
		{"same", 8000, 8000, TrendFlat},
		{"large drop", 4000, 8000, TrendDown},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			vals := append(repeat(tt.recent, 7), repeat(tt.prev, 7)...)
			if got := ComputeSteps(StepInput{Days: daysBack(vals...), Today: today}); got.Trend != tt.want {
				t.Fatalf("trend = %q, want %q", got.Trend, tt.want)
			}
		})
	}
	t.Run("no earlier week is flat", func(t *testing.T) {
		if got := ComputeSteps(StepInput{Days: daysBack(repeat(9000, 7)...), Today: today}); got.Trend != TrendFlat {
			t.Fatalf("trend = %q", got.Trend)
		}
	})
	t.Run("no recent week is flat", func(t *testing.T) {
		vals := append(repeat(0, 7), repeat(9000, 7)...)
		if got := ComputeSteps(StepInput{Days: daysBack(vals...), Today: today}); got.Trend != TrendFlat {
			t.Fatalf("trend = %q", got.Trend)
		}
	})
}

func TestStepsMedianOfAnEvenAndOddCount(t *testing.T) {
	odd := ComputeSteps(StepInput{Days: daysBack(1000, 9000, 5000, 7000, 3000), Today: today})
	if odd.Median14 != 5000 {
		t.Fatalf("odd median = %d", odd.Median14)
	}
	even := ComputeSteps(StepInput{Days: daysBack(1000, 9000, 5000, 6001), Today: today})
	if even.Median14 != 5501 {
		t.Fatalf("even median = %d, want 5501", even.Median14)
	}
}

func TestStepsSuggestionNeedsFiveDays(t *testing.T) {
	four := ComputeSteps(StepInput{Days: daysBack(7000, 7000, 7000, 7000), Today: today})
	if four.Suggestion != nil {
		t.Fatalf("suggestion with 4 days = %+v", four.Suggestion)
	}
	five := ComputeSteps(StepInput{Days: daysBack(7400, 7400, 7400, 7400, 7400), Today: today})
	if five.Suggestion == nil || five.Suggestion.Target != 8500 || five.Suggestion.AgeKnown {
		t.Fatalf("suggestion with 5 days = %+v", five.Suggestion)
	}
	// Days outside the two-week window do not count toward the five.
	old := []StepDay{}
	for i := 15; i < 20; i++ {
		old = append(old, StepDay{Date: today.AddDays(-i), Steps: 8000})
	}
	if got := ComputeSteps(StepInput{Days: old, Today: today}); got.Suggestion != nil {
		t.Fatalf("old days produced a suggestion: %+v", got.Suggestion)
	}
}

func TestStepsSuggestionUsesAge(t *testing.T) {
	days := daysBack(repeat(6500, 14)...)
	young := ComputeSteps(StepInput{Days: days, Today: today, BirthYear: ptr(1995)})
	old := ComputeSteps(StepInput{Days: days, Today: today, BirthYear: ptr(1960)})
	if young.Suggestion.Target != 7500 || young.Suggestion.BandLow != 8000 || !young.Suggestion.AgeKnown {
		t.Fatalf("young = %+v", young.Suggestion)
	}
	if old.Suggestion.Target != 7500 || old.Suggestion.BandHigh != 8000 || old.Suggestion.BandLow != 6000 {
		t.Fatalf("old = %+v", old.Suggestion)
	}
}

func TestStepsBestDayAndEmpty(t *testing.T) {
	got := ComputeSteps(StepInput{Days: daysBack(5000, 12000, 8000, 12000), Today: today, Goal: 8000})
	if got.Best == nil || got.Best.Value != 12000 || got.Best.Date != today.AddDays(-2) {
		t.Fatalf("best = %+v, want the more recent of the tied days", got.Best)
	}
	if got.DaysAtGoal30 != 3 {
		t.Fatalf("daysAtGoal30 = %d", got.DaysAtGoal30)
	}

	empty := ComputeSteps(StepInput{Today: today, Goal: 8000})
	if empty.Best != nil || empty.Suggestion != nil || empty.Avg7 != 0 || empty.Avg30 != 0 || empty.Median14 != 0 ||
		empty.Trend != TrendFlat || empty.Goal != 8000 {
		t.Fatalf("empty = %+v", empty)
	}
}

func TestStepsIgnoresZeroDaysAndOutOfWindow(t *testing.T) {
	days := []StepDay{
		{Date: today.AddDays(-1), Steps: 0},
		{Date: today.AddDays(-2), Steps: 6000},
		{Date: today.AddDays(-40), Steps: 90000},
	}
	got := ComputeSteps(StepInput{Days: days, Today: today})
	if got.Avg7 != 6000 || got.Avg30 != 6000 || got.Best == nil || got.Best.Value != 6000 {
		t.Fatalf("got %+v", got)
	}
}

func TestStepsDaysAtGoalWithoutAGoal(t *testing.T) {
	if got := ComputeSteps(StepInput{Days: daysBack(5000, 6000), Today: today}); got.DaysAtGoal30 != 0 {
		t.Fatalf("daysAtGoal30 = %d with no goal", got.DaysAtGoal30)
	}
}
