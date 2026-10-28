package regularity

import (
	"testing"
	"time"

	"github.com/nc1107/new-me/server/internal/score"
)

var ny = mustZone("America/New_York")

func mustZone(name string) *time.Location {
	loc, err := time.LoadLocation(name)
	if err != nil {
		panic(err)
	}
	return loc
}

// night builds the night ending on the morning of date, from a bedtime offset in minutes after
// 22:00 the evening before and a wake time as minutes after midnight.
func night(date score.Date, bedAfter22, wakeMin int) Night {
	morning := date.Time()
	evening := time.Date(morning.Year(), morning.Month(), morning.Day()-1, 22, 0, 0, 0, ny).Add(time.Duration(bedAfter22) * time.Minute)
	wake := time.Date(morning.Year(), morning.Month(), morning.Day(), 0, 0, 0, 0, ny).Add(time.Duration(wakeMin) * time.Minute)
	return Night{Date: date, BedAt: evening, WakeAt: wake}
}

// routine is n nights before the date, each at 22:30 to 06:30.
func routine(date score.Date, n int) []Night {
	var out []Night
	for i := 1; i <= n; i++ {
		out = append(out, night(date.AddDays(-i), 30, 6*60+30))
	}
	return out
}

func TestEvaluateWindowBoundaries(t *testing.T) {
	date := score.Date("2026-11-10")
	tests := []struct {
		name        string
		bed, wake   int
		window      int
		wantHits    int
		wantBedOff  int
		wantWakeOff int
	}{
		{"on the routine", 30, 6*60 + 30, 45, 2, 0, 0},
		{"edge of the window counts", 30 + 45, 6*60 + 30 - 45, 45, 2, 45, -45},
		{"a minute past the window on bed only", 30 + 46, 6*60 + 30, 45, 1, 46, 0},
		{"both late", 30 + 90, 6*60 + 30 + 90, 45, 0, 90, 90},
		{"wake only is outside", 30, 6*60 + 30 + 60, 45, 1, 0, 60},
		{"a wider window forgives", 30 + 60, 6*60 + 30 + 60, 60, 2, 60, 60},
	}
	for _, tt := range tests {
		nights := append(routine(date, 7), night(date, tt.bed, tt.wake))
		got := Evaluate(nights, date, tt.window, ny)
		if !got.Measurable || got.Hits != tt.wantHits || got.BedOffset != tt.wantBedOff || got.WakeOffset != tt.wantWakeOff {
			t.Errorf("%s: %+v, want hits %d offsets %d/%d", tt.name, got, tt.wantHits, tt.wantBedOff, tt.wantWakeOff)
		}
	}
}

func TestEvaluateUsualTimeIsTheMedianNotTheMean(t *testing.T) {
	date := score.Date("2026-11-10")
	nights := routine(date, 5)
	nights = append(nights, night(date.AddDays(-6), 4*60, 6*60+30), night(date.AddDays(-7), 4*60, 6*60+30))
	nights = append(nights, night(date, 30, 6*60+30))
	got := Evaluate(nights, date, 45, ny)
	if got.BedMedian != 22*60+30 || got.BedOffset != 0 || got.Hits != 2 {
		t.Fatalf("two very late nights moved the usual bedtime: %+v", got)
	}
}

func TestEvaluateReadsTimesRoundTheClock(t *testing.T) {
	date := score.Date("2026-11-10")
	var nights []Night
	for i, bed := range []int{110, 130, 120, 140, 100} {
		nights = append(nights, night(date.AddDays(-(i+1)), bed, 8*60))
	}
	// Usual bedtime is 23:50 to 00:20; 00:10 is on it and 01:30 is not.
	near := Evaluate(append(nights, night(date, 130, 8*60)), date, 45, ny)
	if !near.Measurable || near.BedMedian != 0 || !near.BedOK {
		t.Fatalf("a bedtime that straddles midnight: %+v", near)
	}
	far := Evaluate(append(nights, night(date, 210, 8*60)), date, 45, ny)
	if far.BedOK || far.BedOffset != 90 {
		t.Fatalf("90 minutes after a midnight routine: %+v", far)
	}
	early := Evaluate(append(nights, night(date, 10, 8*60)), date, 45, ny)
	if early.BedOffset != -110 || early.BedOK {
		t.Fatalf("an early bedtime reads as negative minutes: %+v", early)
	}
}

func TestEvaluateNeedsTheNightAndAnEarlierRoutine(t *testing.T) {
	date := score.Date("2026-11-10")
	tonight := night(date, 30, 6*60+30)
	cases := map[string][]Night{
		"no nights":         nil,
		"no night today":    routine(date, 7),
		"two earlier":       append(routine(date, 2), tonight),
		"older than a week": append([]Night{night(date.AddDays(-8), 30, 6*60+30), night(date.AddDays(-9), 30, 6*60+30), night(date.AddDays(-10), 30, 6*60+30)}, tonight),
	}
	for name, nights := range cases {
		if got := Evaluate(nights, date, 45, ny); got.Measurable || got.Hits != 0 {
			t.Errorf("%s: %+v, want not measurable", name, got)
		}
	}
	if got := Evaluate(append(routine(date, 3), tonight), date, 45, ny); !got.Measurable || got.BaselineNights != 3 {
		t.Errorf("three earlier nights are enough: %+v", got)
	}
}

func TestEvaluateIgnoresTheNightsAfterTheDate(t *testing.T) {
	date := score.Date("2026-11-10")
	nights := append(routine(date, 3), night(date, 30, 6*60+30), night(date.AddDays(1), 5*60, 12*60))
	if got := Evaluate(nights, date, 45, ny); got.BaselineNights != 3 || got.Hits != 2 {
		t.Fatalf("a later night leaked into the routine: %+v", got)
	}
}
