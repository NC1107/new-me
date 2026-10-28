package estimate

import (
	"context"
	"fmt"
	"regexp"
	"sort"
	"strconv"
	"strings"
	"sync"
)

// LibraryFood is a food the household saved: exact numbers per serving, used before any
// database or AI so the same food always gets the same answer.
type LibraryFood struct {
	ID           int64
	Name         string
	Brand        string
	ServingText  string
	ServingGrams float64
	N            Nutrients
	Source       string
	SourceID     string
	Servings     []Portion
	UseCount     int
}

// Library lists the saved foods, most used first.
type Library interface {
	All(ctx context.Context) ([]LibraryFood, error)
}

func (l LibraryFood) food() Food {
	n := l.N
	f := Food{
		Source: SourceLibrary, ID: strconv.FormatInt(l.ID, 10), Name: l.Name, Brand: l.Brand, DataType: "Library", Origin: l.Source,
		PerServing: &n, ServingGrams: l.ServingGrams, ServingText: l.ServingText,
	}
	if p, ok := portionFromLabel(l.ServingText, l.ServingGrams); ok {
		f.Portions = append(f.Portions, p)
	}
	for _, s := range l.Servings {
		if p, ok := portionFromLabel(s.Label, s.Grams); ok {
			f.Portions = append(f.Portions, p)
		}
	}
	return f
}

// descriptors are words that qualify a food without changing which food it is, so "apple" and
// "apple, raw, medium" are the same library entry while "apple pie" is not.
var descriptors = map[string]bool{
	"raw": true, "fresh": true, "whole": true, "plain": true, "organic": true, "medium": true,
	"large": true, "small": true, "regular": true, "original": true, "skin": true,
}

// libraryMatch reports whether a saved food is the one the item names, and how many
// descriptor words differ (0 is an exact name match). The brand must agree when either side has one.
func libraryMatch(it Item, l LibraryFood) (diff int, ok bool) {
	itemBrand := toSet(tokens(it.Brand))
	libBrand := tokens(l.Brand)
	ctxTok := toSet(tokens(it.Brand + " " + it.Text + " " + it.Food))
	for _, t := range libBrand {
		if !ctxTok[t] {
			return 0, false
		}
	}
	nameTok := tokens(l.Name)
	if len(itemBrand) > 0 {
		all := toSet(append(append([]string{}, nameTok...), libBrand...))
		for t := range itemBrand {
			if !all[t] {
				return 0, false
			}
		}
	}
	strip := toSet(append(tokens(it.Brand), libBrand...))
	a := toSet(without(nameTok, strip))
	b := toSet(without(tokens(it.Food), strip))
	if len(a) == 0 && len(b) == 0 {
		return 0, false
	}
	common := 0
	for t := range a {
		if b[t] {
			common++
		} else if !descriptors[t] {
			return 0, false
		} else {
			diff++
		}
	}
	for t := range b {
		if !a[t] {
			if !descriptors[t] {
				return 0, false
			}
			diff++
		}
	}
	return diff, common > 0
}

// bestLibrary returns the closest saved food; the list order (most used first) breaks ties.
func bestLibrary(it Item, foods []LibraryFood) (LibraryFood, bool) {
	best, bestDiff, found := LibraryFood{}, 0, false
	for _, l := range foods {
		if d, ok := libraryMatch(it, l); ok && (!found || d < bestDiff) {
			best, bestDiff, found = l, d, true
		}
	}
	return best, found
}

func libraryHit(it Item, l LibraryFood) (hit, bool) {
	f := l.food()
	r, ok := resolve(f, it)
	if !ok {
		return hit{}, false
	}
	conf := ConfidenceHigh
	if r.Basis != basisExact {
		conf = ConfidenceMedium
	}
	return hit{Food: f, Resolved: r, Confidence: conf}, true
}

var multiFood = regexp.MustCompile(`(?i)[,;&+\n]|\band\b|\bplus\b|\bwith\b`)

var leadingQty = regexp.MustCompile(`(?i)^\s*(\d+(?:\.\d+)?|\d+/\d+|an?)\s+(.+)$`)

// exactLibraryItem is the fast path: a single phrase that is exactly a saved food needs no AI
// to split. It returns the item to size, or false when the text needs the parse step.
func exactLibraryItem(text string, foods []LibraryFood) (Item, LibraryFood, bool) {
	text = strings.TrimSpace(text)
	if text == "" || multiFood.MatchString(text) {
		return Item{}, LibraryFood{}, false
	}
	qty, phrase := 1.0, text
	if m := leadingQty.FindStringSubmatch(text); m != nil {
		phrase = m[2]
		if !strings.EqualFold(m[1], "a") && !strings.EqualFold(m[1], "an") {
			qty = parseAmount(m[1])
			if qty <= 0 || qty > maxQuantity {
				return Item{}, LibraryFood{}, false
			}
		}
	}
	for _, candidate := range []struct {
		phrase string
		qty    float64
	}{{text, 1}, {phrase, qty}} {
		it := Item{Text: text, Food: candidate.phrase, Quantity: candidate.qty, Unit: "serving", Kind: KindGeneric}
		for _, l := range foods {
			if d, ok := libraryMatch(it, l); ok && d == 0 {
				it.Label = l.Name
				return it, l, true
			}
		}
	}
	return Item{}, LibraryFood{}, false
}

