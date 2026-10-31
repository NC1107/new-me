package estimate

import (
	"encoding/json"
	"testing"
)

func TestUSDAProduceKind(t *testing.T) {
	cases := []struct {
		name, dataType, category, description, want string
	}{
		{"reference apple", typeFoundation, "Fruits and Fruit Juices", "Apples, fuji, with skin, raw", ProduceFruit},
		{"reference broccoli", typeSRLegacy, "Vegetables and Vegetable Products", "Broccoli, raw", ProduceVegetable},
		{"reference orange juice is juice", typeSRLegacy, "Fruits and Fruit Juices", "Orange juice, raw", ProduceJuice},
		{"a smoothie is juice", typeSRLegacy, "Fruits and Fruit Juices", "Fruit smoothie, bottled", ProduceJuice},
		{"a potato does not count", typeSRLegacy, "Vegetables and Vegetable Products", "Potatoes, baked, flesh and skin, with salt", ""},
		{"cassava does not count", typeSRLegacy, "Vegetables and Vegetable Products", "Cassava, raw", ""},
		{"sweet potato does count", typeSRLegacy, "Vegetables and Vegetable Products", "Sweet potato, cooked, baked in skin", ProduceVegetable},
		{"juice named after the head does not make a fruit juice", typeSRLegacy, "Fruits and Fruit Juices", "Lemons, raw, without peel", ProduceFruit},
		{"survey fruit", typeSurvey, "Citrus fruits", "Orange, raw", ProduceFruit},
		{"survey juice", typeSurvey, "Citrus juice", "Orange juice, 100%, NFS", ProduceJuice},
		{"survey fruit drink is not juice", typeSurvey, "Fruit drinks", "Orange juice beverage, 40-50% juice, light", ""},
		{"survey potatoes", typeSurvey, "White potatoes and Puerto Rican starchy vegetables", "Potato, baked, NFS", ""},
		{"survey beans are a pulse", typeSurvey, "Beans, peas, legumes", "Black beans, NFS", ProducePulse},
		{"survey mixed dish", typeSurvey, "Bean, pea, legume dishes", "Black bean salad", ""},
		{"survey pizza", typeSurvey, "Pizza", "Pizza, cheese", ""},
		{"a branded food never counts", typeBranded, "Fruits and Fruit Juices", "Apple slices", ""},
		{"an unknown category counts for nothing", typeFoundation, "Mystery Group", "Apples, raw", ""},
	}
	for _, c := range cases {
		if got := usdaProduceKind(c.dataType, c.category, c.description); got != c.want {
			t.Errorf("%s: %q, want %q", c.name, got, c.want)
		}
	}
}

func TestUSDAFoodCarriesItsProduceKind(t *testing.T) {
	f := usdaFood{FdcID: 1, Description: "Broccoli, raw", DataType: typeSRLegacy,
		FoodCategory:  json.RawMessage(`"Vegetables and Vegetable Products"`),
		FoodNutrients: []usdaNutrient{{NutrientID: nutKcal, Value: 34}}}
	food, ok := f.toFood()
	if !ok || food.Produce != ProduceVegetable {
		t.Fatalf("produce = %q (ok %v), want vegetable", food.Produce, ok)
	}
}

func TestADatabaseHitCountsItsWholeWeightAsProduce(t *testing.T) {
	e := &Estimator{}
	h := hit{Food: Food{Source: SourceUSDA, ID: "1", Name: "Broccoli, raw", Produce: ProduceVegetable},
		Resolved: resolved{Grams: 150, N: Nutrients{Kcal: 51}}, Confidence: ConfidenceHigh}
	res := e.hitResult(Item{Text: "broccoli", Quantity: 1, Unit: "serving"}, h)
	if res.ProduceKind != ProduceVegetable || res.ProduceGrams != 150 {
		t.Fatalf("produce %q %v g, want vegetable 150", res.ProduceKind, res.ProduceGrams)
	}
	h.Food.Produce = ""
	if res := e.hitResult(Item{Text: "chicken", Quantity: 1, Unit: "serving"}, h); res.ProduceKind != "" || res.ProduceGrams != 0 {
		t.Fatalf("a food that is not produce got %q %v g", res.ProduceKind, res.ProduceGrams)
	}
}

func TestParseReadsTheEstimatedProduceOfAFood(t *testing.T) {
	est, err := Parse(json.RawMessage(`{"name":"Stir fry","kcal":300,"protein":10,"carbs":30,"fat":10,"fiber":6,"confidence":"medium","notes":"","produceKind":"vegetable","produceG":165.44}`))
	if err != nil || est.ProduceKind != ProduceVegetable || est.ProduceG != 165.4 {
		t.Fatalf("got %q %v (err %v), want vegetable 165.4", est.ProduceKind, est.ProduceG, err)
	}
	for _, kind := range []string{"none", "potato", ""} {
		est, err := Parse(json.RawMessage(`{"name":"x","kcal":300,"confidence":"low","produceKind":"` + kind + `","produceG":80}`))
		if err != nil || est.ProduceKind != "" || est.ProduceG != 0 {
			t.Errorf("kind %q gave %q %v (err %v), want none", kind, est.ProduceKind, est.ProduceG, err)
		}
	}
}

func TestOnlyASingleFoodIsAskedForProduce(t *testing.T) {
	if _, ok := schema()["properties"].(map[string]any)["produceKind"]; ok {
		t.Error("the one-meal schema must not ask for produce")
	}
	props := itemSchema()["properties"].(map[string]any)
	if props["produceKind"] == nil || props["produceG"] == nil {
		t.Error("the single food schema must ask for produceKind and produceG")
	}
}
