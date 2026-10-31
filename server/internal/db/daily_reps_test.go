package db_test

import (
	"errors"
	"fmt"
	"testing"

	"github.com/nc1107/new-me/server/internal/db"
	"github.com/nc1107/new-me/server/internal/dbtest"
	"github.com/nc1107/new-me/server/internal/score"
)

func TestLegacyRowsDefaultToPushups(t *testing.T) {
	database := dbtest.Fresh(t)
	u := join(t, database, "Nick", "green", true)

	// A row written the way v17 did, without the exercise column.
	if _, err := database.Pool.Exec(ctx, `
		INSERT INTO activity_logs (user_id, local_date, type, quantity, client_op_id)
		VALUES ($1, $2::date, 'pushups', 25, $3::uuid)`, u.ID, day, fmt.Sprintf(opID, 1)); err != nil {
		t.Fatal(err)
	}
	logs, err := db.ListActivityLogs(ctx, database.Pool, u.ID, day)
	if err != nil || len(logs) != 1 || logs[0].Exercise != "push_up" {
		t.Fatalf("legacy log = %+v err=%v", logs, err)
	}

	templates, err := db.GetQuestTemplates(ctx, database.Pool, u.ID)
	if err != nil {
		t.Fatal(err)
	}
	for _, tpl := range templates {
		if tpl.Exercise != "push_up" {
			t.Errorf("%s template exercise = %q", tpl.Key, tpl.Exercise)
		}
	}
	if err := db.EnsureSnapshot(ctx, database.Pool, u.ID, day); err != nil {
		t.Fatal(err)
	}
	quests, err := db.GetDayQuests(ctx, database.Pool, u.ID, day)
	if err != nil || len(quests) == 0 {
		t.Fatalf("quests = %+v err=%v", quests, err)
	}
	for _, q := range quests {
		if q.Exercise != "push_up" {
			t.Errorf("%s day quest exercise = %q", q.Key, q.Exercise)
		}
	}
	if got, err := db.RepsExerciseOf(ctx, database.Pool, u.ID, day); err != nil || got != "push_up" {
		t.Fatalf("exercise of the day = %q err=%v", got, err)
	}
	in, err := db.LoadDayInputs(ctx, database.Pool, u.ID, day)
	if err != nil || in.Pushups != 25 || in.RepsExercise != "push_up" {
		t.Fatalf("inputs = %+v err=%v", in, err)
	}
}

func TestRepsOfAnotherExerciseCountOnlyForThatExercise(t *testing.T) {
	database := dbtest.Fresh(t)
	u := join(t, database, "Nick", "green", true)
	log := func(n int, exercise string, reps int) {
		t.Helper()
		_, _, err := db.InsertActivityLog(ctx, database.Pool, db.NewActivityLog{UserID: u.ID, LocalDate: day,
			Type: db.ActivityPushups, Quantity: reps, ClientOpID: fmt.Sprintf(opID, n), Exercise: exercise})
		if err != nil {
			t.Fatal(err)
		}
	}
	log(1, "push_up", 30)
	log(2, "air_squat", 12)
	log(3, "", 3)

	tpl := db.QuestTemplate{Key: db.QuestPushups, Target: 45, Unit: "reps", Points: 100, Enabled: true, Exercise: "air_squat"}
	if err := db.UpsertQuestTemplate(ctx, database.Pool, u.ID, tpl); err != nil {
		t.Fatal(err)
	}
	if err := db.EnsureSnapshot(ctx, database.Pool, u.ID, day); err != nil {
		t.Fatal(err)
	}
	in, err := db.LoadDayInputs(ctx, database.Pool, u.ID, day)
	if err != nil || in.Pushups != 12 || in.RepsExercise != "air_squat" {
		t.Fatalf("squat inputs = %+v err=%v", in, err)
	}

	// Push-ups are the 30 and the 3 logged with no exercise.
	tpl.Exercise = "push_up"
	if err := db.UpsertQuestTemplate(ctx, database.Pool, u.ID, tpl); err != nil {
		t.Fatal(err)
	}
	if _, err := database.Pool.Exec(ctx, `DELETE FROM day_quests WHERE user_id = $1`, u.ID); err != nil {
		t.Fatal(err)
	}
	if err := db.EnsureSnapshot(ctx, database.Pool, u.ID, day); err != nil {
		t.Fatal(err)
	}
	if in, err = db.LoadDayInputs(ctx, database.Pool, u.ID, day); err != nil || in.Pushups != 33 {
		t.Fatalf("push-up inputs = %+v err=%v", in, err)
	}

	byDay, err := db.PushupsByDay(ctx, database.Pool, u.ID, day, day)
	if err != nil || byDay[day] != 33 {
		t.Fatalf("progress counts only push-ups: %v err=%v", byDay, err)
	}
	sets, err := db.RepsSets(ctx, database.Pool, u.ID, "air_squat", day, day)
	if err != nil || len(sets[day]) != 1 || sets[day][0] != 12 {
		t.Fatalf("squat sets = %v err=%v", sets, err)
	}
}

