//go:build live

package estimate

import (
	"context"
	"encoding/json"
	"fmt"
	"os"
	"strings"
	"testing"
)

// Run by hand: go test -tags live -run TestLive -v ./internal/estimate
// It calls the real USDA and Open Food Facts services, using NEWME_USDA_API_KEY or DEMO_KEY.
// The split step is replaced by fixed items, so no Claude key is needed; items no database
// knows come back with zero numbers instead of an estimate.
func TestLiveNicksExample(t *testing.T) {
	foods := NewFoods(os.Getenv("NEWME_USDA_API_KEY"), "live")
	e := &Estimator{Foods: foods}
	items := []Item{
		{Text: "an apple", Label: "Apple", Food: "apple, raw", Quantity: 1, Unit: "medium", Kind: KindGeneric},
		{Text: "a chomp meat stick", Label: "Chomps stick", Food: "original beef stick", Brand: "Chomps", Quantity: 1, Unit: "stick", Kind: KindBranded},
		{Text: "a hotpocket", Label: "Hot Pocket", Food: "pepperoni pizza", Brand: "Hot Pockets", Quantity: 1, Unit: "piece", Kind: KindBranded},
		{Text: "1 medium apple", Label: "Apple", Food: "apple, raw", Quantity: 1, Unit: "medium", Kind: KindGeneric},
	}
	results := make([]ItemResult, len(items))
	for i, it := range items {
		results[i], _ = e.item(context.Background(), it, nil)
	}
	raw, _ := json.MarshalIndent(assemble(results[:3]), "", "  ")
	fmt.Println(string(raw))
	for _, r := range results {
		fmt.Printf("%-22s %-14s %-10s %-45q kcal=%d grams=%v conf=%s\n", r.Text, r.Source, r.SourceID, r.MatchedName, r.Kcal, r.Grams, r.Confidence)
	}
}

// Run by hand: go test -tags live -run TestLiveSearchDefaults -v ./internal/estimate
func TestLiveSearchDefaults(t *testing.T) {
	foods := NewFoods(os.Getenv("NEWME_USDA_API_KEY"), "live")
	for _, q := range []string{"chicken", "milk", "potato", "coffee", "bread", "yogurt", "beef", "eggs", "chicken breast"} {
		fmt.Println("==", q)
		for _, f := range foods.SearchRemote(context.Background(), q) {
			v := f.Serving()
			fmt.Printf("   %-50s %-14s %s %.0f kcal\n", f.Name, f.DataType, v.Text, v.N.Kcal)
		}
	}
}

