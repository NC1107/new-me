package engine_test

import (
	"testing"
	"time"

	"github.com/nc1107/new-me/server/internal/db"
	"github.com/nc1107/new-me/server/internal/dbtest"
	"github.com/nc1107/new-me/server/internal/engine"
	"github.com/nc1107/new-me/server/internal/score"
)

// storeDays writes finalized day scores from `start`: x counted, . missed, and 'p' a day at 100%
// that has not been finalized.
func storeDays(t *testing.T, database *db.DB, u db.User, start score.Date, spec string) {
	t.Helper()
	for i, c := range spec {
		actual := 0
		if c == 'x' || c == 'p' {
			actual = 100
		}
		d := score.ScoreDay([]score.QuestResult{{Key: "x", Points: 100, Actual: actual, Target: 100}})
		if _, err := db.UpsertDayScore(ctx, database.Pool, db.DayScoreRow{UserID: u.ID, LocalDate: start.AddDays(i),
			BasePoints: d.BasePoints, MaxBase: d.MaxBase, Percent: d.Percent, Counted: d.Counted, Detail: []byte(`[]`)},
			c != 'p'); err != nil {
			t.Fatal(err)
		}
	}
}

func settle(t *testing.T, database *db.DB, u db.User, now time.Time) {
	t.Helper()
	if err := engine.SettleStreaks(ctx, database.Pool, u, now, ny); err != nil {
		t.Fatalf("settle: %v", err)
	}
}

func row(t *testing.T, database *db.DB, u db.User, date score.Date) db.DayScoreRow {
	t.Helper()
	r, err := db.GetDayScore(ctx, database.Pool, u.ID, date)
	if err != nil {
		t.Fatalf("row %s: %v", date, err)
	}
	return r
}

func TestSettleRecordsFreezesAndBreaks(t *testing.T) {
	database := dbtest.Fresh(t)
	start := score.MustDate("2026-10-19")
	u := join(t, database, "Nick", "green", true, start)
	// x . . . x : the first two misses use the two freezes, the third breaks.
	storeDays(t, database, u, start, "x...x")
	now := time.Date(2026, 10, 24, 12, 0, 0, 0, ny)
	settle(t, database, u, now)

	wantReason := map[int]string{1: "freeze", 2: "freeze", 3: ""}
	for i, want := range wantReason {
		r := row(t, database, u, start.AddDays(i))
		if !r.Settled || r.FrozenReason != want {
			t.Errorf("day %d: settled=%v reason=%q, want reason %q", i, r.Settled, r.FrozenReason, want)
		}
	}
	got, err := engine.StreakFor(ctx, database.Pool, u, now, ny)
	if err != nil {
		t.Fatal(err)
	}
	if got.Count != 1 || got.Freezes.Held != 0 {
		t.Fatalf("streak = %d freezes %+v, want 1 and none left", got.Count, got.Freezes)
	}
	// Settling again changes nothing.
	settle(t, database, u, now)
	if r := row(t, database, u, start.AddDays(3)); r.FrozenReason != "" || !r.Settled {
		t.Fatalf("a settled break must stay: %+v", r)
	}
}

func TestSettledHistoryIsNotRewrittenByLaterEarnings(t *testing.T) {
	database := dbtest.Fresh(t)
	start := score.MustDate("2026-10-12")
	u := join(t, database, "Nick", "green", true, start)
	// Three misses straight away with no streak spend nothing, then a streak, then a miss.
	storeDays(t, database, u, start, "xx.xxxxxxxxx")
	now := time.Date(2026, 10, 24, 12, 0, 0, 0, ny)
	settle(t, database, u, now)
	if r := row(t, database, u, start.AddDays(2)); r.FrozenReason != "freeze" {
		t.Fatalf("reason = %q", r.FrozenReason)
	}
	got, err := engine.StreakFor(ctx, database.Pool, u, now, ny)
	if err != nil {
		t.Fatal(err)
	}
	if got.Count != 11 || got.Freezes.Held != 2 {
		t.Fatalf("count %d freezes %+v: nine counted days after the freeze earn it back", got.Count, got.Freezes)
	}
}

