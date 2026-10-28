package estimate

import (
	"context"
	"testing"
)

type fakeLibrary struct{ foods []LibraryFood }

func (f fakeLibrary) All(context.Context) ([]LibraryFood, error) { return f.foods, nil }

var savedApple = LibraryFood{ID: 7, Name: "Apple", ServingText: "1 medium (182 g)", ServingGrams: 182,
	N: Nutrients{Kcal: 95, Protein: 0.5, Carbs: 25, Fat: 0.3, Fiber: 4.4}, Source: SourceUSDA, SourceID: "171688", UseCount: 5,
	Servings: []Portion{{Label: "1 cup slices", Grams: 109}}}

var savedChomps = LibraryFood{ID: 8, Name: "Original beef stick", Brand: "Chomps", ServingText: "1 stick (32 g)", ServingGrams: 32,
	N: Nutrients{Kcal: 90, Protein: 10, Fat: 6}, Source: "manual"}

func TestLibraryMatchIsNameAndBrandAwareButNotLoose(t *testing.T) {
	cases := []struct {
		name string
		it   Item
		lib  LibraryFood
		want bool
		diff int
	}{
		{"same name", Item{Food: "apple"}, savedApple, true, 0},
		{"descriptors differ", Item{Food: "apple, raw"}, savedApple, true, 1},
		{"a different food that contains the name", Item{Food: "apple pie"}, savedApple, false, 0},
		{"plural", Item{Food: "apples"}, savedApple, true, 0},
		{"branded exact", Item{Food: "original beef stick", Brand: "Chomps", Text: "a chomp meat stick"}, savedChomps, true, 0},
		{"brand typed in the food words", Item{Food: "chomps original beef stick", Text: "chomps original beef stick"}, savedChomps, true, 0},
		{"other brand", Item{Food: "original beef stick", Brand: "Jack Link's"}, savedChomps, false, 0},
		{"branded library food needs its brand in the text", Item{Food: "original beef stick", Text: "beef stick"}, savedChomps, false, 0},
		{"item brand but unbranded library food", Item{Food: "apple", Brand: "Honeycrisp co"}, savedApple, false, 0},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			diff, ok := libraryMatch(tc.it, tc.lib)
			if ok != tc.want || (ok && diff != tc.diff) {
				t.Fatalf("got diff %d ok %v, want diff %d ok %v", diff, ok, tc.diff, tc.want)
			}
		})
	}
}

func TestFastPathNeedsAnExactSinglePhrase(t *testing.T) {
	lib := []LibraryFood{savedApple, savedChomps}
	for text, qty := range map[string]float64{"apple": 1, "an apple": 1, "2 apples": 2, "1/2 apple": 0.5, "Chomps original beef stick": 1} {
		it, _, ok := exactLibraryItem(text, lib)
		if !ok || it.Quantity != qty {
			t.Errorf("%q: ok=%v item=%+v", text, ok, it)
		}
	}
	for _, text := range []string{"apple and a banana", "apple, banana", "apple pie", "apple raw", "toast", "", "0 apples", "3 apples + milk"} {
		if _, _, ok := exactLibraryItem(text, lib); ok {
			t.Errorf("%q must go through the parse step", text)
		}
	}
}

func TestMealUsesTheLibraryFirstAndSkipsClaudeForAnExactPhrase(t *testing.T) {
	claude, client := newFakeClaude(t)
	_, foods := newFakeFoods(t)
	e := &Estimator{Client: client, Foods: foods, Library: fakeLibrary{[]LibraryFood{savedApple, savedChomps}}}

	m, err := e.Meal(context.Background(), "2 apples")
	if err != nil {
		t.Fatal(err)
	}
	if claude.calls("split_meal") != 0 || claude.calls("report_meal_estimate") != 0 {
		t.Fatal("an exact library phrase must not call Claude")
	}
	it := m.Items[0]
	// The label numbers are used exactly: 2 x 95 kcal, not a per-100 g reconstruction.
	if it.Source != "library" || it.SourceID != "7" || it.Kcal != 190 || it.Protein != 1 || it.Grams != 364 ||
		it.Confidence != "high" || it.Quantity != 2 || it.Name != "Apple" || m.DatabaseShare != 100 {
		t.Fatalf("item = %+v share %d", it, m.DatabaseShare)
	}

	// A saved alternate serving converts through its weight.
	claude.tools["split_meal"] = splitItems(
		item("a cup of apple slices", "Apple slices", "apple", nil, 1, "cup", nil, "generic"),
		item("a chomps stick", "Chomps stick", "original beef stick", "Chomps", 1, "stick", nil, "branded"),
		item("rice", "Rice", "rice, white", nil, 1, "cup", nil, "generic"))
	claude.tools["report_meal_estimate"] = itemEstimate(200, "low")
	m, err = e.Meal(context.Background(), "a cup of apple slices and a chomps stick and rice")
	if err != nil {
		t.Fatal(err)
	}
	cup, stick, rice := m.Items[0], m.Items[1], m.Items[2]
	if cup.Source != "library" || cup.Kcal != 57 || cup.Grams != 109 {
		t.Fatalf("cup = %+v", cup)
	}
	if stick.Source != "library" || stick.Kcal != 90 || stick.Brand != "Chomps" {
		t.Fatalf("stick = %+v", stick)
	}
	if rice.Source != "estimated" {
		t.Fatalf("rice = %+v", rice)
	}
	// Library entries taken from a database or a label count toward the database share.
	if m.DatabaseShare != 42 {
		t.Fatalf("share = %d", m.DatabaseShare)
	}
}

