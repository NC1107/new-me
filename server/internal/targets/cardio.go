package targets

import "strconv"

// CardioSource names the table cardioNorms is transcribed from.
const CardioSource = "FRIEND registry treadmill standards, Kaminsky et al., Mayo Clin Proc 2022;97(2):285-293, Table 3"

// Age bounds of the published tables, in years.
const (
	CardioMinAge = 20
	CardioMaxAge = 89
)

// cardioPercentiles are the percentile columns of the published table.
var cardioPercentiles = [...]int{10, 20, 30, 40, 50, 60, 70, 80, 90}

// medianColumn is the index of the 50th percentile in cardioPercentiles.
const medianColumn = 4

// cardioNorms holds peak VO2 in ml/kg/min on a treadmill for apparently healthy US adults, one
// row per decade of age from 20 to 89 with the last row spanning 80 to 89. Peak effort was a
// respiratory exchange ratio of at least 1.0. The columns are cardioPercentiles.
var cardioNorms = map[Sex][7][9]float64{
	Male: {
		{28.6, 35.2, 40.0, 43.6, 46.5, 49.0, 51.9, 54.5, 58.6},
		{24.9, 29.8, 33.5, 37.0, 39.7, 43.4, 46.4, 50.0, 55.5},
		{22.1, 26.7, 29.7, 32.4, 35.3, 37.9, 40.9, 45.2, 50.8},
		{18.6, 22.2, 24.5, 26.9, 29.2, 31.8, 34.3, 38.3, 43.4},
		{15.8, 18.5, 20.7, 22.8, 24.6, 26.5, 28.7, 32.0, 37.1},
		{13.6, 15.9, 17.3, 19.1, 20.6, 22.2, 23.8, 25.9, 29.4},
		{12.9, 14.8, 16.1, 16.6, 17.6, 18.4, 20.0, 21.4, 22.8},
	},
	Female: {
		{22.5, 27.2, 30.8, 34.0, 36.6, 39.0, 41.8, 44.8, 49.0},
		{18.6, 21.9, 24.2, 26.4, 28.3, 31.0, 33.6, 37.0, 42.1},
		{17.2, 19.7, 21.8, 23.9, 25.7, 27.7, 30.0, 33.0, 37.8},
		{16.5, 18.5, 20.1, 21.5, 22.9, 24.6, 26.3, 28.4, 32.4},
		{13.4, 15.4, 17.0, 18.3, 19.6, 20.9, 22.4, 24.3, 27.3},
		{12.3, 14.0, 15.2, 16.2, 17.2, 18.3, 19.6, 20.8, 22.8},
		{11.4, 12.6, 13.7, 14.7, 15.4, 16.0, 17.3, 18.4, 20.8},
	},
}

// CardioPlacement is where a VO2 max falls among people of the same sex and age decade.
type CardioPlacement struct {
	// AgeGroup is the decade the age falls in, like "40-49".
	AgeGroup string
	// Low and High bound the percentile band. Low is 0 below the 10th percentile and High is 100
	// above the 90th, because the table says nothing finer at the ends.
	Low, High int
	// MedianVO2 is the 50th percentile of the group.
	MedianVO2 float64
}

// CardioNorms places a VO2 max against the FRIEND table. A value equal to a column counts as
// reaching that percentile. It reports false for an age outside 20 to 89, an unknown sex, or a
// value that is not positive.
func CardioNorms(vo2 float64, age int, sex Sex) (CardioPlacement, bool) {
	rows, ok := cardioNorms[sex]
	if !ok || age < CardioMinAge || age > CardioMaxAge || vo2 <= 0 {
		return CardioPlacement{}, false
	}
	decade := min((age-CardioMinAge)/10, len(rows)-1)
	row := rows[decade]
	out := CardioPlacement{
		AgeGroup:  cardioAgeGroup(decade),
		High:      cardioPercentiles[0],
		MedianVO2: row[medianColumn],
	}
	for i, v := range row {
		if vo2 < v {
			break
		}
		out.Low, out.High = cardioPercentiles[i], 100
		if i+1 < len(row) {
			out.High = cardioPercentiles[i+1]
		}
	}
	return out, true
}

func cardioAgeGroup(decade int) string {
	lo := CardioMinAge + decade*10
	return strconv.Itoa(lo) + "-" + strconv.Itoa(lo+9)
}
