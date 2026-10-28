package targets

import "testing"

func TestCardioNormsAreOrderedAndFallWithAge(t *testing.T) {
	for sex, rows := range cardioNorms {
		for d, row := range rows {
			for i := 1; i < len(row); i++ {
				if row[i] <= row[i-1] {
					t.Errorf("%s decade %d: column %d (%v) does not exceed column %d (%v)", sex, d, i, row[i], i-1, row[i-1])
				}
			}
			if d > 0 && row[medianColumn] >= rows[d-1][medianColumn] {
				t.Errorf("%s decade %d: median %v does not fall below the decade before", sex, d, row[medianColumn])
			}
		}
	}
}

func TestCardioNormsBandEdges(t *testing.T) {
	// Men 40-49: 10th 22.1, 50th 35.3, 90th 50.8.
	tests := []struct {
		name    string
		vo2     float64
		low, hi int
	}{
		{"below the 10th", 22.0, 0, 10},
		{"exactly the 10th", 22.1, 10, 20},
		{"between the 40th and 50th", 35.0, 40, 50},
		{"exactly the median", 35.3, 50, 60},
		{"just under the 90th", 50.7, 80, 90},
		{"exactly the 90th", 50.8, 90, 100},
		{"far above the 90th", 70, 90, 100},
	}
	for _, tt := range tests {
		got, ok := CardioNorms(tt.vo2, 45, Male)
		if !ok || got.Low != tt.low || got.High != tt.hi || got.AgeGroup != "40-49" || got.MedianVO2 != 35.3 {
			t.Errorf("%s: got %+v ok=%v, want band %d-%d", tt.name, got, ok, tt.low, tt.hi)
		}
	}
}

func TestCardioNormsEveryAgeGroupAndSex(t *testing.T) {
	tests := []struct {
		age    int
		sex    Sex
		group  string
		median float64
	}{
		{20, Male, "20-29", 46.5},
		{29, Male, "20-29", 46.5},
		{30, Male, "30-39", 39.7},
		{40, Male, "40-49", 35.3},
		{50, Male, "50-59", 29.2},
		{60, Male, "60-69", 24.6},
		{70, Male, "70-79", 20.6},
		{80, Male, "80-89", 17.6},
		{89, Male, "80-89", 17.6},
		{20, Female, "20-29", 36.6},
		{35, Female, "30-39", 28.3},
		{49, Female, "40-49", 25.7},
		{55, Female, "50-59", 22.9},
		{65, Female, "60-69", 19.6},
		{75, Female, "70-79", 17.2},
		{85, Female, "80-89", 15.4},
	}
	for _, tt := range tests {
		got, ok := CardioNorms(tt.median, tt.age, tt.sex)
		if !ok || got.AgeGroup != tt.group || got.MedianVO2 != tt.median || got.Low != 50 || got.High != 60 {
			t.Errorf("age %d %s: got %+v ok=%v, want group %s at the median", tt.age, tt.sex, got, ok, tt.group)
		}
	}
}

func TestCardioNormsSameValueRanksHigherForWomenAndOlderPeople(t *testing.T) {
	man, _ := CardioNorms(35, 40, Male)
	woman, _ := CardioNorms(35, 40, Female)
	older, _ := CardioNorms(35, 60, Male)
	if woman.Low <= man.Low || older.Low <= man.Low {
		t.Errorf("man 40 %+v, woman 40 %+v, man 60 %+v", man, woman, older)
	}
}

func TestCardioNormsMissingOrOutOfRangeData(t *testing.T) {
	tests := []struct {
		name string
		vo2  float64
		age  int
		sex  Sex
	}{
		{"under 20", 45, 19, Male},
		{"90 or older", 20, 90, Female},
		{"negative age", 45, -1, Male},
		{"unknown sex", 45, 40, Sex("")},
		{"zero value", 0, 40, Male},
		{"negative value", -3, 40, Female},
	}
	for _, tt := range tests {
		if got, ok := CardioNorms(tt.vo2, tt.age, tt.sex); ok {
			t.Errorf("%s: got %+v, want no placement", tt.name, got)
		}
	}
}
