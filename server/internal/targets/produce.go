package targets

import "math"

// ProduceMaxServings is the most a day can show, the same ceiling the quest's goal has.
const ProduceMaxServings = 30

// ProduceGramsToday is a day's fruit and vegetable grams in meals, split by how NHS 5 A Day
// counts them.
type ProduceGramsToday struct {
	// Whole is fresh, frozen, canned or dried fruit and vegetables, which add up without limit.
	Whole float64
	// Juice is juice and smoothies, which count as at most one serving however much is drunk.
	Juice float64
	// Pulse is beans, peas and lentils, which count as at most one serving however much is eaten.
	Pulse float64
}

// CountedGrams is what the day's meals add to the produce total: the whole produce, plus at
// most one serving each of juice and pulses.
func (g ProduceGramsToday) CountedGrams() float64 {
	return g.Whole + math.Min(g.Juice, ProduceServingGrams) + math.Min(g.Pulse, ProduceServingGrams)
}

// ServingsFromMeals is the whole servings of 80 g in the counted grams of the day. Pooling the
// grams before rounding down lets half a serving in one meal and half in another make one.
func ServingsFromMeals(g ProduceGramsToday) int {
	return int(math.Floor(g.CountedGrams() / ProduceServingGrams))
}

// ProduceServingsToday adds the servings logged by hand to the servings from meals, capped at the
// most a day can show.
func ProduceServingsToday(logged int, g ProduceGramsToday) int {
	return min(logged+ServingsFromMeals(g), ProduceMaxServings)
}
