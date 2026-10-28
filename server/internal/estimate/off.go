package estimate

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"regexp"
	"strconv"
	"strings"
)

// OFFBaseURL is Open Food Facts' world database.
const OFFBaseURL = "https://world.openfoodfacts.org"

// OpenFoodFacts searches the crowd-sourced label database.
type OpenFoodFacts struct {
	BaseURL string
	// UserAgent identifies the app, which Open Food Facts asks every client to do.
	UserAgent string
	HTTP      *http.Client
}

// NewOpenFoodFacts builds a client that identifies itself as NewMe/<version>.
func NewOpenFoodFacts(version string) *OpenFoodFacts {
	return &OpenFoodFacts{BaseURL: OFFBaseURL, UserAgent: offUserAgent(version), HTTP: &http.Client{Timeout: lookupTimeout}}
}

func offUserAgent(version string) string {
	if version == "" {
		version = "dev"
	}
	return "NewMe/" + version + " (self-hosted)"
}

type offProduct struct {
	Code            string          `json:"code"`
	Name            string          `json:"product_name"`
	Brands          string          `json:"brands"`
	ServingSize     string          `json:"serving_size"`
	ServingQuantity json.RawMessage `json:"serving_quantity"`
	Nutriments      map[string]any  `json:"nutriments"`
	ImageSmallURL   string          `json:"image_front_small_url"`
	ImageFrontURL   string          `json:"image_front_url"`
}

// Search returns up to five products for the query.
func (o *OpenFoodFacts) Search(ctx context.Context, query string) ([]Food, error) {
	q := url.Values{}
	q.Set("search_terms", query)
	q.Set("search_simple", "1")
	q.Set("action", "process")
	q.Set("json", "1")
	q.Set("page_size", "5")
	q.Set("fields", "code,product_name,brands,serving_size,serving_quantity,nutriments,image_front_small_url,image_front_url")
	ctx, cancel := context.WithTimeout(ctx, lookupTimeout)
	defer cancel()
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, o.BaseURL+"/cgi/search.pl?"+q.Encode(), nil)
	if err != nil {
		return nil, err
	}
	req.Header.Set("User-Agent", o.UserAgent)
	resp, err := o.HTTP.Do(req)
	if err != nil {
		return nil, fmt.Errorf("%w: openfoodfacts: %v", ErrLookup, err)
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("%w: openfoodfacts status %d", ErrLookup, resp.StatusCode)
	}
	var body struct {
		Products []offProduct `json:"products"`
	}
	if err := json.NewDecoder(io.LimitReader(resp.Body, maxBodyBytes)).Decode(&body); err != nil {
		return nil, fmt.Errorf("%w: openfoodfacts: unreadable answer", ErrLookup)
	}
	var out []Food
	for _, p := range body.Products {
		if f, ok := p.toFood(); ok {
			out = append(out, f)
		}
	}
	return out, nil
}

// ValidBarcode reports whether code is 8 to 14 digits with a correct GS1 check digit, which covers
// EAN-8, UPC-A, EAN-13 and GTIN-14.
func ValidBarcode(code string) bool {
	if len(code) < 8 || len(code) > 14 {
		return false
	}
	sum := 0
	for i := len(code) - 2; i >= 0; i-- {
		c := code[i]
		if c < '0' || c > '9' {
			return false
		}
		d := int(c - '0')
		if (len(code)-2-i)%2 == 0 {
			d *= 3
		}
		sum += d
	}
	last := code[len(code)-1]
	return last >= '0' && last <= '9' && (10-sum%10)%10 == int(last-'0')
}

// ErrNoProduct means Open Food Facts has no usable product for the barcode.
var ErrNoProduct = errors.New("estimate: no product for barcode")

