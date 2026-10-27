package db_test

import (
	"testing"
	"time"

	"github.com/nc1107/new-me/server/internal/db"
	"github.com/nc1107/new-me/server/internal/dbtest"
)

func TestWorkoutTableEnforcesItsOwnBounds(t *testing.T) {
	database := dbtest.Fresh(t)
	u := join(t, database, "Nick", "green", true)
	start := time.Date(2026, 10, 27, 12, 0, 0, 0, time.UTC)
	good := db.Workout{
		HealthID: "w1", Type: "running", LocalDate: "2026-10-27", StartedAt: start, EndedAt: start.Add(30 * time.Minute),
		DurationMin: 30, Source: "Apple Watch",
	}
	if err := db.UpsertWorkout(ctx, database.Pool, u.ID, good); err != nil {
		t.Fatal(err)
	}
	hr := 10.0
	badRows := map[string]func(w *db.Workout){
		"type":     func(w *db.Workout) { w.Type = "skiing" },
		"duration": func(w *db.Workout) { w.DurationMin = 0 },
		"heart":    func(w *db.Workout) { w.AvgHR = &hr },
		"order":    func(w *db.Workout) { w.EndedAt = w.StartedAt },
	}
	for name, mutate := range badRows {
		w := good
		w.HealthID = "bad-" + name
		mutate(&w)
		if err := db.UpsertWorkout(ctx, database.Pool, u.ID, w); err == nil {
			t.Errorf("%s: the table accepted a bad row", name)
		}
	}
	rows, err := db.ListWorkouts(ctx, database.Pool, u.ID, "2026-10-01", "2026-10-31")
	if err != nil || len(rows) != 1 {
		t.Fatalf("rows = %v, err = %v", rows, err)
	}
}

func TestSleepNightTableEnforcesItsOwnBounds(t *testing.T) {
	database := dbtest.Fresh(t)
	u := join(t, database, "Nick", "green", true)
	bed := time.Date(2026, 10, 26, 23, 0, 0, 0, time.UTC)
	good := db.SleepNight{Date: "2026-10-27", BedAt: bed, WakeAt: bed.Add(8 * time.Hour), AsleepMin: 450, Source: "Apple Watch"}
	if err := db.UpsertSleepNight(ctx, database.Pool, u.ID, good); err != nil {
		t.Fatal(err)
	}
	good.AsleepMin = 460
	if err := db.UpsertSleepNight(ctx, database.Pool, u.ID, good); err != nil {
		t.Fatal(err)
	}
	for name, mutate := range map[string]func(n *db.SleepNight){
		"asleep": func(n *db.SleepNight) { n.AsleepMin = 1441 },
		"wake":   func(n *db.SleepNight) { n.WakeAt = n.BedAt },
		"day":    func(n *db.SleepNight) { n.WakeAt = n.BedAt.Add(25 * time.Hour) },
	} {
		n := good
		n.Date = "2026-10-28"
		mutate(&n)
		if err := db.UpsertSleepNight(ctx, database.Pool, u.ID, n); err == nil {
			t.Errorf("%s: the table accepted a bad row", name)
		}
	}
	rows, err := db.ListSleepNights(ctx, database.Pool, u.ID, "2026-10-01", "2026-10-31")
	if err != nil || len(rows) != 1 || rows[0].AsleepMin != 460 {
		t.Fatalf("rows = %v, err = %v", rows, err)
	}
}

func TestBirthYearCheck(t *testing.T) {
	database := dbtest.Fresh(t)
	u := join(t, database, "Nick", "green", true)
	for _, year := range []int{1899, 2101} {
		if _, err := database.Pool.Exec(ctx, `UPDATE users SET birth_year = $2 WHERE id = $1`, u.ID, year); err == nil {
			t.Errorf("birth year %d accepted", year)
		}
	}
}
