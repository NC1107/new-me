package estimate

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"regexp"
	"slices"
	"strconv"
	"strings"
	"time"
	"unicode"
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
	// FoodCategory is a plain string in search results and {"description": ...} in a food's
	// detail, depending on the data type.
	FoodCategory json.RawMessage `json:"foodCategory"`
}

func (f usdaFood) category() string {
	var name string
	if json.Unmarshal(f.FoodCategory, &name) == nil {
		return strings.TrimSpace(name)
	}
	var obj struct {
		Description string `json:"description"`
	}
	if json.Unmarshal(f.FoodCategory, &obj) == nil {
		return strings.TrimSpace(obj.Description)
	}
	return ""
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
	Rank       int     `json:"rank"`
}

func (u *USDA) get(ctx context.Context, path string, q url.Values, out any) error {
	return u.do(ctx, http.MethodGet, path, q, nil, out)
}

func (u *USDA) do(ctx context.Context, method, path string, q url.Values, body any, out any) error {
	ctx, cancel := context.WithTimeout(ctx, lookupTimeout)
	defer cancel()
	var reqBody io.Reader
	if body != nil {
		raw, err := json.Marshal(body)
		if err != nil {
			return err
		}
		reqBody = bytes.NewReader(raw)
	}
	req, err := http.NewRequestWithContext(ctx, method, u.BaseURL+path+"?"+q.Encode(), reqBody)
	if err != nil {
		return err
	}
	if body != nil {
		req.Header.Set("Content-Type", "application/json")
	}
	// A header, not the api_key query parameter, so a transport error that quotes the URL
	// cannot carry the key into the server log.
	req.Header.Set("X-Api-Key", u.Key)
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
	// The search is posted because the GET form intermittently answers 400 when the query or the
	// "Survey (FNDDS)" data type carries parentheses.
	req := struct {
		Query    string   `json:"query"`
		DataType []string `json:"dataType"`
		PageSize int      `json:"pageSize"`
	}{query, dataTypes, 25}
	var body struct {
		Foods []usdaFood `json:"foods"`
	}
	if err := u.do(ctx, http.MethodPost, "/foods/search", url.Values{}, req, &body); err != nil {
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
		if label != "" && p.GramWeight > 0 && !surveyOnlyMeasure.MatchString(label) {
			out = append(out, Portion{Label: label, Grams: p.GramWeight / amount})
		}
	}
	measures := slices.Clone(f.FoodMeasures)
	slices.SortStableFunc(measures, func(a, b usdaMeasure) int { return a.Rank - b.Rank })
	for _, m := range measures {
		label := strings.TrimSpace(m.Modifier)
		// Survey foods carry a numeric portion code as the modifier and the wording in the text.
		if label == "" || measureCode.MatchString(label) {
			label = strings.TrimSpace(m.Text)
		}
		if surveyOnlyMeasure.MatchString(label) {
			continue
		}
		if p, ok := portionFromLabel(label, m.GramWeight); ok {
			out = append(out, p)
		}
	}
	return out
}

func (f usdaFood) unspecifiedGrams() float64 {
	for _, m := range f.FoodMeasures {
		if quantityNotSpecified.MatchString(strings.TrimSpace(m.Text)) && m.GramWeight > 0 {
			return m.GramWeight
		}
	}
	return 0
}

var quantityNotSpecified = regexp.MustCompile(`(?i)^quantity not specified`)

var measureCode = regexp.MustCompile(`^\d+$`)

// surveyOnlyMeasure matches FNDDS measures that are coding aids rather than portions a person
// would pick: per-ounce guideline amounts and the weight used when no quantity was reported.
var surveyOnlyMeasure = regexp.MustCompile(`(?i)^(guideline amount|quantity not specified)`)