// Product looks one barcode up. A product that is missing, unnamed or without calories is
// ErrNoProduct; a failed call is ErrLookup.
func (o *OpenFoodFacts) Product(ctx context.Context, code string) (Food, error) {
	q := url.Values{}
	q.Set("fields", "code,product_name,brands,serving_size,serving_quantity,nutriments,image_front_small_url,image_front_url")
	ctx, cancel := context.WithTimeout(ctx, lookupTimeout)
	defer cancel()
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, o.BaseURL+"/api/v2/product/"+url.PathEscape(code)+"?"+q.Encode(), nil)
	if err != nil {
		return Food{}, err
	}
	req.Header.Set("User-Agent", o.UserAgent)
	resp, err := o.HTTP.Do(req)
	if err != nil {
		return Food{}, fmt.Errorf("%w: openfoodfacts: %v", ErrLookup, err)
	}
	defer resp.Body.Close()
	if resp.StatusCode == http.StatusNotFound {
		return Food{}, ErrNoProduct
	}
	if resp.StatusCode != http.StatusOK {
		return Food{}, fmt.Errorf("%w: openfoodfacts status %d", ErrLookup, resp.StatusCode)
	}
	var body struct {
		Status  int         `json:"status"`
		Product *offProduct `json:"product"`
	}
	if err := json.NewDecoder(io.LimitReader(resp.Body, maxBodyBytes)).Decode(&body); err != nil {
		return Food{}, fmt.Errorf("%w: openfoodfacts: unreadable answer", ErrLookup)
	}
	if body.Status != 1 || body.Product == nil {
		return Food{}, ErrNoProduct
	}
	if body.Product.Code == "" {
		body.Product.Code = code
	}
	f, ok := body.Product.toFood()
	if !ok {
		return Food{}, ErrNoProduct
	}
	return f, nil
}

func number(m map[string]any, key string) (float64, bool) {
	switch v := m[key].(type) {
	case float64:
		return v, finite(v)
	case string:
		f, err := strconv.ParseFloat(strings.TrimSpace(v), 64)
		return f, err == nil && finite(f)
	}
	return 0, false
}

// offBasis reads kcal and macros for a suffix ("_100g" or "_serving"). Energy without kcal is
// not guessed from kilojoules because Open Food Facts rows with only kJ are usually partial.
func offBasis(m map[string]any, suffix string) (*Nutrients, bool) {
	kcal, ok := number(m, "energy-kcal"+suffix)
	if !ok {
		return nil, false
	}
	n := Nutrients{Kcal: kcal}
	n.Protein, _ = number(m, "proteins"+suffix)
	n.Carbs, _ = number(m, "carbohydrates"+suffix)
	n.Fat, _ = number(m, "fat"+suffix)
	n.Fiber, _ = number(m, "fiber"+suffix)
	return &n, true
}

var gramsInText = regexp.MustCompile(`(?i)(\d+(?:[.,]\d+)?)\s*g\b`)

func (p offProduct) servingGrams() float64 {
	var asNumber float64
	if err := json.Unmarshal(p.ServingQuantity, &asNumber); err == nil && asNumber > 0 {
		return asNumber
	}
	var asString string
	if err := json.Unmarshal(p.ServingQuantity, &asString); err == nil {
		if v, err := strconv.ParseFloat(strings.TrimSpace(asString), 64); err == nil && v > 0 {
			return v
		}
	}
	if m := gramsInText.FindStringSubmatch(p.ServingSize); m != nil {
		if v, err := strconv.ParseFloat(strings.Replace(m[1], ",", ".", 1), 64); err == nil {
			return v
		}
	}
	return 0
}

func (p offProduct) toFood() (Food, bool) {
	name := strings.TrimSpace(p.Name)
	if name == "" || p.Code == "" {
		return Food{}, false
	}
	f := Food{
		Source: SourceOpenFoodFacts, ID: p.Code, Name: name,
		Brand: strings.TrimSpace(strings.ReplaceAll(p.Brands, ",", " ")), ServingGrams: p.servingGrams(), ServingText: strings.TrimSpace(p.ServingSize),
	}
	f.ImageURL = firstOFFImage(p.ImageSmallURL, p.ImageFrontURL)
	f.SourceURL = OFFBaseURL + "/product/" + url.PathEscape(p.Code)
	f.Per100g, _ = offBasis(p.Nutriments, "_100g")
	f.PerServing, _ = offBasis(p.Nutriments, "_serving")
	if f.Per100g == nil && f.PerServing == nil {
		return Food{}, false
	}
	if f.ServingGrams > 0 {
		f.Portions = append(f.Portions, Portion{Label: "serving", Grams: f.ServingGrams})
		if port, ok := portionFromLabel(p.ServingSize, f.ServingGrams); ok {
			f.Portions = append(f.Portions, port)
		}
	}
	return f, true
}

func firstOFFImage(candidates ...string) string {
	for _, c := range candidates {
		if u, err := url.Parse(strings.TrimSpace(c)); err == nil && u.Scheme == "https" && isOFFHost(u.Hostname()) {
			return u.String()
		}
	}
	return ""
}

func isOFFHost(host string) bool {
	host = strings.ToLower(host)
	return host == "openfoodfacts.org" || strings.HasSuffix(host, ".openfoodfacts.org")
}