func TestLibraryFoodWithoutAUsableUnitFallsThrough(t *testing.T) {
	claude, client := newFakeClaude(t)
	claude.tools["split_meal"] = splitItems(item("a cup of apple", "Apple", "apple", nil, 1, "cup", nil, "generic"))
	claude.tools["report_meal_estimate"] = itemEstimate(80, "medium")
	noGrams := savedApple
	noGrams.ServingGrams = 0
	noGrams.Servings = nil
	e := &Estimator{Client: client, Library: fakeLibrary{[]LibraryFood{noGrams}}}
	m, err := e.Meal(context.Background(), "a cup of apple, and nothing else")
	if err != nil {
		t.Fatal(err)
	}
	if m.Items[0].Source != "estimated" {
		t.Fatalf("a cup cannot be weighed from this entry: %+v", m.Items[0])
	}
}

func TestSearchLibraryRanksExactThenMostUsed(t *testing.T) {
	foods := []LibraryFood{
		{ID: 1, Name: "Apple pie", UseCount: 9},
		{ID: 2, Name: "Apple", UseCount: 1},
		{ID: 3, Name: "Apple juice", UseCount: 4},
		{ID: 4, Name: "Banana", UseCount: 50},
		{ID: 5, Name: "Beef stick", Brand: "Chomps", UseCount: 2},
	}
	var ids []int64
	for _, f := range SearchLibrary("apple", foods) {
		ids = append(ids, f.ID)
	}
	if len(ids) != 3 || ids[0] != 2 || ids[1] != 1 || ids[2] != 3 {
		t.Fatalf("ids = %v", ids)
	}
	if got := SearchLibrary("chomps bee", foods); len(got) != 1 || got[0].ID != 5 {
		t.Fatalf("prefix + brand = %+v", got)
	}
	if got := SearchLibrary("", foods); len(got) != 5 {
		t.Fatalf("empty query lists all: %d", len(got))
	}
}

func TestSearchRemoteReturnsRankedCandidatesWithServings(t *testing.T) {
	fake, f2 := newFakeFoods(t)
	fake.usda = func(_, dataType string) any {
		if dataType == "Branded" {
			return obj{"foods": []obj{}}
		}
		return appleFoods("", "")
	}
	fake.off = func(string) any {
		return obj{"products": []obj{{"code": "9", "product_name": "Apple sauce", "brands": "Mott's", "serving_size": "1 cup (240 g)",
			"image_front_small_url": "https://images.openfoodfacts.org/images/products/9/front.200.jpg",
			"nutriments":            obj{"energy-kcal_serving": 100, "energy-kcal_100g": 42}}}}
	}
	got := f2.SearchRemote(context.Background(), "apple")
	if len(got) < 2 {
		t.Fatalf("candidates = %+v", got)
	}
	var apple Food
	for _, c := range got {
		if c.ID == "171688" {
			apple = c
		}
	}
	v := apple.Serving()
	if v.Text != `1 medium (3" dia)` || v.Grams != 182 || int(v.N.Kcal+0.5) != 95 || len(v.Alts) != 1 {
		t.Fatalf("apple serving = %+v", v)
	}
	var sauce Food
	for _, c := range got {
		if c.Source == SourceOpenFoodFacts {
			sauce = c
		}
	}
	if sv := sauce.Serving(); sv.Text != "1 cup (240 g)" || sv.N.Kcal != 100 {
		t.Fatalf("sauce serving = %+v", sv)
	}
	if sauce.ImageURL != "https://images.openfoodfacts.org/images/products/9/front.200.jpg" ||
		sauce.SourceURL != "https://world.openfoodfacts.org/product/9" {
		t.Fatalf("sauce links = %q %q", sauce.ImageURL, sauce.SourceURL)
	}
	if apple.ImageURL != "" || apple.SourceURL != "" {
		t.Fatalf("usda food has links: %+v", apple)
	}
	if fake.offSearch.Load() != 1 {
		t.Fatalf("off calls = %d", fake.offSearch.Load())
	}
}

func TestOFFImageAcceptsOnlyHTTPSOpenFoodFactsHosts(t *testing.T) {
	cases := map[string]string{
		"https://images.openfoodfacts.org/a.jpg":      "https://images.openfoodfacts.org/a.jpg",
		"https://static.openfoodfacts.org/a.jpg":      "https://static.openfoodfacts.org/a.jpg",
		"http://images.openfoodfacts.org/a.jpg":       "",
		"https://evil.example/a.jpg":                  "",
		"https://openfoodfacts.org.evil.example/a.jp": "",
		"https://notopenfoodfacts.org/a.jpg":          "",
		"javascript:alert(1)":                         "",
	}
	for in, want := range cases {
		if got := firstOFFImage(in); got != want {
			t.Errorf("firstOFFImage(%q) = %q, want %q", in, got, want)
		}
	}
	if got := firstOFFImage("http://x.test/a.jpg", "https://images.openfoodfacts.org/b.jpg"); got != "https://images.openfoodfacts.org/b.jpg" {
		t.Errorf("fallback = %q", got)
	}
}
