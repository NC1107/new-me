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
	"time"
)

const (
	// USDABaseURL is the FoodData Central API.
	USDABaseURL = "https://api.nal.usda.gov/fdc/v1"
	// DemoKey is the shared, heavily rate-limited key used when none is configured.
	DemoKey = "DEMO_KEY"

	lookupTimeout = 5 * time.Second
	maxBodyBytes  = 2 << 20
)

// ErrLookup wraps a failed call to a food database.
var ErrLookup = errors.New("estimate: food lookup failed")

// USDA searches FoodData Central.
type USDA struct {
	BaseURL string
	Key     string
	HTTP    *http.Client
}

// NewUSDA builds a client; an empty key means DEMO_KEY.
func NewUSDA(key string) *USDA {
	if strings.TrimSpace(key) == "" {
		key = DemoKey
	}
	return &USDA{BaseURL: USDABaseURL, Key: strings.TrimSpace(key), HTTP: &http.Client{Timeout: lookupTimeout}}
}

// Nutrient ids in FoodData Central. Foundation foods carry Atwater energy (2047, 2048) instead
// of 1008, and some records only have kilojoules (1062).
const (
	nutKcal       = 1008
	nutKcalAtwG   = 2047
	nutKcalAtwS   = 2048
	nutKilojoules = 1062
	nutProtein    = 1003
	nutFat        = 1004
	nutCarbs      = 1005
	nutFiber      = 1079
)

type usdaFood struct {
	FdcID         int            `json:"fdcId"`
	Description   string         `json:"description"`
	DataType      string         `json:"dataType"`
	BrandOwner    string         `json:"brandOwner"`
	BrandName     string         `json:"brandName"`
	ServingSize   float64        `json:"servingSize"`
	ServingUnit   string         `json:"servingSizeUnit"`
	Household     string         `json:"householdServingFullText"`
	FoodNutrients []usdaNutrient `json:"foodNutrients"`
	FoodPortions  []usdaPortion  `json:"foodPortions"`
	FoodMeasures  []usdaMeasure  `json:"foodMeasures"`
}

type usdaNutrient struct {
	// Search results use nutrientId; the detail endpoint nests it under nutrient.
	NutrientID int `json:"nutrientId"`
	Nutrient   struct {
		ID int `json:"id"`
	} `json:"nutrient"`
	Value  float64 `json:"value"`
	Amount float64 `json:"amount"`
}

type usdaPortion struct {
	Amount      float64 `json:"amount"`
	GramWeight  float64 `json:"gramWeight"`
	Modifier    string  `json:"modifier"`
	Description string  `json:"portionDescription"`
	MeasureUnit struct {
		Name string `json:"name"`
	} `json:"measureUnit"`
}

type usdaMeasure struct {
	GramWeight float64 `json:"gramWeight"`
	Modifier   string  `json:"modifier"`
	Text       string  `json:"disseminationText"`
}

func (u *USDA) get(ctx context.Context, path string, q url.Values, out any) error {
	q.Set("api_key", u.Key)
	ctx, cancel := context.WithTimeout(ctx, lookupTimeout)
	defer cancel()
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, u.BaseURL+path+"?"+q.Encode(), nil)
	if err != nil {
		return err
	}
	resp, err := u.HTTP.Do(req)
	if err != nil {
		return fmt.Errorf("%w: usda: %v", ErrLookup, err)
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		return fmt.Errorf("%w: usda status %d", ErrLookup, resp.StatusCode)
	}
	if err := json.NewDecoder(io.LimitReader(resp.Body, maxBodyBytes)).Decode(out); err != nil {
		return fmt.Errorf("%w: usda: unreadable answer", ErrLookup)
	}
	return nil
}

// Search returns candidates for a query, restricted to the given data types.
func (u *USDA) Search(ctx context.Context, query string, dataTypes ...string) ([]Food, error) {
	q := url.Values{}
	q.Set("query", query)
	q.Set("dataType", strings.Join(dataTypes, ","))
	q.Set("pageSize", "25")
	var body struct {
		Foods []usdaFood `json:"foods"`
	}
	if err := u.get(ctx, "/foods/search", q, &body); err != nil {
		return nil, err
	}
	var out []Food
	for _, f := range body.Foods {
		if food, ok := f.toFood(); ok {
			out = append(out, food)
		}
	}
	return out, nil
}

