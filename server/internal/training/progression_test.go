package training

import (
	"math"
	"strings"
	"testing"
)

func reps(n ...int) []Set {
	out := make([]Set, len(n))
	for i, r := range n {
		out[i] = Set{Reps: r}
	}
	return out
}

func loaded(load float64, n ...int) []Set {
	out := reps(n...)
	for i := range out {
		out[i].LoadKg = load
	}
	return out
}

var pullups = ExerciseInfo{Key: "pull_up", EasierKey: "negative_pull_up"}
var pushups = ExerciseInfo{Key: "push_up", EasierKey: "incline_push_up", HarderKey: "decline_push_up"}
var row = ExerciseInfo{Key: "db_row", Loaded: true}
var gobletSquat = ExerciseInfo{Key: "goblet_squat", Loaded: true, Lower: true}

func TestNextStartsAtTheBottomOfTheRange(t *testing.T) {
	got := Next(Prescription{Exercise: "pull_up", Sets: 4, Min: 5, Max: 8, RIR: 2}, pullups, nil, Equipment{})
	if got.Amount != 5 || got.Sets != 4 || got.Exercise != "pull_up" || !strings.Contains(got.Reason, "First time") {
		t.Fatalf("got %+v", got)
	}
}

func TestNextAddsARepFromTheLowestSet(t *testing.T) {
	p := Prescription{Exercise: "pull_up", Sets: 3, Min: 5, Max: 8, RIR: 2}
	got := Next(p, pullups, []SessionResult{{Sets: reps(7, 6, 6)}}, Equipment{})
	if got.Amount != 7 || !strings.Contains(got.Reason, "ACSM") {
		t.Fatalf("got %+v", got)
	}
	capped := Next(p, pullups, []SessionResult{{Sets: reps(8, 8, 7)}}, Equipment{})
	if capped.Amount != 8 {
		t.Fatalf("aim must stay inside the range, got %+v", capped)
	}
}

func TestNextHoldsTheTopOnceThenMovesToTheHarderVariation(t *testing.T) {
	p := Prescription{Exercise: "push_up", Sets: 3, Min: 8, Max: 12, RIR: 2}
	once := Next(p, pushups, []SessionResult{{Sets: reps(12, 12, 12)}}, Equipment{})
	if once.Exercise != "push_up" || once.Amount != 12 {
		t.Fatalf("one top session should hold, got %+v", once)
	}
	twice := Next(p, pushups, []SessionResult{{Sets: reps(12, 12, 12)}, {Sets: reps(12, 12, 12)}}, Equipment{})
	if twice.Exercise != "decline_push_up" || twice.Amount != 8 {
		t.Fatalf("two top sessions should move to the harder variation, got %+v", twice)
	}
}

func TestNextTopNeedsTheTargetRepsInReserve(t *testing.T) {
	p := Prescription{Exercise: "db_row", Sets: 2, Min: 8, Max: 12, RIR: 2}
	got := Next(p, row, []SessionResult{{Sets: loaded(20, 12, 12), RIRs: []int{2, 0}}}, Equipment{})
	if got.LoadKg != 20 {
		t.Fatalf("a top set at 0 in reserve when 2 was asked must not add load, got %+v", got)
	}
	unknown := Next(p, row, []SessionResult{{Sets: loaded(20, 12, 12), RIRs: []int{-1, -1}}}, Equipment{})
	if unknown.LoadKg != 22 {
		t.Fatalf("sets without a logged reserve still count, got %+v", unknown)
	}
}

func TestNextAddsLoadByTheACSMStepRoundedToTheEquipment(t *testing.T) {
	p := Prescription{Exercise: "db_row", Sets: 3, Min: 8, Max: 12, RIR: 2}
	cases := []struct {
		name string
		info ExerciseInfo
		load float64
		eq   Equipment
		want float64
	}{
		{"upper dumbbell under 10 kg goes up one 1 kg step", row, 8, Equipment{}, 9},
		{"upper dumbbell from 10 kg goes up one 2 kg step", row, 20, Equipment{}, 22},
		{"lower body takes at least 5%, rounded up to the step", gobletSquat, 40, Equipment{}, 42},
		{"lower body on a heavy dumbbell rounds 5% up", gobletSquat, 50, Equipment{}, 54},
		{"barbell steps by 2.5 kg plates", gobletSquat, 100, Equipment{Barbell: true}, 105},
		{"never past the heaviest dumbbell", row, 24, Equipment{DumbbellMaxKg: 25}, 25},
	}
	for _, c := range cases {
		got := Next(Prescription{Exercise: p.Exercise, Sets: 3, Min: 8, Max: 12, RIR: 2}, c.info,
			[]SessionResult{{Sets: loaded(c.load, 12, 12, 12)}}, c.eq)
		if got.LoadKg != c.want || got.Amount != 8 {
			t.Errorf("%s: got %+v, want %v kg at 8 reps", c.name, got, c.want)
		}
	}
}

