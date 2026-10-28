package estimate

import (
	"context"
	"encoding/json"
	"fmt"
	"math"
	"strings"
	"sync"

	"github.com/nc1107/new-me/server/internal/anthropic"
)

const (
	// MaxItems bounds how many foods one sentence may split into.
	MaxItems = 12
	// lookupConcurrency keeps a burst of items from hammering the databases or the Claude key.
	lookupConcurrency = 3
	maxUnitRunes      = 30
	maxQuantity       = 1000
	maxItemGrams      = 5000
)

// ItemResult is one food of the meal with its nutrition, scaled to the amount eaten.
type ItemResult struct {
	Text        string  `json:"text"`
	Name        string  `json:"name"`
	Brand       string  `json:"brand"`
	Quantity    float64 `json:"quantity"`
	Unit        string  `json:"unit"`
	Grams       float64 `json:"grams"`
	Kcal        int     `json:"kcal"`
	Protein     float64 `json:"protein"`
	Carbs       float64 `json:"carbs"`
	Fat         float64 `json:"fat"`
	Fiber       float64 `json:"fiber"`
	Source      string  `json:"source"`
	SourceID    string  `json:"sourceId"`
	MatchedName string  `json:"matchedName"`
	Confidence  string  `json:"confidence"`
	// Origin is where a saved food's numbers first came from; empty for other sources.
	Origin string `json:"origin"`
	// fromDatabase marks numbers that came from a food database or a label rather than a guess.
	fromDatabase bool
}

// Total is the meal's summed nutrition.
type Total struct {
	Kcal    int     `json:"kcal"`
	Protein float64 `json:"protein"`
	Carbs   float64 `json:"carbs"`
	Fat     float64 `json:"fat"`
	Fiber   float64 `json:"fiber"`
}

// Meal is the itemized answer. The embedded Estimate keeps the one-meal fields at the top level
// so app builds from before itemizing keep working.
type Meal struct {
	Estimate
	Items []ItemResult `json:"items"`
	Total Total        `json:"total"`
	// DatabaseShare is the percent of total kcal that came from a food database.
	DatabaseShare int `json:"databaseShare"`
}

const splitPrompt = `You split a sentence about what a person ate into separate foods for a food log.
Answer only by calling the tool. Do not give or invent any nutrition values here: calories, macros and weights of foods are looked up elsewhere.
Return one item per distinct food or drink, in the order mentioned. Do not merge foods and do not split one food into ingredients.
text is the person's own words for that item. label is a short log name of at most three words (for example "Apple", "Chomps stick", "Hot Pocket").
food is the plain database-style name of the food without the brand and without the amount, for example "apple, raw" or "pepperoni pizza".
brand is the manufacturer or restaurant when the person named a product (for example "a chomp meat stick" is brand "Chomps", food "original beef stick"), otherwise null. Correct obvious misspellings of brands.
kind is "branded" when a specific product or brand is meant, otherwise "generic".
quantity is a number of units (1 when the person says "a" or "an", 0.5 for half). unit is the unit as the person gave it ("medium", "stick", "cup", "g", "slice", "serving"); use "serving" when none is given. For a drink, ounces mean fluid ounces, so write the unit as "fl oz".
grams is the weight only when the person stated it explicitly, otherwise null. Never estimate a weight.`

