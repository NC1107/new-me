package engine_test

import (
	"context"
	"fmt"
	"os"
	"testing"
	"time"

	"github.com/jackc/pgx/v5"

	"github.com/nc1107/new-me/server/internal/db"
	"github.com/nc1107/new-me/server/internal/dbtest"
	"github.com/nc1107/new-me/server/internal/engine"
	"github.com/nc1107/new-me/server/internal/score"
)

func TestMain(m *testing.M) {
	dbtest.Require()
	os.Exit(m.Run())
}

var ctx = context.Background()

var ny = func() *time.Location {
	loc, err := time.LoadLocation("America/New_York")
	if err != nil {
		panic(err)
	}
	return loc
}()

func quests() []db.DayQuest {
	alt := 15
	return []db.DayQuest{
		{Key: db.QuestSteps, Target: 8000, Points: 100},
		{Key: db.QuestPushups, Target: 30, Points: 100},
		{Key: db.QuestReading, Target: 20, TargetAlt: &alt, Points: 100},
		{Key: db.QuestMealsLogged, Target: 2, Points: 50},
		{Key: db.QuestProtein, Target: 100, Points: 50},
	}
}

func byKey(results []score.QuestResult, key string) (score.QuestResult, bool) {
	for _, r := range results {
		if r.Key == key {
			return r, true
		}
	}
	return score.QuestResult{}, false
}

func TestQuestResultsCountListeningAsReadingMinutes(t *testing.T) {
	in := db.DayInputs{ReadingMinutes: 5, ListeningMinutes: 15, ReadingPages: 3}
	r, ok := byKey(engine.QuestResults(quests(), in), db.QuestReading)
	if !ok || r.Actual != 20*15+3*20 || r.Target != 20*15 {
		t.Fatalf("reading = %+v", r)
	}
	var q db.DayQuest
	for _, c := range quests() {
		if c.Key == db.QuestReading {
			q = c
		}
	}
	minutes, pages := engine.Actuals(q, in)
	if minutes != 20 || pages == nil || *pages != 3 {
		t.Fatalf("actuals = %d %v", minutes, pages)
	}
}

func TestQuestResultsMapInputsToQuests(t *testing.T) {
	in := db.DayInputs{Metrics: map[string]float64{db.MetricSteps: 4999.9},
		Synced: map[string]bool{db.MetricSteps: true}, Pushups: 35, ReadingMinutes: 10, ReadingPages: 5,
		Meals: 2, ProteinG: 79.9}
	results := engine.QuestResults(quests(), in)
	want := map[string][2]int{
		db.QuestSteps:       {4999, 8000},
		db.QuestPushups:     {35, 30},
		db.QuestReading:     {10*15 + 5*20, 20 * 15},
		db.QuestMealsLogged: {2, 2},
		db.QuestProtein:     {799, 1000},
	}
	if len(results) != len(want) {
		t.Fatalf("results = %d, want %d", len(results), len(want))
	}
	for key, w := range want {
		r, ok := byKey(results, key)
		if !ok || r.Actual != w[0] || r.Target != w[1] {
			t.Fatalf("%s = %+v, want %v", key, r, w)
		}
	}
}

func TestQuestResultsLeaveStepsOutUntilHealthIsConnected(t *testing.T) {
	results := engine.QuestResults(quests(), db.DayInputs{Pushups: 30})
	if _, ok := byKey(results, db.QuestSteps); ok {
		t.Fatal("steps must not be scored before the first Health reading")
	}
	if len(results) != 4 {
		t.Fatalf("results = %d, want the 4 other quests", len(results))
	}
}

func healthQuests() []db.DayQuest {
	return []db.DayQuest{
		{Key: db.QuestExercise, Target: 30, Points: 100},
		{Key: db.QuestSleep, Target: 420, Points: 50},
	}
}

func TestExerciseAndSleepScoreFromHealthMetrics(t *testing.T) {
	synced := map[string]bool{db.MetricExercise: true, db.MetricSleep: true}
	partial := engine.QuestResults(healthQuests(), db.DayInputs{
		Metrics: map[string]float64{db.MetricExercise: 15.9, db.MetricSleep: 210}, Synced: synced})
	day := score.ScoreDay(partial)
	if day.Quests[0].Actual != 15 || day.Quests[0].Base != 50 || day.Quests[0].Complete ||
		day.Quests[1].Actual != 210 || day.Quests[1].Base != 25 || day.BonusPoints != 0 {
		t.Fatalf("partial = %+v", day)
	}

	done := score.ScoreDay(engine.QuestResults(healthQuests(), db.DayInputs{
		Metrics: map[string]float64{db.MetricExercise: 45, db.MetricSleep: 420}, Synced: synced}))
	if done.BasePoints != 150 || done.BonusPoints != 30 || done.Percent != 100 || !done.Counted {
		t.Fatalf("complete = %+v; want full base and a 20 + 10 bonus", done)
	}
}

