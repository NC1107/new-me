package estimate

import "testing"

func TestTidyNamesAndBrands(t *testing.T) {
	names := map[string]string{
		"TOTINO'S SAUSAGE PIZZA ROLLS":  "Totino's Sausage Pizza Rolls",
		"Totino's Cheese Party Pizza":   "Totino's Cheese Party Pizza",
		"CHICKEN BREAST WITH SKIN, RAW": "Chicken Breast with Skin, Raw",
		"OK":                            "OK",
	}
	for in, want := range names {
		if got := tidyName(in); got != want {
			t.Errorf("tidyName(%q) = %q, want %q", in, got, want)
		}
	}
	brands := []struct{ name, owner, want string }{
		{"Totino's", "GENERAL MILLS SALES INC.", "Totino's"},
		{"", "GENERAL MILLS SALES INC.", "General Mills"},
		{"", "Kraft Heinz Foods Company", "Kraft Heinz Foods"},
		{"TOTINO'S", "General Mills, Inc.", "Totino's"},
		{"", "", ""},
	}
	for _, b := range brands {
		if got := tidyBrand(b.name, b.owner); got != b.want {
			t.Errorf("tidyBrand(%q, %q) = %q, want %q", b.name, b.owner, got, b.want)
		}
	}
}

func TestOpenFoodFactsNamesInCapitalsAreTidied(t *testing.T) {
	f, ok := offProduct{Code: "1", Name: "SPORTYFEEL SPICY CHICKEN & 'NDUJA PIZZA", Brands: "SPORTYFEEL",
		Nutriments: map[string]any{"energy-kcal_100g": 252.0}}.toFood()
	if !ok || f.Name != "Sportyfeel Spicy Chicken & 'Nduja Pizza" || f.Brand != "Sportyfeel" {
		t.Fatalf("food = %q by %q (%v)", f.Name, f.Brand, ok)
	}
}

func TestOpenFoodFactsBrandListsReadAsOneLabel(t *testing.T) {
	for _, c := range []struct{ name, brands, want string }{
		{"Nutella", "Nutella, Ferrero", "Ferrero"},
		{"Nutella", "Nutella,Ferrero France Commerciale", "Ferrero France Commerciale"},
		{"Protein bar", "Grenade,  Grenade , Mondelez", "Grenade Mondelez"},
		{"Oat milk", "", ""},
	} {
		f, ok := offProduct{Code: "1", Name: c.name, Brands: c.brands,
			Nutriments: map[string]any{"energy-kcal_100g": 50.0}}.toFood()
		if !ok || f.Brand != c.want {
			t.Errorf("%q by %q: brand = %q, want %q", c.name, c.brands, f.Brand, c.want)
		}
	}
}

func TestUSDACategoryReadsFromSearchAndDetail(t *testing.T) {
	search := decodeUSDA(1, "Apples, raw", nutrients(52, 0.3, 14, 0.2, 2.4, srIDs))
	search.FoodCategory = []byte(`"Fruits and Fruit Juices"`)
	detail := decodeUSDA(2, "Apples, raw", nutrients(52, 0.3, 14, 0.2, 2.4, srIDs))
	detail.FoodCategory = []byte(`{"id": 9, "code": "0900", "description": "Fruits and Fruit Juices"}`)
	for _, f := range []usdaFood{search, detail} {
		if food, _ := f.toFood(); food.Category != "Fruits and Fruit Juices" {
			t.Errorf("category = %q", food.Category)
		}
	}
	if food, _ := decodeUSDA(3, "Apples, raw", nutrients(52, 0.3, 14, 0.2, 2.4, srIDs)).toFood(); food.Category != "" {
		t.Errorf("no category = %q", food.Category)
	}
}

func TestUSDANamesTidyAShoutedBrandOnly(t *testing.T) {
	for in, want := range map[string]string{
		"JIMMY DEAN, Sausage, Egg, and Cheese Breakfast Biscuit": "Jimmy Dean, Sausage, Egg, and Cheese Breakfast Biscuit",
		"Rice, white, cooked, NS as to fat":                      "Rice, white, cooked, NS as to fat",
		"Babyfood, cereal, NFS":                                  "Babyfood, cereal, NFS",
		"Cheese, Colby Jack":                                     "Cheese, Colby Jack",
	} {
		if got := tidySegments(in); got != want {
			t.Errorf("tidySegments(%q) = %q, want %q", in, got, want)
		}
	}
}
