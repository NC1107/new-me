package targets

import "testing"

func TestDailyFromWeeklyRoundsUp(t *testing.T) {
	for week, want := range map[int]int{150: 22, 300: 43, 140: 20, 7: 1} {
		if got := DailyFromWeekly(week); got != want {
			t.Errorf("DailyFromWeekly(%d) = %d, want %d", week, got, want)
		}
	}
}

func TestWaterAlternativeIsEFSATotalLessFood(t *testing.T) {
	male, female := Male, Female
	for _, c := range []struct {
		sex  *Sex
		want int
	}{{&male, 2050}, {&female, 1600}, {nil, 1600}} {
		got := WaterAlternatives(c.sex)
		if len(got) != 1 || got[0].Value != c.want {
			t.Errorf("WaterAlternatives(%v) = %+v, want %d", c.sex, got, c.want)
		}
	}
}

func TestProteinAlternativesSkipTheRecommendation(t *testing.T) {
	got := ProteinAlternatives(80, 130)
	want := []int{65, 110, 160}
	if len(got) != len(want) {
		t.Fatalf("got %+v", got)
	}
	for i, a := range got {
		if a.Value != want[i] || a.Label == "" {
			t.Errorf("alternative %d = %+v, want %d", i, a, want[i])
		}
	}
	for _, a := range ProteinAlternatives(80, 110) {
		if a.Value == 110 {
			t.Errorf("recommendation repeated: %+v", a)
		}
	}
}

func TestStepAlternativesSkipTheRecommendation(t *testing.T) {
	if got := StepAlternatives(7000, 10000, 7000); len(got) != 1 || got[0].Value != 10000 {
		t.Errorf("got %+v", got)
	}
	if got := StepAlternatives(8000, 10000, 7000); len(got) != 2 {
		t.Errorf("got %+v", got)
	}
}

func TestProduceServingsAreGramsAndHaveExamples(t *testing.T) {
	if ProduceServings*ProduceServingGrams != ProduceWHOGrams {
		t.Errorf("servings do not add up to %d g", ProduceWHOGrams)
	}
	if got := ProduceAlternatives(); len(got) != 1 || got[0].Value != 10 {
		t.Errorf("got %+v", got)
	}
	if len(ProduceExamples) == 0 {
		t.Error("no serving examples")
	}
}