func TestOldRuleDaysKeepTheirRecordedResult(t *testing.T) {
	database := dbtest.Fresh(t)
	start := score.MustDate("2026-10-19")
	u := join(t, database, "Nick", "green", true, start)
	// Three misses in a row: the old rule forgave one and broke on the second.
	storeDays(t, database, u, start, "xxx..x")
	rulesFrom := start.AddDays(5)
	if _, err := database.Pool.Exec(ctx, `UPDATE users SET streak_rules_from = $2::date WHERE id = $1`, u.ID, rulesFrom); err != nil {
		t.Fatal(err)
	}
	u, err := db.GetUser(ctx, database.Pool, u.ID)
	if err != nil {
		t.Fatal(err)
	}
	now := time.Date(2026, 10, 24, 12, 0, 0, 0, ny)
	got, err := engine.StreakFor(ctx, database.Pool, u, now, ny)
	if err != nil {
		t.Fatal(err)
	}
	if got.Outcome(start.AddDays(3)).Reason != score.ReasonRest || got.Outcome(start.AddDays(4)).Status != score.StatusMissed || got.Count != 1 {
		t.Fatalf("old days must keep the old rule: count %d, %+v %+v", got.Count, got.Outcome(start.AddDays(3)), got.Outcome(start.AddDays(4)))
	}
	if got.Freezes.Held != 2 {
		t.Fatalf("freezes = %+v, want the starting two", got.Freezes)
	}
}

func TestRepairTurnsAMissedDayIntoAFrozenOne(t *testing.T) {
	database := dbtest.Fresh(t)
	start := score.MustDate("2026-10-19")
	u := join(t, database, "Nick", "green", true, start)
	// x . . x . : both freezes are gone when the last day is missed, so it breaks.
	storeDays(t, database, u, start, "x..x.")
	yesterday := start.AddDays(4)
	today := start.AddDays(5)
	noon := time.Date(2026, 10, 24, 12, 0, 0, 0, ny)
	settle(t, database, u, noon)

	res, err := engine.StreakFor(ctx, database.Pool, u, noon, ny)
	if err != nil {
		t.Fatal(err)
	}
	repair := engine.RepairFor(res, u, noon, ny)
	if repair == nil || repair.Date != yesterday || !repair.Until.Equal(time.Date(2026, 10, 24, 22, 0, 0, 0, ny)) {
		t.Fatalf("repair window = %+v", repair)
	}
	if res.Count != 0 {
		t.Fatalf("streak before repair = %d, want a break", res.Count)
	}

	// Today at 90%: not enough.
	partial := score.ScoreDay([]score.QuestResult{{Key: "x", Points: 100, Actual: 90, Target: 100}})
	if _, err := db.UpsertDayScore(ctx, database.Pool, db.DayScoreRow{UserID: u.ID, LocalDate: today, BasePoints: partial.BasePoints,
		MaxBase: partial.MaxBase, Percent: partial.Percent, Counted: partial.Counted, Detail: []byte(`[]`)}, false); err != nil {
		t.Fatal(err)
	}
	if ok, err := engine.ApplyRepair(ctx, database.Pool, u, noon, ny); err != nil || ok {
		t.Fatalf("90%% must not repair: %v %v", ok, err)
	}

	// 100% after the window closed: too late.
	full := score.ScoreDay([]score.QuestResult{{Key: "x", Points: 100, Actual: 100, Target: 100}})
	if _, err := db.UpsertDayScore(ctx, database.Pool, db.DayScoreRow{UserID: u.ID, LocalDate: today, BasePoints: full.BasePoints,
		MaxBase: full.MaxBase, Percent: full.Percent, Counted: full.Counted, Detail: []byte(`[]`)}, false); err != nil {
		t.Fatal(err)
	}
	if ok, err := engine.ApplyRepair(ctx, database.Pool, u, time.Date(2026, 10, 24, 22, 0, 0, 0, ny), ny); err != nil || ok {
		t.Fatalf("22:00 is too late: %v %v", ok, err)
	}

	// 100% inside the window repairs it.
	if ok, err := engine.ApplyRepair(ctx, database.Pool, u, noon, ny); err != nil || !ok {
		t.Fatalf("repair = %v %v", ok, err)
	}
	if r := row(t, database, u, yesterday); r.FrozenReason != "repair" || !r.Settled {
		t.Fatalf("repaired day = %+v", r)
	}
	res, err = engine.StreakFor(ctx, database.Pool, u, noon, ny)
	if err != nil {
		t.Fatal(err)
	}
	if o := res.Outcome(yesterday); o.Status != score.StatusFrozen || o.Reason != score.ReasonRepair {
		t.Fatalf("outcome = %+v", o)
	}
	if res.Count != 3 || res.Freezes.Held != 0 {
		t.Fatalf("count %d freezes %+v, want the run of 3 restored and no freeze spent", res.Count, res.Freezes)
	}
	if engine.RepairFor(res, u, noon, ny) != nil {
		t.Fatal("a repaired day has no repair window")
	}
	if ok, _ := engine.ApplyRepair(ctx, database.Pool, u, noon, ny); ok {
		t.Fatal("repairing twice")
	}
}

