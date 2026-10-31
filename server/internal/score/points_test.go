package score

import (
	"reflect"
	"testing"
)

func TestQuestPoints(t *testing.T) {
	tests := []struct {
		name                   string
		points, actual, target int
		want                   int
	}{
		{"zero progress", 100, 0, 8000, 0},
		{"half", 100, 4000, 8000, 50},
		{"rounds half up", 50, 1, 4, 13},
		{"rounds down below half", 100, 1, 300, 0},
		{"just over half rounds up", 100, 1, 200, 1},
		{"complete", 100, 8000, 8000, 100},
		{"capped at target", 100, 20000, 8000, 100},
		{"negative actual", 100, -5, 10, 0},
		{"zero target is safe", 100, 5, 0, 0},
		{"reading mix past one", 100, 10*15 + 8*20, 20 * 15, 100},
	}
	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			if got := QuestPoints(tc.points, tc.actual, tc.target); got != tc.want {
				t.Fatalf("QuestPoints(%d, %d, %d) = %d, want %d", tc.points, tc.actual, tc.target, got, tc.want)
			}
		})
	}
}

func TestBonus(t *testing.T) {
	for points, want := range map[int]int{100: 20, 50: 10, 5: 1, 0: 0} {
		if got := Bonus(points); got != want {
			t.Fatalf("Bonus(%d) = %d, want %d", points, got, want)
		}
	}
}

func TestReadingProgressBasis(t *testing.T) {
	tests := []struct {
		name                   string
		minutes, pages         int
		wantActual, wantTarget int
		wantPoints             int
	}{
		{"nothing", 0, 0, 0, 300, 0},
		{"minutes only complete", 20, 0, 300, 300, 100},
		{"pages only complete", 0, 15, 300, 300, 100},
		{"mixed partial", 10, 5, 10*15 + 5*20, 300, 83},
		{"mixed exactly one", 10, 7, 10*15 + 7*20, 300, 97},
		{"mixed over one is capped", 15, 15, 15*15 + 15*20, 300, 100},
	}
	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			actual, target := ReadingProgressBasis(tc.minutes, tc.pages, 20, 15)
			if actual != tc.wantActual || target != tc.wantTarget {
				t.Fatalf("basis = %d/%d, want %d/%d", actual, target, tc.wantActual, tc.wantTarget)
			}
			if got := QuestPoints(100, actual, target); got != tc.wantPoints {
				t.Fatalf("points = %d, want %d", got, tc.wantPoints)
			}
		})
	}
}

func TestScoreDay(t *testing.T) {
	steps := QuestResult{Key: "steps", Points: 100, Actual: 8000, Target: 8000}
	pushups := QuestResult{Key: "pushups", Points: 100, Actual: 15, Target: 30}
	meals := QuestResult{Key: "meals_logged", Points: 50, Actual: 2, Target: 2}

	tests := []struct {
		name   string
		quests []QuestResult
		want   DayScore
	}{
		{"no quests is not counted", nil, DayScore{}},
		{
			"exactly seventy percent counts",
			[]QuestResult{{Key: "a", Points: 100, Actual: 70, Target: 100}},
			DayScore{BasePoints: 70, MaxBase: 100, Percent: 70, Counted: true},
		},
		{
			"just under seventy percent does not",
			[]QuestResult{{Key: "a", Points: 100, Actual: 69, Target: 100}},
			DayScore{BasePoints: 69, MaxBase: 100, Percent: 69},
		},
		{
			"bonus never helps the percent",
			[]QuestResult{steps, {Key: "x", Points: 100, Actual: 0, Target: 10}, {Key: "y", Points: 100, Actual: 0, Target: 10}},
			DayScore{BasePoints: 100, BonusPoints: 20, MaxBase: 300, Percent: 33},
		},
		{
			"everything done",
			[]QuestResult{steps, {Key: "pushups", Points: 100, Actual: 30, Target: 30}, meals},
			DayScore{BasePoints: 250, BonusPoints: 50, MaxBase: 250, Percent: 100, Counted: true},
		},
		{
			"partial quest earns no bonus",
			[]QuestResult{pushups},
			DayScore{BasePoints: 50, MaxBase: 100, Percent: 50},
		},
	}
	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			got := ScoreDay(tc.quests)
			got.Quests = nil
			tc.want.Quests = nil
			if !reflect.DeepEqual(got, tc.want) {
				t.Fatalf("got %+v, want %+v", got, tc.want)
			}
		})
	}
}

