package yogaplan

import (
	"slices"
	"testing"

	"github.com/nc1107/new-me/server/internal/score"
)

func TestPlaceSpreadsEvenlyWithoutAvoidance(t *testing.T) {
	cases := map[int][]int{1: {1}, 2: {1, 4}, 3: {1, 3, 5}, 7: {1, 2, 3, 4, 5, 6, 7}}
	for n, want := range cases {
		if got := Place(n, nil); !slices.Equal(got, want) {
			t.Errorf("Place(%d) = %v, want %v", n, got, want)
		}
	}
}

func TestPlaceAvoidsLowerBodyDays(t *testing.T) {
	avoid := map[int]bool{1: true, 4: true}
	for n := 1; n <= 5; n++ {
		got := Place(n, avoid)
		if len(got) != n {
			t.Fatalf("Place(%d) = %v", n, got)
		}
		for _, d := range got {
			if avoid[d] {
				t.Errorf("Place(%d) = %v uses avoided day %d", n, got, d)
			}
		}
	}
	if got := Place(3, avoid); minGap(got) < 2 {
		t.Errorf("Place(3) = %v is not spread out", got)
	}
}

func TestPlaceTakesFewestConflictsWhenDaysRunOut(t *testing.T) {
	avoid := map[int]bool{1: true, 2: true, 3: true, 4: true, 5: true}
	got := Place(3, avoid)
	conflicts := 0
	for _, d := range got {
		if avoid[d] {
			conflicts++
		}
	}
	if conflicts != 1 || !slices.Contains(got, 6) || !slices.Contains(got, 7) {
		t.Errorf("Place(3) = %v, want days 6 and 7 plus one conflict", got)
	}
}

func TestLowerBodyDaysNeedTwoLegExercises(t *testing.T) {
	primary := map[string][]string{"squat": {"quads"}, "rdl": {"hamstrings"}, "press": {"chest"}, "row": {"back"}, "calf": {"calves"}}
	days := []Day{
		{Weekday: 1, Exercises: []string{"squat", "rdl", "press"}},
		{Weekday: 3, Exercises: []string{"press", "row", "squat"}},
		{Weekday: 5, Exercises: []string{"calf", "press"}},
	}
	got := LowerBodyDays(days, primary)
	if !got[1] || len(got) != 1 {
		t.Errorf("LowerBodyDays = %v, want only Monday", got)
	}
}

func TestNextFlow(t *testing.T) {
	for in, want := range map[int]int{10: 20, 20: 30, 30: 0, 15: 0} {
		if got := NextFlow(in); got != want {
			t.Errorf("NextFlow(%d) = %d, want %d", in, got, want)
		}
	}
}

func days(ds ...string) map[score.Date]bool {
	out := map[score.Date]bool{}
	for _, d := range ds {
		out[score.MustDate(d)] = true
	}
	return out
}

func TestOfferLongerNeedsTwoFullWeeksAtThisLevel(t *testing.T) {
	today := score.MustDate("2026-10-28") // Wednesday; this week starts 2026-10-26
	done := days("2026-10-12", "2026-10-14", "2026-10-16", "2026-10-19", "2026-10-21", "2026-10-23")
	if !OfferLonger(today, score.MustDate("2026-10-12"), 3, 10, done) {
		t.Error("two finished weeks since the level began should offer")
	}
	if OfferLonger(today, score.MustDate("2026-10-13"), 3, 10, done) {
		t.Error("a week that began before the level started must not count")
	}
	if OfferLonger(today, score.MustDate("2026-10-12"), 4, 10, done) {
		t.Error("three days is not finishing a four day plan")
	}
	if OfferLonger(today, score.MustDate("2026-10-12"), 3, 30, done) {
		t.Error("nothing is longer than 30 minutes")
	}
	short := days("2026-10-14", "2026-10-16", "2026-10-19", "2026-10-21", "2026-10-23")
	if OfferLonger(today, score.MustDate("2026-10-12"), 3, 10, short) {
		t.Error("one short week must not offer")
	}
}

func TestCountStopsAtUpTo(t *testing.T) {
	week := score.MustDate("2026-10-26")
	if got := Count(week, days("2026-10-26", "2026-10-29"), score.MustDate("2026-10-28")); got != 1 {
		t.Errorf("Count = %d, want 1", got)
	}
}
