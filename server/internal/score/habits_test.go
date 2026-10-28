package score

import (
	"slices"
	"testing"
)

func TestHabitScore(t *testing.T) {
	tests := []struct {
		name             string
		days             []HabitDay
		earned, possible int
	}{
		{"nothing due", nil, 0, 0},
		{"one of two slots earns half", []HabitDay{{Check: true, Slots: 2, SlotsDone: 1, Points: 25}}, 12, 25},
		{"both slots", []HabitDay{{Check: true, Slots: 2, SlotsDone: 2, Points: 25}}, 25, 25},
		{"done slots cannot exceed the slots", []HabitDay{{Check: true, Slots: 1, SlotsDone: 3, Points: 10}}, 10, 10},
		{"count below target earns its share", []HabitDay{{Target: 8, Count: 4, Points: 50}}, 25, 50},
		{"count past target caps at the whole", []HabitDay{{Target: 8, Count: 20, Points: 50}}, 50, 50},
		{"just track adds nothing either way", []HabitDay{{Check: true, Slots: 1, SlotsDone: 1, Points: 0}}, 0, 0},
		{"mixed", []HabitDay{{Check: true, Slots: 2, SlotsDone: 2, Points: 10}, {Check: true, Slots: 1, Points: 25},
			{Target: 8, Count: 8, Points: 50}}, 60, 85},
	}
	for _, tc := range tests {
		if earned, possible := HabitScore(tc.days); earned != tc.earned || possible != tc.possible {
			t.Errorf("%s: HabitScore = %d of %d, want %d of %d", tc.name, earned, possible, tc.earned, tc.possible)
		}
	}
}

func TestHabitsCountTowardTheDay(t *testing.T) {
	quests := []QuestResult{{Key: "pushups", Points: 100, Actual: 60, Target: 100}}
	day := ScoreDay(quests)
	if day.Counted {
		t.Fatal("60 of 100 alone does not count")
	}
	with := day.WithHabits(HabitScore([]HabitDay{{Check: true, Slots: 1, SlotsDone: 1, Points: 50}}))
	if with.BasePoints != 110 || with.MaxBase != 150 || with.Percent != 73 || !with.Counted {
		t.Fatalf("with a done habit = %+v", with)
	}
	missed := day.WithHabits(HabitScore([]HabitDay{{Check: true, Slots: 1, Points: 50}}))
	if missed.Percent != 40 || missed.Counted {
		t.Fatalf("a missed habit lowers the day: %+v", missed)
	}
	if same := day.WithHabits(0, 0); same.Percent != day.Percent || same.MaxBase != day.MaxBase {
		t.Fatal("no habits leaves the day alone")
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
