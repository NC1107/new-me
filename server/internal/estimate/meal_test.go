package estimate

import (
	"context"
	"encoding/json"
	"errors"
	"net/http"
	"net/http/httptest"
	"strings"
	"sync"
	"sync/atomic"
	"testing"

	"github.com/nc1107/new-me/server/internal/anthropic"
)

type obj = map[string]any

// fakeClaude answers by forced tool name, so one server plays the split step and the per-item
// fallback.
type fakeClaude struct {
	mu       sync.Mutex
	requests []obj
	tools    map[string]func(req obj) any
	status   int
}

func newFakeClaude(t *testing.T) (*fakeClaude, *anthropic.Client) {
	t.Helper()
	f := &fakeClaude{tools: map[string]func(obj) any{}, status: http.StatusOK}
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		var req obj
		_ = json.NewDecoder(r.Body).Decode(&req)
		f.mu.Lock()
		f.requests = append(f.requests, req)
		status := f.status
		f.mu.Unlock()
		if status != http.StatusOK {
			w.WriteHeader(status)
			return
		}
		name := req["tool_choice"].(obj)["name"].(string)
		reply, ok := f.tools[name]
		if !ok {
			http.Error(w, "unknown tool", http.StatusBadRequest)
			return
		}
		_ = json.NewEncoder(w).Encode(obj{"content": []obj{{"type": "tool_use", "name": name, "input": reply(req)}}})
	}))
	t.Cleanup(srv.Close)
	return f, anthropic.New("k", srv.URL)
}

func (f *fakeClaude) calls(tool string) int {
	f.mu.Lock()
	defer f.mu.Unlock()
	n := 0
	for _, r := range f.requests {
		if r["tool_choice"].(obj)["name"] == tool {
			n++
		}
	}
	return n
}

func splitItems(items ...obj) func(obj) any { return func(obj) any { return obj{"items": items} } }

func item(text, label, food string, brand any, qty float64, unit string, grams any, kind string) obj {
	return obj{"text": text, "label": label, "food": food, "brand": brand, "quantity": qty, "unit": unit, "grams": grams, "kind": kind}
}

func itemEstimate(kcal float64, conf string) func(obj) any {
	return func(obj) any {
		return obj{"name": "x", "kcal": kcal, "protein": 5, "carbs": 30, "fat": 8, "fiber": 1, "confidence": conf, "notes": "n"}
	}
}

type fakeFoods struct {
	usdaSearch, usdaDetail, offSearch atomic.Int32
	usdaQueries                       []string
	mu                                sync.Mutex
	offUA                             string
	usda                              func(query, dataType string) any
	offStatus                         int
	off                               func(query string) any
	usdaStatus                        int
}

func newFakeFoods(t *testing.T) (*fakeFoods, *Foods) {
	t.Helper()
	ff := &fakeFoods{offStatus: 200, usdaStatus: 200,
		usda: func(string, string) any { return obj{"foods": []obj{}} },
		off:  func(string) any { return obj{"products": []obj{}} }}
	usda := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Query().Get("api_key") != "test-key" {
			http.Error(w, "bad key", http.StatusForbidden)
			return
		}
		if ff.usdaStatus != 200 {
			w.WriteHeader(ff.usdaStatus)
			return
		}
		switch {
		case r.URL.Path == "/foods/search":
			ff.usdaSearch.Add(1)
			ff.mu.Lock()
			ff.usdaQueries = append(ff.usdaQueries, r.URL.Query().Get("query")+"|"+r.URL.Query().Get("dataType"))
			ff.mu.Unlock()
			_ = json.NewEncoder(w).Encode(ff.usda(r.URL.Query().Get("query"), r.URL.Query().Get("dataType")))
		case strings.HasPrefix(r.URL.Path, "/food/"):
			ff.usdaDetail.Add(1)
			_ = json.NewEncoder(w).Encode(obj{"fdcId": 171688, "foodPortions": []obj{
				{"amount": 1, "gramWeight": 182, "modifier": `medium (3" dia)`, "measureUnit": obj{"name": "undetermined"}},
				{"amount": 1, "gramWeight": 109, "modifier": "slices", "measureUnit": obj{"name": "cup"}},
			}})
		default:
			http.NotFound(w, r)
		}
	}))
	off := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		ff.offSearch.Add(1)
		ff.mu.Lock()
		ff.offUA = r.UserAgent()
		ff.mu.Unlock()
		if r.URL.Path != "/cgi/search.pl" || r.URL.Query().Get("json") != "1" || r.URL.Query().Get("page_size") != "5" {
			http.NotFound(w, r)
			return
		}
		if ff.offStatus != 200 {
			w.WriteHeader(ff.offStatus)
			return
		}
		_ = json.NewEncoder(w).Encode(ff.off(r.URL.Query().Get("search_terms")))
	}))
	t.Cleanup(usda.Close)
	t.Cleanup(off.Close)
	foods := NewFoods("test-key", "1.2.3")
	foods.USDA.BaseURL = usda.URL
	foods.OFF.BaseURL = off.URL
	return ff, foods
}

