package gems

import (
	"slices"
	"testing"
)

func TestBalanceNeverReadsBelowZero(t *testing.T) {
	if got := (Person{Earned: 900, Paid: 300}).Balance(); got != 600 {
		t.Fatalf("balance = %d", got)
	}
	if got := (Person{Earned: 100, Paid: 300}).Balance(); got != 0 {
		t.Fatalf("a re-score below the spend must read zero, got %d", got)
	}
}

func TestBankIsEverythingEarnedMinusAllSpending(t *testing.T) {
	people := []Person{{Earned: 1500, Paid: 1000}, {Earned: 300, Paid: 0}}
	if got := Bank(people); got != 800 {
		t.Fatalf("bank = %d", got)
	}
	if sum := slices.Max(Balances(people)) + slices.Min(Balances(people)); sum != Bank(people) {
		t.Fatalf("balances %v do not add up to the bank %d", Balances(people), Bank(people))
	}
	if got := Bank([]Person{{Earned: 10, Paid: 50}}); got != 0 {
		t.Fatalf("bank = %d", got)
	}
	if got := Bank(nil); got != 0 {
		t.Fatalf("bank = %d", got)
	}
}

func TestSplitPriceIsProportionalExactAndNeverAboveABalance(t *testing.T) {
	cases := []struct {
		price    int
		balances []int
		want     []int
	}{
		{300, []int{400, 400}, []int{150, 150}},
		{300, []int{500, 300}, []int{188, 112}},
		{1, []int{5, 5}, []int{1, 0}},
		{100, []int{0, 700}, []int{0, 100}},
		{100, []int{1, 1, 1}, []int{34, 33, 33}},
		{0, []int{10, 10}, []int{0, 0}},
		{50, []int{0, 0}, []int{0, 0}},
	}
	for _, c := range cases {
		got := SplitPrice(c.price, c.balances)
		if !slices.Equal(got, c.want) {
			t.Errorf("SplitPrice(%d, %v) = %v, want %v", c.price, c.balances, got, c.want)
		}
	}
	for price := 0; price <= 60; price++ {
		for a := 0; a <= 40; a += 7 {
			for b := 0; b <= 40; b += 5 {
				if a+b < price {
					continue
				}
				shares := SplitPrice(price, []int{a, b})
				if shares[0]+shares[1] != price || shares[0] > a || shares[1] > b {
					t.Fatalf("SplitPrice(%d, [%d %d]) = %v", price, a, b, shares)
				}
			}
		}
	}
}

func TestTreatProgress(t *testing.T) {
	if !TreatReady(1000, 1000) || TreatReady(999, 1000) {
		t.Fatal("ready is balance >= price")
	}
	if TreatProgress(1500, 1000) != 1000 || TreatProgress(-5, 1000) != 0 || TreatProgress(400, 1000) != 400 {
		t.Fatal("progress is clamped to 0..price")
	}
	if Cheapest(nil) != 0 || Cheapest([]int{900, 300, 500}) != 300 {
		t.Fatal("cheapest")
	}
}
