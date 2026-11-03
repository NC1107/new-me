package coach

import (
	"math"
	"regexp"
	"strconv"
	"strings"
)

// A figure the coach proposes must be computed by the app or stated by the person. These
// helpers check the second: the quoted words really are in something the person typed, and the
// figure really is a number in those words, possibly in another unit.

var (
	spaces    = regexp.MustCompile(`\s+`)
	numberRe  = regexp.MustCompile(`(\d[\d,]*(?:\.\d+)?)\s*(k\b)?|\b(zero|one|two|three|four|five|six|seven|eight|nine|ten|eleven|twelve)\b|\b(half|quarter)\b`)
	wordValue = map[string]float64{"zero": 0, "one": 1, "two": 2, "three": 3, "four": 4, "five": 5, "six": 6,
		"seven": 7, "eight": 8, "nine": 9, "ten": 10, "eleven": 11, "twelve": 12}
)

func normalize(s string) string {
	return strings.ToLower(strings.TrimSpace(spaces.ReplaceAllString(s, " ")))
}

// QuoteIsFromPerson reports whether quote appears, ignoring case and spacing, in a message the
// person wrote. Assistant messages never count.
func QuoteIsFromPerson(quote string, turns []ChatTurn) bool {
	q := normalize(quote)
	if q == "" {
		return false
	}
	for _, t := range turns {
		if t.Role == "user" && strings.Contains(normalize(t.Text), q) {
			return true
		}
	}
	return false
}

// NumbersIn lists the numbers written in text: digits (with thousands commas and a k suffix)
// and the words zero to twelve.
func NumbersIn(text string) []float64 {
	var out []float64
	for _, m := range numberRe.FindAllStringSubmatch(strings.ToLower(text), -1) {
		switch {
		case m[1] != "":
			v, err := strconv.ParseFloat(strings.ReplaceAll(m[1], ",", ""), 64)
			if err != nil {
				continue
			}
			if m[2] != "" {
				v *= 1000
			}
			out = append(out, v)
		case m[3] != "":
			out = append(out, wordValue[m[3]])
		case m[4] == "half":
			out = append(out, 0.5)
		case m[4] == "quarter":
			out = append(out, 0.25)
		}
	}
	return out
}

// Factor converts a written number to the stored unit: value = number * Mul, within Tol.
type Factor struct {
	Mul, Tol float64
}

// Same is the factor for a number written in the stored unit.
var Same = []Factor{{1, 0.5}}

// Matches reports whether any number in quote, converted by any of the factors, is value.
func Matches(value float64, quote string, factors []Factor) bool {
	for _, n := range NumbersIn(quote) {
		for _, f := range factors {
			if math.Abs(n*f.Mul-value) <= f.Tol {
				return true
			}
		}
	}
	return false
}

// HeightMatches accepts centimetres, inches, or feet and inches ("5 ft 10", "5'10").
func HeightMatches(cm float64, quote string) bool {
	if Matches(cm, quote, []Factor{{1, 0.5}, {2.54, 1.3}}) {
		return true
	}
	nums := NumbersIn(quote)
	for i := 0; i+1 < len(nums); i++ {
		if math.Abs(nums[i]*30.48+nums[i+1]*2.54-cm) <= 1.3 {
			return true
		}
	}
	return false
}

// BirthYearMatches accepts the year itself, or an age that gives it within a year.
func BirthYearMatches(year, thisYear int, quote string) bool {
	for _, n := range NumbersIn(quote) {
		if int(n) == year || (n >= 5 && n <= 110 && math.Abs(float64(thisYear)-n-float64(year)) <= 1) {
			return true
		}
	}
	return false
}
