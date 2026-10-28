package estimate

import (
	"context"
	"strings"
	"testing"
)

// The rows below are real USDA results captured on 2026-10-28 for a corpus of everyday foods.

func TestClassFirstRowsAnswerTheFoodInTheirSecondPart(t *testing.T) {
	cases := []struct {
		item, row string
		ok        bool
	}{
		{"salmon, baked", "Fish, salmon, baked or broiled", true},
		{"tuna, canned in water", "Fish, tuna, white, canned in water, drained solids", true},
		{"cola", "Soft drink, cola", true},
		{"french fries", "Potato, french fries, NFS", true},
		{"orange, raw", "Orange peel, raw", false},
		{"skim milk", "Yogurt, plain, skim milk", false},
		{"whole milk", "Cheese, mozzarella, whole milk", false},
	}
	for _, tc := range cases {
		_, ok := scoreFood(Item{Food: tc.item}, Food{Name: tc.row, DataType: typeSurvey})
		if ok != tc.ok {
			t.Errorf("%q for %q: ok = %v, want %v", tc.row, tc.item, ok, tc.ok)
		}
	}
	applebees := Food{Name: "APPLEBEE'S, french fries", DataType: typeSRLegacy, Category: "Restaurant Foods"}
	if _, ok := scoreFood(Item{Food: "french fries"}, applebees); ok {
		t.Error("a restaurant's name is not a class of food")
	}
}

func TestNonDairyIsAStandIn(t *testing.T) {
	rows := []Food{
		{ID: "1", Name: "Coffee, Latte, with non-dairy milk", DataType: typeSurvey},
		{ID: "2", Name: "Coffee, Latte", DataType: typeSurvey},
	}
	if best, _ := pickBest(Item{Food: "latte"}, rows); best.Food.ID != "2" {
		t.Fatalf("latte = %+v", best.Food)
	}
}

func TestTheMeasureTheItemNamesWins(t *testing.T) {
	cheddar := []Portion{{Label: "cup, diced", Grams: 132}, {Label: "cup, melted", Grams: 244}, {Label: "cup, shredded", Grams: 113}}
	if p, _ := bestPortion(cheddar, []string{"cup"}, tokens("cheddar cheese, shredded")); p.Grams != 113 {
		t.Errorf("shredded cheddar cup = %+v", p)
	}
	avocado := []Portion{{Label: "cup, mashed or pureed", Grams: 230}, {Label: "cup", Grams: 150}}
	if p, _ := bestPortion(avocado, []string{"cup"}, tokens("avocado")); p.Grams != 150 {
		t.Errorf("plain cup = %+v", p)
	}
}

func TestASizeWordNeverTakesASingleFry(t *testing.T) {
	per100 := &Nutrients{Kcal: 220}
	fries := Food{Name: "Potato, french fries, NFS", Source: SourceUSDA, DataType: typeSurvey, Per100g: per100,
		Portions: []Portion{{Label: "fry, NS as to shape", Grams: 5}, {Label: "cup", Grams: 92}}}
	if got, ok := resolve(fries, Item{Quantity: 1, Unit: "medium"}); ok {
		t.Fatalf("1 medium of fries = %+v", got)
	}
	tomato := Food{Name: "Tomatoes, raw", Source: SourceUSDA, DataType: typeSurvey, Per100g: per100,
		Portions: []Portion{{Label: "slice", Grams: 20}, {Label: "whole", Grams: 125}}}
	if got, _ := resolve(tomato, Item{Quantity: 1, Unit: "medium"}); got.Grams != 125 {
		t.Fatalf("1 medium tomato = %+v", got)
	}
}

func TestPickPrefersAnExactMeasureAmongTheTopRows(t *testing.T) {
	_, foods := newFakeFoods(t)
	per100 := &Nutrients{Kcal: 290}
	rows := []Food{
		{Source: SourceUSDA, ID: "2709456", Name: "Potato, french fries, NFS", DataType: typeSurvey, Per100g: per100,
			Portions: []Portion{{Label: "small", Grams: 30}}},
		{Source: SourceUSDA, ID: "2709462", Name: "Potato, french fries, restaurant", DataType: typeSurvey, Per100g: per100,
			Portions: []Portion{{Label: "small fast food order", Grams: 110}, {Label: "medium fast food order", Grams: 145}}},
	}
	h, ok := foods.pick(context.Background(), Item{Food: "french fries", Quantity: 1, Unit: "medium"}, rows)
	if !ok || h.Food.ID != "2709462" || h.Resolved.Grams != 145 {
		t.Fatalf("medium fries = %+v", h)
	}
}