// SearchLibrary ranks saved foods against a query: all query words must appear in the name or
// brand, then exact names first, then most used. An empty query lists everything by use.
func SearchLibrary(q string, foods []LibraryFood) []LibraryFood {
	want := tokens(q)
	type scored struct {
		f     LibraryFood
		exact bool
	}
	var hits []scored
	for _, f := range foods {
		have := toSet(tokens(f.Name + " " + f.Brand))
		ok := true
		for _, t := range want {
			if !have[t] && !prefixOf(t, have) {
				ok = false
			}
		}
		if !ok {
			continue
		}
		hits = append(hits, scored{f, len(want) > 0 && len(have) == len(want)})
	}
	sort.SliceStable(hits, func(i, j int) bool {
		if hits[i].exact != hits[j].exact {
			return hits[i].exact
		}
		return hits[i].f.UseCount > hits[j].f.UseCount
	})
	out := make([]LibraryFood, len(hits))
	for i, h := range hits {
		out[i] = h.f
	}
	return out
}

func prefixOf(t string, have map[string]bool) bool {
	for h := range have {
		if strings.HasPrefix(h, t) {
			return true
		}
	}
	return false
}

// ServingView is how a database food is offered for saving: one serving with its numbers, and
// other servings by weight.
type ServingView struct {
	Text  string
	Grams float64
	N     Nutrients
	Alts  []Portion
}

// Serving picks a human serving for a database food: the label's serving when it has one,
// otherwise the first household measure (the last for branded foods, whose first is the plain
// "serving"), otherwise 100 g.
func (f Food) Serving() ServingView {
	v := f.serving()
	v.Text = tidyServing(v.Text)
	return v
}

func (f Food) serving() ServingView {
	if f.PerServing != nil {
		text := f.ServingText
		if text == "" {
			text = "1 serving"
		}
		if f.ServingGrams > 0 && !strings.Contains(strings.ToLower(text), " g)") {
			text = fmt.Sprintf("%s (%s g)", text, trimFloat(f.ServingGrams))
		}
		return ServingView{Text: text, Grams: f.ServingGrams, N: *f.PerServing}
	}
	per100, ok := f.per100()
	if !ok {
		return ServingView{}
	}
	if len(f.Portions) > 0 {
		idx := 0
		if f.DataType == typeBranded {
			idx = len(f.Portions) - 1
		}
		p := f.Portions[idx]
		v := ServingView{Text: fmt.Sprintf("1 %s", p.Label), Grams: p.Grams, N: per100.scale(p.Grams / 100)}
		for i, o := range f.Portions {
			if i != idx {
				v.Alts = append(v.Alts, o)
			}
		}
		return v
	}
	return ServingView{Text: "100 g", Grams: 100, N: per100}
}

// SearchRemote finds unsaved candidates in USDA and Open Food Facts for the library search.
// Failures of one database leave the other's results.
func (f *Foods) SearchRemote(ctx context.Context, q string) []Food {
	q = strings.Join(strings.Fields(q), " ")
	if q == "" {
		return nil
	}
	it := Item{Food: q}
	var generic, branded, off []Food
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
			branded, _ = cached(c, "usda|branded|"+key, func() ([]Food, error) { return f.USDA.Search(ctx, q, typeBranded) })
		})
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
	for i, fd := range top(generic, 4) {
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

var servingEcho = regexp.MustCompile(`^(?:1 )?(.+?) \((?:1 )?(.+)\)$`)

// tidyServing cleans database serving wording for display: "1 serving (1 serving)" becomes
// "1 serving", and household text in capitals ("1 POUCH RECONSTITUTED") is lowered.
func tidyServing(text string) string {
	text = strings.Join(strings.Fields(text), " ")
	if m := servingEcho.FindStringSubmatch(text); m != nil && strings.EqualFold(m[1], m[2]) {
		text = strings.TrimSuffix(text, text[strings.LastIndex(text, " ("):])
	}
	if strings.ToUpper(text) == text && strings.ToLower(text) != text {
		text = strings.ToLower(text)
	}
	return text
}

// substitutes are words that mark a stand-in for a food, which someone searching for the food
// itself rarely wants first.
var substitutes = map[string]bool{"meatless": true, "imitation": true, "substitute": true, "analog": true, "vegetarian": true}

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
