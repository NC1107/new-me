package estimate

import (
	"math"
	"regexp"
	"slices"
	"strconv"
	"strings"
)

// Sources a nutrient row can come from.
const (
	SourceUSDA          = "usda"
	SourceOpenFoodFacts = "openfoodfacts"
	SourceEstimated     = "estimated"
	SourceLibrary       = "library"
)

// Data types the USDA API reports, as far as ranking cares.
const (
	typeFoundation = "Foundation"
	typeSRLegacy   = "SR Legacy"
	typeSurvey     = "Survey (FNDDS)"
	typeBranded    = "Branded"
)

// Nutrients is one amount of food: kcal and grams of each macro.
type Nutrients struct {
	Kcal, Protein, Carbs, Fat, Fiber float64
}

func (n Nutrients) scale(f float64) Nutrients {
	return Nutrients{n.Kcal * f, n.Protein * f, n.Carbs * f, n.Fat * f, n.Fiber * f}
}

// Portion is the weight of one unit of a household measure, such as one medium apple.
type Portion struct {
	Label string
	Grams float64
}

// Food is one database row reduced to what the meal estimate needs. Either nutrient basis may
// be missing; a product with only per-serving numbers still resolves through its serving.
type Food struct {
	Source   string
	ID       string
	Name     string
	Brand    string
	DataType string
	// Origin is, for a library food, where its numbers first came from.
	Origin string

	Per100g    *Nutrients
	PerServing *Nutrients
	// ServingGrams is the weight of one serving, zero when the label does not say.
	ServingGrams float64
	// ServingText is the label's wording of one serving, such as "1 stick (32 g)".
	ServingText string
	Portions    []Portion
	// UnspecifiedGrams is the FNDDS "Quantity not specified" weight, what a dietary survey records
	// when someone names the food without an amount; zero for other databases.
	UnspecifiedGrams float64
	// ImageURL and SourceURL are the product photo and page, set only for Open Food Facts rows.
	ImageURL  string
	SourceURL string
}

func (f Food) per100() (Nutrients, bool) {
	if f.Per100g != nil {
		return *f.Per100g, true
	}
	if f.PerServing != nil && f.ServingGrams > 0 {
		return f.PerServing.scale(100 / f.ServingGrams), true
	}
	return Nutrients{}, false
}

// Basis says how firmly the item's unit was converted, which caps the reported confidence.
type basis int

const (
	basisGuess basis = iota
	basisExact
)

var massGrams = map[string]float64{
	"g": 1, "gram": 1, "gm": 1, "kg": 1000, "kilogram": 1000,
	"oz": 28.3495, "ounce": 28.3495, "lb": 453.592, "pound": 453.592,
}

// volumeML is each volume unit in millilitres, by the US customary definitions (NIST Handbook
// 44, Appendix C). A volume has no mass without a density, so it resolves only through a portion
// of the food measured by volume, which supplies the density.
var volumeML = map[string]float64{
	"ml": 1, "l": 1000, "liter": 1000, "litre": 1000, "teaspoon": 4.92892, "tablespoon": 14.7868,
	"floz": 29.5735, "cup": 236.588, "pint": 473.176, "quart": 946.353,
}

var unitAliases = map[string]string{
	"tbsp": "tablespoon", "tbs": "tablespoon", "tsp": "teaspoon", "c": "cup", "cups": "cup",
	"tablespoons": "tablespoon", "teaspoons": "teaspoon", "milliliter": "ml", "millilitre": "ml",
	"liters": "liter", "litres": "litre", "pints": "pint", "quarts": "quart",
	"grams": "gram", "ounces": "ounce", "pounds": "pound", "lbs": "lb", "onz": "ounce", "grm": "gram",
}

var countUnits = map[string]bool{
	"serving": true, "piece": true, "each": true, "item": true, "unit": true, "whole": true,
	"bar": true, "stick": true, "pouch": true, "packet": true, "pack": true, "can": true,
	"bottle": true, "sandwich": true, "pocket": true, "bag": true, "cookie": true, "slice": true,
}

func normUnit(unit string) []string {
	var out []string
	for _, t := range tokens(unit) {
		if a, ok := unitAliases[t]; ok {
			t = a
		}
		out = append(out, t)
	}
	return out
}

// resolved is an item's nutrition and weight after the unit is converted.
type resolved struct {
	N     Nutrients
	Grams float64
	Basis basis
}