func TestNextBacksOffAfterTwoMisses(t *testing.T) {
	p := Prescription{Exercise: "db_row", Sets: 3, Min: 8, Max: 12, RIR: 2}
	missed := []SessionResult{{Sets: loaded(30, 7, 6, 6)}, {Sets: loaded(30, 8, 7, 6)}}
	got := Next(p, row, missed, Equipment{})
	if got.LoadKg != 26 || got.Amount != 8 || !strings.Contains(got.Reason, "comes down") {
		t.Fatalf("got %+v", got)
	}
	one := Next(p, row, missed[:1], Equipment{})
	if one.LoadKg != 30 {
		t.Fatalf("one miss must not deload, got %+v", one)
	}
	bw := Next(Prescription{Exercise: "pull_up", Sets: 3, Min: 5, Max: 8, RIR: 2}, pullups,
		[]SessionResult{{Sets: reps(3, 2, 2)}, {Sets: reps(4, 3, 3)}}, Equipment{})
	if bw.Exercise != "negative_pull_up" || bw.Amount != 5 {
		t.Fatalf("bodyweight misses should step to the easier variation, got %+v", bw)
	}
}

func TestNextTimedHoldsStepBySeconds(t *testing.T) {
	plank := ExerciseInfo{Key: "plank", Timed: true}
	p := Prescription{Exercise: "plank", Sets: 3, Min: 30, Max: 60, RIR: 1}
	got := Next(p, plank, []SessionResult{{Sets: []Set{{Seconds: 40}, {Seconds: 35}, {Seconds: 35}}}}, Equipment{})
	if got.Amount != 40 || !strings.Contains(got.Reason, "seconds") {
		t.Fatalf("got %+v", got)
	}
}

func TestIncrement(t *testing.T) {
	if Increment(8, Equipment{}) != 1 || Increment(10, Equipment{}) != 2 || Increment(8, Equipment{Barbell: true}) != 2.5 {
		t.Fatal("increments do not match the convention")
	}
}

func TestImperialLoadsStepOnAPoundGrid(t *testing.T) {
	p := Prescription{Exercise: "db_row", Sets: 2, Min: 8, Max: 12, RIR: 2}
	lb := func(v float64) float64 { return v * kgPerLb }
	cases := []struct {
		name string
		info ExerciseInfo
		load float64
		eq   Equipment
		want float64
	}{
		{"a 40 lb dumbbell goes to 45 lb", row, lb(40), Equipment{Imperial: true}, 45},
		{"an 8 lb dumbbell goes to the next 2.5 lb step, 10 lb", row, lb(8), Equipment{Imperial: true}, 10},
		{"a 135 lb barbell squat goes up 5% rounded up to 5 lb plates", gobletSquat, lb(135), Equipment{Imperial: true, Barbell: true}, 145},
		{"never past a 50 lb heaviest dumbbell", row, lb(50), Equipment{Imperial: true, DumbbellMaxKg: lb(50)}, 50},
	}
	for _, c := range cases {
		got := Next(p, c.info, []SessionResult{{Sets: loaded(c.load, 12, 12)}}, c.eq)
		if math.Abs(got.LoadKg*lbPerKg-c.want) > 0.05 {
			t.Errorf("%s: got %.2f lb, want %v", c.name, got.LoadKg*lbPerKg, c.want)
		}
		if !strings.Contains(got.Reason, " lb") || strings.Contains(got.Reason, " kg") {
			t.Errorf("%s: reason should be in pounds: %q", c.name, got.Reason)
		}
	}
}
