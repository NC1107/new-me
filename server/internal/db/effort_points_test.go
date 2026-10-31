package db_test

import (
	"testing"

	"github.com/nc1107/new-me/server/internal/db"
	"github.com/nc1107/new-me/server/internal/dbtest"
	"github.com/nc1107/new-me/server/migrations"
)

// The migration repeats score.EffortPoints in SQL, so the two must give the same worth for the
// same templates, including targets far from the defaults.
func TestEffortMigrationMatchesTheGoRule(t *testing.T) {
	database := dbtest.Fresh(t)
	u := join(t, database, "Nick", "green", true)
	for _, e := range []struct {
		key      string
		target   int
		exercise string
	}{
		{db.QuestSteps, 3000, ""}, {db.QuestSteps, 12000, ""}, {db.QuestExercise, 10, ""}, {db.QuestExercise, 45, ""},
		{db.QuestPushups, 100, "push_up"}, {db.QuestPushups, 100, "crunch"}, {db.QuestPushups, 100, "glute_bridge"},
		{db.QuestYoga, 20, ""}, {db.QuestBreathing, 30, ""}, {db.QuestReading, 45, ""},
	} {
		if _, err := database.Pool.Exec(ctx, `
			UPDATE quest_templates SET target = $3, exercise = COALESCE(NULLIF($4, ''), exercise), points = 5
			WHERE user_id = $1 AND key = $2`, u.ID, e.key, e.target, e.exercise); err != nil {
			t.Fatalf("%s: %v", e.key, err)
		}
		sql, err := migrations.Files.ReadFile("0034_v19_effort_points.sql")
		if err != nil {
			t.Fatal(err)
		}
		if _, err := database.Pool.Exec(ctx, string(sql)); err != nil {
			t.Fatalf("migration: %v", err)
		}
		templates, err := db.GetQuestTemplates(ctx, database.Pool, u.ID)
		if err != nil {
			t.Fatal(err)
		}
		for _, tpl := range templates {
			if want := db.EffortPoints(tpl).Points; tpl.Points != want {
				t.Errorf("%s target %d exercise %q: SQL gave %d, Go gives %d", tpl.Key, tpl.Target, tpl.Exercise, tpl.Points, want)
			}
		}
	}
}