func nutrients(kcal, protein, carbs, fat, fiber float64, ids [5]int) []obj {
	vals := [5]float64{kcal, protein, carbs, fat, fiber}
	var out []obj
	for i, v := range vals {
		out = append(out, obj{"nutrientId": ids[i], "value": v})
	}
	return out
}

var srIDs = [5]int{1008, 1003, 1005, 1004, 1079}

func appleFoods(string, string) any {
	return obj{"foods": []obj{
		{"fdcId": 168171, "description": "Rose-apples, raw", "dataType": "SR Legacy", "foodNutrients": nutrients(25, 0.6, 5.7, 0.3, 0, srIDs)},
		{"fdcId": 171688, "description": "Apples, raw, with skin", "dataType": "SR Legacy", "foodNutrients": nutrients(52, 0.26, 13.8, 0.17, 2.4, srIDs)},
	}}
}

func chompsProducts(string) any {
	return obj{"products": []obj{
		{"code": "1", "product_name": "Original Beef Jerky", "brands": "Jack Link's", "serving_size": "28 g", "serving_quantity": 28,
			"nutriments": obj{"energy-kcal_100g": 330, "energy-kcal_serving": 92}},
		{"code": "850", "product_name": "Original Beef Stick", "brands": "Chomps", "serving_size": "1 stick (32 g)", "serving_quantity": "32",
			"nutriments": obj{"energy-kcal_100g": 281.25, "energy-kcal_serving": 90, "proteins_serving": 10, "carbohydrates_serving": 0,
				"fat_serving": 6, "fiber_serving": 0}},
	}}
}

func exampleSplit() func(obj) any {
	return splitItems(
		item("an apple", "Apple", "apple, raw", nil, 1, "medium", nil, "generic"),
		item("a chomp meat stick", "Chomps stick", "original beef stick", "Chomps", 1, "stick", nil, "branded"),
		item("a hotpocket", "Hot Pocket", "pepperoni pizza", "Hot Pockets", 1, "piece", nil, "branded"),
	)
}

