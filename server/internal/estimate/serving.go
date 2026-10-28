package estimate

import (
	"fmt"
	"regexp"
	"strings"
)

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

var gramsEcho = regexp.MustCompile(`(?i)^([\d.]+) (?:g|gm|grm|grams?) \(([\d.]+) g\)$`)

var servingEcho = regexp.MustCompile(`^(?:1 )?(.+?) \((?:1 )?(.+)\)$`)

// tidyServing cleans database serving wording for display: "1 serving (1 serving)" becomes
// "1 serving", and household text in capitals ("1 POUCH RECONSTITUTED") is lowered.
func tidyServing(text string) string {
	text = strings.Join(strings.Fields(text), " ")
	// A label serving that is only a weight ("100 GRAM") gains the same weight in grams.
	if m := gramsEcho.FindStringSubmatch(text); m != nil && m[1] == m[2] {
		return m[1] + " g"
	}
	if m := servingEcho.FindStringSubmatch(text); m != nil && strings.EqualFold(m[1], m[2]) {
		text = strings.TrimSuffix(text, text[strings.LastIndex(text, " ("):])
	}
	words := strings.Fields(text)
	for i, w := range words {
		if len(w) > 1 && strings.ToUpper(w) == w && strings.ToLower(w) != w {
			words[i] = strings.ToLower(w)
		}
		// USDA writes ounces as "ONZ".
		if words[i] == "onz" {
			words[i] = "oz"
		}
	}
	return strings.Join(words, " ")
}
