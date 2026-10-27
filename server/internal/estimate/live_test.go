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
