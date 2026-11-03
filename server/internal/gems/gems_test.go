package gems

import (
	"slices"
	"testing"
)

func TestBalanceNeverGoesBelowZero(t *testing.T) {
	if got := (Person{Earned: 900, Paid: 300}).Balance(); got != 600 {
		t.Fatalf("balance = %d", got)
	}
	if got := (Person{Earned: 100, Paid: 300}).Balance(); got != 0 {
		t.Fatalf("a spend above earnings reads zero, not a debt: %d", got)
	}
}

func TestTaskGemsAreTheirOwnLedgerInTheBalance(t *testing.T) {
	if got := (Person{Earned: 100, Paid: 20, Tasks: 40}).Balance(); got != 120 {
		t.Fatalf("balance = %d, want 120", got)
	}
	if got := (Person{Earned: 100, Tasks: -60}).Balance(); got != 40 {
		t.Fatalf("balance = %d, want 40", got)
	}
}

func TestATaskLossIsOptInAndNeverMoreThanIsHeld(t *testing.T) {
	for _, c := range []struct {
		lose           bool
		stake, balance int
		want           int
	}{
		{false, 50, 500, 0},
		{true, 50, 500, 50},
		{true, 50, 30, 30},
		{true, 50, 0, 0},
		{true, 50, -20, 0},
	} {
		if got := TaskLoss(c.lose, c.stake, c.balance); got != c.want {
			t.Errorf("TaskLoss(%v, %d, %d) = %d, want %d", c.lose, c.stake, c.balance, got, c.want)
		}
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

func TestAPersonWithNothingLeftPaysNothingTowardASharedReward(t *testing.T) {
	people := []Person{{Earned: 100}, {Earned: 10, Paid: 50}}
	if Bank(people) != 100 {
		t.Fatalf("bank = %d, want 100", Bank(people))
	}
	balances := Balances(people)
	if !slices.Equal(balances, []int{100, 0}) {
		t.Fatalf("balances = %v", balances)
	}
	if shares := SplitPrice(60, balances); !slices.Equal(shares, []int{60, 0}) {
		t.Fatalf("shares = %v", shares)
	}
}
