package score

import (
	"slices"
	"testing"
)

func TestHabitBonusPaysPerCompletedSlotAndPerReachedTarget(t *testing.T) {
	tests := []struct {
		name string
		days []HabitDay
		want int
	}{
		{"nothing", nil, 0},
		{"one of two slots", []HabitDay{{Check: true, Slots: 2, SlotsDone: 1}}, 5},
		{"both slots", []HabitDay{{Check: true, Slots: 2, SlotsDone: 2}}, 10},
		{"done slots cannot exceed the slots", []HabitDay{{Check: true, Slots: 1, SlotsDone: 3}}, 5},
		{"count below target", []HabitDay{{Target: 8, Count: 7}}, 0},
		{"count at target", []HabitDay{{Target: 8, Count: 8}}, 5},
		{"count past target still pays once", []HabitDay{{Target: 8, Count: 20}}, 5},
		{"a zero target never pays", []HabitDay{{Target: 0, Count: 3}}, 0},
		{"mixed", []HabitDay{
			{Check: true, Slots: 2, SlotsDone: 2}, {Check: true, Slots: 1}, {Target: 8, Count: 8}}, 15},
	}
	for _, tc := range tests {
		if got := HabitBonus(tc.days); got != tc.want {
			t.Errorf("%s: HabitBonus = %d, want %d", tc.name, got, tc.want)
		}
	}
}

func TestHabitBonusNeverMovesBaseOrWhetherADayCounts(t *testing.T) {
	quests := []QuestResult{{Key: "pushups", Points: 100, Actual: 10, Target: 100}}
	day := ScoreDay(quests)
	boosted := day.WithBonus(HabitBonus([]HabitDay{{Check: true, Slots: 8, SlotsDone: 8}}))
	if boosted.BonusPoints != day.BonusPoints+40 {
		t.Fatalf("bonus = %d, want %d", boosted.BonusPoints, day.BonusPoints+40)
	}
	if boosted.BasePoints != day.BasePoints || boosted.MaxBase != day.MaxBase ||
		boosted.Percent != day.Percent || boosted.Counted != day.Counted {
		t.Fatalf("habit bonus changed base, max, percent or counted: %+v vs %+v", boosted, day)
	}
}

func TestHabitDueFollowsTheWeekdayMask(t *testing.T) {
	weekdays, ok := WeekdaysFromISO([]int{1, 2, 3, 4, 5})
	if !ok {
		t.Fatal("weekdays rejected")
	}
	// 2026-11-02 is a Monday.
	for i, want := range []bool{true, true, true, true, true, false, false} {
		if got := HabitDue(weekdays, MustDate("2026-11-02").AddDays(i)); got != want {
			t.Errorf("day %d due = %v, want %v", i, got, want)
		}
	}
	if !HabitDue(AllWeekdays, MustDate("2026-11-08")) {
		t.Error("every-day mask should include Sunday")
	}
}

func TestWeekdaysRoundTripAndRejection(t *testing.T) {
	mask, ok := WeekdaysFromISO([]int{7, 1, 1, 3})
	if !ok || !slices.Equal(ISOWeekdays(mask), []int{1, 3, 7}) {
		t.Fatalf("mask %b ok=%v days=%v", mask, ok, ISOWeekdays(mask))
	}
	for _, bad := range [][]int{nil, {}, {0}, {8}, {1, -1}} {
		if _, ok := WeekdaysFromISO(bad); ok {
			t.Errorf("WeekdaysFromISO(%v) accepted", bad)
		}
	}
}