func TestMealItemizesTheExampleFromDatabasesAndFallsBackToAnEstimate(t *testing.T) {
	claude, client := newFakeClaude(t)
	claude.tools["split_meal"] = exampleSplit()
	claude.tools["report_meal_estimate"] = itemEstimate(300, "medium")
	ff, foods := newFakeFoods(t)
	ff.usda = appleFoods
	ff.off = chompsProducts
	e := &Estimator{Client: client, Foods: foods}

	m, err := e.Meal(context.Background(), "an apple, a chomp meat stick, and a hotpocket")
	if err != nil {
		t.Fatal(err)
	}
	if len(m.Items) != 3 {
		t.Fatalf("items = %+v", m.Items)
	}
	apple, chomps, pocket := m.Items[0], m.Items[1], m.Items[2]

	// 52 kcal per 100 g and a 182 g medium apple, from the portion list in the detail record.
	if apple.Source != "usda" || apple.SourceID != "171688" || apple.MatchedName != "Apples, raw, with skin" ||
		apple.Kcal != 95 || apple.Grams != 182 || apple.Name != "Apple" || apple.Confidence != "high" {
		t.Fatalf("apple = %+v", apple)
	}
	// Per-serving numbers are used as printed, and the other brand's product is ignored.
	if chomps.Source != "openfoodfacts" || chomps.SourceID != "850" || chomps.Kcal != 90 || chomps.Protein != 10 ||
		chomps.Fat != 6 || chomps.Grams != 32 || chomps.Confidence != "high" {
		t.Fatalf("chomps = %+v", chomps)
	}
	if pocket.Source != "estimated" || pocket.SourceID != "" || pocket.MatchedName != "" || pocket.Kcal != 300 ||
		pocket.Confidence != "medium" || pocket.Name != "Hot Pocket" {
		t.Fatalf("pocket = %+v", pocket)
	}
	if claude.calls("split_meal") != 1 || claude.calls("report_meal_estimate") != 1 {
		t.Fatalf("claude calls: split %d, estimate %d", claude.calls("split_meal"), claude.calls("report_meal_estimate"))
	}

	if m.Total.Kcal != 485 || m.Total.Protein != 15.3 || m.DatabaseShare != 62 {
		t.Fatalf("total = %+v share %d", m.Total, m.DatabaseShare)
	}
	// The one-meal fields older app builds read.
	if m.Name != "Apple, Chomps stick, Hot Pocket" || m.Kcal != 485 || m.Protein != 15.3 || m.Confidence != "low" && m.Confidence != "medium" ||
		!strings.Contains(m.Notes, "2 of 3") {
		t.Fatalf("legacy = %+v", m.Estimate)
	}
	if ff.offUA != "NewMe/1.2.3 (self-hosted)" {
		t.Fatalf("User-Agent = %q", ff.offUA)
	}
}

func TestMealJSONKeepsLegacyFieldsAtTheTopLevel(t *testing.T) {
	m := assemble([]ItemResult{{Name: "Apple", Kcal: 95, Protein: 0.5, Source: "usda", Confidence: "high"}})
	raw, _ := json.Marshal(m)
	var got obj
	_ = json.Unmarshal(raw, &got)
	for _, key := range []string{"name", "kcal", "protein", "carbs", "fat", "fiber", "confidence", "notes", "items", "total", "databaseShare"} {
		if _, ok := got[key]; !ok {
			t.Errorf("missing %q in %s", key, raw)
		}
	}
	items := got["items"].([]any)[0].(obj)
	for _, key := range []string{"text", "name", "quantity", "unit", "grams", "kcal", "protein", "carbs", "fat", "fiber", "source", "sourceId", "matchedName", "confidence"} {
		if _, ok := items[key]; !ok {
			t.Errorf("missing item key %q", key)
		}
	}
}

func TestSplitStepNeverAsksForNutrition(t *testing.T) {
	claude, client := newFakeClaude(t)
	claude.tools["split_meal"] = exampleSplit()
	claude.tools["report_meal_estimate"] = itemEstimate(100, "low")
	e := &Estimator{Client: client}
	if _, err := e.Meal(context.Background(), "toast"); err != nil {
		t.Fatal(err)
	}
	req := claude.requests[0]
	if req["model"] != "claude-sonnet-4-6" {
		t.Fatalf("model = %v", req["model"])
	}
	system := req["system"].(string)
	if !strings.Contains(system, "Do not give or invent any nutrition values") {
		t.Fatalf("prompt = %q", system)
	}
	schema, _ := json.Marshal(req["tools"].([]any)[0].(obj)["input_schema"])
	for _, banned := range []string{"kcal", "protein", "calories", "carbs"} {
		if strings.Contains(string(schema), banned) {
			t.Errorf("split schema must not ask for %q", banned)
		}
	}
}