func TestMaxTestsAreKeptPerExercise(t *testing.T) {
	database := dbtest.Fresh(t)
	u := join(t, database, "Nick", "green", true)
	if _, err := db.LatestRepsMax(ctx, database.Pool, u.ID, "air_squat"); !errors.Is(err, db.ErrNotFound) {
		t.Fatalf("no test yet: %v", err)
	}

	squat, err := db.ExerciseByKey(ctx, database.Pool, u.ID, "air_squat")
	if err != nil {
		t.Fatal(err)
	}
	reps := 20
	if err := db.UpsertMaxTest(ctx, database.Pool, u.ID, db.MaxTest{ExerciseID: squat.ID, LocalDate: score.Date("2026-10-27"), Reps: &reps}); err != nil {
		t.Fatal(err)
	}
	// A v8 push-up max recorded after it belongs to push-ups alone.
	if err := db.SetPushupMax(ctx, database.Pool, u.ID, score.Date("2026-10-28"), 40); err != nil {
		t.Fatal(err)
	}
	if m, err := db.LatestRepsMax(ctx, database.Pool, u.ID, "air_squat"); err != nil || m.Reps != 20 {
		t.Fatalf("squat max = %+v err=%v", m, err)
	}
	if m, err := db.LatestRepsMax(ctx, database.Pool, u.ID, "push_up"); err != nil || m.Reps != 40 {
		t.Fatalf("push-up max = %+v err=%v", m, err)
	}
	if _, err := db.LatestRepsMax(ctx, database.Pool, u.ID, "lunge"); !errors.Is(err, db.ErrNotFound) {
		t.Fatalf("lunge was never tested: %v", err)
	}
}

func TestDailyRepsChoicesAreCatalogExercisesWithKnownEquipment(t *testing.T) {
	database := dbtest.Fresh(t)
	u := join(t, database, "Nick", "green", true)
	for _, c := range db.RepsExercises {
		e, err := db.ExerciseByKey(ctx, database.Pool, u.ID, c.Key)
		if err != nil {
			t.Fatalf("%s is not in the catalog: %v", c.Key, err)
		}
		if e.Measure != "reps" || e.Load != db.LoadBodyweight {
			t.Errorf("%s measures %s with %s load", c.Key, e.Measure, e.Load)
		}
		switch {
		case c.Needs == "" && len(e.Equipment) != 0:
			t.Errorf("%s needs %v but is offered to everyone", c.Key, e.Equipment)
		case c.Needs != "" && (len(e.Equipment) != 1 || e.Equipment[0] != c.Needs):
			t.Errorf("%s equipment %v does not match %s", c.Key, e.Equipment, c.Needs)
		}
	}
	if got := db.RepsNoun("air_squat", 1); got != "squat" {
		t.Errorf("one rep = %q", got)
	}
	if got := db.RepsNoun("nope", 3); got != "reps" {
		t.Errorf("unknown = %q", got)
	}
}
