package api

import (
	"net/http"
	"net/http/httptest"
	"testing"
)

func TestFoodByBarcode(t *testing.T) {
	var calls int
	off := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		calls++
		switch r.URL.Path {
		case "/api/v2/product/3017620422003":
			writeJSON(w, http.StatusOK, obj{"status": 1, "product": obj{"code": "3017620422003", "product_name": "Hazelnut spread",
				"brands": "Ferrero", "serving_size": "15 g", "serving_quantity": 15,
				"image_front_small_url": "https://images.openfoodfacts.org/x.200.jpg",
				"nutriments":            obj{"energy-kcal_100g": 539, "energy-kcal_serving": 81, "proteins_100g": 6.3, "proteins_serving": 0.9}}})
		case "/api/v2/product/96385074":
			writeJSON(w, http.StatusOK, obj{"status": 0, "status_verbose": "product not found"})
		default:
			w.WriteHeader(http.StatusBadGateway)
		}
	}))
	t.Cleanup(off.Close)
	h := newHarness(t, func(s *Server) { s.foods.OFF.BaseURL = off.URL })
	nick := h.joinAdmin("Nick", "green")

	got := h.get("/api/foods/barcode/3017620422003", nick.Token).expect(http.StatusOK)
	if got.flag("saved") || got.str("name") != "Hazelnut spread" || got.str("source") != "openfoodfacts" || got.str("sourceId") != "3017620422003" ||
		got.num("kcal") != 81 || got.str("imageUrl") == "" || got.str("sourceUrl") != "https://world.openfoodfacts.org/product/3017620422003" {
		t.Fatalf("candidate = %s", got.Body)
	}

	// Once saved, the saved copy answers without another Open Food Facts call.
	h.post("/api/foods", nick.Token, obj{"name": "Hazelnut spread", "servingText": "15 g", "kcal": 81, "source": "openfoodfacts", "sourceId": "3017620422003"}).expect(http.StatusCreated)
	before := calls
	saved := h.get("/api/foods/barcode/3017620422003", nick.Token).expect(http.StatusOK)
	if !saved.flag("saved") || calls != before {
		t.Fatalf("saved = %s, calls %d -> %d", saved.Body, before, calls)
	}

	h.get("/api/foods/barcode/96385074", nick.Token).expect(http.StatusNotFound).code("not_found")
	h.get("/api/foods/barcode/00012345678905", nick.Token).expect(http.StatusBadGateway).code("unavailable")
	h.get("/api/foods/barcode/3017620422004", nick.Token).expect(http.StatusUnprocessableEntity).code("invalid_request")
	h.get("/api/foods/barcode/abc", nick.Token).expect(http.StatusUnprocessableEntity)
	h.get("/api/foods/barcode/3017620422003", "").expect(http.StatusUnauthorized)
}
