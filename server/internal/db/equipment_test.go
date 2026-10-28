package db_test

import (
	"slices"
	"testing"

	"github.com/nc1107/new-me/server/internal/db"
	"github.com/nc1107/new-me/server/internal/dbtest"
)

// A doorway pull-up bar and a hangboard, Nick's whole kit, once got a plan with inverted rows,
// which hang under a bar at waist height.
func TestCatalogEquipmentFollowsTheStepsOfEachExercise(t *testing.T) {
	database := dbtest.Fresh(t)
	u := join(t, database, "Nick", "green", true)
	all, err := db.ListExercises(ctx, database.Pool, u.ID)
	if err != nil {
		t.Fatal(err)
	}
	want := map[string][]string{"inverted_row": {"low_bar"}, "decline_push_up": {"bench"}, "incline_push_up": {}, "negative_pull_up": {"pullup_bar"}}
	kit := []string{"pullup_bar", "hangboard"}
	seen := 0
	for _, e := range all {
		need, ok := want[e.Key]
		if !ok {
			continue
		}
		seen++
		if !slices.Equal(e.Equipment, need) && !(len(need) == 0 && len(e.Equipment) == 0) {
			t.Errorf("%s needs %v, want %v", e.Key, e.Equipment, need)
		}
		fits := true
		for _, n := range e.Equipment {
			fits = fits && slices.Contains(kit, n)
		}
		if fits != (e.Key == "incline_push_up" || e.Key == "negative_pull_up") {
			t.Errorf("%s fits a doorway bar and hangboard = %v", e.Key, fits)
		}
	}
	if seen != len(want) {
		t.Fatalf("found %d of the %d exercises this guards; one was renamed or dropped", seen, len(want))
	}
}
