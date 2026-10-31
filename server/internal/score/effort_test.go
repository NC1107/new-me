package score

import "testing"

func TestEffortPoints(t *testing.T) {
	for _, tc := range []struct {
		name     string
		key      string
		target   int
		exercise string
		want     int
		basis    EffortBasis
	}{
		{"steps capped", "steps", 7000, "", 150, BasisWalk},
		{"steps default capped", "steps", 8000, "", 150, BasisWalk},
		{"short steps goal", "steps", 3000, "", 85, BasisWalk},
		{"exercise half hour", "exercise", 30, "", 85, BasisModerate},
		{"exercise ten minutes", "exercise", 10, "", 30, BasisModerate},
		{"thirty push-ups floor", "pushups", 30, "push_up", 20, BasisReps},
		{"hundred push-ups", "pushups", 100, "push_up", 45, BasisReps},
		{"hundred crunches are lighter", "pushups", 100, "crunch", 30, BasisReps},
		{"reading half hour", "reading", 30, "", 30, BasisFocus},
		{"reading twenty floors", "reading", 20, "", 20, BasisFocus},
		{"yoga twenty minutes", "yoga", 20, "", 25, BasisYoga},
		{"breathing floors", "breathing", 5, "", 20, BasisFocus},
		{"water", "water", 3000, "", 20, BasisNone},
		{"meals", "meals_logged", 3, "", 20, BasisNone},
		{"protein", "protein", 150, "", 20, BasisNone},
		{"sleep", "sleep", 450, "", 20, BasisNone},
		{"produce", "produce", 5, "", 20, BasisNone},
		{"regularity", "sleep_regularity", 45, "", 20, BasisNone},
	} {
		t.Run(tc.name, func(t *testing.T) {
			got := EffortPoints(tc.key, tc.target, tc.exercise)
			if got.Points != tc.want || got.Basis != tc.basis {
				t.Fatalf("EffortPoints(%s, %d) = %d %s, want %d %s", tc.key, tc.target, got.Points, got.Basis, tc.want, tc.basis)
			}
		})
	}
}

func TestEffortPointsStayInRangeRoundedAndGrowWithTheTarget(t *testing.T) {
	for _, key := range []string{"steps", "exercise", "pushups", "yoga", "reading", "breathing"} {
		prev := 0
		for target := 1; target <= 30000; target += 7 {
			p := EffortPoints(key, target, "push_up").Points
			if p < PointsFloor || p > PointsCap || p%PointsStep != 0 {
				t.Fatalf("%s %d: %d out of range or not rounded", key, target, p)
			}
			if p < prev {
				t.Fatalf("%s %d: %d fell below %d", key, target, p, prev)
			}
			prev = p
		}
	}
}

func TestEffortReason(t *testing.T) {
	for _, tc := range []struct {
		key    string
		target int
		want   string
	}{
		{"exercise", 30, "Worth 85: about 30 min of moderate effort."},
		{"steps", 7000, "Worth 150, the game's maximum: about 70 min of walking at a moderate pace."},
		{"pushups", 30, "Worth 20, the game's minimum: about 5 min of effort, counting 10 seconds a rep with rests."},
		{"water", 2200, "Worth 20, the game's minimum: no measured effort."},
	} {
		if got := EffortPoints(tc.key, tc.target, "push_up").Reason(); got != tc.want {
			t.Errorf("%s reason = %q, want %q", tc.key, got, tc.want)
		}
	}
}
