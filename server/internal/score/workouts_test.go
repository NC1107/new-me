package score

import "testing"

func TestPushupsProgress(t *testing.T) {
	strength := func(min float64) []WorkoutSpan { return []WorkoutSpan{{Type: "strength", DurationMin: min}} }
	cases := []struct {
		name        string
		reps        int
		target      int
		workouts    []WorkoutSpan
		wantActual  int
		wantDoneBy  bool
		wantMinutes int
	}{
		{"no workout keeps the logged reps", 12, 30, nil, 12, false, 0},
		{"strength of 20 completes the quest", 0, 30, strength(20), 30, true, 20},
		{"strength under 20 does nothing", 5, 30, strength(19.9), 5, false, 0},
		{"hiit without a threshold counts like strength", 0, 30, []WorkoutSpan{{Type: "hiit", DurationMin: 22.5}}, 30, true, 22},
		{"hiit of 19 without a threshold does not", 0, 30, []WorkoutSpan{{Type: "hiit", DurationMin: 19}}, 0, false, 0},
		{"running does not count", 0, 30, []WorkoutSpan{{Type: "running", DurationMin: 60}}, 0, false, 0},
		{"enough logged reps are credited to the reps", 40, 30, strength(45), 40, false, 0},
		{"the longest qualifying workout is named", 0, 30,
			[]WorkoutSpan{{Type: "hiit", DurationMin: 25}, {Type: "strength", DurationMin: 42}, {Type: "strength", DurationMin: 10}}, 30, true, 42},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			actual, by := PushupsProgress(tc.reps, tc.target, tc.workouts, nil)
			if actual != tc.wantActual || (by != nil) != tc.wantDoneBy || (by != nil && by.Minutes != tc.wantMinutes) {
				t.Fatalf("got %d %+v", actual, by)
			}
		})
	}
}

func TestWorkoutCreditEarnsFullPointsAndBonus(t *testing.T) {
	actual, _ := PushupsProgress(0, 30, []WorkoutSpan{{Type: "strength", DurationMin: 40}}, nil)
	day := ScoreDay([]QuestResult{{Key: "pushups", Points: 100, Actual: actual, Target: 30}})
	if day.BasePoints != 100 || day.BonusPoints != 20 || !day.Quests[0].Complete {
		t.Fatalf("day = %+v", day)
	}
}

func TestYogaProgressAddsWorkoutMinutes(t *testing.T) {
	cases := []struct {
		logged     int
		workouts   []WorkoutSpan
		wantActual int
		wantBy     int
	}{
		{0, nil, 0, 0},
		{5, []WorkoutSpan{{Type: "yoga", DurationMin: 20.9}}, 25, 20},
		{0, []WorkoutSpan{{Type: "yoga", DurationMin: 10}, {Type: "yoga", DurationMin: 12}}, 22, 22},
		{10, []WorkoutSpan{{Type: "strength", DurationMin: 60}}, 10, 0},
	}
	for _, tc := range cases {
		actual, by := YogaProgress(tc.logged, tc.workouts)
		got := 0
		if by != nil {
			got = by.Minutes
		}
		if actual != tc.wantActual || got != tc.wantBy {
			t.Errorf("%v: got %d %+v", tc, actual, by)
		}
	}
}

func TestISOWeek(t *testing.T) {
	cases := []struct {
		week, monday string
		ok           bool
	}{
		{"2026-W45", "2026-11-02", true},
		{"2026-W01", "2025-12-29", true},
		{"2026-W53", "2026-12-28", true},
		{"2025-W53", "", false},
		{"2024-W01", "2024-01-01", true},
		{"2026-W00", "", false},
		{"2026-W54", "", false},
		{"2026-45", "", false},
	}
	for _, tc := range cases {
		got, err := ParseISOWeek(tc.week)
		if (err == nil) != tc.ok || (tc.ok && string(got) != tc.monday) {
			t.Errorf("%s: got %q, %v", tc.week, got, err)
		}
		if tc.ok {
			if label := ISOWeekLabel(got); label != tc.week {
				t.Errorf("%s round-trips to %s", tc.week, label)
			}
		}
	}
}

func TestHIITMinHR(t *testing.T) {
	age, rest := 40, 60.0
	got := HIITMinHR(&age, &rest)
	// Reserve is 220-40-60 = 120, so 60% of it above resting is 132.
	if got == nil || *got != 132 {
		t.Fatalf("got %v", got)
	}
	if HIITMinHR(nil, &rest) != nil || HIITMinHR(&age, nil) != nil {
		t.Fatal("unknown age or resting HR gives no threshold")
	}
	high := 200.0
	if HIITMinHR(&age, &high) != nil {
		t.Fatal("a resting rate above the maximum gives no threshold")
	}
}

func TestHIITCreditUsesIntensityWhenTheThresholdIsKnown(t *testing.T) {
	age, rest := 40, 60.0
	min := HIITMinHR(&age, &rest) // 132
	hr := func(v float64) *float64 { return &v }
	cases := []struct {
		name string
		w    WorkoutSpan
		want bool
	}{
		{"15 minutes at the threshold", WorkoutSpan{Type: "hiit", DurationMin: 15, AvgHR: hr(132)}, true},
		{"15 minutes just under", WorkoutSpan{Type: "hiit", DurationMin: 15, AvgHR: hr(131.9)}, false},
		{"14 minutes at high intensity", WorkoutSpan{Type: "hiit", DurationMin: 14.9, AvgHR: hr(170)}, false},
		{"30 minutes too easy does not count", WorkoutSpan{Type: "hiit", DurationMin: 30, AvgHR: hr(110)}, false},
		{"no heart rate falls back to 20 minutes", WorkoutSpan{Type: "hiit", DurationMin: 20}, true},
		{"no heart rate and 19 minutes", WorkoutSpan{Type: "hiit", DurationMin: 19}, false},
		{"strength ignores heart rate", WorkoutSpan{Type: "strength", DurationMin: 20, AvgHR: hr(90)}, true},
		{"strength of 15 never counts", WorkoutSpan{Type: "strength", DurationMin: 15, AvgHR: hr(170)}, false},
	}
	for _, tc := range cases {
		if got := StrengthCredit([]WorkoutSpan{tc.w}, min) != nil; got != tc.want {
			t.Errorf("%s: got %v", tc.name, got)
		}
	}
}