func TestRepairNeedsAFinalizedMissAndSkipsFrozenDays(t *testing.T) {
	database := dbtest.Fresh(t)
	start := score.MustDate("2026-10-19")
	u := join(t, database, "Nick", "green", true, start)
	// The last miss is covered by a freeze, so there is nothing to repair.
	storeDays(t, database, u, start, "xx.pp")
	noon := time.Date(2026, 10, 23, 12, 0, 0, 0, ny)
	settle(t, database, u, noon)
	res, err := engine.StreakFor(ctx, database.Pool, u, noon, ny)
	if err != nil {
		t.Fatal(err)
	}
	if engine.RepairFor(res, u, noon, ny) != nil {
		t.Fatalf("yesterday counted: no repair window, got %+v", res.Outcome(start.AddDays(3)))
	}
}

func TestAwaySpanKeepsAMissedDayOffTheStreak(t *testing.T) {
	database := dbtest.Fresh(t)
	start := score.MustDate("2026-10-19")
	u := join(t, database, "Nick", "green", true, start)
	storeDays(t, database, u, start, "xx...x")
	if _, err := db.CreateAway(ctx, database.Pool, u.ID, start.AddDays(2), start.AddDays(4), "flu"); err != nil {
		t.Fatal(err)
	}
	now := time.Date(2026, 10, 25, 12, 0, 0, 0, ny)
	res, err := engine.StreakFor(ctx, database.Pool, u, now, ny)
	if err != nil {
		t.Fatal(err)
	}
	if res.Count != 3 || res.Freezes.Held != 2 {
		t.Fatalf("count %d freezes %+v: away days break nothing and spend nothing", res.Count, res.Freezes)
	}
	settle(t, database, u, now)
	for i := 2; i <= 4; i++ {
		if r := row(t, database, u, start.AddDays(i)); !r.Away || !r.Settled || r.FrozenReason != "" {
			t.Errorf("day %d = %+v, want settled away", i, r)
		}
	}
	// Removing the span afterwards does not rewrite the past.
	spans, _ := db.AwaySpansFrom(ctx, database.Pool, u.ID, start)
	if _, err := db.DeleteAway(ctx, database.Pool, u.ID, spans[0].ID); err != nil {
		t.Fatal(err)
	}
	res, err = engine.StreakFor(ctx, database.Pool, u, now, ny)
	if err != nil || res.Count != 3 {
		t.Fatalf("after deleting the span: %d %v", res.Count, err)
	}
}

func TestCoverFreezesThePartnersDayAndSpendsTheCoverersFreeze(t *testing.T) {
	database := dbtest.Fresh(t)
	start := score.MustDate("2026-10-19")
	nick := join(t, database, "Nick", "green", true, start)
	nadia := join(t, database, "Nadia", "sky", false, start)
	storeDays(t, database, nick, start, "xxxxx")
	storeDays(t, database, nadia, start, "xxxx.")
	// Yesterday is Oct 23 (index 4), still inside its grace window at 09:00 on Oct 24.
	morning := time.Date(2026, 10, 24, 9, 0, 0, 0, ny)
	before, _ := engine.StreakFor(ctx, database.Pool, nadia, morning, ny)
	if o := before.Outcome(start.AddDays(4)); o.Status != score.StatusPending {
		t.Fatalf("before the cover: %+v", o)
	}
	if created, err := db.CreateCover(ctx, database.Pool, nadia.ID, nick.ID, start.AddDays(4)); err != nil || !created {
		t.Fatalf("cover = %v %v", created, err)
	}
	after, _ := engine.StreakFor(ctx, database.Pool, nadia, morning, ny)
	if o := after.Outcome(start.AddDays(4)); o.Status != score.StatusFrozen || o.Reason != score.ReasonCover {
		t.Fatalf("covered day = %+v", o)
	}
	if after.Freezes.Held != 2 {
		t.Fatalf("the covered person keeps their freezes: %+v", after.Freezes)
	}
	mine, _ := engine.StreakFor(ctx, database.Pool, nick, morning, ny)
	if mine.Freezes.Held != 1 {
		t.Fatalf("the coverer spent one: %+v", mine.Freezes)
	}

	// At finalize the cover is recorded as the reason, and a cover on a day that counted is refunded.
	later := time.Date(2026, 10, 24, 11, 0, 0, 0, ny)
	settle(t, database, nadia, later)
	if r := row(t, database, nadia, start.AddDays(4)); r.FrozenReason != "cover" {
		t.Fatalf("settled reason = %q", r.FrozenReason)
	}
	if created, _ := db.CreateCover(ctx, database.Pool, nick.ID, nadia.ID, start.AddDays(3)); !created {
		t.Fatal("second cover")
	}
	settle(t, database, nick, later)
	covered, spent, err := db.CoversFor(ctx, database.Pool, nadia.ID)
	if err != nil || len(covered) != 1 || len(spent) != 0 {
		t.Fatalf("covers = %v %v %v", covered, spent, err)
	}
}

