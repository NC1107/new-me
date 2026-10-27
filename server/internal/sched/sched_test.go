package sched_test

import (
	"context"
	"fmt"
	"os"
	"testing"
	"time"

	"github.com/jackc/pgx/v5"

	"github.com/nc1107/new-me/server/internal/db"
	"github.com/nc1107/new-me/server/internal/dbtest"
	"github.com/nc1107/new-me/server/internal/sched"
	"github.com/nc1107/new-me/server/internal/score"
)

func TestMain(m *testing.M) {
	dbtest.Require()
	os.Exit(m.Run())
}

var ctx = context.Background()

func zone(name string) *time.Location {
	loc, err := time.LoadLocation(name)
	if err != nil {
		panic(err)
	}
	return loc
}

var newYork = zone("America/New_York")

func join(t *testing.T, database *db.DB, name, color, tz string, admin bool, joined string) db.User {
	t.Helper()
	var u db.User
	err := database.WithTx(ctx, func(tx pgx.Tx) error {
		var err error
		u, err = db.CreateUser(ctx, tx, db.NewUser{Name: name, Color: color, Timezone: tz, IsAdmin: admin,
			JoinedOn: score.MustDate(joined)}, 5)
		return err
	})
	if err != nil {
		t.Fatalf("join %s: %v", name, err)
	}
	return u
}

func rows(t *testing.T, database *db.DB, u db.User) map[score.Date]db.DayScoreRow {
	t.Helper()
	all, err := db.ListDayScores(ctx, database.Pool, u.ID, "2000-01-01", "2100-01-01")
	if err != nil {
		t.Fatal(err)
	}
	out := map[score.Date]db.DayScoreRow{}
	for _, r := range all {
		out[r.LocalDate] = r
	}
	return out
}

func TestFinalizeDueCatchesUpEveryMissedDayPerTimezone(t *testing.T) {
	database := dbtest.Fresh(t)
	nick := join(t, database, "Nick", "green", "America/New_York", true, "2026-10-28")
	kai := join(t, database, "Kai", "sky", "Asia/Tokyo", false, "2026-10-30")

	// A day with entries, and the server was down for the whole week after.
	if _, _, err := db.InsertActivityLog(ctx, database.Pool, db.NewActivityLog{
		UserID: nick.ID, LocalDate: "2026-10-30", Type: db.ActivityPushups, Quantity: 30,
		ClientOpID: fmt.Sprintf("00000000-0000-4000-8000-%012d", 1)}); err != nil {
		t.Fatal(err)
	}

	// 09:00 in New York on Nov 3 is 23:00 in Tokyo: Tokyo's Nov 2 closed 13 hours ago, New
	// York's Nov 2 is still open for another hour.
	s := &sched.Scheduler{DB: database, Now: func() time.Time { return time.Date(2026, 11, 3, 9, 0, 0, 0, newYork) }}
	if err := s.FinalizeDue(ctx); err != nil {
		t.Fatal(err)
	}

	nickRows := rows(t, database, nick)
	for _, d := range []score.Date{"2026-10-28", "2026-10-29", "2026-10-30", "2026-10-31", "2026-11-01"} {
		r, ok := nickRows[d]
		if !ok || r.FinalizedAt == nil {
			t.Fatalf("Nick %s = %+v (present %v), want a finalized row", d, r, ok)
		}
	}
	if r := nickRows["2026-10-30"]; r.BasePoints != 100 || r.BonusPoints != 20 || r.MaxBase != 300 || r.Percent != 33 {
		t.Fatalf("the logged day was scored as %+v, want base 100, bonus 20 of 300", r)
	}
	if r := nickRows["2026-10-29"]; r.BasePoints != 0 || r.Counted {
		t.Fatalf("an empty day = %+v, want a zero, uncounted row", r)
	}
	if r, ok := nickRows["2026-11-02"]; ok && r.FinalizedAt != nil {
		t.Fatal("New York's Nov 2 is still inside its grace window")
	}

	kaiRows := rows(t, database, kai)
	if r, ok := kaiRows["2026-11-02"]; !ok || r.FinalizedAt == nil {
		t.Fatalf("Tokyo's Nov 2 should be final: %+v", kaiRows)
	}
	if _, ok := kaiRows["2026-10-29"]; ok {
		t.Fatal("days before a user joined are never scored")
	}
	if r, ok := kaiRows["2026-11-03"]; ok && r.FinalizedAt != nil {
		t.Fatal("the current day must not be finalized")
	}
}

