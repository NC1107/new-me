package estimate

import (
	"context"
	"encoding/json"
	"strings"
	"testing"
)

// Production on 2026-10-31: "Dave's Killer Bread" was saved with the brand as its name, and the
// next meal naming it matched a different USDA bread instead of the saved one.
func TestASavedFoodNamedAfterItsBrandIsFound(t *testing.T) {
	saved := []LibraryFood{{ID: 9, Name: "Dave's Killer Bread", Brand: "Dave's Killer Bread"}}
	for _, it := range []Item{
		{Text: "2 slices of dave's killer bread", Food: "Dave's Killer Bread", Brand: "Dave's Killer Bread"},
		{Text: "dave's killer bread", Food: "Dave's Killer Bread"},
		{Text: "2 slices of dave's killer bread", Food: "bread", Brand: "Dave's Killer Bread"},
	} {
		if l, ok := bestLibrary(it, saved); !ok || l.ID != 9 {
			t.Errorf("%+v: got %v %v, want the saved bread", it, l.ID, ok)
		}
	}
}

var savedBread = LibraryFood{ID: 9, Name: "Organic sprouted whole grains bread", Brand: "Dave's Killer Bread",
	ServingText: "1 slice (37 g)", ServingGrams: 37, N: Nutrients{Kcal: 90, Protein: 4, Carbs: 17, Fat: 1, Fiber: 3},
	Source: SourceUSDA, SourceID: "2490627", UseCount: 3}

func TestTheSplitStepSeesTheSavedFoodsAndItsPickIsUsed(t *testing.T) {
	claude, client := newFakeClaude(t)
	pick := item("2 slices of dave's", "Dave's bread", "bread", nil, 2, "slice", nil, "branded")
	pick["savedFoodId"] = 9
	claude.tools["split_meal"] = splitItems(pick)
	e := &Estimator{Client: client, Library: fakeLibrary{[]LibraryFood{savedApple, savedBread}}}

	m, err := e.Meal(context.Background(), "2 slices of dave's toasted")
	if err != nil {
		t.Fatal(err)
	}
	user, _ := json.Marshal(claude.requests[0]["messages"])
	if !strings.Contains(string(user), "9: Organic sprouted whole grains bread, Dave's Killer Bread, 1 slice (37 g)") ||
		!strings.Contains(string(user), "7: Apple, 1 medium (182 g)") {
		t.Fatalf("the split step must see the saved foods: %s", user)
	}
	it := m.Items[0]
	if it.Source != SourceLibrary || it.SourceID != "9" || it.Kcal != 180 || it.Grams != 74 {
		t.Fatalf("item = %+v", it)
	}
	if claude.calls("report_meal_estimate") != 0 {
		t.Fatal("a saved food must not be estimated")
	}
}

func TestASavedFoodIdThatIsNotInTheListIsIgnored(t *testing.T) {
	claude, client := newFakeClaude(t)
	pick := item("a slice of bread", "Bread", "bread", nil, 1, "slice", nil, "generic")
	pick["savedFoodId"] = 4242
	claude.tools["split_meal"] = splitItems(pick)
	claude.tools["report_meal_estimate"] = itemEstimate(80, "medium")
	e := &Estimator{Client: client, Library: fakeLibrary{[]LibraryFood{savedBread}}}

	m, err := e.Meal(context.Background(), "a slice of bread and nothing else")
	if err != nil {
		t.Fatal(err)
	}
	if m.Items[0].Source != SourceEstimated {
		t.Fatalf("an unknown id must not pick a saved food: %+v", m.Items[0])
	}
}

// USDA FNDDS portions of "Bread, white, toasted" and "Butter, NFS" as FoodData Central lists them.
var toastPortions = []Portion{{Label: "1 cup", Grams: 40}, {Label: "1 cubic inch", Grams: 3.9}, {Label: "Quantity not specified", Grams: 25},
	{Label: "1 slice, snack-size", Grams: 9}, {Label: "1 small or thin/very thin slice", Grams: 22}, {Label: "1 slice, crust not eaten", Grams: 12},
	{Label: "1 large or thick slice", Grams: 39}, {Label: "1 medium or regular slice", Grams: 25}}

var butterPortions = []Portion{{Label: "Guideline amount on regular sandwich", Grams: 14}, {Label: "Quantity not specified", Grams: 14},
	{Label: "1 individual container", Grams: 5}, {Label: "1 pat", Grams: 7}, {Label: "Guideline amount on large sandwich", Grams: 28},
	{Label: "1 cup", Grams: 224}, {Label: "Guideline amount per slice of bread/roll", Grams: 7}, {Label: "1 tablespoon", Grams: 14}}

func TestASliceWithNoSizeIsTheRegularSlice(t *testing.T) {
	for _, c := range []struct {
		unit, food string
		want       float64
	}{
		{"slice", "bread, white, toasted", 25},
		{"slice", "thin bread", 22},
		{"slice", "thick toast", 39},
		{"slice of bread", "butter", 7},
		{"pat", "butter", 7},
	} {
		ps := toastPortions
		if c.food == "butter" {
			ps = butterPortions
		}
		p, ok := bestPortion(ps, normUnit(c.unit), tokens(c.food))
		if !ok || p.Grams != c.want {
			t.Errorf("%s of %s: %+v %v, want %v g", c.unit, c.food, p, ok, c.want)
		}
	}
}

func TestASpreadWithNoPerSliceAmountTakesTheSurveyDefault(t *testing.T) {
	cream := Food{Source: SourceUSDA, DataType: typeSurvey, Name: "Cheese spread, cream cheese", Per100g: &Nutrients{Kcal: 295},
		UnspecifiedGrams: 30, Portions: []Portion{{Label: "1 oz", Grams: 28.35}, {Label: "1 cup", Grams: 240}}}
	r, ok := resolve(cream, Item{Food: "cream cheese", Unit: "slice of bread", Quantity: 1})
	if !ok || r.Grams != 30 {
		t.Fatalf("cream cheese on a bagel = %+v %v, want the 30 g survey default", r, ok)
	}
}
