package score

import "testing"

func TestEffortPoints(t *testing.T) {
	for _, tc := range []struct {
		name     string
		key      string
		target   int
		strength int
		want     int
		basis    EffortBasis
	}{
		{"steps capped", "steps", 7000, 0, 100, BasisWalk},
		{"steps default capped", "steps", 8000, 0, 100, BasisWalk},
		{"short steps goal", "steps", 3000, 0, 85, BasisWalk},
		{"exercise half hour", "exercise", 30, 0, 85, BasisModerate},
		{"exercise ten minutes", "exercise", 10, 0, 30, BasisModerate},
		{"strength without a plan is thirty minutes", "pushups", 30, 0, 75, BasisStrength},
		{"strength ignores the reps target", "pushups", 100, 0, 75, BasisStrength},
		{"strength follows the planned session", "pushups", 30, 20, 50, BasisStrength},
		{"a long session is capped", "pushups", 30, 60, 100, BasisStrength},
		{"reading half hour", "reading", 30, 0, 30, BasisFocus},
		{"reading twenty floors", "reading", 20, 0, 20, BasisFocus},
		{"yoga twenty minutes", "yoga", 20, 0, 25, BasisYoga},
		{"breathing floors", "breathing", 5, 0, 20, BasisFocus},
		{"water", "water", 3000, 0, 20, BasisNone},
		{"meals", "meals_logged", 3, 0, 20, BasisNone},
		{"protein", "protein", 150, 0, 20, BasisNone},
		{"sleep", "sleep", 450, 0, 20, BasisNone},
		{"produce", "produce", 5, 0, 20, BasisNone},
		{"regularity", "sleep_regularity", 45, 0, 20, BasisNone},
	} {
		t.Run(tc.name, func(t *testing.T) {
			got := EffortPoints(tc.key, tc.target, tc.strength)
			if got.Points != tc.want || got.Basis != tc.basis {
				t.Fatalf("EffortPoints(%s, %d, %d) = %d %s, want %d %s", tc.key, tc.target, tc.strength, got.Points, got.Basis, tc.want, tc.basis)
			}
		})
	}
}

func TestEffortPointsStayInRangeRoundedAndGrowWithTheTarget(t *testing.T) {
	for _, key := range []string{"steps", "exercise", "pushups", "yoga", "reading", "breathing"} {
		prev := 0
		for target := 1; target <= 30000; target += 7 {
			strength := 0
			if key == "pushups" {
				strength = 1 + target/330
			}
			p := EffortPoints(key, target, strength).Points
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
		key      string
		target   int
		strength int
		want     string
	}{
		{"exercise", 30, 0, "Worth 85: about 30 min of moderate effort."},
		{"steps", 7000, 0, "Worth 100, the most any goal earns: about 70 min of walking at a moderate pace."},
		{"pushups", 30, 0, "Worth 75: priced as a 30 min strength session (a game default), which this goal also accepts."},
		{"pushups", 30, 30, "Worth 75: priced as your 30 min strength session, which this goal also accepts."},
		{"pushups", 30, 60, "Worth 100, the most any goal earns: priced as your 60 min strength session, which this goal also accepts."},
		{"water", 2200, 0, "Worth 20, the least any goal earns: no measured effort."},
	} {
		if got := EffortPoints(tc.key, tc.target, tc.strength).Reason(); got != tc.want {
			t.Errorf("%s reason = %q, want %q", tc.key, got, tc.want)
		}
	}
}