func (f usdaFood) toFood() (Food, bool) {
	per100, ok := f.per100()
	if !ok || f.FdcID == 0 || strings.TrimSpace(f.Description) == "" {
		return Food{}, false
	}
	food := Food{
		Source: SourceUSDA, ID: strconv.Itoa(f.FdcID),
		Name:  tidySegments(strings.TrimSpace(usdaNote.ReplaceAllString(f.Description, ""))),
		Brand: tidyBrand(f.BrandName, f.BrandOwner), DataType: f.DataType,
		Per100g: &per100, Portions: f.portions(), UnspecifiedGrams: f.unspecifiedGrams(),
		Category: f.category(),
	}
	switch strings.ToLower(f.ServingUnit) {
	case "g", "grm":
		food.ServingGrams = f.ServingSize
	}
	if food.ServingGrams > 0 {
		household := cleanHousehold(f.Household)
		food.ServingText = firstNonEmpty(household, "1 serving")
		food.PerServing = &Nutrients{}
		*food.PerServing = per100.scale(food.ServingGrams / 100)
		food.Portions = append(food.Portions, Portion{Label: "serving", Grams: food.ServingGrams})
		if p, ok := portionFromLabel(household, food.ServingGrams); ok {
			food.Portions = append(food.Portions, p)
		}
	}
	return food, true
}

// perContainer matches the package count some labels append to the serving ("1.96 OZ SERVING,
// About 82 Servings Per Container"), which says nothing about one serving.
var perContainer = regexp.MustCompile(`(?i),?\s*(about\s+)?[\d.]+\s+servings?\s+per\s+container.*$`)

func cleanHousehold(s string) string {
	return strings.TrimSpace(perContainer.ReplaceAllString(s, ""))
}

// usdaNote drops notes such as "(Includes foods for USDA's Food Distribution Program)", which
// would count as extra words against an otherwise exact name, and keeps descriptors such as the
// "(2%)" in "Milk, reduced fat (2%)".
var usdaNote = regexp.MustCompile(`(?i)\s*\(includes [^)]*\)`)

func firstNonEmpty(ss ...string) string {
	for _, s := range ss {
		if strings.TrimSpace(s) != "" {
			return s
		}
	}
	return ""
}

// corporateSuffix matches the company words a USDA brand owner carries ("General Mills Sales
// Inc."), which are not what anyone calls the food.
var corporateSuffix = regexp.MustCompile(`(?i)[,.]?\s+(sales\s+)?(inc|incorporated|llc|l\.l\.c|co|corp|corporation|company|ltd|limited|usa|us)\.?$`)

// tidyBrand is the brand people know: the brand name when USDA has one, else the owner without
// its company suffixes, in normal capitals.
func tidyBrand(name, owner string) string {
	brand := strings.TrimSpace(name)
	if brand == "" {
		brand = strings.TrimSpace(owner)
		for {
			trimmed := strings.TrimSpace(corporateSuffix.ReplaceAllString(brand, ""))
			if trimmed == brand || trimmed == "" {
				break
			}
			brand = trimmed
		}
	}
	return tidyName(brand)
}

// tidySegments tidies each comma-separated part on its own, since branded rows often shout only
// the brand ("JIMMY DEAN, Sausage, Egg, and Cheese Biscuit").
func tidySegments(s string) string {
	parts := strings.Split(s, ",")
	for i, p := range parts {
		lead := p[:len(p)-len(strings.TrimLeft(p, " "))]
		parts[i] = lead + tidyName(strings.TrimLeft(p, " "))
	}
	return strings.Join(parts, ",")
}

// tidyName turns an all-capitals label ("TOTINO'S SAUSAGE PIZZA ROLLS") into normal capitals
// ("Totino's Sausage Pizza Rolls") and leaves mixed-case names alone.
func tidyName(s string) string {
	letters, upper := 0, 0
	for _, r := range s {
		if unicode.IsLetter(r) {
			letters++
			if unicode.IsUpper(r) {
				upper++
			}
		}
	}
	if letters < 4 || upper*10 < letters*8 {
		return s
	}
	words := strings.Fields(strings.ToLower(s))
	for i, w := range words {
		if i > 0 && smallWords[w] {
			continue
		}
		r := []rune(w)
		for j, c := range r {
			if unicode.IsLetter(c) {
				r[j] = unicode.ToUpper(c)
				break
			}
		}
		words[i] = string(r)
	}
	return strings.Join(words, " ")
}

var smallWords = map[string]bool{"a": true, "an": true, "and": true, "of": true, "with": true, "in": true,
	"or": true, "the": true, "to": true, "for": true, "on": true}