func splitSchema() map[string]any {
	str := func(desc string) map[string]any { return map[string]any{"type": "string", "description": desc} }
	nullable := func(typ, desc string) map[string]any {
		return map[string]any{"type": []string{typ, "null"}, "description": desc}
	}
	return map[string]any{
		"type": "object",
		"properties": map[string]any{
			"items": map[string]any{
				"type": "array", "description": "One entry per distinct food or drink", "maxItems": MaxItems,
				"items": map[string]any{
					"type": "object",
					"properties": map[string]any{
						"text":     str("The person's own words for this item"),
						"label":    str("Short log name, at most three words"),
						"food":     str("Plain database-style food name without brand or amount"),
						"brand":    nullable("string", "Brand or restaurant, or null"),
						"quantity": map[string]any{"type": "number", "description": "Number of units"},
						"unit":     str("Unit of the quantity, such as medium, stick, cup, g, slice, serving"),
						"grams":    nullable("number", "Total weight in grams only if the person stated it, else null"),
						"kind":     map[string]any{"type": "string", "enum": []string{KindGeneric, KindBranded}},
					},
					"required":             []string{"text", "label", "food", "brand", "quantity", "unit", "grams", "kind"},
					"additionalProperties": false,
				},
			},
		},
		"required":             []string{"items"},
		"additionalProperties": false,
	}
}

// parseItems validates the split. Nutrition is never read from it, even if the model adds some.
func parseItems(raw json.RawMessage) ([]Item, error) {
	var in struct {
		Items []struct {
			Text     string   `json:"text"`
			Label    string   `json:"label"`
			Food     string   `json:"food"`
			Brand    *string  `json:"brand"`
			Quantity *float64 `json:"quantity"`
			Unit     string   `json:"unit"`
			Grams    *float64 `json:"grams"`
			Kind     string   `json:"kind"`
		} `json:"items"`
	}
	if err := json.Unmarshal(raw, &in); err != nil {
		return nil, fmt.Errorf("%w: %v", ErrUnusable, err)
	}
	var out []Item
	for _, r := range in.Items {
		it := Item{
			Text: cleanText(r.Text, MaxNameRunes), Label: cleanText(r.Label, 40),
			Food: cleanText(r.Food, MaxNameRunes), Unit: strings.ToLower(cleanText(r.Unit, maxUnitRunes)),
			Quantity: 1, Kind: KindGeneric,
		}
		if r.Brand != nil {
			it.Brand = cleanText(*r.Brand, 40)
		}
		if strings.EqualFold(r.Kind, KindBranded) {
			it.Kind = KindBranded
		}
		if r.Quantity != nil && finite(*r.Quantity) && *r.Quantity > 0 {
			it.Quantity = math.Min(*r.Quantity, maxQuantity)
		}
		if r.Grams != nil && finite(*r.Grams) && *r.Grams > 0 {
			g := math.Min(*r.Grams, maxItemGrams)
			it.Grams = &g
		}
		if it.Food == "" {
			it.Food = it.Text
		}
		if it.Text == "" {
			it.Text = it.Food
		}
		if it.Text == "" {
			continue
		}
		if it.Unit == "" {
			it.Unit = "serving"
		}
		if it.Label == "" {
			it.Label = it.Text
		}
		out = append(out, it)
		if len(out) == MaxItems {
			break
		}
	}
	if len(out) == 0 {
		return nil, fmt.Errorf("%w: no items", ErrUnusable)
	}
	return out, nil
}

func (e *Estimator) split(ctx context.Context, text string) ([]Item, error) {
	raw, err := e.Client.ToolInput(ctx, anthropic.Request{
		System: splitPrompt, User: []anthropic.Block{{Text: "What the person ate: " + text}}, MaxTokens: 1500,
		Tool: &anthropic.Tool{
			Name: "split_meal", Description: "Report the separate foods in the description.", Schema: splitSchema()},
	})
	if err != nil {
		return nil, err
	}
	return parseItems(raw)
}

const itemPrompt = `You estimate the nutrition of one food item for a personal food log, because no food database knew it.
Answer only by calling the tool. Estimate the whole amount given (quantity and unit), not per 100 g.
Use typical values for the named product or food. name is a short title of the item. kcal is a whole number. protein, carbs, fat and fiber are grams.
confidence is high only when the food and its amount are both clear, medium when one is a guess, low when both are.
notes is one short sentence on the main assumption. Never refuse: give your best estimate.`

