package together

import "slices"

// MaxRewardPrice is the most a reward may cost, in gems.
const MaxRewardPrice = 100000

// Bank is the pair's spendable gems: everything both have earned minus what claimed rewards
// cost. A later re-score can lower the total below what was spent; the bank then reads zero.
func Bank(total, spent int) int { return max(total-spent, 0) }

// RewardProgress is how much of the price the bank covers, never above the price.
func RewardProgress(bank, price int) int { return min(max(bank, 0), price) }

// RewardReady reports whether the bank covers the price.
func RewardReady(bank, price int) bool { return bank >= price }

// MedianInt is the median of values, rounding half up for an even count. It is 0 for none.
func MedianInt(values []int) int {
	if len(values) == 0 {
		return 0
	}
	sorted := slices.Clone(values)
	slices.Sort(sorted)
	mid := len(sorted) / 2
	if len(sorted)%2 == 1 {
		return sorted[mid]
	}
	return (sorted[mid-1] + sorted[mid] + 1) / 2
}

// PriceOption is a suggested price: what the pair earns at its own pace over Days days.
type PriceOption struct {
	Days  int
	Price int
}

// PriceHelp is the pair's median combined daily gems and the prices that follow from it.
type PriceHelp struct {
	MedianDaily int
	// SampleDays is how many days the median is taken over.
	SampleDays int
	Options    []PriceOption
}

// PriceHorizons are the lengths, in days, a price is suggested for.
var PriceHorizons = []int{7, 14, 30}

// SuggestPrices turns the pair's combined gems per day (the last 14 days, or fewer when the
// pair is newer) into prices for a week, two weeks and a month at that pace. It answers nil
// when there is no history or no gems to base a figure on, so nothing is ever invented.
func SuggestPrices(daily []int) *PriceHelp {
	median := MedianInt(daily)
	if median <= 0 {
		return nil
	}
	help := &PriceHelp{MedianDaily: median, SampleDays: len(daily)}
	for _, days := range PriceHorizons {
		if price := median * days; price <= MaxRewardPrice {
			help.Options = append(help.Options, PriceOption{Days: days, Price: price})
		}
	}
	return help
}
