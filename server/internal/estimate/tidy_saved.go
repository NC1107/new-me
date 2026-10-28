package estimate

import (
	"strings"
	"unicode"
)

// TidySaved applies the search-result tidy rules to a database food saved before they existed. A
// saved brand may be "<brand> <OWNER IN CAPITALS> <company suffix>", from when the owner was
// appended to the brand name; the owner words go and the brand stays. Running it on its own
// output changes nothing.
func TidySaved(name, brand string) (string, string) {
	return tidyName(strings.TrimSpace(name)), tidySavedBrand(strings.TrimSpace(brand))
}

func tidySavedBrand(brand string) string {
	stripped := brand
	for {
		trimmed := strings.TrimSpace(corporateSuffix.ReplaceAllString(stripped, ""))
		if trimmed == stripped || trimmed == "" {
			break
		}
		stripped = trimmed
	}
	if stripped == brand {
		return tidyName(brand)
	}
	words := strings.Fields(stripped)
	end := len(words)
	for end > 1 && isAllCaps(words[end-1]) {
		end--
	}
	if end < len(words) && !isAllCaps(words[end-1]) {
		stripped = strings.Join(words[:end], " ")
	}
	return tidyName(stripped)
}

func isAllCaps(w string) bool {
	letters := 0
	for _, r := range w {
		if unicode.IsLetter(r) {
			letters++
			if !unicode.IsUpper(r) {
				return false
			}
		}
	}
	return letters > 0
}
