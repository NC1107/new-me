package estimate

import (
	"reflect"
	"testing"
)

func ptrf(v float64) *float64 { return &v }

func TestTokensMeetTheirPlurals(t *testing.T) {
	for _, pair := range [][2]string{{"Tomatoes", "tomato"}, {"Strawberries", "strawberry"}, {"Apples", "apple"}, {"Potatoes", "potato"}} {
		if a, b := tokens(pair[0]), tokens(pair[1]); !reflect.DeepEqual(a, b) {
			t.Errorf("%q = %v, %q = %v", pair[0], a, pair[1], b)
		}
	}
	if got := tokens("Swiss glass"); !reflect.DeepEqual(got, []string{"swiss", "glass"}) {
		t.Errorf("double s = %v", got)
	}
}

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
	partial := Food{Name: "PEPPERONI PLANT BASED PIZZA POCKET PIES", Brand: "DEL MONTE Del Monte Foods Inc.", DataType: typeBranded}
	if _, ok := scoreFood(Item{Food: "pepperoni pizza", Brand: "Hot Pockets"}, partial); ok {
		t.Fatal("a brand that matches only some of its words is a different brand")
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
	food := Food{Source: SourceUSDA, Per100g: per100, Portions: []Portion{{Label: `medium (3" dia)`, Grams: 182}, {Label: "cup slices", Grams: 109}}}
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

func TestUSDANoteInParenthesesDoesNotCountAgainstTheName(t *testing.T) {
	f := decodeUSDA(171688, "Apples, raw, with skin (Includes foods for USDA's Food Distribution Program)", nutrients(52, 0.3, 13.8, 0.2, 2.4, srIDs))
	food, ok := f.toFood()
	if !ok || food.Name != "Apples, raw, with skin" {
		t.Fatalf("name = %q", food.Name)
	}
}

// The rows below are real USDA search results captured on 2026-10-27, in the order USDA
// returned them, so the ranking is checked against what production will see.
func TestRankingOnCapturedUSDAResults(t *testing.T) {
	apples := []Food{
		{ID: "168171", Name: "Rose-apples, raw", DataType: typeSRLegacy},
		{ID: "1750340", Name: "Apples, fuji, with skin, raw", DataType: typeFoundation},
		{ID: "1750341", Name: "Apples, gala, with skin, raw", DataType: typeFoundation},
		{ID: "171689", Name: "Apples, raw, without skin", DataType: typeSRLegacy},
		{ID: "169909", Name: "Mammy-apple, (mamey), raw", DataType: typeSRLegacy},
		{ID: "168202", Name: "Apples, raw, golden delicious, with skin", DataType: typeSRLegacy},
		{ID: "171725", Name: "Custard-apple, (bullock's-heart), raw", DataType: typeSRLegacy},
		{ID: "171688", Name: "Apples, raw, with skin", DataType: typeSRLegacy},
		{ID: "167782", Name: "Abiyuch, raw", DataType: typeSRLegacy},
	}
	best, ok := pickBest(Item{Food: "apple, raw"}, apples)
	if !ok || best.Food.ID != "171688" {
		t.Fatalf("apple = %+v", best.Food)
	}

	pockets := []Food{
		{ID: "2775462", Name: "HOT POCKETS Pepperoni Pizza 4 oz. Sandwich", Brand: "HOT POCKETS Société des Produits Nestlé S.A.", DataType: typeBranded},
		{ID: "2290824", Name: "TOFURKY, POCKETS SANDWICHES, PEPPERONI PIZZA", Brand: "TOFURKY Turtle Island Foods, Inc.", DataType: typeBranded},
		{ID: "2372974", Name: "PEPPERONI PLANT BASED PIZZA POCKET PIES, PEPPERONI", Brand: "DEL MONTE Del Monte Foods Inc.", DataType: typeBranded},
		{ID: "2165137", Name: "PEPPERONI PIZZA, PEPPERONI", Brand: "ORV'S Bernatello's Pizza, Inc.", DataType: typeBranded},
	}
	best, ok = pickBest(Item{Food: "pepperoni pizza", Brand: "Hot Pockets", Kind: KindBranded}, pockets)
	if !ok || best.Food.ID != "2775462" {
		t.Fatalf("hot pocket = %+v", best.Food)
	}
	if _, ok := pickBest(Item{Food: "pepperoni pizza", Brand: "Hot Pockets"}, pockets[1:]); ok {
		t.Fatal("without a Hot Pockets row nothing may match")
	}

	sticks := []Food{
		{ID: "1997336", Name: "ORIGINAL BEEF STICK, ORIGINAL", Brand: "JACK LINK'S Link Snacks, Inc.", DataType: typeBranded},
		{ID: "2664594", Name: "ORIGINAL BEEF STICK, ORIGINAL", Brand: "COUNTRY ARCHER JERKY CO. S&E Gourmet Cuts Inc.", DataType: typeBranded},
	}
	if _, ok := pickBest(Item{Food: "original beef stick", Brand: "Chomps"}, sticks); ok {
		t.Fatal("another brand's beef stick must never answer for Chomps")
	}
}

// Real USDA rows captured on 2026-10-28 for "whole milk", which picked mozzarella and logged
// 12 oz of milk as 1017 kcal.
func TestRankingFindsTheFoodNotWhatIsMadeFromIt(t *testing.T) {
	milk := []Food{
		{ID: "170845", Name: "Cheese, mozzarella, whole milk", DataType: typeSRLegacy},
		{ID: "746766", Name: "Cheese, ricotta, whole milk", DataType: typeFoundation},
		{ID: "172225", Name: "Milk, buttermilk, fluid, whole", DataType: typeSRLegacy},
		{ID: "171284", Name: "Yogurt, plain, whole milk", DataType: typeSRLegacy},
		{ID: "170876", Name: "Milk, dry, whole, with added vitamin D", DataType: typeSRLegacy},
		{ID: "2705385", Name: "Milk, whole", DataType: typeSurvey},
		{ID: "2705399", Name: "Milk, evaporated, whole", DataType: typeSurvey},
		{ID: "2705467", Name: "Chocolate milk, whole", DataType: typeSurvey},
	}
	for _, q := range []string{"whole milk", "milk, whole"} {
		if best, ok := pickBest(Item{Food: q}, milk); !ok || best.Food.ID != "2705385" {
			t.Errorf("%q = %+v", q, best.Food)
		}
	}
	if _, ok := pickBest(Item{Food: "whole milk"}, milk[:2]); ok {
		t.Error("a cheese made from whole milk must never answer for milk")
	}

	avocado := []Food{
		{ID: "2710208", Name: "Avocado dressing", DataType: typeSurvey},
		{ID: "2709223", Name: "Avocado, raw", DataType: typeSurvey},
		{ID: "171706", Name: "Avocados, raw, California", DataType: typeSRLegacy},
	}
	if best, _ := pickBest(Item{Food: "avocado"}, avocado); best.Food.ID != "2709223" {
		t.Errorf("avocado = %+v", best.Food)
	}

	almonds := []Food{
		{ID: "2707533", Name: "Almond butter", DataType: typeSurvey},
		{ID: "2707490", Name: "Almonds, flavored", DataType: typeSurvey},
		{ID: "2707485", Name: "Almonds, NFS", DataType: typeSurvey},
		{ID: "170567", Name: "Nuts, almonds", DataType: typeSRLegacy},
	}
	if best, _ := pickBest(Item{Food: "almonds"}, almonds); best.Food.ID != "2707485" {
		t.Errorf("almonds = %+v", best.Food)
	}

	skim := []Food{
		{ID: "170887", Name: "Yogurt, plain, skim milk", DataType: typeSRLegacy},
		{ID: "2705388", Name: "Milk, fat free (skim)", DataType: typeSurvey},
	}
	if best, _ := pickBest(Item{Food: "skim milk"}, skim); best.Food.ID != "2705388" {
		t.Errorf("skim milk = %+v", best.Food)
	}
}

func TestResolveConvertsVolumesThroughAVolumePortion(t *testing.T) {
	per100 := &Nutrients{Kcal: 47}
	juice := Food{Source: SourceUSDA, Per100g: per100, Portions: []Portion{{Label: "can (6 fl oz)", Grams: 187}, {Label: "cup (8 fl oz)", Grams: 249}}}
	got, ok := resolve(juice, Item{Quantity: 8, Unit: "fl oz"})
	if !ok || got.Grams < 248 || got.Grams > 250 || got.Basis != basisExact {
		t.Fatalf("8 fl oz = %+v %v, want the cup's 249 g", got, ok)
	}
	if _, ok := resolve(Food{Source: SourceUSDA, Per100g: per100, Portions: []Portion{{Label: "medium", Grams: 180}}}, Item{Quantity: 8, Unit: "fl oz"}); ok {
		t.Fatal("a volume must not take the weight of a measure that is not a volume")
	}
	butter := Food{Source: SourceUSDA, Per100g: per100, Portions: []Portion{{Label: `pat (1" sq, 1/3" high)`, Grams: 5}, {Label: "tbsp", Grams: 14.2}}}
	if got, _ := resolve(butter, Item{Quantity: 1, Unit: "tbsp"}); got.Grams != 14.2 {
		t.Fatalf("1 tbsp of butter = %v g", got.Grams)
	}
	avocado := Food{Name: "Avocado, raw", Source: SourceUSDA, DataType: typeSurvey, Per100g: per100,
		Portions: []Portion{{Label: "slice", Grams: 15}, {Label: "fruit", Grams: 150}}}
	if got, _ := resolve(avocado, Item{Quantity: 0.5, Unit: "whole"}); got.Grams != 75 || got.Basis != basisExact {
		t.Fatalf("half an avocado = %+v", got)
	}
}

// A sandwich logged without amounts once took a cup of mayonnaise, the food's first measure.
func TestAServingWithoutALabelUsesTheSurveyUnspecifiedAmount(t *testing.T) {
	per100 := &Nutrients{Kcal: 680}
	mayo := Food{Name: "Mayonnaise, regular", Source: SourceUSDA, DataType: typeSurvey, Per100g: per100,
		Portions: []Portion{{Label: "cup", Grams: 220}, {Label: "tablespoon", Grams: 13.8}}, UnspecifiedGrams: 9}
	got, ok := resolve(mayo, Item{Quantity: 1, Unit: "serving"})
	if !ok || got.Grams != 9 || got.Basis != basisStandard {
		t.Fatalf("a serving of mayonnaise = %+v %v", got, ok)
	}
	reference := Food{Name: "Mayonnaise, made with tofu", Source: SourceUSDA, DataType: typeSRLegacy, Per100g: per100,
		Portions: []Portion{{Label: "cup", Grams: 240}}}
	if got, ok := resolve(reference, Item{Quantity: 1, Unit: "serving"}); ok {
		t.Fatalf("a serving must not become the first measure: %+v", got)
	}
}

func TestUSDAKeepsTheUnspecifiedAmountOutOfTheMeasures(t *testing.T) {
	f := decodeUSDA(2710154, "Mayonnaise, regular", nutrients(680, 1, 0.6, 75, 0, srIDs))
	f.DataType = typeSurvey
	f.FoodMeasures = []usdaMeasure{
		{GramWeight: 13.8, Modifier: "10200", Rank: 1, Text: "1 tablespoon"},
		{GramWeight: 9, Modifier: "90000", Rank: 2, Text: "Quantity not specified"},
	}
	food, ok := f.toFood()
	if !ok || food.UnspecifiedGrams != 9 || len(food.Portions) != 1 {
		t.Fatalf("food = %+v", food)
	}
}

func TestRankingPutsAStandInBelowTheFood(t *testing.T) {
	sour := []Food{
		{ID: "2705617", Name: "Sour cream, imitation", DataType: typeSurvey},
		{ID: "2705610", Name: "Sour cream, regular", DataType: typeSurvey},
	}
	if best, _ := pickBest(Item{Food: "sour cream"}, sour); best.Food.ID != "2705610" {
		t.Fatalf("sour cream = %+v", best.Food)
	}
	if best, _ := pickBest(Item{Food: "imitation sour cream"}, sour); best.Food.ID != "2705617" {
		t.Fatalf("asked-for imitation = %+v", best.Food)
	}
}