func TestParseItemsValidatesAndIgnoresInventedNutrition(t *testing.T) {
	items, err := parseItems(json.RawMessage(`{"items":[
		{"text":"2 eggs","label":"","food":"egg, whole, cooked","brand":null,"quantity":2,"unit":"","grams":-5,"kind":"generic","kcal":999},
		{"text":"x","food":"","brand":"B","quantity":0,"unit":"CUP","grams":120,"kind":"BRANDED"},
		{"text":" ","food":" "}]}`))
	if err != nil {
		t.Fatal(err)
	}
	if len(items) != 2 {
		t.Fatalf("items = %+v", items)
	}
	if a := items[0]; a.Quantity != 2 || a.Unit != "serving" || a.Grams != nil || a.Label != "2 eggs" || a.Kind != KindGeneric {
		t.Fatalf("a = %+v", a)
	}
	if b := items[1]; b.Quantity != 1 || b.Unit != "cup" || b.Grams == nil || *b.Grams != 120 || b.Kind != KindBranded || b.Food != "x" {
		t.Fatalf("b = %+v", b)
	}
	for _, bad := range []string{`{}`, `{"items":[]}`, `nope`} {
		if _, err := parseItems(json.RawMessage(bad)); !errors.Is(err, ErrUnusable) {
			t.Errorf("%s: err = %v", bad, err)
		}
	}
}

func TestAnItemTheDatabasesFailOnBecomesEstimated(t *testing.T) {
	claude, client := newFakeClaude(t)
	claude.tools["split_meal"] = splitItems(
		item("an apple", "Apple", "apple, raw", nil, 1, "medium", nil, "generic"),
		item("a chomps stick", "Chomps stick", "original beef stick", "Chomps", 1, "stick", nil, "branded"))
	claude.tools["report_meal_estimate"] = itemEstimate(120, "medium")
	ff, foods := newFakeFoods(t)
	ff.usdaStatus = http.StatusInternalServerError
	ff.offStatus = http.StatusServiceUnavailable
	e := &Estimator{Client: client, Foods: foods}

	m, err := e.Meal(context.Background(), "apple and chomps")
	if err != nil {
		t.Fatal(err)
	}
	for _, it := range m.Items {
		if it.Source != "estimated" || it.Kcal != 120 {
			t.Fatalf("item = %+v", it)
		}
	}
	if m.DatabaseShare != 0 || m.Total.Kcal != 240 {
		t.Fatalf("meal = %+v", m)
	}
}

func TestBrandedItemFallsBackFromOpenFoodFactsToUSDABranded(t *testing.T) {
	claude, client := newFakeClaude(t)
	claude.tools["split_meal"] = splitItems(item("a hot pocket", "Hot Pocket", "pepperoni pizza", "Hot Pockets", 1, "piece", nil, "branded"))
	ff, foods := newFakeFoods(t)
	ff.offStatus = http.StatusServiceUnavailable
	ff.usda = func(_, dataType string) any {
		if dataType != "Branded" {
			t.Errorf("dataType = %q", dataType)
		}
		return obj{"foods": []obj{{"fdcId": 2000, "description": "PEPPERONI PIZZA SANDWICHES", "dataType": "Branded",
			"brandOwner": "Nestle", "brandName": "HOT POCKETS", "servingSize": 127.0, "servingSizeUnit": "g",
			"householdServingFullText": "1 sandwich", "foodNutrients": nutrients(260, 9, 31, 11, 1.6, srIDs)}}}
	}
	e := &Estimator{Client: client, Foods: foods}
	m, err := e.Meal(context.Background(), "a hot pocket")
	if err != nil {
		t.Fatal(err)
	}
	it := m.Items[0]
	// 260 kcal per 100 g and one 127 g serving.
	if it.Source != "usda" || it.SourceID != "2000" || it.Kcal != 330 || it.Grams != 127 || !strings.Contains(it.MatchedName, "HOT POCKETS") {
		t.Fatalf("item = %+v", it)
	}
	if claude.calls("report_meal_estimate") != 0 {
		t.Fatal("no estimate should be needed")
	}
}

