package together

import (
	"slices"
	"strings"
	"testing"

	"github.com/nc1107/new-me/server/internal/db"
	"github.com/nc1107/new-me/server/internal/score"
)

func TestMeasuredShareIsTenPercentAboveTheAverageCappedAtTheBestWeek(t *testing.T) {
	cases := []struct {
		name string
		kind string
		r    Recent
		away int
		want int
	}{
		{"nights follow the average", KindSleepNights, Recent{Last: 5, Before: 4}, 0, 5},
		{"nights never pass the days at home", KindSleepNights, Recent{Last: 7, Before: 7}, 0, 7},
		{"away days shrink the cap", KindSleepNights, Recent{Last: 6, Before: 6}, 3, 4},
		{"no history still asks for one night", KindSleepNights, Recent{}, 0, 1},
		{"a week away still asks for one", KindMealDays, Recent{Last: 5, Before: 5}, 7, 1},
		{"reps round to five", KindPushupReps, Recent{Last: 100, Before: 40}, 0, 75},
		{"reps from one good week", KindPushupReps, Recent{Last: 100, Before: 0}, 0, 55},
		{"rounding up is held under 125 percent of the best week", KindPushupReps, Recent{Last: 7, Before: 7}, 0, 5},
		{"yoga minutes", KindYogaMinutes, Recent{Last: 60, Before: 60}, 0, 65},
		{"habit marks are not rounded", KindHabitMarks, Recent{Last: 30, Before: 20}, 0, 28},
		{"away days do not cap volume kinds", KindHabitMarks, Recent{Last: 30, Before: 20}, 5, 28},
		{"active days", KindActiveDays, Recent{Last: 4, Before: 3}, 0, 4},
		{"a lopsided pair of weeks", KindProteinDays, Recent{Last: 7, Before: 1}, 0, 4},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			got := MeasuredShare(tc.kind, tc.r, tc.away)
			if got != tc.want {
				t.Fatalf("MeasuredShare(%s, %+v, away %d) = %d, want %d", tc.kind, tc.r, tc.away, got, tc.want)
			}
			if limit := float64(tc.r.Best()) * bestWeekCap; float64(got) > limit && got > 5 {
				t.Fatalf("share %d is over 125%% of the best week (%d)", got, tc.r.Best())
			}
		})
	}
}

func TestShareUsesTheMeasuredSizingForNewKinds(t *testing.T) {
	in := Sizing{Recent: map[string]Recent{KindPushupReps: {Last: 100, Before: 40}}, AwayDays: 0}
	if got := Share(KindPushupReps, in); got != 75 {
		t.Fatalf("share = %d, want 75", got)
	}
	if got := Share(KindSleepNights, in); got != 1 {
		t.Fatalf("a kind with no history asks for the minimum, got %d", got)
	}
}

func TestEligibilityNeedsSevenDaysOfHistoryFromBothPeople(t *testing.T) {
	enough := Recent{Last: 4, Before: 3, HistoryDays: 7}
	short := Recent{Last: 4, Before: 1, HistoryDays: 6}
	cases := []struct {
		name string
		c    Candidate
		want bool
	}{
		{"both have seven days", Candidate{Kind: KindMealDays, People: []Recent{enough, enough}}, true},
		{"one has six", Candidate{Kind: KindMealDays, People: []Recent{enough, short}}, false},
		{"nobody to measure", Candidate{Kind: KindMealDays}, false},
		{"the older kinds always may", Candidate{Kind: KindSteps}, true},
		{"counted days always may", Candidate{Kind: KindCountedDays}, true},
		{"too few days at home for a day-count kind",
			Candidate{Kind: KindSleepNights, People: []Recent{enough, enough}, AwayDays: []int{0, 5}}, false},
		{"three days at home is enough",
			Candidate{Kind: KindSleepNights, People: []Recent{enough, enough}, AwayDays: []int{0, 4}}, true},
		{"away days do not matter to a volume kind",
			Candidate{Kind: KindPushupReps, People: []Recent{enough, enough}, AwayDays: []int{0, 6}}, true},
	}
	for _, tc := range cases {
		if got := tc.c.Eligible(); got != tc.want {
			t.Errorf("%s: eligible = %v, want %v", tc.name, got, tc.want)
		}
	}
}