func TestSharedStreakAcrossTwoPeople(t *testing.T) {
	database := dbtest.Fresh(t)
	start := score.MustDate("2026-10-19")
	nick := join(t, database, "Nick", "green", true, start)
	nadia := join(t, database, "Nadia", "sky", false, start)
	storeDays(t, database, nick, start, "xxxxx")
	storeDays(t, database, nadia, start, "xx.xx")
	now := time.Date(2026, 10, 24, 12, 0, 0, 0, ny)
	users := []db.User{nick, nadia}
	results := map[int64]score.StreakResult{}
	for _, u := range users {
		res, err := engine.StreakFor(ctx, database.Pool, u, now, ny)
		if err != nil {
			t.Fatal(err)
		}
		results[u.ID] = res
	}
	shared := engine.SharedStreakFor(users, results, now)
	// Nadia's miss was frozen and Nick counted, so the day still adds one to the shared streak.
	if shared.Current != 5 || shared.Best != 5 {
		t.Fatalf("shared = %+v, want 5", shared)
	}
	if got := engine.SharedStreakFor(users[:1], results, now); got != (score.SharedResult{}) {
		t.Fatalf("one person has no couple streak: %+v", got)
	}
}

func TestManualActivityCountsTowardExerciseMinutes(t *testing.T) {
	exercise := []db.DayQuest{{Key: db.QuestExercise, Target: 30, Points: 100}}
	cases := []struct {
		name   string
		in     db.DayInputs
		actual int
		listed bool
	}{
		{"nothing synced and nothing logged leaves the quest out", db.DayInputs{}, 0, false},
		{"hard and moderate count fully", db.DayInputs{OtherFullMinutes: 25}, 25, true},
		{"easy counts half", db.DayInputs{OtherEasyMinutes: 40}, 20, true},
		{"one easy minute counts nothing", db.DayInputs{OtherEasyMinutes: 1}, 0, false},
		{"added to Health's minutes", db.DayInputs{Metrics: map[string]float64{db.MetricExercise: 12.9},
			Synced: map[string]bool{db.MetricExercise: true}, OtherFullMinutes: 10, OtherEasyMinutes: 10}, 27, true},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			results := engine.QuestResults(exercise, tc.in)
			if len(results) != btoi(tc.listed) {
				t.Fatalf("results = %v", results)
			}
			if tc.listed && results[0].Actual != tc.actual {
				t.Fatalf("actual = %d, want %d", results[0].Actual, tc.actual)
			}
			actual, _ := engine.Actuals(exercise[0], tc.in)
			if actual != tc.actual {
				t.Fatalf("shown actual = %d, want %d", actual, tc.actual)
			}
		})
	}
}

func btoi(b bool) int {
	if b {
		return 1
	}
	return 0
}

func TestEasyReadinessMorningRestsAMissedDayWithoutAFreeze(t *testing.T) {
	database := dbtest.Fresh(t)
	start := score.MustDate("2026-10-19")
	u := join(t, database, "Nick", "green", true, start)
	storeDays(t, database, u, start, "xx.xx")
	// Four hours of sleep against the 7 h default target: an easy morning.
	if _, err := db.UpsertHealthDaily(ctx, database.Pool, u.ID, start.AddDays(2), db.MetricSleep, 240, "healthkit",
		time.Date(2026, 10, 21, 8, 0, 0, 0, ny)); err != nil {
		t.Fatal(err)
	}
	now := time.Date(2026, 10, 24, 12, 0, 0, 0, ny)
	res, err := engine.StreakFor(ctx, database.Pool, u, now, ny)
	if err != nil {
		t.Fatal(err)
	}
	if o := res.Outcome(start.AddDays(2)); o.Status != score.StatusFrozen || o.Reason != score.ReasonReadiness {
		t.Fatalf("outcome = %+v", o)
	}
	if res.Freezes.Held != 2 {
		t.Fatalf("freezes = %+v, a readiness rest spends none", res.Freezes)
	}
	settle(t, database, u, now)
	if r := row(t, database, u, start.AddDays(2)); r.FrozenReason != "readiness" {
		t.Fatalf("recorded reason = %q", r.FrozenReason)
	}

}
