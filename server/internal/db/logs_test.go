package db_test

import (
	"errors"
	"fmt"
	"testing"
	"time"

	"github.com/nc1107/new-me/server/internal/db"
	"github.com/nc1107/new-me/server/internal/dbtest"
	"github.com/nc1107/new-me/server/internal/score"
)

const day = score.Date("2026-10-27")

func TestActivityLogReplayReturnsTheStoredRow(t *testing.T) {
	database := dbtest.Fresh(t)
	u := join(t, database, "Nick", "green", true)
	in := db.NewActivityLog{UserID: u.ID, LocalDate: day, Type: db.ActivityPushups, Quantity: 20, ClientOpID: fmt.Sprintf(opID, 1)}

	first, created, err := db.InsertActivityLog(ctx, database.Pool, in)
	if err != nil || !created {
		t.Fatalf("first insert: created=%v err=%v", created, err)
	}
	in.Quantity = 99
	replay, created, err := db.InsertActivityLog(ctx, database.Pool, in)
	if err != nil || created {
		t.Fatalf("replay: created=%v err=%v", created, err)
	}
	if replay.ID != first.ID || replay.Quantity != 20 || replay.LocalDate != day {
		t.Fatalf("replay = %+v, want the original %+v", replay, first)
	}

	if _, err := db.SoftDeleteLog(ctx, database.Pool, u.ID, first.ID); err != nil {
		t.Fatal(err)
	}
	again, created, err := db.InsertActivityLog(ctx, database.Pool, in)
	if err != nil || created || again.DeletedAt == nil {
		t.Fatalf("replay of a deleted row: %+v created=%v err=%v; it must stay deleted", again, created, err)
	}
	if logs, _ := db.ListActivityLogs(ctx, database.Pool, u.ID, day); len(logs) != 0 {
		t.Fatalf("listed %d logs after delete", len(logs))
	}
}

func TestSameClientOpIDIsPerUser(t *testing.T) {
	database := dbtest.Fresh(t)
	nick := join(t, database, "Nick", "green", true)
	nadia := join(t, database, "Nadia", "sky", false)
	for _, u := range []db.User{nick, nadia} {
		_, created, err := db.InsertActivityLog(ctx, database.Pool, db.NewActivityLog{
			UserID: u.ID, LocalDate: day, Type: db.ActivityPushups, Quantity: 10, ClientOpID: fmt.Sprintf(opID, 7)})
		if err != nil || !created {
			t.Fatalf("user %d: created=%v err=%v", u.ID, created, err)
		}
	}
}

func TestLogCaps(t *testing.T) {
	database := dbtest.Fresh(t)
	u := join(t, database, "Nick", "green", true)
	cases := []struct {
		typ string
		qty int
		ok  bool
	}{
		{db.ActivityPushups, 500, true},
		{db.ActivityPushups, 501, false},
		{db.ActivityReadingPages, 2000, true},
		{db.ActivityReadingPages, 2001, false},
		{db.ActivityReadingMinutes, 1441, false},
		{db.ActivityYogaMinutes, 1440, true},
		{db.ActivityPushups, 0, false},
		{"situps", 5, false},
	}
	for i, c := range cases {
		_, _, err := db.InsertActivityLog(ctx, database.Pool, db.NewActivityLog{
			UserID: u.ID, LocalDate: day, Type: c.typ, Quantity: c.qty, ClientOpID: fmt.Sprintf(opID, 100+i)})
		if (err == nil) != c.ok {
			t.Fatalf("%s x %d: err = %v, want ok=%v", c.typ, c.qty, err, c.ok)
		}
	}
	_, _, err := db.InsertMealLog(ctx, database.Pool, db.NewMealLog{
		UserID: u.ID, LocalDate: day, Name: "Brick", Kcal: 10001, ClientOpID: fmt.Sprintf(opID, 200)})
	if err == nil {
		t.Fatal("kcal above the cap must be rejected")
	}
}

