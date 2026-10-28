package lookback

import (
	"testing"

	"github.com/nc1107/new-me/server/internal/db"
	"github.com/nc1107/new-me/server/internal/progress"
	"github.com/nc1107/new-me/server/internal/training"
)

func lift(key, date string, reps, seconds int, load float64) db.LiftSet {
	return db.LiftSet{Key: key, Name: key, Loaded: load > 0,
		Set: training.Set{Date: date, Reps: reps, Seconds: seconds, LoadKg: load}}
}

func TestLiftsCompareTheMonthWithTheFirstMonth(t *testing.T) {
	sets := []db.LiftSet{
		lift("pull_up", "2026-09-03", 3, 0, 0),
		lift("pull_up", "2026-09-20", 4, 0, 0),
		lift("pull_up", "2026-10-02", 6, 0, 0),
		lift("pull_up", "2026-11-05", 8, 0, 0),
		lift("pull_up", "2026-11-06", 7, 0, 0),
		lift("db_row", "2026-10-10", 10, 0, 20),
		lift("db_row", "2026-11-10", 8, 0, 24),
		lift("plank", "2026-11-12", 0, 60, 0),
	}
	got := Lifts(sets, "2026-11-01", "2026-11-30")
	if len(got) != 3 {
		t.Fatalf("lifts = %+v", got)
	}
	pull := got[0]
	if pull.Key != "pull_up" || pull.Value != 8 || pull.Measure != LiftReps || *pull.First != 4 ||
		*pull.FirstMonth != "2026-09" || pull.Best.Date != "2026-11-05" {
		t.Fatalf("pull-ups = %+v", pull)
	}
	row := got[1]
	if row.Measure != LiftE1RM || row.Value != 30.4 || *row.First != 26.7 || row.Best.LoadKg != 24 {
		t.Fatalf("db row = %+v", row)
	}
	plank := got[2]
	if plank.Measure != LiftSeconds || plank.Value != 60 || plank.First != nil || plank.FirstMonth != nil {
		t.Fatalf("a first-month exercise has no comparison: %+v", plank)
	}
}

func TestLiftsCapAndSkipQuietExercises(t *testing.T) {
	var sets []db.LiftSet
	for _, k := range []string{"a", "b", "c", "d", "e", "f"} {
		sets = append(sets, lift(k, "2026-11-02", 5, 0, 0))
	}
	sets = append(sets, lift("old", "2026-10-02", 5, 0, 0))
	got := Lifts(sets, "2026-11-01", "2026-11-30")
	if len(got) != MaxLifts {
		t.Fatalf("lifts = %d", len(got))
	}
	for _, l := range got {
		if l.Key == "old" {
			t.Fatal("an exercise not logged this month is not a lift of the month")
		}
	}
}

func TestBodyWordsKilogramsInPoundsForImperial(t *testing.T) {
	m := Month{Label: "October 2026", People: []PersonMonth{{UserID: 1, Improvements: []progress.Improvement{
		{Title: "Lean mass", Unit: "kg", Value: 61, Previous: 60, Summary: "Lean mass: 61.0 kg, up from 60.0"}}}}}
	if got := Body(m, 1, true); got != "Lean mass: 134.5 lb, up from 132.3." {
		t.Fatalf("imperial body = %q", got)
	}
	if got := Body(m, 1, false); got != "Lean mass: 61.0 kg, up from 60.0." {
		t.Fatalf("metric body = %q", got)
	}
}
