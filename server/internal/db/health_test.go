package db_test

import (
	"fmt"
	"github.com/nc1107/new-me/server/internal/score"
	"math"
	"reflect"
	"testing"
	"time"

	"github.com/nc1107/new-me/server/internal/db"
	"github.com/nc1107/new-me/server/internal/dbtest"
)

func TestHealthUpsertNeverLetsAStaleReadingWin(t *testing.T) {
	database := dbtest.Fresh(t)
	u := join(t, database, "Nick", "green", true)
	noon := time.Date(2026, 10, 27, 12, 0, 0, 0, time.UTC)
	put := func(value float64, at time.Time) bool {
		applied, err := db.UpsertHealthDaily(ctx, database.Pool, u.ID, day, db.MetricSteps, value, "healthkit", at)
		if err != nil {
			t.Fatal(err)
		}
		return applied
	}
	steps := func() float64 {
		in, err := db.LoadDayInputs(ctx, database.Pool, u.ID, day)
		if err != nil {
			t.Fatal(err)
		}
		return in.Metric(db.MetricSteps)
	}

	if !put(5000, noon) || steps() != 5000 {
		t.Fatal("first reading must apply")
	}
	if !put(6000, noon.Add(time.Hour)) || steps() != 6000 {
		t.Fatal("a newer reading must apply")
	}
	if put(4000, noon) || steps() != 6000 {
		t.Fatal("a stale retry must not lower the count")
	}
	if !put(6000, noon.Add(time.Hour)) {
		t.Fatal("the same instant is an idempotent retry and may apply")
	}
}

func TestHealthRejectsOutOfRangeValues(t *testing.T) {
	database := dbtest.Fresh(t)
	u := join(t, database, "Nick", "green", true)
	for i, v := range []float64{-1, 200001, math.NaN(), math.Inf(1)} {
		_, err := db.UpsertHealthDaily(ctx, database.Pool, u.ID, day, db.MetricSteps, v, "healthkit", time.Now())
		if err == nil {
			t.Fatalf("case %d (%v) must be rejected", i, v)
		}
	}
	if _, err := db.UpsertHealthDaily(ctx, database.Pool, u.ID, day, "heart_rate", 60, "healthkit", time.Now()); err == nil {
		t.Fatal("an unknown metric must be rejected")
	}
	if _, err := db.UpsertHealthDaily(ctx, database.Pool, u.ID, day, db.MetricActiveEnergy, 20001, "healthkit", time.Now()); err == nil {
		t.Fatal("active energy above its cap must be rejected")
	}
}

func TestLoadDayInputsAggregatesTheDay(t *testing.T) {
	database := dbtest.Fresh(t)
	u := join(t, database, "Nick", "green", true)
	n := 0
	act := func(typ string, qty int) {
		n++
		if _, _, err := db.InsertActivityLog(ctx, database.Pool, db.NewActivityLog{
			UserID: u.ID, LocalDate: day, Type: typ, Quantity: qty, ClientOpID: fmt.Sprintf(opID, n)}); err != nil {
			t.Fatal(err)
		}
	}
	act(db.ActivityPushups, 20)
	act(db.ActivityPushups, 15)
	act(db.ActivityReadingMinutes, 12)
	act(db.ActivityReadingPages, 5)
	act(db.ActivityYogaMinutes, 30)
	for i, m := range []db.NewMealLog{
		{Name: "A", Kcal: 500, ProteinG: 30.5, CarbsG: 50, FatG: 10, FiberG: 4.5},
		{Name: "B", Kcal: 700, ProteinG: 40.4, CarbsG: 70, FatG: 20, FiberG: 3},
	} {
		m.UserID, m.LocalDate, m.ClientOpID = u.ID, day, fmt.Sprintf(opID, 50+i)
		if _, _, err := db.InsertMealLog(ctx, database.Pool, m); err != nil {
			t.Fatal(err)
		}
	}
	at := time.Now()
	if _, err := db.UpsertHealthDaily(ctx, database.Pool, u.ID, day, db.MetricSteps, 4321, "healthkit", at); err != nil {
		t.Fatal(err)
	}
	if _, err := db.UpsertHealthDaily(ctx, database.Pool, u.ID, day, db.MetricActiveEnergy, 540, "healthkit", at); err != nil {
		t.Fatal(err)
	}

	in, err := db.LoadDayInputs(ctx, database.Pool, u.ID, day)
	if err != nil {
		t.Fatal(err)
	}
	want := db.DayInputs{
		Metrics: map[string]float64{db.MetricSteps: 4321, db.MetricActiveEnergy: 540},
		Synced:  map[string]bool{db.MetricSteps: true, db.MetricActiveEnergy: true}, Pushups: 35, ReadingMinutes: 12,
		ReadingPages: 5, YogaMinutes: 30, Meals: 2, Kcal: 1200, ProteinG: 70.9, CarbsG: 120, FatG: 30, FiberG: 7.5}
	if !reflect.DeepEqual(in, want) {
		t.Fatalf("inputs = %+v\nwant     %+v", in, want)
	}

	before, err := db.LoadDayInputs(ctx, database.Pool, u.ID, day.AddDays(-1))
	if err != nil {
		t.Fatal(err)
	}
	if before.Connected(db.MetricSteps) || before.Metric(db.MetricSteps) != 0 || before.Pushups != 0 {
		t.Fatalf("the day before the first reading = %+v; steps are not connected yet", before)
	}
	after, _ := db.LoadDayInputs(ctx, database.Pool, u.ID, day.AddDays(1))
	if !after.Connected(db.MetricSteps) || after.Metric(db.MetricSteps) != 0 {
		t.Fatalf("the day after = %+v; connected but with no reading yet", after)
	}

	if synced, err := db.LastHealthSync(ctx, database.Pool, u.ID); err != nil || synced == nil {
		t.Fatalf("last sync = %v, %v", synced, err)
	}
}

