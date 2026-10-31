package db_test

import (
	"testing"

	"github.com/nc1107/new-me/server/internal/db"
	"github.com/nc1107/new-me/server/internal/dbtest"
	"github.com/nc1107/new-me/server/migrations"
)

// The migration repeats score.EffortPoints in SQL, so the two must give the same worth for the
// same templates and training profile, including targets far from the defaults.
func TestEffortMigrationMatchesTheGoRule(t *testing.T) {
	database := dbtest.Fresh(t)
	u := join(t, database, "Nick", "green", true)
	sql, err := migrations.Files.ReadFile("0034_v19_effort_points.sql")
	if err != nil {
		t.Fatal(err)
	}
	for _, session := range []int{0, 20, 35, 45, 90} {
		for _, e := range []struct {
			key    string
			target int
		}{
			{db.QuestSteps, 3000}, {db.QuestSteps, 12000}, {db.QuestExercise, 10}, {db.QuestExercise, 45},
			{db.QuestPushups, 100}, {db.QuestYoga, 20}, {db.QuestBreathing, 30}, {db.QuestReading, 45},
		} {
			if _, err := database.Pool.Exec(ctx, `
				UPDATE quest_templates SET target = $3, points = 5 WHERE user_id = $1 AND key = $2`,
				u.ID, e.key, e.target); err != nil {
				t.Fatalf("%s: %v", e.key, err)
			}
			if session > 0 {
				if _, err := db.PutTrainingProfile(ctx, database.Pool, u.ID, db.TrainingProfile{
					Equipment: []string{}, DaysPerWeek: 3, SessionMinutes: session, Experience: "new"}); err != nil {
					t.Fatal(err)
				}
			}
			if _, err := database.Pool.Exec(ctx, string(sql)); err != nil {
				t.Fatalf("migration: %v", err)
			}
			templates, err := db.GetQuestTemplates(ctx, database.Pool, u.ID)
			if err != nil {
				t.Fatal(err)
			}
			for _, tpl := range templates {
				if want := db.EffortPoints(tpl, session).Points; tpl.Points != want {
					t.Errorf("%s target %d session %d: SQL gave %d, Go gives %d", tpl.Key, tpl.Target, session, tpl.Points, want)
				}
			}
		}
	}
}

func TestRepriceStrengthFollowsTheTrainingProfile(t *testing.T) {
	database := dbtest.Fresh(t)
	u := join(t, database, "Nick", "green", true)
	pushups := func() int {
		templates, _ := db.GetQuestTemplates(ctx, database.Pool, u.ID)
		for _, tpl := range templates {
			if tpl.Key == db.QuestPushups {
				return tpl.Points
			}
		}
		return -1
	}
	if got := pushups(); got != 75 {
		t.Fatalf("a new person's strength quest is worth %d, want 75", got)
	}
	if _, err := db.PutTrainingProfile(ctx, database.Pool, u.ID, db.TrainingProfile{
		Equipment: []string{}, DaysPerWeek: 3, SessionMinutes: 20, Experience: "new"}); err != nil {
		t.Fatal(err)
	}
	changed, err := db.RepriceStrength(ctx, database.Pool, u.ID)
	if err != nil || !changed || pushups() != 50 {
		t.Fatalf("reprice = %v, %v, points %d; want changed and 50", changed, err, pushups())
	}
	if changed, _ := db.RepriceStrength(ctx, database.Pool, u.ID); changed {
		t.Fatal("a second reprice changes nothing")
	}
}
