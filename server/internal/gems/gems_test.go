package gems

import (
	"slices"
	"testing"
)

func TestBalanceShowsADebtButSpendableNeverGoesBelowZero(t *testing.T) {
	if got := (Person{Earned: 900, Paid: 300}).Balance(); got != 600 {
		t.Fatalf("balance = %d", got)
	}
	debt := Person{Earned: 100, Paid: 300}
	if debt.Balance() != -200 || debt.Spendable() != 0 {
		t.Fatalf("a spend above earnings is a debt of 200: balance %d, spendable %d", debt.Balance(), debt.Spendable())
	}
}

func TestTaskGemsAreTheirOwnLedgerInTheBalance(t *testing.T) {
	won := Person{Earned: 100, Paid: 20, Tasks: 40}
	if won.Balance() != 120 {
		t.Fatalf("balance = %d, want 120", won.Balance())
	}
	lost := Person{Earned: 100, Tasks: -150}
	if lost.Balance() != -50 || lost.Spendable() != 0 {
		t.Fatalf("a missed stake above the balance is a debt: %d / %d", lost.Balance(), lost.Spendable())
	}
	paidDown := Person{Earned: 160, Tasks: -150}
	if paidDown.Balance() != 10 {
		t.Fatalf("later earnings pay the debt down first: %d", paidDown.Balance())
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

func TestOnePersonsDebtIsCoveredByTheOthersGemsInTheBank(t *testing.T) {
	people := []Person{{Earned: 100}, {Earned: 10, Tasks: -50}}
	if Bank(people) != 60 {
		t.Fatalf("bank = %d, want 100 - 40", Bank(people))
	}
	balances := Balances(people)
	if !slices.Equal(balances, []int{100, 0}) {
		t.Fatalf("spendable = %v", balances)
	}
	shares := SplitPrice(60, balances)
	if !slices.Equal(shares, []int{60, 0}) {
		t.Fatalf("the debtor pays nothing toward a reward: %v", shares)
	}
	after := []Person{{Earned: 100, Paid: 60}, {Earned: 10, Tasks: -50}}
	if Bank(after) != 0 {
		t.Fatalf("bank after = %d", Bank(after))
	}
	if Bank([]Person{{Earned: 10, Tasks: -50}, {Earned: 10}}) != 0 {
		t.Fatal("a bank in debt reads zero")
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
