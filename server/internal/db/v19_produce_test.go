package db_test

import (
	"fmt"
	"testing"

	"github.com/nc1107/new-me/server/internal/db"
	"github.com/nc1107/new-me/server/internal/dbtest"
)

func TestProduceInsideMealsCountsAlongsideLoggedServings(t *testing.T) {
	database := dbtest.Fresh(t)
	u := join(t, database, "Nick", "green", true)
	meal := func(n int, produce, juice, pulse float64) {
		t.Helper()
		if _, _, err := db.InsertMealLog(ctx, database.Pool, db.NewMealLog{
			UserID: u.ID, LocalDate: day, Name: fmt.Sprintf("meal %d", n), Kcal: 300,
			ProduceG: produce, JuiceG: juice, PulseG: pulse, ClientOpID: fmt.Sprintf(opID, 300+n)}); err != nil {
			t.Fatal(err)
		}
	}
	// 100 g and 70 g of whole produce pool to 170 g. 450 g of juice and 300 g of beans count one
	// serving each, so 170 + 80 + 80 = 330 g, which is 4 servings.
	meal(1, 100, 250, 0)
	meal(2, 70, 200, 300)
	if _, _, err := db.InsertActivityLog(ctx, database.Pool, db.NewActivityLog{
		UserID: u.ID, LocalDate: day, Type: db.ActivityProduce, Quantity: 1, ClientOpID: fmt.Sprintf(opID, 400)}); err != nil {
		t.Fatal(err)
	}
	in, err := db.LoadDayInputs(ctx, database.Pool, u.ID, day)
	if err != nil {
		t.Fatal(err)
	}
	if in.ProduceFromMeals != 4 || in.ProduceLogged != 1 || in.ProduceServings != 5 {
		t.Fatalf("from meals %d, logged %d, total %d; want 4, 1 and 5", in.ProduceFromMeals, in.ProduceLogged, in.ProduceServings)
	}
}

func TestAMealWithoutProduceAddsNoServings(t *testing.T) {
	database := dbtest.Fresh(t)
	u := join(t, database, "Nick", "green", true)
	if _, _, err := db.InsertMealLog(ctx, database.Pool, db.NewMealLog{
		UserID: u.ID, LocalDate: day, Name: "Chicken", Kcal: 400, ClientOpID: fmt.Sprintf(opID, 500)}); err != nil {
		t.Fatal(err)
	}
	in, err := db.LoadDayInputs(ctx, database.Pool, u.ID, day)
	if err != nil {
		t.Fatal(err)
	}
	if in.ProduceServings != 0 {
		t.Fatalf("servings %d, want 0", in.ProduceServings)
	}
}

func TestADeletedMealNoLongerCountsItsProduce(t *testing.T) {
	database := dbtest.Fresh(t)
	u := join(t, database, "Nick", "green", true)
	log, _, err := db.InsertMealLog(ctx, database.Pool, db.NewMealLog{
		UserID: u.ID, LocalDate: day, Name: "Salad", Kcal: 200, ProduceG: 240, ClientOpID: fmt.Sprintf(opID, 600)})
	if err != nil {
		t.Fatal(err)
	}
	in, _ := db.LoadDayInputs(ctx, database.Pool, u.ID, day)
	if in.ProduceServings != 3 {
		t.Fatalf("servings %d, want 3", in.ProduceServings)
	}
	if _, err := db.SoftDeleteLog(ctx, database.Pool, u.ID, log.ID); err != nil {
		t.Fatal(err)
	}
	in, _ = db.LoadDayInputs(ctx, database.Pool, u.ID, day)
	if in.ProduceServings != 0 {
		t.Fatalf("servings after delete %d, want 0", in.ProduceServings)
	}
}