// Run by hand after any matching change:
// NEWME_USDA_API_KEY=... go test -tags live -run TestLiveCorpus -v ./internal/estimate
// Each everyday food, worded as the split step words it, must land on the named USDA row with a
// believable amount. An empty row means no row names it and the item is estimated, which is
// expected for those foods today. Expectations were checked against live USDA on 2026-10-28.
func TestLiveCorpus(t *testing.T) {
	foods := NewFoods(os.Getenv("NEWME_USDA_API_KEY"), "live")
	foods.OFF = nil
	e := &Estimator{Foods: foods}
	cases := []struct {
		food     string
		qty      float64
		unit     string
		row      string
		min, max int
	}{
		{"whole milk", 12, "fl oz", "Milk, whole", 200, 250},
		{"milk, 2%", 1, "cup", "Milk, reduced fat (2%)", 110, 135},
		{"salmon, baked", 5, "oz", "Fish, salmon, baked or broiled", 280, 420},
		{"chicken breast, grilled", 6, "oz", "Chicken breast, grilled", 250, 380},
		{"chicken breast", 1, "serving", "Chicken breast, NS as to cooking method", 150, 300},
		{"broccoli, steamed", 1, "cup", "", 0, 0},
		{"sour cream", 2, "tbsp", "Cream, sour", 40, 70},
		{"oatmeal, cooked", 1, "cup", "Oatmeal, any kind", 140, 200},
		{"coffee, black", 1, "cup", "Coffee, any kind", 0, 10},
		{"scrambled eggs", 2, "large", "Egg, whole, cooked, scrambled", 150, 220},
		{"egg, fried", 1, "large", "Egg, whole", 80, 110},
		{"bacon, cooked", 3, "slice", "Bacon", 60, 140},
		{"bagel, plain", 1, "medium", "Bagels, plain", 220, 300},
		{"cream cheese", 2, "tbsp", "Cheese, cream", 80, 110},
		{"banana", 1, "medium", "Bananas, raw", 95, 115},
		{"strawberries", 1, "cup", "Strawberries, raw", 45, 80},
		{"grapes", 1, "cup", "Grapes, raw", 100, 130},
		{"carrots, raw", 1, "medium", "Carrots, raw", 20, 30},
		{"potato, baked", 1, "medium", "Potato, baked", 160, 300},
		{"french fries", 1, "medium", "Potato, french fries, restaurant", 350, 480},
		{"white rice, cooked", 1, "cup", "Rice, white, cooked", 190, 250},
		{"brown rice, cooked", 1, "cup", "Rice, brown, cooked", 210, 260},
		{"marinara sauce", 0.5, "cup", "marinara", 25, 90},
		{"black beans", 0.5, "cup", "Black beans", 100, 180},
		{"tortilla, flour", 1, "medium", "Tortilla, flour", 120, 160},
		{"cheddar cheese, shredded", 0.25, "cup", "Cheese, cheddar", 100, 125},
		{"mozzarella cheese", 1, "oz", "Cheese, Mozzarella", 70, 95},
		{"greek yogurt, plain, nonfat", 1, "cup", "Yogurt, Greek, nonfat milk, plain", 130, 160},
		{"almond milk, unsweetened", 1, "cup", "Almond milk, unsweetened", 30, 45},
		{"orange juice", 8, "fl oz", "Orange juice", 105, 125},
		{"beer", 12, "fl oz", "Beer", 140, 170},
		{"red wine", 5, "fl oz", "Wine, red", 115, 135},
		{"cola", 12, "fl oz", "Soft drink, cola", 140, 170},
		{"almonds", 1, "oz", "Almonds, NFS", 160, 175},
		{"peanut butter", 2, "tbsp", "Peanut butter", 180, 200},
		{"avocado", 0.5, "whole", "Avocado, raw", 100, 130},
		{"tuna, canned in water", 1, "can", "Fish, tuna", 150, 250},
		{"shrimp, cooked", 4, "oz", "shrimp, cooked", 90, 140},
		{"lettuce, romaine", 2, "cup", "Romaine lettuce, raw", 10, 20},
		{"tomato, raw", 1, "medium", "Tomatoes, raw", 15, 30},
		{"olive oil", 1, "tbsp", "Olive oil", 115, 130},
		{"honey", 1, "tbsp", "Honey", 60, 70},
		{"hamburger", 1, "each", "Hamburger", 250, 550},
		{"apple, raw", 1, "medium", "Apple", 90, 130},
		{"butter", 1, "tbsp", "Butter", 95, 110},
		{"beer", 12, "oz", "Beer", 140, 170},
	}
	for _, c := range cases {
		it := Item{Text: c.food, Label: c.food, Food: c.food, Quantity: c.qty, Unit: c.unit, Kind: KindGeneric}
		r, _ := e.item(context.Background(), it, nil)
		switch {
		case c.row == "" && r.Source != SourceEstimated:
			t.Errorf("%s: expected no row, got %q", c.food, r.MatchedName)
		case c.row != "" && (!strings.Contains(strings.ToLower(r.MatchedName), strings.ToLower(c.row)) || r.Kcal < c.min || r.Kcal > c.max):
			t.Errorf("%s %v %s: got %q %d kcal (%.0f g), want %q %d to %d kcal", c.food, c.qty, c.unit, r.MatchedName, r.Kcal, r.Grams, c.row, c.min, c.max)
		}
	}
}