func (e *Estimator) estimateItem(ctx context.Context, it Item) (ItemResult, error) {
	if e.Client == nil {
		return ItemResult{}, fmt.Errorf("%w: no Claude client", ErrUnusable)
	}
	desc := fmt.Sprintf("Item: %s\nFood: %s\n", it.Text, it.Food)
	if it.Brand != "" {
		desc += "Brand: " + it.Brand + "\n"
	}
	desc += fmt.Sprintf("Amount: %s %s", trimFloat(it.Quantity), it.Unit)
	if it.Grams != nil {
		desc += fmt.Sprintf(" (%s g in total)", trimFloat(*it.Grams))
	}
	est, err := e.run(ctx, itemPrompt, []anthropic.Block{{Text: desc}})
	if err != nil {
		return ItemResult{}, err
	}
	res := baseResult(it)
	res.Source = SourceEstimated
	res.Confidence = est.Confidence
	res.Grams = knownGrams(it)
	fill(&res, Nutrients{Kcal: float64(est.Kcal), Protein: est.Protein, Carbs: est.Carbs, Fat: est.Fat, Fiber: est.Fiber})
	return res, nil
}

func trimFloat(v float64) string {
	return strings.TrimRight(strings.TrimRight(fmt.Sprintf("%.2f", v), "0"), ".")
}

func baseResult(it Item) ItemResult {
	name := it.Label
	if name == "" {
		name = it.Text
	}
	return ItemResult{Text: it.Text, Name: cleanText(name, MaxNameRunes), Brand: it.Brand, Quantity: it.Quantity, Unit: it.Unit}
}

// knownGrams is the item's weight when the sentence alone settles it.
func knownGrams(it Item) float64 {
	if f, ok := massGrams[strings.Join(normUnit(it.Unit), "")]; ok {
		return roundTenth(math.Min(it.Quantity*f, maxItemGrams))
	}
	if it.Grams != nil {
		return roundTenth(*it.Grams)
	}
	return 0
}

func roundTenth(v float64) float64 { return math.Round(v*10) / 10 }

// fill writes nutrients into the result, clamped to what the meal log accepts.
func fill(r *ItemResult, n Nutrients) {
	r.Kcal = int(math.Min(math.Max(math.Round(n.Kcal), 0), MaxKcal))
	r.Protein = clampGrams(n.Protein)
	r.Carbs = clampGrams(n.Carbs)
	r.Fat = clampGrams(n.Fat)
	r.Fiber = clampGrams(n.Fiber)
}

func clampGrams(v float64) float64 {
	if !finite(v) {
		return 0
	}
	return roundTenth(math.Min(math.Max(v, 0), MaxMacroGrams))
}

func (e *Estimator) item(ctx context.Context, it Item, library []LibraryFood) (res ItemResult, failed bool) {
	if l, ok := bestLibrary(it, library); ok {
		if h, ok := libraryHit(it, l); ok {
			return e.hitResult(it, h), false
		}
	}
	if e.Foods != nil {
		if h, ok, _ := e.Foods.Lookup(ctx, it); ok {
			return e.hitResult(it, h), false
		}
	}
	res, err := e.estimateItem(ctx, it)
	if err == nil {
		return res, false
	}
	// The person can still type the numbers into the row, so an item nobody could size stays in
	// the list at zero instead of failing the whole meal.
	res = baseResult(it)
	res.Source = SourceEstimated
	res.Confidence = ConfidenceLow
	res.Grams = knownGrams(it)
	return res, true
}

func (e *Estimator) hitResult(it Item, h hit) ItemResult {
	res := baseResult(it)
	res.Source = h.Food.Source
	res.SourceID = h.Food.ID
	res.MatchedName = matchedName(h.Food)
	res.Confidence = h.Confidence
	res.Grams = roundTenth(math.Min(h.Resolved.Grams, maxItemGrams))
	res.fromDatabase = countsAsDatabase(h.Food.Source)
	if h.Food.Source == SourceLibrary {
		res.Brand = h.Food.Brand
		res.Origin = h.Food.Origin
		res.fromDatabase = h.Food.Origin != SourceEstimated
	}
	fill(&res, h.Resolved.N)
	return res
}

