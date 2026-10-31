// Package gems is the pure arithmetic of who holds which gems: each person's balance, the shared
// bank and how a shared reward is paid. See docs/design-v19-treats.md.
package gems

import "slices"

// MaxTreatsPerPerson caps how many open treats one person keeps.
const MaxTreatsPerPerson = 30

// Person is one person's lifetime gems: earned from scored days, and paid out on their own
// treats and on their share of shared rewards.
type Person struct {
	Earned int
	Paid   int
}

// Balance is what the person can spend on a treat. It never reads below zero; a later re-score
// can lower Earned below Paid.
func (p Person) Balance() int { return max(p.Earned-p.Paid, 0) }

// Bank is the shared bank: both people's earnings minus all spending, shared rewards and treats
// alike. It equals the sum of the balances unless a re-score pushed someone below zero.
func Bank(people []Person) int {
	earned, paid := 0, 0
	for _, p := range people {
		earned += p.Earned
		paid += p.Paid
	}
	return max(earned-paid, 0)
}

// Balances lists each person's balance in order.
func Balances(people []Person) []int {
	out := make([]int, len(people))
	for i, p := range people {
		out[i] = p.Balance()
	}
	return out
}

// SplitPrice divides the price of a shared reward between people in proportion to the balance
// each holds now, so nobody pays more than they hold and the shares add up to the price exactly.
// Whole gems left over go to the largest fractions, earlier people first. The caller has checked
// that the balances cover the price.
func SplitPrice(price int, balances []int) []int {
	sum := 0
	for _, b := range balances {
		sum += b
	}
	shares := make([]int, len(balances))
	if sum <= 0 {
		return shares
	}
	type remainder struct{ index, frac int }
	rest := make([]remainder, len(balances))
	given := 0
	for i, b := range balances {
		shares[i] = price * b / sum
		rest[i] = remainder{i, price * b % sum}
		given += shares[i]
	}
	slices.SortStableFunc(rest, func(a, b remainder) int { return b.frac - a.frac })
	for i := 0; given < price && i < len(rest); i++ {
		shares[rest[i].index]++
		given++
	}
	return shares
}

// TreatReady reports whether a balance covers a treat's price.
func TreatReady(balance, price int) bool { return balance >= price }

// TreatProgress is how much of the price the balance covers, never above the price.
func TreatProgress(balance, price int) int { return min(max(balance, 0), price) }

// Cheapest is the lowest of prices, or 0 for none.
func Cheapest(prices []int) int {
	if len(prices) == 0 {
		return 0
	}
	return slices.Min(prices)
}
