package insights

import (
	"math"
	"testing"

	"github.com/nc1107/new-me/server/internal/score"
)

func near(t *testing.T, name string, got, want, tol float64) {
	t.Helper()
	if math.Abs(got-want) > tol {
		t.Fatalf("%s = %v, want %v", name, got, want)
	}
}

func readings(start score.Date, step int, values ...float64) []Reading {
	out := make([]Reading, len(values))
	for i, v := range values {
		out[i] = Reading{Date: start.AddDays(i * step), Value: v}
	}
	return out
}

func TestSmoothIsAnExponentialMovingAverageWithAlphaOneTenth(t *testing.T) {
	got := Smooth(readings("2026-10-05", 7, 80, 79, 78, 77, 76))
	want := []float64{80, 79.9, 79.71, 79.439, 79.0951}
	for i, p := range got {
		near(t, "smoothed", p.Smoothed, want[i], 1e-9)
	}
	if len(Smooth(nil)) != 0 {
		t.Fatal("no readings")
	}
	// A single heavy morning barely moves the trend.
	spike := Smooth(readings("2026-10-05", 1, 80, 80, 80, 83))
	near(t, "after a 3 kg spike", spike[3].Smoothed, 80.3, 1e-9)
}

func TestComputeWeightRate(t *testing.T) {
	tests := []struct {
		name   string
		in     []Reading
		rate   *float64
		smooth float64
	}{
		{"no readings", nil, nil, 0},
		{"one reading has no rate", readings("2026-10-05", 7, 80), nil, 80},
		{"under a week of history", readings("2026-10-05", 1, 80, 80.5, 80.2), nil, 80.065},
		{"exactly a week uses the first reading", readings("2026-10-05", 7, 80, 79), fptr(-0.1), 79.9},
		{"four weeks use the reading 28 days back", readings("2026-10-05", 7, 80, 79, 78, 77, 76), fptr((79.0951 - 80) / 28 * 7), 79.0951},
		{"older history uses the newest reading at least 28 days back", readings("2026-09-14", 7, 82, 81, 80, 79, 78, 77, 76),
			fptr((80.217 - 81.71) / 28 * 7), 0},
	}
	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			w := ComputeWeight(tc.in)
			if tc.in == nil {
				if w != nil {
					t.Fatalf("got %+v", w)
				}
				return
			}
			if tc.smooth != 0 {
				near(t, "smoothed", w.SmoothedKg, tc.smooth, 0.006)
			}
			switch {
			case tc.rate == nil && w.WeeklyRateKg != nil:
				t.Fatalf("rate = %v, want none", *w.WeeklyRateKg)
			case tc.rate != nil && w.WeeklyRateKg == nil:
				t.Fatal("no rate")
			case tc.rate != nil:
				near(t, "rate", *w.WeeklyRateKg, *tc.rate, 0.011)
			}
		})
	}
}

func fptr(v float64) *float64 { return &v }

func TestComputeWeightKeepsTheLastNinetyPoints(t *testing.T) {
	values := make([]float64, 120)
	for i := range values {
		values[i] = 80
	}
	w := ComputeWeight(readings("2026-01-01", 1, values...))
	if len(w.Points) != 90 || w.Points[89].Date != score.MustDate("2026-01-01").AddDays(119) {
		t.Fatalf("points = %d ending %s", len(w.Points), w.Points[len(w.Points)-1].Date)
	}
	if w.WeeklyRateKg == nil || *w.WeeklyRateKg != 0 {
		t.Fatalf("a flat weight has a zero rate: %v", w.WeeklyRateKg)
	}
}
