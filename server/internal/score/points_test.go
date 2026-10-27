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
