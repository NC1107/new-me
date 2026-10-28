package db_test

import (
	"strings"
	"testing"

	"github.com/nc1107/new-me/server/internal/db"
	"github.com/nc1107/new-me/server/internal/dbtest"
)

func TestTidyFoodNamesRunsOnceAndSparesTypedNames(t *testing.T) {
	database := dbtest.Fresh(t)
	nick := join(t, database, "Nick", "blue", true)
	save := func(name, brand, source, sourceID string) db.Food {
		t.Helper()
		f, err := db.InsertFood(ctx, database.Pool, db.Food{
			Name: name, Brand: brand, ServingText: "1 serving", Kcal: 100, Source: source, SourceID: sourceID,
			Servings: []db.FoodServing{},
		}, nick.ID)
		if err != nil {
			t.Fatalf("insert %s: %v", name, err)
		}
		return f
	}
	pizza := save("Totino's Cheese Party Pizza", "Totino's GENERAL MILLS SALES INC.", "usda", "1")
	typed := save("Shouting Pizza", "Totino's GENERAL MILLS SALES INC.", "manual", "")

	tidy := func(name, brand string) (string, string) {
		return name, strings.TrimSuffix(brand, " GENERAL MILLS SALES INC.")
	}
	changed, err := database.TidyFoodNames(ctx, tidy)
	if err != nil || changed != 1 {
		t.Fatalf("first run changed %d, err %v; want 1", changed, err)
	}
	got, _ := db.GetFood(ctx, database.Pool, pizza.ID)
	if got.Brand != "Totino's" {
		t.Errorf("brand = %q, want Totino's", got.Brand)
	}
	same, _ := db.GetFood(ctx, database.Pool, typed.ID)
	if same.Brand != typed.Brand {
		t.Errorf("typed food changed to %q", same.Brand)
	}

	edited := got
	edited.Brand = "Totino's GENERAL MILLS SALES INC."
	if _, err := db.UpdateFood(ctx, database.Pool, edited); err != nil {
		t.Fatal(err)
	}
	changed, err = database.TidyFoodNames(ctx, tidy)
	if err != nil || changed != 0 {
		t.Fatalf("second run changed %d, err %v; want 0", changed, err)
	}
}
