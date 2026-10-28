package api

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"slices"
	"strings"
	"testing"
)

func apple() obj {
	return obj{"name": "Apple", "servingText": "1 medium (182 g)", "servingGrams": 182, "kcal": 95, "protein": 0.5,
		"carbs": 25.1, "fat": 0.3, "fiber": 4.4, "source": "usda", "sourceId": "171688",
		"servings": []obj{{"text": "1 cup slices", "grams": 109}}}
}

func TestFoodLibraryCreateSearchPatchUseDelete(t *testing.T) {
	h := newHarness(t)
	nick, nadia := h.pair()

	created := h.post("/api/foods", nick.Token, apple()).expect(http.StatusCreated)
	id := created.num("id")
	if !created.flag("saved") || created.str("name") != "Apple" || created.num("kcal") != 95 || created.at("servings.0.grams") != 109.0 {
		t.Fatalf("created = %s", created.Body)
	}
	// Saving the same database food again returns the saved copy, so save-on-log can repeat.
	again := h.post("/api/foods", nadia.Token, apple()).expect(http.StatusOK)
	if again.num("id") != id {
		t.Fatalf("duplicate saved twice: %s", again.Body)
	}
	h.post("/api/foods", nadia.Token, obj{"name": "Oat bar", "servingText": "1 bar", "kcal": 190, "protein": 4}).expect(http.StatusCreated)

	// The library is shared and ranks the most used first.
	h.post("/api/foods/"+itoa(id)+"/use", nadia.Token, nil).expect(http.StatusOK)
	h.post("/api/foods/"+itoa(id)+"/use", nick.Token, nil).expect(http.StatusOK)
	list := h.get("/api/foods", nadia.Token).expect(http.StatusOK)
	if list.str("foods.0.name") != "Apple" || list.num("foods.0.useCount") != 2 || list.at("foods.0.lastUsedAt") == nil {
		t.Fatalf("list = %s", list.Body)
	}
	found := h.get("/api/foods?q=oat", nick.Token).expect(http.StatusOK)
	if len(found.at("foods").([]any)) != 1 || len(found.at("candidates").([]any)) != 0 {
		t.Fatalf("search = %s", found.Body)
	}

	patched := h.patch("/api/foods/"+itoa(id), nick.Token, obj{"kcal": 100, "servingText": "1 large (200 g)", "servingGrams": 200}).expect(http.StatusOK)
	if patched.num("kcal") != 100 || patched.str("servingText") != "1 large (200 g)" || patched.str("name") != "Apple" {
		t.Fatalf("patched = %s", patched.Body)
	}
	h.patch("/api/foods/"+itoa(id), nick.Token, obj{"source": "manual"}).expect(http.StatusUnprocessableEntity).code("invalid_request")

	h.delete("/api/foods/"+itoa(id), nadia.Token).expect(http.StatusNoContent)
	h.delete("/api/foods/"+itoa(id), nadia.Token).expect(http.StatusNotFound).code("not_found")
	h.post("/api/foods/"+itoa(id)+"/use", nick.Token, nil).expect(http.StatusNotFound)
	h.patch("/api/foods/"+itoa(id), nick.Token, obj{"kcal": 1}).expect(http.StatusNotFound)
	h.get("/api/foods", "").expect(http.StatusUnauthorized)
}

