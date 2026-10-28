package training

import (
	"strings"
	"testing"
)

func TestEaseDropsOneSetAndHoldsLoadAndReps(t *testing.T) {
	p := Prescription{Exercise: "db_row", Sets: 3, Min: 6, Max: 10, RIR: 2}
	// Every set at the top: Next would raise the load, Ease must not.
	history := []SessionResult{{Sets: loaded(20, 10, 10, 10)}}
	if up := Next(p, row, history, Equipment{}); up.LoadKg <= 20 {
		t.Fatalf("precondition: Next should progress the load, got %+v", up)
	}
	got := Ease(p, history)
	if got.Sets != 2 || got.LoadKg != 20 || got.Amount != 10 || got.Exercise != "db_row" {
		t.Fatalf("got %+v", got)
	}
}

func TestEaseHoldsTheLowestSetNotTheNextRep(t *testing.T) {
	p := Prescription{Exercise: "pull_up", Sets: 4, Min: 5, Max: 8, RIR: 2}
	got := Ease(p, []SessionResult{{Sets: reps(7, 6, 6, 6)}})
	if got.Sets != 3 || got.Amount != 6 || got.LoadKg != 0 {
		t.Fatalf("got %+v", got)
	}
	if !strings.Contains(got.Reason, "Held") {
		t.Fatalf("reason = %q", got.Reason)
	}
}

func TestEaseNeverGoesBelowOneSet(t *testing.T) {
	for _, sets := range []int{1, 2} {
		got := Ease(Prescription{Exercise: "push_up", Sets: sets, Min: 6, Max: 12}, nil)
		if want := max(1, sets-1); got.Sets != want {
			t.Fatalf("sets %d -> %d, want %d", sets, got.Sets, want)
		}
	}
}

func TestEaseWithoutHistoryStartsAtTheBottom(t *testing.T) {
	got := Ease(Prescription{Exercise: "push_up", Sets: 3, Min: 6, Max: 12}, nil)
	if got.Amount != 6 || got.Sets != 2 || got.LoadKg != 0 || !strings.Contains(got.Reason, "First time") {
		t.Fatalf("got %+v", got)
	}
}

func TestEaseKeepsHeldRepsInsideTheRange(t *testing.T) {
	p := Prescription{Exercise: "push_up", Sets: 3, Min: 6, Max: 12}
	if got := Ease(p, []SessionResult{{Sets: reps(3, 4, 4)}}); got.Amount != 6 {
		t.Fatalf("below the range should hold at the bottom: %+v", got)
	}
	if got := Ease(p, []SessionResult{{Sets: reps(15, 14, 14)}}); got.Amount != 12 {
		t.Fatalf("above the range should hold at the top: %+v", got)
	}
}

func TestEasedReasonNamesTheMostTellingSignal(t *testing.T) {
	cases := []struct {
		kinds []string
		want  string
	}{
		{[]string{"sleep", "hrv"}, "Your HRV is below its usual level, so today is one set lighter."},
		{[]string{"resting_hr"}, "Your resting heart rate is above its usual level, so today is one set lighter."},
		{[]string{"sleep"}, "You slept less than your target, so today is one set lighter."},
		{nil, "You look under-recovered this morning, so today is one set lighter."},
	}
	for _, c := range cases {
		if got := EasedReason(c.kinds); got != c.want {
			t.Errorf("EasedReason(%v) = %q, want %q", c.kinds, got, c.want)
		}
	}
}
