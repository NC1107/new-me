//go:build live

package estimate

import (
	"context"
	"fmt"
	"os"
	"testing"

	"github.com/nc1107/new-me/server/internal/anthropic"
)

// Run by hand with a real Claude key:
// NEWME_ANTHROPIC_API_KEY=... go test -tags live -run TestLiveSavedFoods -v ./internal/estimate
// The household's saved foods are the ones production had on 2026-10-31.
func TestLiveSavedFoods(t *testing.T) {
	key := os.Getenv("NEWME_ANTHROPIC_API_KEY")
	if key == "" {
		t.Skip("NEWME_ANTHROPIC_API_KEY is not set")
	}
	library := fakeLibrary{[]LibraryFood{
		{ID: 9, Name: "Dave's Killer Bread", Brand: "Dave's Killer Bread", ServingText: "1 slice (37 g)", ServingGrams: 37, N: Nutrients{Kcal: 90, Protein: 4, Fat: 1}, Source: SourceUSDA},
		{ID: 20, Name: "Fried Eggs", ServingText: "1 medium (55 g)", ServingGrams: 55, N: Nutrients{Kcal: 102, Protein: 6.4, Fat: 8.3}, Source: SourceUSDA},
		{ID: 15, Name: "Egg Bites", ServingText: "1 serving", N: Nutrients{Kcal: 276, Protein: 21.1}, Source: SourceEstimated},
		{ID: 5, Name: "Chobani Yogurt Drink", Brand: "Chobani", ServingText: "1 bottle (207 g)", ServingGrams: 207, N: Nutrients{Kcal: 149, Protein: 10}, Source: SourceUSDA},
		{ID: 16, Name: "Huel Essential Vanilla Flavor", Brand: "Huel", ServingText: "1 scoop (51 g)", ServingGrams: 51, N: Nutrients{Kcal: 200, Protein: 25}, Source: SourceUSDA},
	}}
	e := &Estimator{Client: anthropic.New(key, ""), Foods: NewFoods(os.Getenv("NEWME_USDA_API_KEY"), "live"), Library: library}
	for _, text := range []string{
		"2 slices of daves bread toasted and 2 fried eggs",
		"my huel shake with 2 scoops",
		"a chobani drink and some egg bites",
		"2 slices of white toast",
		"2 pieces of buttered toast",
		"a bagel with cream cheese",
		"toast with peanut butter",
	} {
		m, err := e.Meal(context.Background(), text)
		if err != nil {
			t.Fatalf("%s: %v", text, err)
		}
		fmt.Printf("\n%s -> %d kcal\n", text, m.Total.Kcal)
		for _, r := range m.Items {
			fmt.Printf("  %-28q %-10s %-4s %-40q kcal=%d\n", r.Text, r.Source, r.SourceID, r.MatchedName, r.Kcal)
		}
	}
}