func TestFoodLibraryValidation(t *testing.T) {
	h := newHarness(t)
	nick := h.joinAdmin("Nick", "green")
	bad := map[string]obj{
		"no name":        {"servingText": "1", "kcal": 1},
		"blank name":     {"name": "  ", "servingText": "1", "kcal": 1},
		"long name":      {"name": strings.Repeat("a", 81), "servingText": "1", "kcal": 1},
		"no serving":     {"name": "x", "kcal": 1},
		"no kcal":        {"name": "x", "servingText": "1"},
		"kcal too big":   {"name": "x", "servingText": "1", "kcal": 10001},
		"negative macro": {"name": "x", "servingText": "1", "kcal": 1, "fat": -1},
		"macro too big":  {"name": "x", "servingText": "1", "kcal": 1, "protein": 5001},
		"grams too big":  {"name": "x", "servingText": "1", "kcal": 1, "servingGrams": 5001},
		"bad source":     {"name": "x", "servingText": "1", "kcal": 1, "source": "web"},
		"too many alts":  {"name": "x", "servingText": "1", "kcal": 1, "servings": make([]obj, 9)},
		"alt without wt": {"name": "x", "servingText": "1", "kcal": 1, "servings": []obj{{"text": "cup", "grams": 0}}},
		"control chars":  {"name": "a\x00b", "servingText": "1", "kcal": 1},
	}
	for name, body := range bad {
		t.Run(name, func(t *testing.T) {
			h.post("/api/foods", nick.Token, body).expect(http.StatusUnprocessableEntity).code("invalid_request")
		})
	}
	h.post("/api/foods", nick.Token, obj{"name": "x", "servingText": "1", "kcal": 1, "extra": 1}).expect(http.StatusBadRequest).code("invalid_json")
	h.get("/api/foods/abc", nick.Token).expect(http.StatusMethodNotAllowed)
	h.delete("/api/foods/abc", nick.Token).expect(http.StatusNotFound)
}

func TestFoodSearchReturnsRemoteCandidatesOnlyOnRequest(t *testing.T) {
	usda := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != "/foods/search" {
			http.NotFound(w, r)
			return
		}
		var req struct {
			DataType []string `json:"dataType"`
		}
		if r.Method != http.MethodPost || json.NewDecoder(r.Body).Decode(&req) != nil {
			http.Error(w, "bad search", http.StatusBadRequest)
			return
		}
		foods := []obj{}
		if !slices.Contains(req.DataType, "Branded") {
			foods = append(foods, obj{"fdcId": 171688, "description": "Apples, raw, with skin", "dataType": "SR Legacy",
				"foodNutrients": []obj{{"nutrientId": 1008, "value": 52}, {"nutrientId": 1003, "value": 0.26}}})
		}
		writeJSON(w, http.StatusOK, obj{"foods": foods})
	}))
	t.Cleanup(usda.Close)
	h := newHarness(t, func(s *Server) {
		s.foods.USDA.BaseURL = usda.URL
		s.foods.OFF = nil
	})
	nick := h.joinAdmin("Nick", "green")

	local := h.get("/api/foods?q=apple", nick.Token).expect(http.StatusOK)
	if len(local.at("candidates").([]any)) != 0 {
		t.Fatalf("remote must be opt-in: %s", local.Body)
	}
	remote := h.get("/api/foods?q=apple&remote=1", nick.Token).expect(http.StatusOK)
	c := remote.at("candidates.0").(map[string]any)
	if c["id"] != nil || c["saved"] != false || c["source"] != "usda" || c["sourceId"] != "171688" || c["servingText"] != "100 g" || c["kcal"] != 52.0 {
		t.Fatalf("candidate = %v", c)
	}

	// Once saved it stops showing up as a candidate.
	h.post("/api/foods", nick.Token, obj{"name": "Apple", "servingText": "100 g", "kcal": 52, "source": "usda", "sourceId": "171688"}).expect(http.StatusCreated)
	after := h.get("/api/foods?q=apple&remote=1", nick.Token).expect(http.StatusOK)
	if len(after.at("candidates").([]any)) != 0 || len(after.at("foods").([]any)) != 1 {
		t.Fatalf("after save = %s", after.Body)
	}
}

func TestEstimateAnswersFromTheLibraryWithoutCallingClaude(t *testing.T) {
	fake, srv := newFakeClaude(t)
	h := newHarness(t, withClaude(srv), func(s *Server) { s.estimator.Library = libraryStore{s.db} })
	nick := h.joinAdmin("Nick", "green")
	id := h.post("/api/foods", nick.Token, apple()).expect(http.StatusCreated).num("id")

	got := h.post("/api/meals/estimate", nick.Token, obj{"text": "2 apples"}).expect(http.StatusOK)
	if fake.count() != 0 {
		t.Fatalf("claude calls = %d", fake.count())
	}
	if got.str("items.0.source") != "library" || got.str("items.0.sourceId") != itoa(id) || got.num("items.0.kcal") != 190 ||
		got.num("kcal") != 190 || got.num("databaseShare") != 100 {
		t.Fatalf("estimate = %s", got.Body)
	}
}