func TestMealLogRoundTripsMacros(t *testing.T) {
	database := dbtest.Fresh(t)
	u := join(t, database, "Nick", "green", true)
	in := db.NewMealLog{UserID: u.ID, LocalDate: day, Name: "Oats", Kcal: 350, ProteinG: 12.5,
		CarbsG: 60.2, FatG: 6.1, FiberG: 8, ClientOpID: fmt.Sprintf(opID, 1)}
	got, created, err := db.InsertMealLog(ctx, database.Pool, in)
	if err != nil || !created {
		t.Fatalf("insert: %v %v", created, err)
	}
	if got.ProteinG != 12.5 || got.CarbsG != 60.2 || got.FatG != 6.1 || got.FiberG != 8 {
		t.Fatalf("macros = %+v", got)
	}
	replay, created, err := db.InsertMealLog(ctx, database.Pool, in)
	if err != nil || created || replay.ID != got.ID {
		t.Fatalf("replay = %+v created=%v err=%v", replay, created, err)
	}
	meals, err := db.ListMealLogs(ctx, database.Pool, u.ID, day)
	if err != nil || len(meals) != 1 {
		t.Fatalf("list = %d, %v", len(meals), err)
	}
}

func TestSoftDeleteLogFindsEitherTable(t *testing.T) {
	database := dbtest.Fresh(t)
	u := join(t, database, "Nick", "green", true)
	other := join(t, database, "Nadia", "sky", false)
	act, _, _ := db.InsertActivityLog(ctx, database.Pool, db.NewActivityLog{
		UserID: u.ID, LocalDate: day, Type: db.ActivityPushups, Quantity: 5, ClientOpID: fmt.Sprintf(opID, 1)})
	meal, _, _ := db.InsertMealLog(ctx, database.Pool, db.NewMealLog{
		UserID: u.ID, LocalDate: day.AddDays(-1), Name: "Toast", Kcal: 100, ClientOpID: fmt.Sprintf(opID, 2)})
	if act.ID == meal.ID {
		t.Fatal("activity and meal ids must come from one sequence")
	}

	if _, err := db.SoftDeleteLog(ctx, database.Pool, other.ID, act.ID); !errors.Is(err, db.ErrNotFound) {
		t.Fatalf("deleting another user's log err = %v", err)
	}
	got, err := db.SoftDeleteLog(ctx, database.Pool, u.ID, act.ID)
	if err != nil || got.Kind != db.KindActivity || got.LocalDate != day {
		t.Fatalf("delete activity = %+v %v", got, err)
	}
	got, err = db.SoftDeleteLog(ctx, database.Pool, u.ID, meal.ID)
	if err != nil || got.Kind != db.KindMeal || got.LocalDate != day.AddDays(-1) {
		t.Fatalf("delete meal = %+v %v", got, err)
	}
	if _, err := db.SoftDeleteLog(ctx, database.Pool, u.ID, meal.ID); !errors.Is(err, db.ErrNotFound) {
		t.Fatalf("second delete err = %v", err)
	}
}

func TestRecentMealsAreDistinctAcrossBothUsers(t *testing.T) {
	database := dbtest.Fresh(t)
	nick := join(t, database, "Nick", "green", true)
	nadia := join(t, database, "Nadia", "sky", false)

	n := 0
	add := func(u db.User, name string, kcal int, protein float64) db.MealLog {
		n++
		m, _, err := db.InsertMealLog(ctx, database.Pool, db.NewMealLog{
			UserID: u.ID, LocalDate: day, Name: name, Kcal: kcal, ProteinG: protein, ClientOpID: fmt.Sprintf(opID, n)})
		if err != nil {
			t.Fatal(err)
		}
		time.Sleep(2 * time.Millisecond)
		return m
	}
	add(nick, "Chili", 600, 40)
	add(nadia, "chili", 600, 40)
	add(nick, "Chili", 700, 40)
	gone := add(nick, "Salad", 200, 5)
	newest := add(nadia, "Rice", 300, 6)
	if _, err := db.SoftDeleteLog(ctx, database.Pool, nick.ID, gone.ID); err != nil {
		t.Fatal(err)
	}

	meals, err := db.RecentMeals(ctx, database.Pool, 10)
	if err != nil {
		t.Fatal(err)
	}
	if len(meals) != 3 {
		t.Fatalf("recent = %d meals, want 3 distinct (chili 600, chili 700, rice): %+v", len(meals), meals)
	}
	if meals[0].ID != newest.ID {
		t.Fatalf("newest first: got %q", meals[0].Name)
	}
	for _, m := range meals {
		if m.Name == "Salad" {
			t.Fatal("a deleted meal must not be suggested")
		}
	}
	if limited, _ := db.RecentMeals(ctx, database.Pool, 2); len(limited) != 2 {
		t.Fatalf("limit ignored: %d", len(limited))
	}
}
