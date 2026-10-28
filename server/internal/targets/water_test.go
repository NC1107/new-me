package targets

import "testing"

func TestComputeWaterFollowsTheAdequateIntakeOfDrinksBySex(t *testing.T) {
	male, female := Male, Female
	tests := []struct {
		name         string
		sex          *Sex
		want         int
		personalized bool
	}{
		{"male", &male, 3000, true},
		{"female", &female, 2200, true},
		{"no sex uses the lower figure", nil, 2200, false},
	}
	for _, tt := range tests {
		got := ComputeWater(tt.sex)
		if got.ML != tt.want || got.Personalized != tt.personalized {
			t.Errorf("%s: got %+v, want %d ml personalized=%v", tt.name, got, tt.want, tt.personalized)
		}
	}
	near(t, "male drinks share of total water", float64(WaterMaleML)/(WaterMaleTotalL*1000), 0.81, 0.005)
	near(t, "female drinks share of total water", float64(WaterFemaleML)/(WaterFemaleTotalL*1000), 0.81, 0.005)
}

func TestWaterSourcesAreCited(t *testing.T) {
	for _, key := range []string{"nasem2005", "efsa2010"} {
		if Sources[key] == "" {
			t.Errorf("source %s is missing", key)
		}
	}
}
