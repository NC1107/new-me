package estimate

import (
	"context"
	"regexp"
	"slices"
	"sort"
	"strings"
	"sync"
)

// SearchRemote finds unsaved candidates in USDA and Open Food Facts for the library search.
// Failures of one database leave the other's results.
func (f *Foods) SearchRemote(ctx context.Context, q string) []Food {
	q = strings.Join(strings.Fields(q), " ")
	if q == "" {
		return nil
	}
	it := Item{Food: q}
	var generic, asEaten, branded, off, survey []Food
	var wg sync.WaitGroup
	run := func(fn func()) {
		wg.Add(1)
		go func() { defer wg.Done(); fn() }()
	}
	c := f.memo()
	key := strings.ToLower(q)
	if f.USDA != nil {
		run(func() {
			generic, _ = cached(c, "usda|generic|"+key, func() ([]Food, error) { return f.USDA.Search(ctx, q, typeFoundation, typeSRLegacy) })
		})
		run(func() {
			asEaten, _ = cached(c, "usda|survey|"+key, func() ([]Food, error) { return f.USDA.Search(ctx, q, typeSurvey) })
		})
		run(func() {
			branded, _ = cached(c, "usda|branded|"+key, func() ([]Food, error) { return f.USDA.Search(ctx, q, typeBranded) })
		})
		if words := strings.Fields(nonAlnum.ReplaceAllString(key, " ")); len(words) > 0 {
			run(func() {
				survey, _ = cached(c, "usda|default|"+key, func() ([]Food, error) {
					return f.USDA.Search(ctx, strings.Join(words, " ")+" AND (NFS OR NS)", typeSurvey)
				})
			})
		}
	}
	if f.OFF != nil {
		run(func() { off, _ = cached(c, "off|"+key, func() ([]Food, error) { return f.OFF.Search(ctx, q) }) })
	}
	wg.Wait()

	top := func(foods []Food, n int) []Food {
		type s struct {
			f     Food
			score float64
		}
		var ranked []s
		for _, fd := range foods {
			if m, ok := scoreFood(it, fd); ok {
				ranked = append(ranked, s{fd, searchScore(it, m)})
			}
		}
		sort.SliceStable(ranked, func(i, j int) bool { return ranked[i].score > ranked[j].score })
		var out []Food
		for i := 0; i < len(ranked) && i < n; i++ {
			out = append(out, ranked[i].f)
		}
		return out
	}
	var out []Food
	if fd, ok := unspecifiedDefault(q, survey); ok {
		out = append(out, fd)
	}
	for i, fd := range top(append(generic, asEaten...), 4) {
		if i < 3 && len(fd.Portions) == 0 && f.USDA != nil {
			if ps, err := cached(c, "usda|portions|"+fd.ID, func() ([]Portion, error) { return f.USDA.Portions(ctx, fd.ID) }); err == nil {
				fd.Portions = ps
			}
		}
		out = append(out, fd)
	}
	out = append(out, top(off, 3)...)
	out = append(out, top(branded, 3)...)
	return out
}

// substitutes are words that mark a stand-in for a food, which someone searching for the food
// itself rarely wants first.
var substitutes = map[string]bool{"meatless": true, "imitation": true, "substitute": true, "analog": true, "vegetarian": true,
	// "Non-dairy milk" and "non-alcoholic beer" stand in for the food they name.
	"non": true}

// searchScore ranks a remote candidate for the library search: the estimate's match score,
// lowered for stand-ins the query did not ask for.
func searchScore(it Item, m match) float64 {
	asked := toSet(tokens(it.Food))
	for _, t := range tokens(m.Food.Name) {
		if substitutes[t] && !asked[t] {
			return m.Score - 0.5
		}
	}
	return m.Score
}

// unspecifiedMarker matches the FNDDS descriptors "NFS" (not further specified) and "NS as to ..."
// (not specified).
var unspecifiedMarker = regexp.MustCompile(`^(?:NFS|NS as to .+)$`)

// unspecifiedDefault finds the FNDDS food a dietary survey records when someone names the food
// with no detail, such as "Milk, NFS" for "milk". FNDDS bases those foods' nutrients and portions on
// how often each kind is reported in What We Eat in America (FNDDS 2021-2023 documentation, "NFS
// and NS food codes"), so it is the best answer to a bare food name. Only a food whose every
// descriptor is unspecified qualifies; "Potato, boiled, NFS" already says how it was cooked.
func unspecifiedDefault(q string, survey []Food) (Food, bool) {
	want := tokens(q)
	for _, fd := range survey {
		parts := strings.Split(fd.Name, ",")
		if len(parts) < 2 || !slices.Equal(tokens(parts[0]), want) {
			continue
		}
		plain := true
		for _, p := range parts[1:] {
			if !unspecifiedMarker.MatchString(strings.TrimSpace(p)) {
				plain = false
				break
			}
		}
		if plain {
			fd.Name = strings.TrimSpace(parts[0]) + ", any kind"
			return fd, true
		}
	}
	return Food{}, false
}
