package api

import (
	"net/http"
	"strings"
	"testing"
)

func TestProduceInsideMealsCountsTowardTheQuestAndSaysWhere(t *testing.T) {
	h := newHarness(t)
	nick := h.joinAdmin("Nick", "green")
	enableV17(t, h, nick, "produce")

	// 170 g of whole produce over two meals, one glass of juice: 170 + 80 = 250 g, three servings.
	h.logMeal(nick, "Salad", 200, 5, obj{"produceG": 100}).expect(http.StatusCreated)
	h.logMeal(nick, "Stir fry", 400, 20, obj{"produceG": 70, "juiceG": 250}).expect(http.StatusCreated)
	h.logActivity(nick, "produce", "servings", 1).expect(http.StatusCreated)

	today := h.get("/api/today", nick.Token).expect(http.StatusOK)
	q := questIndex(t, today, "produce")
	if today.num(q+".actual") != 4 || today.num(q+".detail.fromMeals") != 3 || today.num(q+".detail.logged") != 1 {
		t.Fatalf("3 from meals and 1 logged = %s", today.Body)
	}

	done := h.logMeal(nick, "Big bowl", 300, 8, obj{"produceG": 90}).expect(http.StatusCreated)
	q = questAt(t, done, "day.quests", "produce")
	if !done.flag(q+".done") || done.num(q+".actual") != 5 {
		t.Fatalf("260 g plus a juice and a logged serving = 5 servings: %s", done.Body)
	}
}

func TestJuiceAndPulsesInMealsCountOncePerDay(t *testing.T) {
	h := newHarness(t)
	nick := h.joinAdmin("Nick", "green")
	enableV17(t, h, nick, "produce")

	h.logMeal(nick, "Juice", 100, 1, obj{"juiceG": 300}).expect(http.StatusCreated)
	h.logMeal(nick, "Juice again", 100, 1, obj{"juiceG": 300}).expect(http.StatusCreated)
	h.logMeal(nick, "Chili", 500, 25, obj{"pulseG": 400}).expect(http.StatusCreated)

	today := h.get("/api/today", nick.Token).expect(http.StatusOK)
	if got := today.num(questIndex(t, today, "produce") + ".actual"); got != 2 {
		t.Fatalf("600 g of juice and 400 g of beans = %d servings, want one of each: %s", got, today.Body)
	}
}

func TestAMealLogCarriesItsProduceBack(t *testing.T) {
	h := newHarness(t)
	nick := h.joinAdmin("Nick", "green")

	got := h.logMeal(nick, "Salad", 200, 5, obj{"produceG": 120.44}).expect(http.StatusCreated)
	if got.at("log.produceG") != 120.4 {
		t.Fatalf("log = %s", got.Body)
	}
	plain := h.logMeal(nick, "Toast", 100, 3).expect(http.StatusCreated)
	if strings.Contains(string(plain.Body), "produceG") {
		t.Fatalf("a meal with no produce sends none: %s", plain.Body)
	}
	recent := h.get("/api/meals/recent", nick.Token).expect(http.StatusOK)
	found := false
	for i := range recent.length("meals") {
		p := "meals." + itoa(i)
		if recent.str(p+".name") == "Salad" {
			found = recent.at(p+".produceG") == 120.4
		}
	}
	if !found {
		t.Fatalf("a recent meal keeps its produce: %s", recent.Body)
	}
}

func TestMealProduceGramsAreBounded(t *testing.T) {
	h := newHarness(t)
	nick := h.joinAdmin("Nick", "green")
	for _, bad := range []obj{{"produceG": -1}, {"juiceG": 10001}, {"pulseG": -0.5}} {
		h.logMeal(nick, "Salad", 200, 5, bad).expect(http.StatusUnprocessableEntity)
	}
	h.logMeal(nick, "Salad", 200, 5, obj{"produceG": 10000}).expect(http.StatusCreated)
}

func TestASavedFoodKeepsWhatItsDatabaseSaidItIs(t *testing.T) {
	h := newHarness(t)
	nick := h.joinAdmin("Nick", "green")

	created := h.post("/api/foods", nick.Token, obj{"name": "Apple", "servingText": "1 medium (182 g)",
		"servingGrams": 182, "kcal": 95, "source": "usda", "sourceId": "171688", "produceKind": "fruit"}).expect(http.StatusCreated)
	if created.str("produceKind") != "fruit" {
		t.Fatalf("food = %s", created.Body)
	}
	listed := h.get("/api/foods", nick.Token).expect(http.StatusOK)
	if listed.str("foods.0.produceKind") != "fruit" {
		t.Fatalf("list = %s", listed.Body)
	}
	h.post("/api/foods", nick.Token, obj{"name": "Mystery", "servingText": "1", "kcal": 10,
		"produceKind": "potato"}).expect(http.StatusUnprocessableEntity)
	plain := h.post("/api/foods", nick.Token, obj{"name": "Toast", "servingText": "1 slice", "kcal": 80}).expect(http.StatusCreated)
	if plain.str("produceKind") != "" {
		t.Fatalf("a food that is not produce says so with an empty kind: %s", plain.Body)
	}
}
