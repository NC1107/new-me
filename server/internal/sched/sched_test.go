package sched_test

import (
	"context"
	"fmt"
	"os"
	"testing"
	"time"

	"github.com/jackc/pgx/v5"

	"github.com/nc1107/new-me/server/internal/abs/abstest"
	"github.com/nc1107/new-me/server/internal/db"
	"github.com/nc1107/new-me/server/internal/dbtest"
	"github.com/nc1107/new-me/server/internal/engine"
	"github.com/nc1107/new-me/server/internal/listening"
	"github.com/nc1107/new-me/server/internal/lookback"
	"github.com/nc1107/new-me/server/internal/milestone"
	"github.com/nc1107/new-me/server/internal/sched"
	"github.com/nc1107/new-me/server/internal/score"
	"github.com/nc1107/new-me/server/internal/together"
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

func TestPollListeningReadsEveryLinkedAccount(t *testing.T) {
	database := dbtest.Fresh(t)
	now := time.Date(2026, 11, 2, 12, 0, 0, 0, newYork)
	fake := abstest.New(t, func() time.Time { return now })
	fake.AddUser("nick", "pw")
	fake.AddUser("nadia", "pw2")
	fake.SetListening("nick", "2026-11-02", 15*60)
	fake.SetListening("nadia", "2026-11-02", 40*60)
	nick := join(t, database, "Nick", "green", "America/New_York", true, "2026-11-02")
	nadia := join(t, database, "Nadia", "violet", "America/New_York", false, "2026-11-02")
	join(t, database, "Unlinked", "sky", "America/New_York", false, "2026-11-02")

	syn := listening.New(database, fake.URL)
	syn.Now = func() time.Time { return now }
	for user, creds := range map[db.User][2]string{nick: {"nick", "pw"}, nadia: {"nadia", "pw2"}} {
		sess, err := syn.ABS.Login(ctx, creds[0], creds[1])
		if err != nil {
			t.Fatal(err)
		}
		// Link would sync at once; store the account directly so the poll is what does the work.
		if _, err := db.LinkABSAccount(ctx, database.Pool, db.ABSAccount{UserID: user.ID, ABSUserID: sess.UserID,
			Username: sess.Username, AccessToken: sess.AccessToken, RefreshToken: sess.RefreshToken,
			AccessExpiresAt: sess.AccessExpires}); err != nil {
			t.Fatal(err)
		}
	}

	s := sched.New(database)
	s.Now = func() time.Time { return now }
	if err := s.PollListening(ctx); err != nil {
		t.Fatalf("poll without a syncer must be a no-op: %v", err)
	}
	s.Listening = syn
	if err := s.PollListening(ctx); err != nil {
		t.Fatal(err)
	}
	for user, want := range map[db.User]int{nick: 15, nadia: 40} {
		got, err := db.ListeningMinutes(ctx, database.Pool, user.ID, "2026-11-02")
		if err != nil || got != want {
			t.Fatalf("%s listening = %d, %v, want %d", user.Name, got, err, want)
		}
		if row := rows(t, database, user)["2026-11-02"]; row.BasePoints == 0 {
			t.Fatalf("%s's open day was not rescored: %+v", user.Name, row)
		}
	}
	if _, _, stats := fake.Counts(); stats != 2 {
		t.Fatalf("stats calls = %d, want one per linked account", stats)
	}
}

func TestListeningIsPolledEveryFiveMinutes(t *testing.T) {
	if sched.ListeningInterval != 5*time.Minute {
		t.Fatalf("ListeningInterval = %v", sched.ListeningInterval)
	}
}

func TestFinalizeDueSettlesStreakOutcomesAndRepairsYesterday(t *testing.T) {
	database := dbtest.Fresh(t)
	nick := join(t, database, "Nick", "green", "America/New_York", true, "2026-11-02")
	op := 0
	// A full day of entries: push-ups, reading minutes and two meals worth 100 g of protein, which
	// is every quest that is in the day before Health reports anything.
	fullDay := func(date string) {
		d := score.MustDate(date)
		for _, typ := range []string{db.ActivityPushups, db.ActivityReadingMinutes} {
			op++
			quantity := 30
			if typ == db.ActivityReadingMinutes {
				quantity = 20
			}
			if _, _, err := db.InsertActivityLog(ctx, database.Pool, db.NewActivityLog{UserID: nick.ID, LocalDate: d, Type: typ,
				Quantity: quantity, ClientOpID: fmt.Sprintf("00000000-0000-4000-8000-%012d", op)}); err != nil {
				t.Fatal(err)
			}
		}
		for range 2 {
			op++
			if _, _, err := db.InsertMealLog(ctx, database.Pool, db.NewMealLog{UserID: nick.ID, LocalDate: d, Name: "Meal", Kcal: 500,
				ProteinG: 50, ClientOpID: fmt.Sprintf("00000000-0000-4000-8000-%012d", op)}); err != nil {
				t.Fatal(err)
			}
		}
	}
	// Mon counted, Tue and Wed missed (both freezes), Thu counted, Fri missed (breaks), and today
	// already at 100% when Friday finalizes at 10:00 on Saturday.
	for _, d := range []string{"2026-11-02", "2026-11-05", "2026-11-07"} {
		fullDay(d)
	}
	// The person's own entries scored today at 09:00, before Friday had finalized.
	if err := database.WithTx(ctx, func(tx pgx.Tx) error {
		_, err := engine.RecomputeDayAt(ctx, tx, nick.ID, "2026-11-07", newYork, time.Date(2026, 11, 7, 9, 0, 0, 0, newYork))
		return err
	}); err != nil {
		t.Fatal(err)
	}
	now := time.Date(2026, 11, 7, 11, 0, 0, 0, newYork)
	s := &sched.Scheduler{DB: database, Now: func() time.Time { return now }}
	if err := s.FinalizeDue(ctx); err != nil {
		t.Fatal(err)
	}
	got := rows(t, database, nick)
	wantReason := map[string]string{"2026-11-03": "freeze", "2026-11-04": "freeze", "2026-11-06": "repair", "2026-11-02": "", "2026-11-05": ""}
	for date, want := range wantReason {
		r := got[score.MustDate(date)]
		if r.FinalizedAt == nil || !r.Settled || r.FrozenReason != want {
			t.Errorf("%s: finalized=%v settled=%v reason=%q, want %q", date, r.FinalizedAt != nil, r.Settled, r.FrozenReason, want)
		}
	}
	if r := got["2026-11-07"]; r.FinalizedAt != nil || r.Settled {
		t.Errorf("today must stay open: %+v", r)
	}
}

func TestPassRecordsMilestonesAndSendsTheLookbackOnTheFirst(t *testing.T) {
	database := dbtest.Fresh(t)
	nick := join(t, database, "Nick", "green", "America/New_York", true, "2026-10-20")
	for i := range 8 {
		d := score.ScoreDay([]score.QuestResult{{Key: "x", Points: 100, Actual: 100, Target: 100}})
		if _, err := db.UpsertDayScore(ctx, database.Pool, db.DayScoreRow{UserID: nick.ID, LocalDate: score.MustDate("2026-10-20").AddDays(i),
			BasePoints: d.BasePoints, MaxBase: d.MaxBase, Percent: d.Percent, Counted: d.Counted, Detail: []byte(`[]`)}, true); err != nil {
			t.Fatal(err)
		}
	}
	now := time.Date(2026, 10, 28, 12, 0, 0, 0, newYork)
	clock := func() time.Time { return now }
	tg := &together.Service{DB: database, Now: clock}
	s := &sched.Scheduler{DB: database, Now: clock, Together: tg,
		Milestones: &milestone.Service{DB: database, Together: tg, Now: clock},
		Lookback:   &lookback.Service{DB: database, Together: tg, Now: clock}}
	if err := s.RunOnce(ctx); err != nil {
		t.Fatal(err)
	}
	have, err := db.MilestoneKinds(ctx, database.Pool, &nick.ID)
	if err != nil || !have["streak:7"] {
		t.Fatalf("milestones = %v %v", have, err)
	}
	// Running the pass again records nothing new.
	if err := s.RunOnce(ctx); err != nil {
		t.Fatal(err)
	}
	list, _ := db.ListMilestones(ctx, database.Pool, nick.ID)
	if len(list) != 1 {
		t.Fatalf("recorded twice: %v", list)
	}
}
