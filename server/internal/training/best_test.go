package training

import "testing"

func TestEpley(t *testing.T) {
	cases := []struct {
		load float64
		reps int
		want float64
	}{
		{100, 1, 100},
		{100, 10, 133.3},
		{20, 8, 25.3},
		{0, 5, 0},
		{50, 0, 0},
	}
	for _, c := range cases {
		if got := Epley(c.load, c.reps); got != c.want {
			t.Errorf("Epley(%v, %d) = %v, want %v", c.load, c.reps, got, c.want)
		}
	}
}

func TestBestSetBodyweightPicksMostReps(t *testing.T) {
	sets := []Set{{Date: "2026-10-01", Reps: 5}, {Date: "2026-10-03", Reps: 8}, {Date: "2026-10-05", Reps: 6}}
	best, ok := BestSet(sets, false)
	if !ok || best.Reps != 8 || best.Date != "2026-10-03" || best.E1RMKg != 0 {
		t.Fatalf("best = %+v, %v", best, ok)
	}
}

func TestBestSetTiesGoToTheNewest(t *testing.T) {
	sets := []Set{{Date: "2026-10-01", Reps: 8}, {Date: "2026-10-04", Reps: 8}}
	if best, _ := BestSet(sets, false); best.Date != "2026-10-04" {
		t.Fatalf("tie went to %s, want the newest", best.Date)
	}
}

func TestBestSetSecondsForHolds(t *testing.T) {
	sets := []Set{{Date: "2026-10-01", Seconds: 40}, {Date: "2026-10-02", Seconds: 65}}
	if best, _ := BestSet(sets, false); best.Seconds != 65 {
		t.Fatalf("best = %+v", best)
	}
}

func TestBestSetLoadedUsesTheEstimate(t *testing.T) {
	// 60 kg x 10 (80.0) beats 70 kg x 3 (77.0) on the estimated one-rep max.
	sets := []Set{{Date: "2026-10-01", Reps: 3, LoadKg: 70}, {Date: "2026-10-02", Reps: 10, LoadKg: 60}}
	best, _ := BestSet(sets, true)
	if best.LoadKg != 60 || best.E1RMKg != 80 {
		t.Fatalf("best = %+v", best)
	}
}

func TestBestSetEmpty(t *testing.T) {
	if _, ok := BestSet(nil, false); ok {
		t.Fatal("no sets must not report a best")
	}
}