func matchedName(f Food) string {
	name := f.Name
	if f.Brand != "" && !strings.Contains(strings.ToLower(name), strings.ToLower(f.Brand)) {
		name = f.Brand + " " + name
	}
	return cleanText(name, MaxNameRunes)
}

// Meal splits the text into foods, sizes each one and returns the itemized meal. It fails only
// when the text cannot be split or when no item could be sized at all.
func (e *Estimator) Meal(ctx context.Context, text string) (Meal, error) {
	var library []LibraryFood
	if e.Library != nil {
		library, _ = e.Library.All(ctx)
	}
	if it, l, ok := exactLibraryItem(text, library); ok {
		if h, ok := libraryHit(it, l); ok {
			return assemble([]ItemResult{e.hitResult(it, h)}), nil
		}
	}
	items, err := e.split(ctx, text)
	if err != nil {
		return Meal{}, err
	}
	results := make([]ItemResult, len(items))
	failed := make([]bool, len(items))
	sem := make(chan struct{}, lookupConcurrency)
	var wg sync.WaitGroup
	for i, it := range items {
		wg.Add(1)
		sem <- struct{}{}
		go func() {
			defer wg.Done()
			defer func() { <-sem }()
			results[i], failed[i] = e.item(ctx, it, library)
		}()
	}
	wg.Wait()
	allFailed := true
	for _, f := range failed {
		allFailed = allFailed && f
	}
	if allFailed {
		return Meal{}, fmt.Errorf("%w: no item could be sized", ErrUnusable)
	}
	return assemble(results), nil
}

// countsAsDatabase: a saved food counts when its numbers came from a database or a label, not
// from an old guess; the saved food keeps that origin.
func countsAsDatabase(source string) bool {
	return source == SourceUSDA || source == SourceOpenFoodFacts
}

// assemble sums the items and builds the legacy one-meal fields from them.
func assemble(items []ItemResult) Meal {
	var kcal, dbKcal int
	var protein, carbs, fat, fiber float64
	var names []string
	lowest, fromDB := ConfidenceHigh, 0
	rank := map[string]int{ConfidenceLow: 0, ConfidenceMedium: 1, ConfidenceHigh: 2}
	for _, it := range items {
		kcal += it.Kcal
		protein += it.Protein
		carbs += it.Carbs
		fat += it.Fat
		fiber += it.Fiber
		names = append(names, it.Name)
		if it.fromDatabase {
			dbKcal += it.Kcal
			fromDB++
		}
		if rank[it.Confidence] < rank[lowest] {
			lowest = it.Confidence
		}
	}
	total := Total{
		Kcal: min(kcal, MaxKcal), Protein: clampGrams(protein), Carbs: clampGrams(carbs),
		Fat: clampGrams(fat), Fiber: clampGrams(fiber),
	}
	share := 0
	if kcal > 0 {
		share = int(math.Round(100 * float64(dbKcal) / float64(kcal)))
	}
	name := cleanText(strings.Join(names, ", "), MaxNameRunes)
	if name == "" {
		name = "Meal"
	}
	notes := fmt.Sprintf("%d of %d items matched a nutrition database; the rest are estimated.", fromDB, len(items))
	if fromDB == len(items) {
		notes = fmt.Sprintf("All %d items matched a nutrition database.", len(items))
	}
	legacyKcal := max(total.Kcal, 1)
	return Meal{
		Estimate: Estimate{
			Name: name, Kcal: legacyKcal, Protein: total.Protein, Carbs: total.Carbs, Fat: total.Fat,
			Fiber: total.Fiber, Confidence: lowest, Notes: notes,
		},
		Items: items, Total: total, DatabaseShare: share,
	}
}
