package estimate

import (
	"context"
	"errors"
	"strings"
	"time"
)

// Item kinds the parse step reports.
const (
	KindGeneric = "generic"
	KindBranded = "branded"
)

// Item is one food the person named, split out of the sentence. It carries no nutrition: the
// numbers come from a database, or from a separate estimate when no database knows the item.
type Item struct {
	Text     string
	Label    string
	Food     string
	Brand    string
	Quantity float64
	Unit     string
	Grams    *float64
	Kind     string
}

// Foods looks items up in Open Food Facts and USDA FoodData Central. A nil source is skipped.
type Foods struct {
	USDA *USDA
	OFF  *OpenFoodFacts

	cache *ttlCache
}

// NewFoods wires both databases; an empty usdaKey uses DEMO_KEY.
func NewFoods(usdaKey, version string) *Foods {
	return &Foods{USDA: NewUSDA(usdaKey), OFF: NewOpenFoodFacts(version), cache: newTTLCache(time.Now)}
}

// SetVersion updates the User-Agent Open Food Facts sees.
func (f *Foods) SetVersion(version string) {
	if f != nil && f.OFF != nil {
		f.OFF.UserAgent = offUserAgent(version)
	}
}

func (f *Foods) memo() *ttlCache {
	if f.cache == nil {
		f.cache = newTTLCache(time.Now)
	}
	return f.cache
}

// maxCandidates bounds how many ranked rows are tried when a unit will not convert, since each
// USDA candidate may cost a detail call.
const maxCandidates = 5

// hit is a chosen database row with its converted nutrients.
type hit struct {
	Food       Food
	Resolved   resolved
	Confidence string
}

// cached runs search once per key per hour. Failures are not cached, so a database blip heals.
func cached[T any](c *ttlCache, key string, search func() (T, error)) (T, error) {
	if v, ok := c.get(key); ok {
		return v.(T), nil
	}
	v, err := search()
	if err != nil {
		var zero T
		return zero, err
	}
	c.set(key, v)
	return v, nil
}

// Lookup finds the best database row for the item and converts its amount. ok is false when no
// database has an acceptable match; err reports only the last failed call and the caller treats
// it the same as no match.
func (f *Foods) Lookup(ctx context.Context, it Item) (hit, bool, error) {
	var firstErr error
	try := func(foods []Food, err error) (hit, bool) {
		if err != nil {
			if firstErr == nil {
				firstErr = err
			}
			return hit{}, false
		}
		return f.pick(ctx, it, foods)
	}
	query := searchQuery(it)
	if query == "" {
		return hit{}, false, nil
	}
	c := f.memo()

	if it.Kind == KindBranded {
		if f.OFF != nil {
			foods, err := cached(c, "off|"+strings.ToLower(query), func() ([]Food, error) { return f.OFF.Search(ctx, query) })
			if h, ok := try(foods, err); ok {
				return h, true, nil
			}
		}
		if f.USDA != nil {
			foods, err := cached(c, "usda|branded|"+strings.ToLower(query), func() ([]Food, error) {
				return f.USDA.Search(ctx, query, typeBranded)
			})
			if h, ok := try(foods, err); ok {
				return h, true, nil
			}
		}
		return hit{}, false, firstErr
	}
	if f.USDA != nil {
		reference, err := cached(c, "usda|generic|"+strings.ToLower(query), func() ([]Food, error) {
			return f.USDA.Search(ctx, query, typeFoundation, typeSRLegacy)
		})
		// FNDDS describes foods as people report eating them ("Milk, whole") with household
		// measures such as fl oz, where the reference data often ranks a cheese or a yogurt
		// made from the food above the food itself. It is searched on its own so the reference
		// rows cannot crowd it out of one page of results.
		survey, surveyErr := cached(c, "usda|survey|"+strings.ToLower(query), func() ([]Food, error) {
			return f.USDA.Search(ctx, query, typeSurvey)
		})
		if h, ok := f.pick(ctx, it, append(append([]Food{}, reference...), survey...)); ok {
			return h, true, nil
		}
		if h, ok := f.unspecified(ctx, it); ok {
			return h, true, nil
		}
		if firstErr == nil {
			firstErr = errors.Join(err, surveyErr)
		}
	}
	return hit{}, false, firstErr
}

// pick ranks the candidates and converts the best one that the item's unit can be applied to.
// Among the top few, one that converts the unit exactly beats a better named one that can only
// guess it: "1 medium" french fries is a medium order from the restaurant row, not the first
// measure of the generic row, which is a single fry.
func (f *Foods) pick(ctx context.Context, it Item, foods []Food) (hit, bool) {
	remaining := foods
	var guess *hit
	for tries := 0; tries < maxCandidates && len(remaining) > 0; tries++ {
		best, ok := pickBest(it, remaining)
		if !ok {
			break
		}
		food := best.Food
		if f.USDA != nil && food.Source == SourceUSDA && food.DataType != typeBranded && len(food.Portions) == 0 {
			if ps, err := cached(f.memo(), "usda|portions|"+food.ID, func() ([]Portion, error) {
				return f.USDA.Portions(ctx, food.ID)
			}); err == nil {
				food.Portions = ps
			}
		}
		if r, ok := resolve(food, it); ok {
			h := hit{Food: food, Resolved: r, Confidence: confidenceFor(best, r.Basis)}
			if r.Basis != basisGuess {
				return h, true
			}
			if guess == nil {
				guess = &h
			}
		}
		next := remaining[:0:0]
		for _, c := range remaining {
			if c.Source != food.Source || c.ID != food.ID {
				next = append(next, c)
			}
		}
		remaining = next
	}
	if guess != nil {
		return *guess, true
	}
	return hit{}, false
}

// unspecified falls back to the FNDDS food a dietary survey records when the detail is unknown,
// such as "Coffee, NFS" for "coffee, black" or "Oatmeal, NFS" for "oatmeal, cooked", when no row
// names the food with the person's own descriptors. Confidence follows how many of their words
// it kept, so a dropped descriptor reads as lower confidence (FNDDS 2021-2023 documentation,
// "NFS and NS food codes").
func (f *Foods) unspecified(ctx context.Context, it Item) (hit, bool) {
	name := strings.TrimSpace(strings.Split(it.Food, ",")[0])
	words := strings.Fields(nonAlnum.ReplaceAllString(strings.ToLower(name), " "))
	if len(words) == 0 {
		return hit{}, false
	}
	key := strings.Join(words, " ")
	survey, err := cached(f.memo(), "usda|default|"+key, func() ([]Food, error) {
		return f.USDA.Search(ctx, key+" AND (NFS OR NS)", typeSurvey)
	})
	if err != nil {
		return hit{}, false
	}
	food, ok := unspecifiedDefault(name, survey)
	if !ok {
		return hit{}, false
	}
	r, ok := resolve(food, it)
	if !ok {
		return hit{}, false
	}
	recall := share(tokens(it.Food), toSet(tokens(food.Name)))
	return hit{Food: food, Resolved: r, Confidence: confidenceFor(match{Recall: recall}, r.Basis)}, true
}