// Portions fetches the household measures of one food; search results do not carry them for
// Foundation and SR Legacy foods.
func (u *USDA) Portions(ctx context.Context, fdcID string) ([]Portion, error) {
	var f usdaFood
	if err := u.get(ctx, "/food/"+url.PathEscape(fdcID), url.Values{}, &f); err != nil {
		return nil, err
	}
	return f.portions(), nil
}

func (f usdaFood) nutrient(id int) (float64, bool) {
	for _, n := range f.FoodNutrients {
		nid := n.NutrientID
		if nid == 0 {
			nid = n.Nutrient.ID
		}
		if nid == id {
			v := n.Value
			if v == 0 {
				v = n.Amount
			}
			return v, true
		}
	}
	return 0, false
}

func (f usdaFood) per100() (Nutrients, bool) {
	var n Nutrients
	switch {
	case has(f.nutrient(nutKcal)):
		n.Kcal, _ = f.nutrient(nutKcal)
	case has(f.nutrient(nutKcalAtwG)):
		n.Kcal, _ = f.nutrient(nutKcalAtwG)
	case has(f.nutrient(nutKcalAtwS)):
		n.Kcal, _ = f.nutrient(nutKcalAtwS)
	case has(f.nutrient(nutKilojoules)):
		kj, _ := f.nutrient(nutKilojoules)
		n.Kcal = kj / 4.184
	default:
		return n, false
	}
	n.Protein, _ = f.nutrient(nutProtein)
	n.Carbs, _ = f.nutrient(nutCarbs)
	n.Fat, _ = f.nutrient(nutFat)
	n.Fiber, _ = f.nutrient(nutFiber)
	return n, true
}

func has(_ float64, ok bool) bool { return ok }

func (f usdaFood) portions() []Portion {
	var out []Portion
	for _, p := range f.FoodPortions {
		label := strings.TrimSpace(p.Description)
		if label == "" {
			label = strings.TrimSpace(p.Modifier)
		}
		if unit := strings.TrimSpace(p.MeasureUnit.Name); unit != "" && unit != "undetermined" {
			label = strings.TrimSpace(unit + " " + label)
		}
		amount := p.Amount
		if amount <= 0 {
			amount = 1
		}
		if label != "" && p.GramWeight > 0 {
			out = append(out, Portion{Label: label, Grams: p.GramWeight / amount})
		}
	}
	for _, m := range f.FoodMeasures {
		label := strings.TrimSpace(m.Modifier)
		if label == "" {
			label = strings.TrimSpace(m.Text)
		}
		if p, ok := portionFromLabel(label, m.GramWeight); ok {
			out = append(out, p)
		}
	}
	return out
}

func (f usdaFood) toFood() (Food, bool) {
	per100, ok := f.per100()
	if !ok || f.FdcID == 0 || strings.TrimSpace(f.Description) == "" {
		return Food{}, false
	}
	food := Food{
		Source: SourceUSDA, ID: strconv.Itoa(f.FdcID), Name: strings.TrimSpace(parenthetical.ReplaceAllString(f.Description, "")),
		Brand: strings.TrimSpace(firstNonEmpty(f.BrandName, f.BrandOwner)), DataType: f.DataType,
		Per100g: &per100, Portions: f.portions(),
	}
	if f.BrandOwner != "" && f.BrandName != "" && !strings.EqualFold(f.BrandOwner, f.BrandName) {
		food.Brand = f.BrandName + " " + f.BrandOwner
	}
	switch strings.ToLower(f.ServingUnit) {
	case "g", "grm":
		food.ServingGrams = f.ServingSize
	}
	if food.ServingGrams > 0 {
		food.ServingText = firstNonEmpty(f.Household, "1 serving")
		food.PerServing = &Nutrients{}
		*food.PerServing = per100.scale(food.ServingGrams / 100)
		food.Portions = append(food.Portions, Portion{Label: "serving", Grams: food.ServingGrams})
		if p, ok := portionFromLabel(f.Household, food.ServingGrams); ok {
			food.Portions = append(food.Portions, p)
		}
	}
	return food, true
}

// parenthetical drops notes such as "(Includes foods for USDA's Food Distribution Program)", which
// would count as extra words against an otherwise exact name.
var parenthetical = regexp.MustCompile(`\s*\([^)]*\)`)

func firstNonEmpty(ss ...string) string {
	for _, s := range ss {
		if strings.TrimSpace(s) != "" {
			return s
		}
	}
	return ""
}