func pair(kind string, attainment int) Candidate {
	r := Recent{Last: 4, Before: 4, HistoryDays: 10}
	return Candidate{Kind: kind, People: []Recent{r, r}, AwayDays: []int{0, 0}, Attainment: attainment}
}

func TestPickFavoursTheLowestAreaAndStoresTheReason(t *testing.T) {
	week := score.MustDate("2026-11-02")
	cands := []Candidate{
		{Kind: KindCountedDays, Attainment: 70},
		pair(KindSleepNights, 40),
		pair(KindProteinDays, 85),
		pair(KindMealDays, 95),
	}
	got := PickKind(week, nil, cands)
	if got.Kind != KindSleepNights {
		t.Fatalf("kind = %s, want sleep_nights", got.Kind)
	}
	if !strings.Contains(got.Reason, "Sleep") || !strings.Contains(got.Reason, "40%") {
		t.Fatalf("reason %q should name the area and its figure", got.Reason)
	}
}

func TestPickNeverRepeatsAKindOfTheLastTwoWeeks(t *testing.T) {
	week := score.MustDate("2026-11-02")
	cands := []Candidate{pair(KindSleepNights, 10), pair(KindMealDays, 50), pair(KindProteinDays, 60)}
	got := PickKind(week, []string{KindSleepNights, KindMealDays}, cands)
	if got.Kind != KindProteinDays {
		t.Fatalf("kind = %s, want protein_days", got.Kind)
	}
}

func TestPickIgnoresIneligibleKinds(t *testing.T) {
	week := score.MustDate("2026-11-02")
	thin := pair(KindSleepNights, 0)
	thin.People[1].HistoryDays = 3
	got := PickKind(week, nil, []Candidate{thin, {Kind: KindSteps, Attainment: -1}})
	if got.Kind != KindSteps {
		t.Fatalf("kind = %s, want steps", got.Kind)
	}
}

func TestPickFallsBackWhenEveryEligibleKindWasUsedRecently(t *testing.T) {
	week := score.MustDate("2026-11-02")
	got := PickKind(week, []string{KindSteps, KindCountedDays}, []Candidate{
		{Kind: KindSteps, Attainment: -1}, {Kind: KindCountedDays, Attainment: 60}})
	if got.Kind != KindCountedDays {
		t.Fatalf("kind = %s, want the lower area when the repeat rule cannot be kept", got.Kind)
	}
}

func TestPickWithNothingEligibleCountsDays(t *testing.T) {
	got := PickKind(score.MustDate("2026-11-02"), nil, nil)
	if got.Kind != KindCountedDays || got.Reason == "" {
		t.Fatalf("pick = %+v", got)
	}
}

func TestPickBreaksTiesWithAHashOfTheWeek(t *testing.T) {
	cands := []Candidate{pair(KindSleepNights, 50), pair(KindMealDays, 50), pair(KindProteinDays, 50), pair(KindActiveDays, 50)}
	week := score.MustDate("2026-11-02")
	first := PickKind(week, nil, cands)
	for range 5 {
		if again := PickKind(week, nil, cands); again != first {
			t.Fatalf("the same week picked %+v then %+v", first, again)
		}
	}
	seen := map[string]bool{}
	for d := week; len(seen) < 3 && d.Before(week.AddDays(7*60)); d = d.AddDays(7) {
		got := PickKind(d, nil, cands)
		seen[got.Kind] = true
		if !strings.Contains(got.Reason, "among your lowest") {
			t.Fatalf("a tie should say so: %q", got.Reason)
		}
	}
	if len(seen) < 3 {
		t.Fatalf("sixty weeks of ties only picked %v", seen)
	}
}

