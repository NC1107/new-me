//go:build live

package estimate

import (
	"context"
	"encoding/json"
	"fmt"
	"os"
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

// Run by hand: go test -tags live -run TestLiveCommonFoods -v ./internal/estimate
// Each line should name the food itself with a believable weight for the amount.
func TestLiveCommonFoods(t *testing.T) {
	foods := NewFoods(os.Getenv("NEWME_USDA_API_KEY"), "live")
	e := &Estimator{Foods: foods}
	for _, it := range []Item{
		{Food: "whole milk", Quantity: 12, Unit: "fl oz"},
		{Food: "milk, whole", Quantity: 12, Unit: "oz"},
		{Food: "2% milk", Quantity: 1, Unit: "cup"},
		{Food: "skim milk", Quantity: 1, Unit: "cup"},
		{Food: "apple, raw", Quantity: 1, Unit: "medium"},
		{Food: "gala apple", Quantity: 1, Unit: "medium"},
		{Food: "banana", Quantity: 1, Unit: "medium"},
		{Food: "egg, scrambled", Quantity: 2, Unit: "large"},
		{Food: "egg, hard boiled", Quantity: 2, Unit: "large"},
		{Food: "chicken breast, grilled", Quantity: 6, Unit: "oz"},
		{Food: "ground beef 93/7, cooked", Quantity: 4, Unit: "oz"},
		{Food: "white rice, cooked", Quantity: 1, Unit: "cup"},
		{Food: "oatmeal, cooked", Quantity: 1, Unit: "cup"},
		{Food: "peanut butter", Quantity: 2, Unit: "tbsp"},
		{Food: "whole wheat bread", Quantity: 2, Unit: "slice"},
		{Food: "broccoli, steamed", Quantity: 1, Unit: "cup"},
		{Food: "salmon, baked", Quantity: 5, Unit: "oz"},
		{Food: "cheddar cheese", Quantity: 1, Unit: "slice"},
		{Food: "greek yogurt, plain", Quantity: 1, Unit: "cup"},
		{Food: "orange juice", Quantity: 8, Unit: "fl oz"},
		{Food: "coffee, black", Quantity: 1, Unit: "cup"},
		{Food: "olive oil", Quantity: 1, Unit: "tbsp"},
		{Food: "butter", Quantity: 1, Unit: "tbsp"},
		{Food: "sweet potato, baked", Quantity: 1, Unit: "medium"},
		{Food: "avocado", Quantity: 0.5, Unit: "whole"},
		{Food: "almonds", Quantity: 1, Unit: "oz"},
		{Food: "pasta, cooked", Quantity: 2, Unit: "cup"},
		{Food: "cottage cheese", Quantity: 0.5, Unit: "cup"},
		{Food: "beer", Quantity: 12, Unit: "fl oz"},
		{Food: "orange", Quantity: 1, Unit: "medium"},
	} {
		it.Text, it.Label, it.Kind = it.Food, it.Food, KindGeneric
		r, _ := e.item(context.Background(), it, nil)
		fmt.Printf("%-26s %4.4g %-6s -> %-8s %-60q kcal=%d g=%.0f %s\n", it.Food, it.Quantity, it.Unit, r.SourceID, r.MatchedName, r.Kcal, r.Grams, r.Confidence)
	}
}
