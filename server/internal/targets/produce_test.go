package targets

import "testing"

func TestServingsFromMealsPoolsGramsAcrossMeals(t *testing.T) {
	cases := []struct {
		name string
		in   ProduceGramsToday
		want int
	}{
		{"nothing", ProduceGramsToday{}, 0},
		{"just under one serving", ProduceGramsToday{Whole: 79}, 0},
		{"exactly one serving", ProduceGramsToday{Whole: 80}, 1},
		{"two meals of 50 g make one serving", ProduceGramsToday{Whole: 100}, 1},
		{"250 g is three servings", ProduceGramsToday{Whole: 250}, 3},
		{"400 g is the five a day", ProduceGramsToday{Whole: 400}, 5},
	}
	for _, c := range cases {
		if got := ServingsFromMeals(c.in); got != c.want {
			t.Errorf("%s: %d servings, want %d", c.name, got, c.want)
		}
	}
}

func TestJuiceAndPulsesCountOncePerDay(t *testing.T) {
	// Three glasses of juice (450 g) and a big bowl of beans (300 g) are one serving each.
	if got := ServingsFromMeals(ProduceGramsToday{Juice: 450, Pulse: 300}); got != 2 {
		t.Errorf("juice and pulses gave %d servings, want 2", got)
	}
	// A little juice is a part of a serving that can complete one with whole produce.
	if got := ServingsFromMeals(ProduceGramsToday{Whole: 40, Juice: 40}); got != 1 {
		t.Errorf("40 g fruit and 40 g juice gave %d servings, want 1", got)
	}
}

func TestProduceServingsTodayAddsLoggedAndCaps(t *testing.T) {
	if got := ProduceServingsToday(2, ProduceGramsToday{Whole: 160}); got != 4 {
		t.Errorf("2 logged and 160 g in meals = %d, want 4", got)
	}
	if got := ProduceServingsToday(25, ProduceGramsToday{Whole: 800}); got != ProduceMaxServings {
		t.Errorf("over the ceiling = %d, want %d", got, ProduceMaxServings)
	}
}