// resolve converts the item's amount into nutrients for this food. It returns false when the
// unit cannot be turned into a weight or a serving, so the caller falls back to an estimate.
func resolve(f Food, it Item) (resolved, bool) {
	units := normUnit(it.Unit)
	unit := strings.Join(units, "")
	per100, havePer100 := f.per100()
	byGrams := func(grams float64, b basis) (resolved, bool) {
		if !havePer100 || grams <= 0 {
			return resolved{}, false
		}
		return resolved{N: per100.scale(grams / 100), Grams: grams, Basis: b}, true
	}

	if factor, ok := massGrams[unit]; ok {
		return byGrams(it.Quantity*factor, basisExact)
	}
	if len(units) > 0 {
		for _, p := range f.Portions {
			if containsAll(portionUnit(p.Label), units) {
				// The label's own numbers beat per-100 g ones scaled by a serving weight.
				if f.PerServing != nil && f.ServingGrams > 0 && p.Grams == f.ServingGrams {
					return resolved{N: f.PerServing.scale(it.Quantity), Grams: it.Quantity * p.Grams, Basis: basisExact}, true
				}
				return byGrams(it.Quantity*p.Grams, basisExact)
			}
		}
	}
	ml, isVolume := volumeML[unit]
	if isVolume {
		if density, ok := gramsPerML(f.Portions); ok {
			return byGrams(it.Quantity*ml*density, basisExact)
		}
	}
	if !isVolume {
		servingWord := countUnits[unit] || unit == ""
		if f.PerServing != nil {
			b := basisGuess
			if servingWord || servingTextMentions(f, units) {
				b = basisExact
			}
			grams := 0.0
			if f.ServingGrams > 0 {
				grams = it.Quantity * f.ServingGrams
			}
			return resolved{N: f.PerServing.scale(it.Quantity), Grams: grams, Basis: b}, true
		}
		if f.ServingGrams > 0 && servingWord {
			return byGrams(it.Quantity*f.ServingGrams, basisExact)
		}
		if f.UnspecifiedGrams > 0 && (unit == "serving" || unit == "") {
			return byGrams(it.Quantity*f.UnspecifiedGrams, basisGuess)
		}
		if p, ok := wholePortion(f); ok && servingWord {
			return byGrams(it.Quantity*p.Grams, basisExact)
		}
	}
	if it.Grams != nil {
		return byGrams(*it.Grams, basisGuess)
	}
	// Only a size word USDA does not list ("huge") is near enough to one whole item, or failing
	// that its first measure. A volume is not, and neither is "a serving" of a food with no serving,
	// since that first measure may be a cup of mayonnaise; those are estimated instead.
	if isVolume || countUnits[unit] || unit == "" || f.Source != SourceUSDA || f.DataType == typeBranded {
		return resolved{}, false
	}
	if p, ok := wholePortion(f); ok {
		return byGrams(it.Quantity*p.Grams, basisGuess)
	}
	if len(f.Portions) > 0 && f.Portions[0].Grams > 0 {
		return byGrams(it.Quantity*f.Portions[0].Grams, basisGuess)
	}
	return resolved{}, false
}

// wholePortion is the measure of one whole item, which FNDDS names after the item itself
// ("banana", "egg") or calls "fruit".
func wholePortion(f Food) (Portion, bool) {
	lead := tokens(strings.Split(f.Name, ",")[0])
	for _, p := range f.Portions {
		u := portionUnit(p.Label)
		if len(u) == 1 && p.Grams > 0 && (u[0] == "fruit" || slices.Contains(lead, u[0])) {
			return p, true
		}
	}
	return Portion{}, false
}

// gramsPerML is the food's density from its first portion measured by volume alone, such as
// "cup" or "fl oz"; "cup, chopped" is left out because its weight depends on how it was cut.
func gramsPerML(portions []Portion) (float64, bool) {
	for _, p := range portions {
		if ml, ok := volumeML[strings.Join(portionUnit(p.Label), "")]; ok && p.Grams > 0 {
			return p.Grams / ml, true
		}
	}
	return 0, false
}

// portionUnit is a portion label's unit without its note, so "cup (8 fl oz)" is a cup and never
// answers for a fluid ounce.
func portionUnit(label string) []string {
	return normUnit(portionNote.ReplaceAllString(label, ""))
}

var portionNote = regexp.MustCompile(`\([^)]*\)`)

func servingTextMentions(f Food, units []string) bool {
	for _, p := range f.Portions {
		if len(units) > 0 && containsAll(normUnit(p.Label), units) {
			return true
		}
	}
	return false
}

func containsAll(have, want []string) bool {
	set := make(map[string]bool, len(have))
	for _, t := range have {
		set[t] = true
	}
	for _, t := range want {
		if !set[t] {
			return false
		}
	}
	return true
}

var nonAlnum = regexp.MustCompile(`[^a-z0-9]+`)

var stopwords = map[string]bool{"a": true, "an": true, "the": true, "of": true, "and": true, "with": true, "in": true, "s": true}

// tokens lowercases, splits on punctuation, drops filler words and strips a plural "s" so
// "Apples" and "apple" meet.
func tokens(s string) []string {
	var out []string
	for _, t := range nonAlnum.Split(strings.ToLower(s), -1) {
		if t == "" || stopwords[t] {
			continue
		}
		if len(t) > 3 && strings.HasSuffix(t, "s") && !strings.HasSuffix(t, "ss") {
			t = strings.TrimSuffix(t, "s")
		}
		out = append(out, t)
	}
	return out
}

var leadingAmount = regexp.MustCompile(`^\s*(\d+(?:\.\d+)?(?:\s+\d+/\d+|/\d+)?)\s*`)

// portionFromLabel turns "1 stick (50 g)" or "2 tbsp" plus the weight of that whole measure
// into the weight of a single unit.
func portionFromLabel(label string, grams float64) (Portion, bool) {
	label = strings.TrimSpace(label)
	if label == "" || grams <= 0 {
		return Portion{}, false
	}
	amount := 1.0
	if m := leadingAmount.FindStringSubmatch(label); m != nil {
		amount = parseAmount(m[1])
		label = strings.TrimSpace(label[len(m[0]):])
	}
	if amount <= 0 || label == "" {
		return Portion{}, false
	}
	return Portion{Label: label, Grams: grams / amount}, true
}

func parseAmount(s string) float64 {
	total := 0.0
	for _, part := range strings.Fields(s) {
		if a, b, ok := strings.Cut(part, "/"); ok {
			num, err1 := strconv.ParseFloat(a, 64)
			den, err2 := strconv.ParseFloat(b, 64)
			if err1 != nil || err2 != nil || den == 0 {
				return 0
			}
			if a == "" {
				num = 1
			}
			total += num / den
			continue
		}
		v, err := strconv.ParseFloat(part, 64)
		if err != nil {
			return 0
		}
		total += v
	}
	return total
}

func finite(v float64) bool { return !math.IsNaN(v) && !math.IsInf(v, 0) }
