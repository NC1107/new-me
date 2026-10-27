package estimate

import (
	"reflect"
	"testing"
)

func ptrf(v float64) *float64 { return &v }

func TestTokensSingularizeAndDropFiller(t *testing.T) {
	got := tokens("Apples, raw, with skin (Jack Link's)")
	want := []string{"apple", "raw", "skin", "jack", "link"}
	if !reflect.DeepEqual(got, want) {
		t.Fatalf("tokens = %v, want %v", got, want)
	}
}

func TestScoringPrefersTheRightFoodAndRejectsOtherBrands(t *testing.T) {
	rose := Food{Name: "Rose-apples, raw", DataType: typeSRLegacy}
	plain := Food{Name: "Apples, raw, with skin", DataType: typeSRLegacy}
	fuji := Food{Name: "Apples, fuji, with skin, raw", DataType: typeFoundation}
	other := Food{Name: "Orange juice, raw", DataType: typeSRLegacy}
	best, ok := pickBest(Item{Food: "apple, raw"}, []Food{rose, fuji, other, plain})
	if !ok || best.Food.Name != plain.Name {
		t.Fatalf("best = %+v ok=%v", best, ok)
	}
	if _, ok := pickBest(Item{Food: "apple, raw"}, []Food{other}); ok {
		t.Fatal("an unrelated food must not match")
	}

	jack := Food{Name: "Original beef stick", Brand: "JACK LINK'S", DataType: typeBranded}
	chomps := Food{Name: "Original Beef Stick", Brand: "Chomps"}
	it := Item{Food: "original beef stick", Brand: "Chomps", Kind: KindBranded}
	best, ok = pickBest(it, []Food{jack, chomps})
	if !ok || best.Food.Brand != "Chomps" {
		t.Fatalf("best = %+v", best)
	}
	if _, ok := pickBest(it, []Food{jack}); ok {
		t.Fatal("a different brand must never match")
	}
	if _, ok := scoreFood(Item{Food: "pepperoni pizza", Brand: "Hot Pockets"}, Food{Name: "Pepperoni Pizza", Brand: "Hot Pockets"}); !ok {
		t.Fatal("brand plural must match")
	}
}

func TestDataTypePreferenceBreaksTies(t *testing.T) {
	branded := Food{Name: "Banana", DataType: typeBranded}
	sr := Food{Name: "Banana", DataType: typeSRLegacy}
	best, _ := pickBest(Item{Food: "banana"}, []Food{branded, sr})
	if best.Food.DataType != typeSRLegacy {
		t.Fatalf("best = %+v", best.Food)
	}
}

func TestConfidenceCombinesMatchAndUnit(t *testing.T) {
	cases := []struct {
		recall float64
		b      basis
		want   string
	}{{1, basisExact, "high"}, {1, basisGuess, "medium"}, {0.8, basisExact, "medium"}, {0.5, basisExact, "low"}}
	for _, tc := range cases {
		if got := confidenceFor(match{Recall: tc.recall}, tc.b); got != tc.want {
			t.Errorf("%+v = %s, want %s", tc, got, tc.want)
		}
	}
}

func TestResolveConvertsUnits(t *testing.T) {
	per100 := &Nutrients{Kcal: 200, Protein: 10, Carbs: 20, Fat: 5, Fiber: 2}
	food := Food{Per100g: per100, Portions: []Portion{{Label: `medium (3" dia)`, Grams: 182}, {Label: "cup slices", Grams: 109}}}
	cases := []struct {
		name  string
		food  Food
		item  Item
		kcal  float64
		grams float64
		basis basis
		ok    bool
	}{
		{"grams", food, Item{Quantity: 150, Unit: "g"}, 300, 150, basisExact, true},
		{"ounces", food, Item{Quantity: 2, Unit: "oz"}, 113.4, 56.7, basisExact, true},
		{"portion by size word", food, Item{Quantity: 2, Unit: "medium"}, 728, 364, basisExact, true},
		{"portion by alias", Food{Per100g: per100, Portions: []Portion{{Label: "tablespoon", Grams: 15}}}, Item{Quantity: 2, Unit: "tbsp"}, 60, 30, basisExact, true},
		{"cup needs a portion", Food{Per100g: per100}, Item{Quantity: 1, Unit: "cup"}, 0, 0, basisGuess, false},
		{"cup with parsed grams", Food{Per100g: per100}, Item{Quantity: 1, Unit: "cup", Grams: ptrf(240)}, 480, 240, basisGuess, true},
		{"unknown size word guesses the first portion", food, Item{Quantity: 1, Unit: "huge"}, 364, 182, basisGuess, true},
		{"label serving", Food{PerServing: &Nutrients{Kcal: 90, Protein: 10}, ServingGrams: 32}, Item{Quantity: 2, Unit: "stick"}, 180, 64, basisExact, true},
		{"label serving without weight", Food{PerServing: &Nutrients{Kcal: 90}}, Item{Quantity: 1, Unit: "serving"}, 90, 0, basisExact, true},
		{"label serving by grams from per serving only", Food{PerServing: &Nutrients{Kcal: 90}, ServingGrams: 30}, Item{Quantity: 60, Unit: "g"}, 180, 60, basisExact, true},
		{"serving weight with per 100 g", Food{Per100g: per100, ServingGrams: 40}, Item{Quantity: 1, Unit: "serving"}, 80, 40, basisExact, true},
		{"nothing to convert with", Food{Per100g: per100}, Item{Quantity: 1, Unit: "serving"}, 0, 0, basisGuess, false},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			got, ok := resolve(tc.food, tc.item)
			if ok != tc.ok {
				t.Fatalf("ok = %v, want %v (%+v)", ok, tc.ok, got)
			}
			if !ok {
				return
			}
			if diff := got.N.Kcal - tc.kcal; diff > 0.01 || diff < -0.01 || got.Grams < tc.grams-0.01 || got.Grams > tc.grams+0.01 || got.Basis != tc.basis {
				t.Fatalf("got %+v, want kcal %v grams %v basis %v", got, tc.kcal, tc.grams, tc.basis)
			}
		})
	}
}

func TestPortionFromLabelDividesByTheAmount(t *testing.T) {
	cases := []struct {
		label string
		grams float64
		want  Portion
		ok    bool
	}{
		{"2 tbsp", 30, Portion{"tbsp", 15}, true},
		{"1 stick (50 g)", 50, Portion{"stick (50 g)", 50}, true},
		{"1/2 cup", 60, Portion{"cup", 120}, true},
		{"1 1/2 cup", 180, Portion{"cup", 120}, true},
		{"sandwich", 120, Portion{"sandwich", 120}, true},
		{"", 10, Portion{}, false},
		{"1 cup", 0, Portion{}, false},
	}
	for _, tc := range cases {
		got, ok := portionFromLabel(tc.label, tc.grams)
		if ok != tc.ok || (ok && got != tc.want) {
			t.Errorf("%q: got %+v %v, want %+v %v", tc.label, got, ok, tc.want, tc.ok)
		}
	}
}