func TestPickTreatsAttainmentWithinOnePointAsATie(t *testing.T) {
	week := score.MustDate("2026-11-02")
	cands := []Candidate{pair(KindSleepNights, 50), pair(KindMealDays, 51), pair(KindProteinDays, 53)}
	seen := map[string]bool{}
	for d := week; d.Before(week.AddDays(7 * 60)); d = d.AddDays(7) {
		seen[PickKind(d, nil, cands).Kind] = true
	}
	if !seen[KindSleepNights] || !seen[KindMealDays] || seen[KindProteinDays] {
		t.Fatalf("picked %v, want only the two within a point of the lowest", seen)
	}
}

func TestKindsWithoutATargetComeLast(t *testing.T) {
	week := score.MustDate("2026-11-02")
	got := PickKind(week, nil, []Candidate{{Kind: KindSteps, Attainment: -1}, pair(KindProteinDays, 99)})
	if got.Kind != KindProteinDays {
		t.Fatalf("kind = %s, want the kind that has a measured gap", got.Kind)
	}
	only := PickKind(week, nil, []Candidate{{Kind: KindSteps, Attainment: -1}})
	if only.Kind != KindSteps || only.Reason == "" {
		t.Fatalf("pick = %+v", only)
	}
}

func TestAwayDaysInCountsEachDayOnce(t *testing.T) {
	spans := []db.AwaySpan{
		{From: score.MustDate("2026-11-03"), To: score.MustDate("2026-11-05")},
		{From: score.MustDate("2026-11-05"), To: score.MustDate("2026-11-06")},
		{From: score.MustDate("2026-11-20"), To: score.MustDate("2026-11-22")},
	}
	if got := AwayDaysIn(spans, score.MustDate("2026-11-02"), score.MustDate("2026-11-08")); got != 4 {
		t.Fatalf("away days = %d, want 4", got)
	}
	if got := AwayDaysIn(nil, score.MustDate("2026-11-02"), score.MustDate("2026-11-08")); got != 0 {
		t.Fatalf("away days = %d, want 0", got)
	}
}

func TestEveryKindHasATitleAndAPhrase(t *testing.T) {
	for _, kind := range AllKinds() {
		if title := Title(kind, 12); kind != KindCountedDays && !strings.Contains(title, "12") || strings.Contains(title, "Reach") {
			t.Errorf("%s: title %q", kind, title)
		}
		if p := Phrase(kind, 12); !strings.HasPrefix(p, "12") {
			t.Errorf("%s: phrase %q", kind, p)
		}
		if a := areaOf(kind); a == "" {
			t.Errorf("%s: no area", kind)
		}
	}
	if got := Phrase(KindSleepNights, 1); got != "1 night" {
		t.Errorf("phrase = %q", got)
	}
	if got := Phrase(KindSteps, 12000); got != "12,000 steps" {
		t.Errorf("phrase = %q", got)
	}
}

func TestAllKindsAreUniqueAndMatchTheDatabaseConstraint(t *testing.T) {
	kinds := AllKinds()
	if len(kinds) != 11 {
		t.Fatalf("kinds = %v", kinds)
	}
	seen := map[string]bool{}
	for _, k := range kinds {
		if seen[k] {
			t.Errorf("duplicate kind %s", k)
		}
		seen[k] = true
	}
	for _, k := range []string{db.ChallengeSleepNights, db.ChallengeMealDays, db.ChallengeProteinDays,
		db.ChallengePushupReps, db.ChallengeYogaMinutes, db.ChallengeHabitMarks, db.ChallengeActiveDays} {
		if !slices.Contains(kinds, k) {
			t.Errorf("db kind %s is not a together kind", k)
		}
	}
}

func TestPickReasonsStayShort(t *testing.T) {
	for _, kind := range AllKinds() {
		for _, tie := range []bool{false, true} {
			for _, attainment := range []int{-1, 0, 100} {
				r := reasonFor(Candidate{Kind: kind, Attainment: attainment}, tie)
				if len(r) > 200 {
					t.Errorf("%s: reason %q is %d characters", kind, r, len(r))
				}
			}
		}
	}
}
