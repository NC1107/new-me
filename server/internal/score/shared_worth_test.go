package score

import "testing"

func TestSharedCreditSplitsTheWorthAndGivesTheOddGemToTheMarker(t *testing.T) {
	tests := []struct {
		by           string
		worth        int
		mine, theirs int
	}{
		{SharedBySelf, 25, 25, 0},
		{SharedByPartner, 25, 0, 25},
		{SharedByTogether, 40, 20, 20},
		{SharedByTogether, 25, 13, 12},
		{SharedByTogether, 1, 1, 0},
		{SharedByTogether, 99, 50, 49},
	}
	for _, tc := range tests {
		mine, theirs, ok := SharedCredit(tc.by, tc.worth)
		if !ok || mine != tc.mine || theirs != tc.theirs || mine+theirs != tc.worth {
			t.Errorf("%s %d: got %d + %d (ok %v), want %d + %d", tc.by, tc.worth, mine, theirs, ok, tc.mine, tc.theirs)
		}
	}
	if _, _, ok := SharedCredit("everyone", 25); ok {
		t.Error("an unknown way of doing it pays nobody")
	}
}

func TestValidSharedWorth(t *testing.T) {
	for _, w := range []int{SharedMinWorth, 25, SharedMaxWorth} {
		if !ValidSharedWorth(w) {
			t.Errorf("%d should be valid", w)
		}
	}
	for _, w := range []int{-5, 0, SharedMaxWorth + 1} {
		if ValidSharedWorth(w) {
			t.Errorf("%d should be invalid", w)
		}
	}
}

// Mask 64 is Sunday and 32 is Saturday, so a chore picked for Sunday on a Saturday is not due
// until the next day. The app's two "S" chips once made that an easy mix-up.
func TestSharedWeekdayMaskFollowsMondayFirstBits(t *testing.T) {
	saturday := MustDate("2026-10-31")
	sunday, _ := WeekdaysFromISO([]int{7})
	satMask, _ := WeekdaysFromISO([]int{6})
	if sunday != 64 || satMask != 32 {
		t.Fatalf("masks = %d, %d", sunday, satMask)
	}
	got := SharedDue(SharedSchedule{Kind: SharedWeekdays, Weekdays: sunday}, saturday, nil, saturday)
	if got.State != SharedUpcoming || got.DueOn != MustDate("2026-11-01") {
		t.Errorf("Sunday chore on Saturday = %+v", got)
	}
	got = SharedDue(SharedSchedule{Kind: SharedWeekdays, Weekdays: satMask}, saturday, nil, saturday)
	if got.State != SharedDueToday {
		t.Errorf("Saturday chore on Saturday = %+v", got)
	}
}
