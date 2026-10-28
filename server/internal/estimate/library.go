package estimate

import (
	"context"
	"regexp"
	"sort"
	"strconv"
	"strings"
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
