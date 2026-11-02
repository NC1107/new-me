// Package gems is the pure arithmetic of who holds which gems: each person's balance, the shared
// bank and how a shared reward is paid. See docs/design-v19-treats.md.
package gems

import "slices"

// MaxTreatsPerPerson caps how many open treats one person keeps.
const MaxTreatsPerPerson = 30

// Person is one person's lifetime gems: earned from scored days, and paid out on their own
// treats and on their share of shared rewards. Tasks is the net of their settled tasks (gems won
// by finishing, minus stakes lost by missing); it is a ledger of its own, never day points.
type Person struct {
	Earned int
	Paid   int
	Tasks  int
}

// Balance is what the person holds. It reads below zero when missed tasks or a re-score took
// more than they had, so a debt shows and later earnings pay it down. See docs/design-v21-tasks.md.
func (p Person) Balance() int { return p.Earned + p.Tasks - p.Paid }

// Spendable is the balance a treat or a shared reward may draw on: a debt spends nothing.
func (p Person) Spendable() int { return max(p.Balance(), 0) }

// Bank is the shared bank: both people's balances added up, so one person's debt is covered by
// the other's gems before anything is left to claim. It never reads below zero.
func Bank(people []Person) int {
	total := 0
	for _, p := range people {
		total += p.Balance()
	}
	return max(total, 0)
}

// Balances lists what each person can spend, in order. A person in debt contributes zero, which
// keeps SplitPrice from asking them for gems they do not hold.
func Balances(people []Person) []int {
	out := make([]int, len(people))
	for i, p := range people {
		out[i] = p.Spendable()
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