func TestNoNamedRowFallsBackToTheUnspecifiedFood(t *testing.T) {
	ff, foods := newFakeFoods(t)
	ff.usda = func(query, dataType string) any {
		if strings.Contains(query, "AND (NFS OR NS)") {
			return obj{"foods": []obj{{"fdcId": 2710373, "description": "Coffee, NFS", "dataType": "Survey (FNDDS)",
				"foodNutrients": nutrients(1, 0.1, 0, 0, 0, srIDs),
				"foodMeasures":  []obj{{"gramWeight": 240, "modifier": "64", "rank": 1, "disseminationText": "1 cup (8 fl oz)"}}}}}
		}
		return obj{"foods": []obj{{"fdcId": 1, "description": "Coffee, Cuban", "dataType": "Survey (FNDDS)",
			"foodNutrients": nutrients(5, 0.1, 0, 0, 0, srIDs)}}}
	}
	h, ok, _ := foods.Lookup(context.Background(), Item{Food: "coffee, black", Quantity: 1, Unit: "cup", Kind: KindGeneric})
	if !ok || h.Food.ID != "2710373" || h.Food.Name != "Coffee, any kind" || h.Resolved.Grams != 240 || h.Confidence != ConfidenceLow {
		t.Fatalf("black coffee = %+v ok=%v", h, ok)
	}
}

// The NFS row answers a bare name; a detail the person gave must still pick the specific row.
func TestTheUnspecifiedRowLosesToTheDetailTheyGave(t *testing.T) {
	almonds := []Food{
		{ID: "2707485", Name: "Almonds, NFS", DataType: typeSurvey},
		{ID: "2707491", Name: "Almonds, salted", DataType: typeSurvey},
		{ID: "2707494", Name: "Almonds, unsalted", DataType: typeSurvey},
	}
	if best, _ := pickBest(Item{Food: "almonds, salted"}, almonds); best.Food.ID != "2707491" {
		t.Fatalf("salted almonds = %+v", best.Food)
	}
	if best, _ := pickBest(Item{Food: "almonds"}, almonds); best.Food.ID != "2707485" {
		t.Fatalf("almonds = %+v", best.Food)
	}
}

// More rows from the 2026-10-28 corpus, so the everyday cases run without the live tag.
func TestCorpusRowsRankOffline(t *testing.T) {
	cases := []struct {
		item string
		rows []Food
		want string
	}{
		{"milk, 2%", []Food{
			{ID: "171302", Name: "Milk, evaporated, 2% fat, with added vitamin A and vitamin D", DataType: typeSRLegacy},
			{ID: "168787", Name: "Egg custards, dry mix, prepared with 2% milk", DataType: typeSRLegacy},
			{ID: "2705386", Name: "Milk, reduced fat (2%)", DataType: typeSurvey},
		}, "2705386"},
		{"white rice, cooked", []Food{
			{ID: "2708422", Name: "Rice, white, cooked, glutinous", DataType: typeSurvey},
			{ID: "169711", Name: "Rice, white, glutinous, unenriched, cooked", DataType: typeSRLegacy},
			{ID: "2708403", Name: "Rice, white, cooked, NS as to fat", DataType: typeSurvey},
		}, "2708403"},
		{"orange", []Food{
			{ID: "169103", Name: "Orange peel, raw", DataType: typeSRLegacy},
			{ID: "2709171", Name: "Orange, raw", DataType: typeSurvey},
		}, "2709171"},
		{"cottage cheese", []Food{
			{ID: "169078", Name: "Cheese, cottage, with vegetables", DataType: typeSRLegacy},
			{ID: "2705747", Name: "Cheese, cottage, NFS", DataType: typeSurvey},
		}, "2705747"},
	}
	for _, c := range cases {
		if best, ok := pickBest(Item{Food: c.item}, c.rows); !ok || best.Food.ID != c.want {
			t.Errorf("%s = %+v, want %s", c.item, best.Food, c.want)
		}
	}
}
