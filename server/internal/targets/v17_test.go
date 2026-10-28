package targets

import "testing"

func TestProduceServingsAreTheWHOMinimumInPortions(t *testing.T) {
	if ProduceServings != 5 || ProduceServings*ProduceServingGrams != ProduceWHOGrams {
		t.Errorf("servings = %d of %d g, want 5 servings making 400 g", ProduceServings, ProduceServingGrams)
	}
	if ProduceLowestRiskGrams/ProduceServingGrams != 10 {
		t.Errorf("800 g is %d servings, want 10", ProduceLowestRiskGrams/ProduceServingGrams)
	}
}

func TestV17SourcesAreCited(t *testing.T) {
	for _, key := range []string{"who2003", "nhs5aday", "aune2017", "balban2023", "zaccaro2018"} {
		if Sources[key] == "" {
			t.Errorf("source %s is missing", key)
		}
	}
}