func TestFinalizeDueClosesYesterdayAtTheGraceHourAndIsIdempotent(t *testing.T) {
	database := dbtest.Fresh(t)
	nick := join(t, database, "Nick", "green", "America/New_York", true, "2026-11-01")
	now := time.Date(2026, 11, 3, 9, 59, 0, 0, newYork)
	s := &sched.Scheduler{DB: database, Now: func() time.Time { return now }}

	if err := s.FinalizeDue(ctx); err != nil {
		t.Fatal(err)
	}
	if r := rows(t, database, nick)["2026-11-02"]; r.FinalizedAt != nil {
		t.Fatal("09:59 is still inside the window for yesterday")
	}

	now = time.Date(2026, 11, 3, 10, 0, 0, 0, newYork)
	if err := s.FinalizeDue(ctx); err != nil {
		t.Fatal(err)
	}
	first := rows(t, database, nick)
	if r := first["2026-11-02"]; r.FinalizedAt == nil {
		t.Fatal("10:00 closes yesterday")
	}
	// 2026-11-01 is the 25-hour day when daylight saving ends; it finalized like any other.
	if r := first["2026-11-01"]; r.FinalizedAt == nil {
		t.Fatal("the DST day must finalize")
	}

	if err := s.FinalizeDue(ctx); err != nil {
		t.Fatal(err)
	}
	second := rows(t, database, nick)
	for d, r := range first {
		if !r.ComputedAt.Equal(second[d].ComputedAt) {
			t.Fatalf("%s was rescored on a second pass", d)
		}
	}
}

func TestFinalizeDueSkipsAUserWithAnUnknownZoneAndStillServesTheRest(t *testing.T) {
	database := dbtest.Fresh(t)
	broken := join(t, database, "Broken", "rose", "America/New_York", true, "2026-10-30")
	good := join(t, database, "Good", "green", "America/New_York", false, "2026-10-30")
	if _, err := database.Pool.Exec(ctx, `UPDATE users SET timezone = 'Mars/Olympus' WHERE id = $1`, broken.ID); err != nil {
		t.Fatal(err)
	}

	s := &sched.Scheduler{DB: database, Now: func() time.Time { return time.Date(2026, 11, 3, 12, 0, 0, 0, newYork) }}
	if err := s.FinalizeDue(ctx); err == nil {
		t.Fatal("the broken user's failure should be reported")
	}
	if len(rows(t, database, good)) != 4 {
		t.Fatalf("the healthy user must still be finalized: %v", rows(t, database, good))
	}
}

func TestRunStopsWhenTheContextEnds(t *testing.T) {
	database := dbtest.Fresh(t)
	runCtx, cancel := context.WithCancel(ctx)
	done := make(chan struct{})
	go func() {
		sched.New(database).Run(runCtx)
		close(done)
	}()
	cancel()
	select {
	case <-done:
	case <-time.After(5 * time.Second):
		t.Fatal("Run did not stop after its context ended")
	}
}

func TestFinalizeDuePutsAStagedZoneIntoForceForAnInactiveUser(t *testing.T) {
	database := dbtest.Fresh(t)
	nick := join(t, database, "Nick", "green", "America/New_York", true, "2026-11-01")
	if err := db.StageTimezone(ctx, database.Pool, nick.ID, "Asia/Tokyo", "2026-11-03"); err != nil {
		t.Fatal(err)
	}
	now := time.Date(2026, 11, 2, 23, 0, 0, 0, newYork)
	s := &sched.Scheduler{DB: database, Now: func() time.Time { return now }}

	if err := s.FinalizeDue(ctx); err != nil {
		t.Fatal(err)
	}
	if got, _ := db.GetUser(ctx, database.Pool, nick.ID); got.Timezone != "America/New_York" {
		t.Fatalf("zone = %s, the old zone has not reached the staged date", got.Timezone)
	}

	now = time.Date(2026, 11, 3, 1, 0, 0, 0, newYork)
	if err := s.FinalizeDue(ctx); err != nil {
		t.Fatal(err)
	}
	if got, _ := db.GetUser(ctx, database.Pool, nick.ID); got.Timezone != "Asia/Tokyo" || got.PendingTimezone != nil {
		t.Fatalf("zone = %+v, want Tokyo in force", got)
	}
}