func TestExerciseAndSleepWaitForTheirOwnMetric(t *testing.T) {
	in := db.DayInputs{
		Metrics: map[string]float64{db.MetricExercise: 10},
		Synced:  map[string]bool{db.MetricExercise: true, db.MetricSteps: true}}
	results := engine.QuestResults(healthQuests(), in)
	if len(results) != 1 || results[0].Key != db.QuestExercise {
		t.Fatalf("results = %+v; sleep has never been synced so it must not appear", results)
	}
	if got := engine.QuestResults(healthQuests(), db.DayInputs{}); len(got) != 0 {
		t.Fatalf("nothing synced produced %+v", got)
	}
	a, _ := engine.Actuals(healthQuests()[1], db.DayInputs{Metrics: map[string]float64{db.MetricSleep: 400.7}})
	if a != 400 {
		t.Fatalf("sleep actual = %d", a)
	}
}

func TestQuestResultsHandleYogaAndEmptyDays(t *testing.T) {
	yoga := []db.DayQuest{{Key: db.QuestYoga, Target: 20, Points: 50}}
	r := engine.QuestResults(yoga, db.DayInputs{YogaMinutes: 25})
	if len(r) != 1 || r[0].Actual != 25 {
		t.Fatalf("yoga = %+v", r)
	}
	if got := engine.QuestResults(nil, db.DayInputs{}); len(got) != 0 {
		t.Fatalf("no quests produced %d results", len(got))
	}
}

const day = score.Date("2026-10-27")

func join(t *testing.T, database *db.DB, name, color string, admin bool, joined score.Date) db.User {
	t.Helper()
	var u db.User
	err := database.WithTx(ctx, func(tx pgx.Tx) error {
		var err error
		u, err = db.CreateUser(ctx, tx, db.NewUser{
			Name: name, Color: color, Timezone: "America/New_York", IsAdmin: admin, JoinedOn: joined}, 2)
		return err
	})
	if err != nil {
		t.Fatal(err)
	}
	return u
}

func recompute(t *testing.T, database *db.DB, u db.User, date score.Date, now time.Time) db.DayScoreRow {
	t.Helper()
	var row db.DayScoreRow
	err := database.WithTx(ctx, func(tx pgx.Tx) error {
		var err error
		row, err = engine.RecomputeDayAt(ctx, tx, u.ID, date, ny, now)
		return err
	})
	if err != nil {
		t.Fatalf("recompute %s: %v", date, err)
	}
	return row
}

var opSeq int

func logPushups(t *testing.T, database *db.DB, u db.User, date score.Date, qty int) {
	t.Helper()
	opSeq++
	if _, _, err := db.InsertActivityLog(ctx, database.Pool, db.NewActivityLog{
		UserID: u.ID, LocalDate: date, Type: db.ActivityPushups, Quantity: qty,
		ClientOpID: fmt.Sprintf("22222222-2222-4222-8222-%012d", opSeq)}); err != nil {
		t.Fatal(err)
	}
}

func putSteps(t *testing.T, database *db.DB, u db.User, date score.Date, steps float64) {
	t.Helper()
	if _, err := db.UpsertHealthDaily(ctx, database.Pool, u.ID, date, db.MetricSteps, steps, "healthkit", time.Now()); err != nil {
		t.Fatal(err)
	}
}

func TestRecomputeDayScoresAndStores(t *testing.T) {
	database := dbtest.Fresh(t)
	u := join(t, database, "Nick", "green", true, day)
	noon := time.Date(2026, 10, 27, 12, 0, 0, 0, ny)

	empty := recompute(t, database, u, day, noon)
	if empty.BasePoints != 0 || empty.MaxBase != 300 || empty.Counted || empty.FinalizedAt != nil {
		t.Fatalf("empty day = %+v; steps are excluded so max is 300", empty)
	}

	logPushups(t, database, u, day, 30)
	putSteps(t, database, u, day, 8000)
	full := recompute(t, database, u, day, noon)
	if full.BasePoints != 200 || full.BonusPoints != 40 || full.MaxBase != 400 || full.Percent != 50 || full.Counted {
		t.Fatalf("pushups and steps = %+v", full)
	}
	if full.Points() != 240 {
		t.Fatalf("points = %d, want 240", full.Points())
	}

	stored, err := db.GetDayScore(ctx, database.Pool, u.ID, day)
	if err != nil || stored.BasePoints != 200 || len(stored.Detail) == 0 {
		t.Fatalf("stored = %+v %v", stored, err)
	}
	quests, err := db.GetDayQuests(ctx, database.Pool, u.ID, day)
	if err != nil || len(quests) != 8 {
		t.Fatalf("snapshot = %d quests, %v", len(quests), err)
	}
}

