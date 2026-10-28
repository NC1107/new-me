package score

import "testing"

func TestHabitGemsAreThreeAMinuteCappedAtAHundred(t *testing.T) {
	for minutes, want := range map[int]int{-1: 0, 0: 0, 1: 3, 2: 6, 10: 30, 30: 90, 33: 99, 34: 100, 60: 100} {
		if got := HabitGems(minutes); got != want {
			t.Errorf("HabitGems(%d) = %d, want %d", minutes, got, want)
		}
	}
}