func TestScoreDayReportsPerQuestCredit(t *testing.T) {
	got := ScoreDay([]QuestResult{
		{Key: "steps", Points: 100, Actual: 8000, Target: 8000},
		{Key: "pushups", Points: 100, Actual: 15, Target: 30},
	})
	if len(got.Quests) != 2 {
		t.Fatalf("quests = %d, want 2", len(got.Quests))
	}
	if q := got.Quests[0]; q.Base != 100 || q.Bonus != 20 || !q.Complete {
		t.Fatalf("steps = %+v", q)
	}
	if q := got.Quests[1]; q.Base != 50 || q.Bonus != 0 || q.Complete {
		t.Fatalf("pushups = %+v", q)
	}
}

func TestReadingMinutesAddsListeningCreditToManualMinutes(t *testing.T) {
	for _, c := range []struct{ manual, listening, want int }{
		{0, 0, 0}, {10, 0, 10}, {0, 25, 16}, {10, 25, 26}, {10, -5, 10}, {0, 238, 155}, {0, 1, 0},
	} {
		if got := ReadingMinutes(c.manual, c.listening); got != c.want {
			t.Fatalf("ReadingMinutes(%d, %d) = %d, want %d", c.manual, c.listening, got, c.want)
		}
	}
}

func TestListeningCreditIsTheWordsHeardOverTheWordsReadInAMinute(t *testing.T) {
	// 60 minutes of narration is 9,300 words, which a silent reader gets through in 39 minutes.
	if got := ListeningCredit(60); got != 39 {
		t.Fatalf("ListeningCredit(60) = %d, want 39", got)
	}
	for m := 0; m <= 1440; m++ {
		if credit := ListeningCredit(m); credit > m {
			t.Fatalf("ListeningCredit(%d) = %d, more than the time listened", m, credit)
		}
	}
}

func TestPagesForMinutesIsMinutesTimesWordsPerMinuteOverWordsPerPage(t *testing.T) {
	for _, c := range []struct{ minutes, want int }{
		{1, 1}, {5, 5}, {10, 10}, {20, 19}, {30, 29}, {45, 43}, {60, 57}, {120, 114}, {1440, 1371},
	} {
		if got := PagesForMinutes(c.minutes); got != c.want {
			t.Fatalf("PagesForMinutes(%d) = %d, want %d", c.minutes, got, c.want)
		}
	}
}

func TestPagesForMinutesNeverDecreasesAndStaysInsideTheStoredRange(t *testing.T) {
	prev := 0
	for m := 1; m <= 1440; m++ {
		got := PagesForMinutes(m)
		if got < prev || got < 1 || got > 2000 {
			t.Fatalf("PagesForMinutes(%d) = %d after %d", m, got, prev)
		}
		prev = got
	}
}

func TestListeningFillsTheReadingQuestWithoutTouchingPages(t *testing.T) {
	// 10 manual + 15 listened minutes (worth 9) of a 20 minute target, plus 3 of 19 pages.
	actual, target := ReadingProgressBasis(ReadingMinutes(10, 15), 3, 20, 19)
	if want := 19*19 + 3*20; actual != want || target != 20*19 {
		t.Fatalf("basis = %d/%d, want %d/380", actual, target, want)
	}
	// Listening for the whole target and a third more completes the quest.
	actual, target = ReadingProgressBasis(ReadingMinutes(0, 31), 0, 20, 19)
	if actual < target {
		t.Fatalf("31 listened minutes = %d/%d, want complete", actual, target)
	}
}

func TestGoalPercentIsFullExactlyWhenTheDayCounts(t *testing.T) {
	for maxBase := 1; maxBase <= 400; maxBase++ {
		for base := 0; base <= maxBase; base++ {
			counted := base*100 >= CountedPercent*maxBase
			if got := GoalPercent(base, maxBase) >= 100; got != counted {
				t.Fatalf("base %d of %d: goalPercent>=100 is %v, counted is %v", base, maxBase, got, counted)
			}
		}
	}
}

func TestGoalPoints(t *testing.T) {
	cases := map[int]int{0: 0, 1: 1, 10: 7, 11: 8, 100: 70, 143: 101}
	for maxBase, want := range cases {
		if got := GoalPoints(maxBase); got != want {
			t.Errorf("GoalPoints(%d) = %d, want %d", maxBase, got, want)
		}
	}
	if got := GoalPercent(100, 100); got != 142 {
		t.Errorf("full day goalPercent = %d, want 142", got)
	}
	if got := GoalPercent(5, 0); got != 0 {
		t.Errorf("empty day goalPercent = %d, want 0", got)
	}
}
