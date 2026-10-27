package readiness

import (
	"slices"
	"testing"
)

func f(v float64) *float64 { return &v }
func i(v int) *int         { return &v }

func days(n int, v float64) []float64 {
	out := make([]float64, n)
	for k := range out {
		out[k] = v
	}
	return out
}

func kinds(r Result) []string {
	var out []string
	for _, reason := range r.Reasons {
		out = append(out, reason.Kind)
	}
	return out
}

func TestCompute(t *testing.T) {
	cases := []struct {
		name      string
		in        Input
		ok        bool
		level     string
		basis     string
		wantKinds []string
	}{
		{"nothing to go on", Input{SleepTargetMin: 420}, false, "", "", nil},
		{"sleep only, short", Input{SleepMin: i(360), SleepTargetMin: 420}, true, LevelEasy, BasisSleepOnly, []string{"sleep", "basis"}},
		{"sleep only, met", Input{SleepMin: i(425), SleepTargetMin: 420}, true, LevelReady, BasisSleepOnly, []string{"sleep", "basis"}},
		{"sleep only, 20 under is within slack of nothing", Input{SleepMin: i(400), SleepTargetMin: 420}, true, LevelNormal, BasisSleepOnly, []string{"steady", "basis"}},
		{"sleep only, in between gives a steady line", Input{SleepMin: i(380), SleepTargetMin: 420}, true, LevelNormal, BasisSleepOnly, []string{"steady", "basis"}},
		{"six days of HRV is not a baseline", Input{SleepMin: i(430), SleepTargetMin: 420, HRV: f(40), HRVBase: days(6, 60)},
			true, LevelReady, BasisSleepOnly, []string{"sleep", "basis"}},
		{"HRV down 15% but on-target sleep balances to normal", Input{SleepMin: i(410), SleepTargetMin: 420, HRV: f(51), HRVBase: days(10, 60)},
			true, LevelNormal, BasisFull, []string{"hrv", "sleep"}},
		{"HRV exactly 15% down is strain (neutral sleep)", Input{SleepMin: i(380), SleepTargetMin: 420, HRV: f(51), HRVBase: days(10, 60)},
			true, LevelEasy, BasisFull, []string{"hrv"}},
		{"HRV 14% down is not", Input{SleepMin: i(380), SleepTargetMin: 420, HRV: f(51.6), HRVBase: days(10, 60)},
			true, LevelNormal, BasisFull, []string{"steady"}},
		{"resting HR 5 up is strain", Input{SleepMin: i(380), SleepTargetMin: 420, RestingHR: f(60), RestingBase: days(30, 55)},
			true, LevelEasy, BasisFull, []string{"resting_hr"}},
		{"resting HR 4 up is not", Input{SleepMin: i(380), SleepTargetMin: 420, RestingHR: f(59), RestingBase: days(30, 55)},
			true, LevelNormal, BasisFull, []string{"steady"}},
		{"above-baseline HRV and on-target sleep is ready", Input{SleepMin: i(420), SleepTargetMin: 420, HRV: f(66), HRVBase: days(20, 60)},
			true, LevelReady, BasisFull, []string{"hrv", "sleep"}},
		{"good HRV alone stays normal", Input{SleepMin: i(380), SleepTargetMin: 420, HRV: f(70), HRVBase: days(20, 60)},
			true, LevelNormal, BasisFull, []string{"hrv"}},
		{"great sleep offsets one strain", Input{SleepMin: i(430), SleepTargetMin: 420, RestingHR: f(62), RestingBase: days(20, 55)},
			true, LevelNormal, BasisFull, []string{"resting_hr", "sleep"}},
		{"short sleep and low HRV", Input{SleepMin: i(350), SleepTargetMin: 420, HRV: f(49), HRVBase: days(30, 60)},
			true, LevelEasy, BasisFull, []string{"hrv", "sleep"}},
		{"no sleep recorded but heart data is enough", Input{SleepTargetMin: 420, HRV: f(40), HRVBase: days(8, 60)},
			true, LevelEasy, BasisFull, []string{"hrv"}},
		{"no reading today means no comparison", Input{SleepMin: i(300), SleepTargetMin: 420, HRVBase: days(30, 60)},
			true, LevelEasy, BasisSleepOnly, []string{"sleep", "basis"}},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			got, ok := Compute(tc.in)
			if ok != tc.ok {
				t.Fatalf("ok = %v", ok)
			}
			if !ok {
				return
			}
			if got.Level != tc.level || got.Basis != tc.basis || !slices.Equal(kinds(got), tc.wantKinds) {
				t.Fatalf("got %+v, want level %s basis %s kinds %v", got, tc.level, tc.basis, tc.wantKinds)
			}
		})
	}
}

func TestReasonText(t *testing.T) {
	got, _ := Compute(Input{SleepMin: i(370), SleepTargetMin: 480, HRV: f(49.2), HRVBase: days(30, 60)})
	want := []string{"HRV 18% below your usual", "Slept 6 h 10, 1 h 50 under your target"}
	for n, reason := range got.Reasons {
		if reason.Text != want[n] {
			t.Errorf("reason %d = %q, want %q", n, reason.Text, want[n])
		}
	}
}

func TestDuration(t *testing.T) {
	for in, want := range map[int]string{45: "45 min", 60: "1 h", 370: "6 h 10", 425: "7 h 05"} {
		if got := Duration(in); got != want {
			t.Errorf("Duration(%d) = %q, want %q", in, got, want)
		}
	}
}