func TestLastHealthSyncIsNilWithoutReadings(t *testing.T) {
	database := dbtest.Fresh(t)
	u := join(t, database, "Nick", "green", true)
	if synced, err := db.LastHealthSync(ctx, database.Pool, u.ID); err != nil || synced != nil {
		t.Fatalf("last sync = %v, %v", synced, err)
	}
}

func TestHealthAcceptsEveryMetricWithinItsBounds(t *testing.T) {
	database := dbtest.Fresh(t)
	u := join(t, database, "Nick", "green", true)
	cases := []struct {
		metric       string
		lo, hi       float64
		below, above float64
	}{
		{"steps", 0, 200000, -1, 200001},
		{"active_energy", 0, 20000, -1, 20001},
		{"basal_energy", 0, 20000, -1, 20001},
		{"exercise_minutes", 0, 1440, -1, 1441},
		{"distance_m", 0, 200000, -1, 200001},
		{"flights", 0, 1000, -1, 1001},
		{"workouts", 0, 50, -1, 51},
		{"workout_minutes", 0, 1440, -1, 1441},
		{"sleep_minutes", 0, 1440, -1, 1441},
		{"mindful_minutes", 0, 1440, -1, 1441},
		{"water_ml", 0, 20000, -1, 20001},
		{"resting_hr", 20, 250, 19, 251},
		{"hrv_ms", 0, 500, -1, 501},
		{"vo2max", 0, 100, -1, 101},
		{"weight_kg", 20, 400, 19, 401},
		{"body_fat_pct", 1, 80, 0, 81},
		{"lean_mass_kg", 10, 300, 9, 301},
	}
	for _, c := range cases {
		for _, ok := range []float64{c.lo, c.hi} {
			if _, err := db.UpsertHealthDaily(ctx, database.Pool, u.ID, day, c.metric, ok, "healthkit", time.Now()); err != nil {
				t.Fatalf("%s %v: %v", c.metric, ok, err)
			}
		}
		for _, bad := range []float64{c.below, c.above, math.NaN()} {
			if _, err := db.UpsertHealthDaily(ctx, database.Pool, u.ID, day, c.metric, bad, "healthkit", time.Now()); err == nil {
				t.Fatalf("%s %v must be rejected", c.metric, bad)
			}
		}
	}
}

func TestLatestHealthAndSeries(t *testing.T) {
	database := dbtest.Fresh(t)
	u := join(t, database, "Nick", "green", true)
	put := func(d score.Date, metric string, v float64) {
		if _, err := db.UpsertHealthDaily(ctx, database.Pool, u.ID, d, metric, v, "healthkit", time.Now()); err != nil {
			t.Fatal(err)
		}
	}
	put(day.AddDays(-3), "weight_kg", 80)
	put(day.AddDays(-1), "weight_kg", 79.5)
	put(day.AddDays(1), "weight_kg", 70)
	put(day, "steps", 100)

	latest, err := db.LatestHealth(ctx, database.Pool, u.ID, day, []string{"weight_kg", "vo2max"})
	if err != nil {
		t.Fatal(err)
	}
	if got := latest["weight_kg"]; got.Value != 79.5 || got.Date != day.AddDays(-1) || len(latest) != 1 {
		t.Fatalf("latest = %+v", latest)
	}
	series, err := db.HealthSeries(ctx, database.Pool, u.ID, "weight_kg", day.AddDays(-2), day)
	if err != nil || len(series) != 1 || series[0].Value != 79.5 {
		t.Fatalf("series = %+v, %v", series, err)
	}
}
