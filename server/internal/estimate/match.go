package estimate

import (
	"slices"
	"strings"
)

// minRecall is the share of the item's name tokens a candidate must contain to be accepted.
const minRecall = 0.6

type match struct {
	Food  Food
	Score float64
	// Recall is the share of the item's name tokens found in the candidate.
	Recall float64
}

func dataTypePreference(f Food) float64 {
	switch f.DataType {
	// FNDDS takes its nutrients from Foundation and SR Legacy foods or from recipes built on
	// them (FNDDS 2021-2023 documentation, "Nutrient values"), so it is as trustworthy and only
	// worded the way people eat.
	case typeFoundation, typeSRLegacy, typeSurvey:
		return 1
	case typeBranded:
		return 0.2
	}
	return 0.5
}

// scoreFood rates one candidate against the item. ok is false when the candidate must not be
// used at all: too few of the name tokens, or a different brand than the one asked for.
func scoreFood(it Item, f Food) (match, bool) {
	want := tokens(it.Food)
	brand := tokens(it.Brand)
	if len(want) == 0 && len(brand) == 0 {
		return match{}, false
	}
	have := tokens(f.Name + " " + f.Brand)
	haveSet := toSet(have)

	brandRecall := 0.0
	if len(brand) > 0 {
		brandRecall = share(brand, haveSet)
		if brandRecall < 1 {
			return match{}, false
		}
	}
	// A brand token is not part of the food name, so it must not count against recall.
	nameWant := without(want, toSet(brand))
	recall := 1.0
	if len(nameWant) > 0 {
		recall = share(nameWant, haveSet)
	}
	if recall < minRecall {
		return match{}, false
	}

	nameTokens := tokens(f.Name)
	// USDA generic descriptions lead with the food itself and add descriptors after commas
	// ("Milk, whole", "Cheese, mozzarella, whole milk"). A lead the person did not name is another
	// food, whatever order they said their words in: "whole milk" is not mozzarella and "avocado"
	// is not "Avocado dressing".
	if isGenericUSDA(f) {
		segments := strings.Split(f.Name, ",")
		if !namesTheFood(segments, nameWant, restaurantRow(f)) {
			return match{}, false
		}
		nameTokens = specifiedTokens(segments)
	}
	precision := 0.0
	if len(nameTokens) > 0 {
		wantSet := toSet(append(append([]string{}, nameWant...), brand...))
		hits := 0
		for _, t := range nameTokens {
			if wantSet[t] {
				hits++
			}
		}
		precision = float64(hits) / float64(len(nameTokens))
	}
	first := 0.0
	if isGenericUSDA(f) || (len(nameTokens) > 0 && len(nameWant) > 0 && nameTokens[0] == nameWant[0]) {
		first = 1
	}
	last := dataTypePreference(f)
	if len(brand) > 0 {
		last = brandRecall
	}
	return match{Food: f, Recall: recall, Score: 0.5*recall + 0.2*precision + 0.15*first + 0.15*last}, true
}

// namesTheFood is whether a USDA generic row is the food the person named. The lead segment is
// usually the food itself ("Milk, whole"), and must then be words they said. Some rows lead with
// a class instead ("Fish, salmon, baked", "Soft drink, cola"); those count when the second
// segment is words they said and holds their leading word, so "Fish, salmon" answers "salmon,
// baked" while "Orange peel, raw" still does not answer "orange, raw".
func namesTheFood(segments, want []string, restaurant bool) bool {
	if lead := tokens(segments[0]); len(lead) > 0 && containsAll(want, lead) {
		return true
	}
	// A restaurant row leads with the restaurant ("APPLEBEE'S, french fries"), which is a brand
	// the person did not name, not a class of food.
	if restaurant || len(segments) < 2 || len(want) == 0 {
		return false
	}
	second := tokens(segments[1])
	return len(second) > 0 && containsAll(want, second) && slices.Contains(second, want[0])
}

// specifiedTokens leaves out FNDDS "NFS" and "NS as to ..." descriptors, which say the detail was
// not given (FNDDS 2021-2023 documentation, "NFS and NS food codes"), so they do not count as
// words the person left out: "almonds" is exactly "Almonds, NFS".
func specifiedTokens(segments []string) []string {
	var out []string
	for _, seg := range segments {
		if !unspecifiedMarker.MatchString(strings.TrimSpace(seg)) {
			out = append(out, tokens(seg)...)
		}
	}
	return out
}

// restaurantRow is whether USDA files the row under a restaurant's or fast food chain's food.
func restaurantRow(f Food) bool {
	return f.Category == "Restaurant Foods" || f.Category == "Fast Foods"
}

func isGenericUSDA(f Food) bool {
	switch f.DataType {
	case typeFoundation, typeSRLegacy, typeSurvey:
		return true
	}
	return false
}

// pickBest returns the highest scoring acceptable candidate. Ties keep the earlier result,
// which is the database's own relevance order.
func pickBest(it Item, foods []Food) (match, bool) {
	var best match
	found := false
	for _, f := range foods {
		m, ok := scoreFood(it, f)
		m.Score = searchScore(it, m)
		if ok && (!found || m.Score > best.Score) {
			best, found = m, true
		}
	}
	return best, found
}

func toSet(ts []string) map[string]bool {
	m := make(map[string]bool, len(ts))
	for _, t := range ts {
		m[t] = true
	}
	return m
}

func share(want []string, have map[string]bool) float64 {
	hits := 0
	for _, t := range want {
		if have[t] {
			hits++
		}
	}
	return float64(hits) / float64(len(want))
}

func without(ts []string, drop map[string]bool) []string {
	var out []string
	for _, t := range ts {
		if !drop[t] {
			out = append(out, t)
		}
	}
	return out
}

// confidenceFor combines how well the name matched with how firmly the unit converted.
func confidenceFor(m match, b basis) string {
	switch {
	case m.Recall >= 1 && b == basisExact:
		return ConfidenceHigh
	case m.Recall >= 0.75:
		return ConfidenceMedium
	}
	return ConfidenceLow
}

// searchQuery is what goes to a food database: brand and food name, without punctuation.
func searchQuery(it Item) string {
	return strings.Join(strings.Fields(strings.NewReplacer(",", " ", "(", " ", ")", " ").Replace(it.Brand+" "+it.Food)), " ")
}
