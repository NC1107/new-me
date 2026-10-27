package goals

import (
	"testing"

	"github.com/nc1107/new-me/server/internal/insights"
)

func TestSteps(t *testing.T) {
	cases := []struct {
		name     string
		goal     int
		sug      *insights.Suggestion
		wantNil  bool
		proposed int
	}{
		{"no suggestion yet", 8000, nil, true, 0},
		{"no goal", 0, &insights.Suggestion{Target: 8000}, true, 0},
		{"same", 8000, &insights.Suggestion{Target: 8000, Median14: 7500}, true, 0},
		{"a small difference is not worth a card", 8000, &insights.Suggestion{Target: 8500 - 1}, true, 0},
		{"raise", 6000, &insights.Suggestion{Target: 8000, Median14: 7200}, false, 8000},
		{"lower", 10000, &insights.Suggestion{Target: 5500, Median14: 4800}, false, 5500},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			got := Steps(tc.goal, tc.sug, 14)
			if (got == nil) != tc.wantNil {
				t.Fatalf("got %+v", got)
			}
			if got != nil && (got.Proposed != tc.proposed || got.Current != tc.goal || got.Key != "steps" || got.Reason == "") {
				t.Fatalf("got %+v", got)
			}
		})
	}
	if got := Steps(6000, &insights.Suggestion{Target: 8000, Median14: 7200}, 14); got.Reason !=
		"You usually walk about 7,200 steps a day. 8,000 is a reachable step up." {
		t.Fatalf("reason = %q", got.Reason)
	}
}

func nights(n, minutes int) []int {
	out := make([]int, n)
	for i := range out {
		out[i] = minutes
	}
	return out
}

func TestSleep(t *testing.T) {
	cases := []struct {
		name     string
		target   int
		asleep   []int
		wantNil  bool
		proposed int
	}{
		{"too few nights", 480, nights(4, 360), true, 0},
		{"gap of 44 is realistic enough", 480, nights(10, 436), true, 0},
		{"gap of 45 triggers", 480, nights(10, 435), false, 465},
		{"halfway rounds to 15", 480, nights(14, 365), false, 420},
		{"never below the floor", 420, nights(14, 100), false, 300},
		{"meeting the target needs nothing", 420, nights(14, 450), true, 0},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			got := Sleep(tc.target, tc.asleep)
			if (got == nil) != tc.wantNil {
				t.Fatalf("got %+v", got)
			}
			if got != nil && (got.Proposed != tc.proposed || got.Current != tc.target) {
				t.Fatalf("got %+v", got)
			}
		})
	}
	got := Sleep(480, nights(14, 365))
	want := "You averaged 6 h 05 over the last 14 nights, 1 h 55 under your 8 h target. 7 h is a step toward it."
	if got.Reason != want {
		t.Fatalf("reason = %q", got.Reason)
	}
}

func TestStepsRaiseNeedsTenGoodDaysButLoweringDoesNot(t *testing.T) {
	up := &insights.Suggestion{Target: 8000, Median14: 7200}
	for met, want := range map[int]bool{0: false, 9: false, 10: true, 14: true} {
		if got := Steps(6000, up, met) != nil; got != want {
			t.Errorf("raise with %d good days: %v, want %v", met, got, want)
		}
	}
	down := &insights.Suggestion{Target: 5500, Median14: 4800}
	if Steps(10000, down, 0) == nil {
		t.Error("lowering is always allowed")
	}
}

func TestFormulaMovedNeedsMoreThanFivePercentOrOneHundredKcal(t *testing.T) {
	tests := []struct {
		key           string
		baseline, now float64
		want          bool
	}{
		{"calories", 2750, 2850, false}, {"calories", 2750, 2851, true}, {"calories", 2750, 2649, true}, {"calories", 2750, 2650, false},
		{"protein", 130, 136, false}, {"protein", 130, 137, true}, {"protein", 130, 123, true}, {"protein", 130, 124, false},
		{"protein", 0, 100, false},
	}
	for _, tt := range tests {
		if got := FormulaMoved(tt.key, tt.baseline, tt.now); got != tt.want {
			t.Errorf("FormulaMoved(%s, %v, %v) = %v, want %v", tt.key, tt.baseline, tt.now, got, tt.want)
		}
	}
}

func TestProteinProposalFollowsTheFormulaValue(t *testing.T) {
	if p := Protein(120, 80, 160, 2.0); p == nil || p.Proposed != 160 || p.Current != 120 {
		t.Errorf("a 25%% gap proposes the formula value: %+v", p)
	}
	if p := Protein(130, 80, 160, 2.0); p != nil {
		t.Errorf("an 18.75%% gap is within the rule: %+v", p)
	}
}
