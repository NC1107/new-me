package insights

import (
	"reflect"
	"testing"

	"github.com/nc1107/new-me/server/internal/score"
)

func TestWorkoutsWeekIsTheISOWeekOfToday(t *testing.T) {
	// 2026-11-02 is a Monday, so the week holds only today.
	ws := []Workout{
		{Type: "running", Date: "2026-11-02", DurationMin: 30.4},
		{Type: "running", Date: "2026-11-01", DurationMin: 45},
		{Type: "yoga", Date: "2026-10-26", DurationMin: 20},
	}
	got := ComputeWorkouts(ws, "2026-11-02")
	if got.Week != (Summary{Count: 1, Minutes: 30}) {
		t.Fatalf("week on Monday = %+v", got.Week)
	}
	// On Friday the week runs Monday to Friday.
	got = ComputeWorkouts(ws, "2026-11-06")
	if got.Week != (Summary{Count: 1, Minutes: 30}) {
		t.Fatalf("week on Friday = %+v", got.Week)
	}
	got = ComputeWorkouts(ws, "2026-11-01")
	if got.Week != (Summary{Count: 2, Minutes: 65}) {
		t.Fatalf("week on Sunday = %+v", got.Week)
	}
}

func TestWorkoutsLast30ByTypeIsSortedByMinutes(t *testing.T) {
	today := score.Date("2026-11-02")
	ws := []Workout{
		{Type: "running", Date: "2026-10-30", DurationMin: 30},
		{Type: "running", Date: "2026-10-28", DurationMin: 40},
		{Type: "yoga", Date: "2026-10-29", DurationMin: 70},
		{Type: "walking", Date: "2026-10-04", DurationMin: 20},
		{Type: "cycling", Date: "2026-10-03", DurationMin: 90},
		{Type: "hiit", Date: "2026-10-31", DurationMin: 20},
		{Type: "dance", Date: "2026-10-31", DurationMin: 20},
	}
	got := ComputeWorkouts(ws, today)
	if got.Last30.Count != 6 || got.Last30.Minutes != 200 {
		t.Fatalf("last30 = %+v (the 31st day back must be excluded)", got.Last30)
	}
	want := []TypeSummary{
		{"running", 2, 70}, {"yoga", 1, 70}, {"dance", 1, 20}, {"hiit", 1, 20}, {"walking", 1, 20},
	}
	if !reflect.DeepEqual(got.Last30.ByType, want) {
		t.Fatalf("byType = %+v, want %+v", got.Last30.ByType, want)
	}
}

func TestWorkoutsEmptyHasNonNilList(t *testing.T) {
	got := ComputeWorkouts(nil, "2026-11-02")
	if got.Last30.ByType == nil || len(got.Last30.ByType) != 0 || got.Week.Count != 0 {
		t.Fatalf("empty = %+v", got)
	}
}

func TestWorkoutsIgnoreFutureDates(t *testing.T) {
	got := ComputeWorkouts([]Workout{{Type: "yoga", Date: "2026-11-03", DurationMin: 30}}, "2026-11-02")
	if got.Last30.Count != 0 || got.Week.Count != 0 {
		t.Fatalf("got %+v", got)
	}
}
