package estimate

import (
	"regexp"
	"strings"
)

// What a food is for the fruit and vegetable quest. Empty is not produce or not known.
const (
	ProduceFruit     = "fruit"
	ProduceVegetable = "vegetable"
	// ProduceJuice is juice and smoothies, which count at most once a day (NHS 5 A Day).
	ProduceJuice = "juice"
	// ProducePulse is beans, peas and lentils, which count at most once a day (NHS 5 A Day).
	ProducePulse = "pulse"
)

// ValidProduceKind reports whether kind is one of the four kinds or empty.
func ValidProduceKind(kind string) bool {
	switch kind {
	case "", ProduceFruit, ProduceVegetable, ProduceJuice, ProducePulse:
		return true
	}
	return false
}

// usdaProduceCategory maps the food category USDA files a food under to what it is for the
// quest. FNDDS categories are fine grained, so juice, potatoes and fried or mixed vegetable
// dishes are separate from plain fruit and vegetables. A category missing here counts for
// nothing, which undercounts rather than guesses.
var usdaProduceCategory = map[string]string{
	// Foundation and SR Legacy file produce in these two groups, with juice and potatoes inside
	// them; usdaProduceKind separates those from the food's own USDA description.
	"Fruits and Fruit Juices":           ProduceFruit,
	"Vegetables and Vegetable Products": ProduceVegetable,

	// FNDDS (what people report eating), as named in What We Eat in America.
	"Apples":                            ProduceFruit,
	"Bananas":                           ProduceFruit,
	"Grapes":                            ProduceFruit,
	"Citrus fruits":                     ProduceFruit,
	"Melons":                            ProduceFruit,
	"Berries":                           ProduceFruit,
	"Peaches and nectarines":            ProduceFruit,
	"Pears":                             ProduceFruit,
	"Pineapple":                         ProduceFruit,
	"Mango and papaya":                  ProduceFruit,
	"Other fruits and fruit salads":     ProduceFruit,
	"Tomatoes":                          ProduceVegetable,
	"Carrots":                           ProduceVegetable,
	"Other red and orange vegetables":   ProduceVegetable,
	"Dark green vegetables":             ProduceVegetable,
	"Lettuce and lettuce salads":        ProduceVegetable,
	"String beans":                      ProduceVegetable,
	"Cabbage":                           ProduceVegetable,
	"Onions":                            ProduceVegetable,
	"Other vegetables and combinations": ProduceVegetable,
	"Citrus juice":                      ProduceJuice,
	"Apple juice":                       ProduceJuice,
	"Other fruit juice":                 ProduceJuice,
	"Vegetable juice":                   ProduceJuice,
	"Beans, peas, legumes":              ProducePulse,
}

// starchyHeads are the foods NHS 5 A Day says do not count. SR Legacy and Foundation file
// potatoes under "Vegetables and Vegetable Products" and give no finer category, so USDA's own
// description, which always starts with the food, is the only field that separates them.
var starchyHeads = map[string]bool{"potatoes": true, "cassava": true, "yams": true, "plantains": true}

var juiceWord = regexp.MustCompile(`\b(juices?|smoothies?|nectars?)\b`)

// usdaProduceKind is what a USDA food is for the quest, from its category and the head of its
// description ("Potatoes, baked, ..." has the head "potatoes"). Branded foods are never produce
// here: their categories are the manufacturer's shelf, not the food.
func usdaProduceKind(dataType, category, description string) string {
	if dataType == typeBranded {
		return ""
	}
	kind := usdaProduceCategory[category]
	if kind == "" {
		return ""
	}
	if category == "Fruits and Fruit Juices" || category == "Vegetables and Vegetable Products" {
		head, _, _ := strings.Cut(strings.ToLower(strings.TrimSpace(description)), ",")
		if juiceWord.MatchString(head) {
			return ProduceJuice
		}
		if starchyHeads[strings.TrimSpace(head)] {
			return ""
		}
	}
	return kind
}