func TestRecomputeDayCountsAtSeventyPercent(t *testing.T) {
	database := dbtest.Fresh(t)
	u := join(t, database, "Nick", "green", true, day)
	noon := time.Date(2026, 10, 27, 12, 0, 0, 0, ny)

	putSteps(t, database, u, day, 8000)
	logPushups(t, database, u, day, 30)
	if _, _, err := db.InsertActivityLog(ctx, database.Pool, db.NewActivityLog{
		UserID: u.ID, LocalDate: day, Type: db.ActivityReadingMinutes, Quantity: 20,
		ClientOpID: "33333333-3333-4333-8333-000000000001"}); err != nil {
		t.Fatal(err)
	}
	row := recompute(t, database, u, day, noon)
	if row.BasePoints != 300 || row.MaxBase != 400 || row.Percent != 75 || !row.Counted {
		t.Fatalf("75%% day = %+v", row)
	}
}

func TestRecomputeDayFinalizesOnlyAfterTheGraceWindow(t *testing.T) {
	database := dbtest.Fresh(t)
	u := join(t, database, "Nick", "green", true, day)

	during := recompute(t, database, u, day, time.Date(2026, 10, 28, 9, 59, 0, 0, ny))
	if during.FinalizedAt != nil {
		t.Fatal("a day inside its grace window must not be finalized")
	}
	after := recompute(t, database, u, day, time.Date(2026, 10, 28, 10, 0, 0, 0, ny))
	if after.FinalizedAt == nil {
		t.Fatal("a day past its grace window must be finalized")
	}
	again := recompute(t, database, u, day, time.Date(2026, 10, 28, 9, 0, 0, 0, ny))
	if again.FinalizedAt == nil {
		t.Fatal("a recompute must never un-finalize a day")
	}
}

func TestRecomputeDayKeepsTheSnapshotWhenTemplatesChange(t *testing.T) {
	database := dbtest.Fresh(t)
	u := join(t, database, "Nick", "green", true, day)
	noon := time.Date(2026, 10, 27, 12, 0, 0, 0, ny)
	recompute(t, database, u, day, noon)

	if err := db.UpsertQuestTemplate(ctx, database.Pool, u.ID, db.QuestTemplate{
		Key: db.QuestPushups, Target: 5, Unit: "reps", Points: 100, Enabled: true}); err != nil {
		t.Fatal(err)
	}
	logPushups(t, database, u, day, 15)
	row := recompute(t, database, u, day, noon)
	if row.BasePoints != 50 {
		t.Fatalf("base = %d; 15 of the snapshotted 30 is half credit, not the lowered target", row.BasePoints)
	}
}

func TestRecomputeDayIsSafeUnderConcurrentWriters(t *testing.T) {
	database := dbtest.Fresh(t)
	u := join(t, database, "Nick", "green", true, day)
	noon := time.Date(2026, 10, 27, 12, 0, 0, 0, ny)
	putSteps(t, database, u, day, 1)

	done := make(chan error, 8)
	for i := 0; i < cap(done); i++ {
		go func() {
			done <- database.WithTx(ctx, func(tx pgx.Tx) error {
				_, err := engine.RecomputeDayAt(ctx, tx, u.ID, day, ny, noon)
				return err
			})
		}()
	}
	for i := 0; i < cap(done); i++ {
		if err := <-done; err != nil {
			t.Fatalf("concurrent recompute: %v", err)
		}
	}
}

func TestStreakForFreezesAMissedStoredDay(t *testing.T) {
	database := dbtest.Fresh(t)
	start := score.MustDate("2026-10-26")
	u := join(t, database, "Nick", "green", true, start)
	store := func(date score.Date, counted bool) {
		base := 0
		if counted {
			base = 100
		}
		d := score.ScoreDay([]score.QuestResult{{Key: "x", Points: 100, Actual: base, Target: 100}})
		if _, err := db.UpsertDayScore(ctx, database.Pool, db.DayScoreRow{UserID: u.ID, LocalDate: date,
			BasePoints: d.BasePoints, BonusPoints: d.BonusPoints, MaxBase: d.MaxBase, Percent: d.Percent,
			Counted: d.Counted, Detail: []byte(`[]`)}, true); err != nil {
			t.Fatal(err)
		}
	}
	store(start, true)
	store(start.AddDays(1), true)
	store(start.AddDays(2), false)
	store(start.AddDays(3), true)

	now := time.Date(2026, 10, 30, 15, 0, 0, 0, ny)
	got, err := engine.StreakFor(ctx, database.Pool, u, now, ny)
	if err != nil {
		t.Fatal(err)
	}
	if o := got.Outcome(start.AddDays(2)); got.Count != 3 || o.Status != score.StatusFrozen || got.Freezes.Held != 1 {
		t.Fatalf("streak = %+v, want 3 (the frozen day adds nothing) with %s frozen and one freeze left", got, start.AddDays(2))
	}
}

func TestStreakForTreatsUnscoredDaysAsMisses(t *testing.T) {
	database := dbtest.Fresh(t)
	start := score.MustDate("2026-10-26")
	u := join(t, database, "Nick", "green", true, start)

	now := time.Date(2026, 10, 30, 15, 0, 0, 0, ny)
	got, err := engine.StreakFor(ctx, database.Pool, u, now, ny)
	if err != nil || got.Count != 0 {
		t.Fatalf("streak with nothing stored = %+v %v", got, err)
	}
}