func TestLookupsAreCachedForAnHour(t *testing.T) {
	claude, client := newFakeClaude(t)
	claude.tools["split_meal"] = splitItems(item("an apple", "Apple", "apple, raw", nil, 1, "medium", nil, "generic"))
	ff, foods := newFakeFoods(t)
	ff.usda = appleFoods
	now := timeNow()
	foods.cache = newTTLCache(now.get)
	e := &Estimator{Client: client, Foods: foods}

	for range 2 {
		if _, err := e.Meal(context.Background(), "an apple"); err != nil {
			t.Fatal(err)
		}
	}
	if ff.usdaSearch.Load() != 1 || ff.usdaDetail.Load() != 1 {
		t.Fatalf("search %d, detail %d, want 1 and 1", ff.usdaSearch.Load(), ff.usdaDetail.Load())
	}
	now.advance(61 * 60)
	if _, err := e.Meal(context.Background(), "an apple"); err != nil {
		t.Fatal(err)
	}
	if ff.usdaSearch.Load() != 2 {
		t.Fatalf("search after expiry = %d", ff.usdaSearch.Load())
	}
}

func TestFailedLookupsAreNotCached(t *testing.T) {
	claude, client := newFakeClaude(t)
	claude.tools["split_meal"] = splitItems(item("an apple", "Apple", "apple, raw", nil, 1, "medium", nil, "generic"))
	claude.tools["report_meal_estimate"] = itemEstimate(90, "low")
	ff, foods := newFakeFoods(t)
	ff.usdaStatus = http.StatusServiceUnavailable
	e := &Estimator{Client: client, Foods: foods}
	if _, err := e.Meal(context.Background(), "an apple"); err != nil {
		t.Fatal(err)
	}
	ff.usdaStatus = http.StatusOK
	ff.usda = appleFoods
	m, err := e.Meal(context.Background(), "an apple")
	if err != nil || m.Items[0].Source != "usda" {
		t.Fatalf("second try = %+v, %v", m.Items, err)
	}
}

func TestNothingSizedFailsTheMealButOneSizedItemDoesNot(t *testing.T) {
	claude, client := newFakeClaude(t)
	claude.tools["split_meal"] = splitItems(
		item("a", "Alpha", "alpha", nil, 1, "serving", nil, "generic"),
		item("b", "Beta", "beta", nil, 1, "serving", nil, "generic"))
	var n atomic.Int32
	claude.tools["report_meal_estimate"] = func(obj) any {
		if n.Add(1)%2 == 0 {
			return obj{"name": "no energy"}
		}
		return obj{"name": "x", "kcal": 100, "confidence": "low"}
	}
	e := &Estimator{Client: client}
	m, err := e.Meal(context.Background(), "alpha, beta")
	if err != nil {
		t.Fatal(err)
	}
	zero := 0
	for _, it := range m.Items {
		if it.Kcal == 0 && it.Source == "estimated" && it.Confidence == "low" {
			zero++
		}
	}
	if zero != 1 || m.Total.Kcal != 100 {
		t.Fatalf("meal = %+v", m)
	}

	claude.tools["report_meal_estimate"] = func(obj) any { return obj{"name": "no energy"} }
	if _, err := e.Meal(context.Background(), "alpha, beta"); !errors.Is(err, ErrUnusable) {
		t.Fatalf("err = %v", err)
	}
	claude.status = http.StatusInternalServerError
	if _, err := e.Meal(context.Background(), "alpha"); !errors.Is(err, anthropic.ErrUpstream) {
		t.Fatalf("split failure err = %v", err)
	}
}

