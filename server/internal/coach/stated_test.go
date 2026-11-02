package coach

import "testing"

func TestNumbersInReadsDigitsWordsAndSuffixes(t *testing.T) {
	got := NumbersIn("Make it 10,000 steps, or 10k, three days, 7.5 hours")
	want := []float64{10000, 10000, 3, 7.5}
	if len(got) != len(want) {
		t.Fatalf("got %v, want %v", got, want)
	}
	for i := range want {
		if got[i] != want[i] {
			t.Fatalf("got %v, want %v", got, want)
		}
	}
}

func TestQuoteMustBeThePersonsOwnWords(t *testing.T) {
	turns := []ChatTurn{
		{Role: "user", Text: "Please make my goal  10,000 steps"},
		{Role: "assistant", Text: "How about 12,000 steps?"},
		{Role: "user", Text: "ok"},
	}
	if !QuoteIsFromPerson("goal 10,000 STEPS", turns) {
		t.Error("spacing and case must not matter")
	}
	if QuoteIsFromPerson("12,000 steps", turns) {
		t.Error("the coach's own words are not the person's")
	}
	if QuoteIsFromPerson("", turns) {
		t.Error("an empty quote proves nothing")
	}
}

func TestMatchesConvertsUnits(t *testing.T) {
	hours := []Factor{{1, 0.5}, {60, 0.5}}
	water := []Factor{{1, 0.5}, {1000, 5}, {29.5735, 14.8}}
	for _, c := range []struct {
		value   float64
		quote   string
		factors []Factor
		want    bool
	}{
		{450, "7.5 hours of sleep", hours, true},
		{480, "7.5 hours of sleep", hours, false},
		{2000, "2 litres", water, true},
		{1893, "64 oz", water, true},
		{1500, "64 oz", water, false},
		{3, "three days", Same, true},
	} {
		if got := Matches(c.value, c.quote, c.factors); got != c.want {
			t.Errorf("Matches(%v, %q) = %v", c.value, c.quote, got)
		}
	}
}

func TestHeightAndBirthYear(t *testing.T) {
	if !HeightMatches(178, "I'm 178 cm") || !HeightMatches(177.8, "5 ft 10") || !HeightMatches(177.8, "5'10") || !HeightMatches(177.8, "70 inches") {
		t.Error("a stated height must match in cm, inches, or feet and inches")
	}
	if HeightMatches(190, "I'm 178 cm") {
		t.Error("a different height must not match")
	}
	if !BirthYearMatches(1992, 2026, "born in 1992") || !BirthYearMatches(1992, 2026, "I'm 34") || BirthYearMatches(1980, 2026, "I'm 34") {
		t.Error("birth year matching is wrong")
	}
}
