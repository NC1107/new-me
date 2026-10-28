package db_test

import (
	"fmt"
	"testing"
	"time"

	"github.com/nc1107/new-me/server/internal/db"
	"github.com/nc1107/new-me/server/internal/dbtest"
	"github.com/nc1107/new-me/server/internal/score"
)

func TestLoadDayInputsReadsTheV17Logs(t *testing.T) {
	database := dbtest.Fresh(t)
	u := join(t, database, "Nick", "green", true)
	for i, l := range []struct {
		typ string
		qty int
	}{
		{db.ActivityProduce, 2}, {db.ActivityProduce, 3}, {db.ActivityBreathing, 5}, {db.ActivityBreathing, 2},
	} {
		if _, _, err := db.InsertActivityLog(ctx, database.Pool, db.NewActivityLog{
			UserID: u.ID, LocalDate: day, Type: l.typ, Quantity: l.qty, ClientOpID: fmt.Sprintf(opID, 100+i)}); err != nil {
			t.Fatal(err)
		}
	}
	in, err := db.LoadDayInputs(ctx, database.Pool, u.ID, day)
	if err != nil {
		t.Fatal(err)
	}
	if in.ProduceServings != 5 || in.BreathingLoggedMin != 7 {
		t.Fatalf("servings %d, breathing %d; want 5 and 7", in.ProduceServings, in.BreathingLoggedMin)
	}
	if _, _, err := db.InsertActivityLog(ctx, database.Pool, db.NewActivityLog{
		UserID: u.ID, LocalDate: day, Type: db.ActivityProduce, Quantity: 31, ClientOpID: fmt.Sprintf(opID, 200)}); err == nil {
		t.Fatal("31 servings in one entry must be rejected by the table")
	}
}

func TestLoadDayInputsCarriesTheSevenNightsBeforeAndTheNight(t *testing.T) {
	database := dbtest.Fresh(t)
	u := join(t, database, "Nick", "green", true)
	night := func(d int, month time.Month) db.SleepNight {
		morning := time.Date(2026, month, d, 6, 30, 0, 0, time.UTC)
		return db.SleepNight{
			Date: score.Date(morning.Format("2006-01-02")), BedAt: morning.Add(-8 * time.Hour), WakeAt: morning, AsleepMin: 450, Source: "test",
		}
	}
	for _, n := range []db.SleepNight{
		night(18, time.October), night(19, time.October), night(20, time.October), night(26, time.October), night(27, time.October), night(28, time.October),
	} {
		if err := db.UpsertSleepNight(ctx, database.Pool, u.ID, n); err != nil {
			t.Fatal(err)
		}
	}
	in, err := db.LoadDayInputs(ctx, database.Pool, u.ID, "2026-10-27")
	if err != nil {
		t.Fatal(err)
	}
	var dates []string
	for _, n := range in.SleepNights {
		dates = append(dates, string(n.Date))
	}
	if fmt.Sprint(dates) != "[2026-10-20 2026-10-26 2026-10-27]" {
		t.Fatalf("nights = %v; want the 7 mornings before the date and the date, none after it", dates)
	}
	if in.Loc == nil || in.Loc.String() != u.Timezone || in.Date != "2026-10-27" {
		t.Fatalf("zone %v date %q", in.Loc, in.Date)
	}
}
