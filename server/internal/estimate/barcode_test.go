package estimate

import (
	"context"
	"encoding/json"
	"errors"
	"net/http"
	"net/http/httptest"
	"testing"
)

func TestValidBarcode(t *testing.T) {
	for code, want := range map[string]bool{
		"3017620422003": true, "036000291452": true, "96385074": true, "00012345678905": true,
		"3017620422004": false, "1234567": false, "123456789012345": false, "30176204220a3": false, "": false,
	} {
		if got := ValidBarcode(code); got != want {
			t.Errorf("ValidBarcode(%q) = %v, want %v", code, got, want)
		}
	}
}

func TestOFFProduct(t *testing.T) {
	var gotPath, gotFields, gotUA string
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		gotPath, gotFields, gotUA = r.URL.Path, r.URL.Query().Get("fields"), r.UserAgent()
		switch r.URL.Path {
		case "/api/v2/product/3017620422003":
			_ = json.NewEncoder(w).Encode(obj{"status": 1, "product": obj{"code": "3017620422003", "product_name": "Hazelnut spread", "brands": "Nutella,Ferrero",
				"serving_size": "15 g", "serving_quantity": 15,
				"image_front_small_url": "https://images.openfoodfacts.org/x.200.jpg",
				"nutriments":            obj{"energy-kcal_100g": 539, "energy-kcal_serving": 81, "proteins_100g": 6.3}}})
		case "/api/v2/product/96385074":
			_ = json.NewEncoder(w).Encode(obj{"status": 0, "status_verbose": "product not found"})
		case "/api/v2/product/036000291452":
			_ = json.NewEncoder(w).Encode(obj{"status": 1, "product": obj{"code": "036000291452", "product_name": "No numbers", "nutriments": obj{}}})
		default:
			w.WriteHeader(http.StatusInternalServerError)
		}
	}))
	defer srv.Close()
	o := NewOpenFoodFacts("1.2.3")
	o.BaseURL = srv.URL

	f, err := o.Product(context.Background(), "3017620422003")
	if err != nil || f.Name != "Hazelnut spread" || f.Brand != "Nutella Ferrero" || f.ServingGrams != 15 || f.PerServing == nil ||
		f.ImageURL == "" || f.SourceURL != OFFBaseURL+"/product/3017620422003" {
		t.Fatalf("food = %+v err = %v", f, err)
	}
	if gotPath != "/api/v2/product/3017620422003" || gotFields == "" || gotUA != "NewMe/1.2.3 (self-hosted)" {
		t.Fatalf("request = %q %q %q", gotPath, gotFields, gotUA)
	}
	for _, code := range []string{"96385074", "036000291452"} {
		if _, err := o.Product(context.Background(), code); !errors.Is(err, ErrNoProduct) {
			t.Fatalf("%s err = %v", code, err)
		}
	}
	if _, err := o.Product(context.Background(), "00012345678905"); !errors.Is(err, ErrLookup) {
		t.Fatalf("500 err = %v", err)
	}
}
