package estimate

import "testing"

func TestTidyServing(t *testing.T) {
	for in, want := range map[string]string{
		"1 serving (1 serving)":           "1 serving",
		"1 POUCH RECONSTITUTED TO 2 CUPS": "1 pouch reconstituted to 2 cups",
		"1 stick (32 g)":                  "1 stick (32 g)",
		"1 cup, chopped (140 g)":          "1 cup, chopped (140 g)",
		"100 g":                           "100 g",
		"  1  slice   (28 g) ":            "1 slice (28 g)",
		"1 Pizza (278 g)":                 "1 Pizza (278 g)",
	} {
		if got := tidyServing(in); got != want {
			t.Errorf("tidyServing(%q) = %q, want %q", in, got, want)
		}
	}
}

func TestSearchPutsSubstitutesBelowTheFood(t *testing.T) {
	it := Item{Food: "chicken"}
	real, _ := scoreFood(it, Food{Name: "Chicken, ground, raw"})
	fake, _ := scoreFood(it, Food{Name: "Chicken, meatless"})
	if searchScore(it, fake) >= searchScore(it, real) {
		t.Fatalf("meatless %v should rank below ground %v", searchScore(it, fake), searchScore(it, real))
	}
	asked := Item{Food: "meatless chicken"}
	m, _ := scoreFood(asked, Food{Name: "Chicken, meatless"})
	if searchScore(asked, m) != m.Score {
		t.Fatal("a substitute the query asks for is not lowered")
	}
}