func TestEstimatedAndDatabaseNumbersAreClampedToTheMealLogBounds(t *testing.T) {
	claude, client := newFakeClaude(t)
	claude.tools["split_meal"] = splitItems(
		item("big", "Big", "huge thing", nil, 1, "serving", nil, "generic"),
		item("big2", "Big two", "huge thing two", nil, 1, "serving", nil, "generic"),
		item("ounces", "Beef", "beef, ground", nil, 1000, "oz", nil, "generic"))
	claude.tools["report_meal_estimate"] = func(obj) any {
		return obj{"name": "x", "kcal": 1e9, "protein": 99999, "carbs": -4, "fat": 1.26, "fiber": 0, "confidence": "certain"}
	}
	ff, foods := newFakeFoods(t)
	ff.usda = func(q, _ string) any {
		if !strings.Contains(q, "beef") {
			return obj{"foods": []obj{}}
		}
		return obj{"foods": []obj{{"fdcId": 1, "description": "Beef, ground, raw", "dataType": "SR Legacy", "foodNutrients": nutrients(250, 17, 0, 20, 0, srIDs)}}}
	}
	e := &Estimator{Client: client, Foods: foods}
	m, err := e.Meal(context.Background(), "lots")
	if err != nil {
		t.Fatal(err)
	}
	big, beef := m.Items[0], m.Items[2]
	if big.Kcal != MaxKcal || big.Protein != MaxMacroGrams || big.Carbs != 0 || big.Fat != 1.3 || big.Confidence != "low" {
		t.Fatalf("big = %+v", big)
	}
	// 1000 oz of beef is 28 kg, far past a meal.
	if beef.Source != "usda" || beef.Kcal != MaxKcal || beef.Grams != maxItemGrams {
		t.Fatalf("beef = %+v", beef)
	}
	if m.Total.Kcal != MaxKcal || m.Total.Protein != MaxMacroGrams || m.Kcal != MaxKcal || m.DatabaseShare != 33 {
		t.Fatalf("total = %+v / %+v share %d", m.Total, m.Estimate, m.DatabaseShare)
	}
}

func decodeUSDA(id int, desc string, ns []obj) usdaFood {
	raw, _ := json.Marshal(obj{"fdcId": id, "description": desc, "foodNutrients": ns})
	var f usdaFood
	_ = json.Unmarshal(raw, &f)
	return f
}

func TestFoundationEnergyFallsBackToAtwaterAndKilojoules(t *testing.T) {
	atwater := decodeUSDA(1, "x", nutrients(61, 0.1, 14, 0.2, 2, [5]int{2047, 1003, 1005, 1004, 1079}))
	f, ok := atwater.toFood()
	if !ok || f.Per100g.Kcal != 61 || f.Per100g.Fiber != 2 {
		t.Fatalf("atwater = %+v %v", f, ok)
	}
	kj := usdaFood{FdcID: 2, Description: "y", FoodNutrients: []usdaNutrient{{NutrientID: 1062, Value: 418.4}}}
	f, ok = kj.toFood()
	if !ok || int(f.Per100g.Kcal) != 100 {
		t.Fatalf("kj = %+v", f)
	}
	none := decodeUSDA(3, "z", nutrients(0, 1, 1, 1, 1, [5]int{9, 1003, 1005, 1004, 1079}))
	if _, ok := none.toFood(); ok {
		t.Fatal("a food without energy is unusable")
	}
}

func TestDatabaseFailuresAndAbsentFoodsDoNotCallTheDatabasesForNoFoods(t *testing.T) {
	_, foods := newFakeFoods(t)
	if _, ok, err := foods.Lookup(context.Background(), Item{}); ok || err != nil {
		t.Fatalf("empty item: ok=%v err=%v", ok, err)
	}
}
