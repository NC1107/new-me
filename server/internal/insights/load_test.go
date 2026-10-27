package insights

import (
	"testing"

	"github.com/nc1107/new-me/server/internal/score"
)

func TestComputeActivityAgainstTheWHOGuideline(t *testing.T) {
	today := score.MustDate("2026-11-02")
	hr := func(v float64) *float64 { return &v }
	day := func(ago int) score.Date { return today.AddDays(-ago) }
	tests := []struct {
		name                   string
		sessions               []Session
		rest, max              float64
		moderate, hard, equiv  int
		strengthDays           int
		meetsAerobic, meetsStr bool
	}{
		{name: "nothing"},
		{name: "unknown heart rate: walking is moderate, HIIT vigorous",
			sessions: []Session{{Date: day(1), Type: "walking", DurationMin: 60}, {Date: day(2), Type: "hiit", DurationMin: 20}},
			moderate: 60, hard: 20, equiv: 100},
		{name: "heart rate decides: 60% of reserve is vigorous",
			sessions: []Session{{Date: day(1), Type: "running", DurationMin: 30, AvgHR: hr(132)}, {Date: day(2), Type: "running", DurationMin: 30, AvgHR: hr(131)}},
			rest:     60, max: 180, moderate: 30, hard: 30, equiv: 90},
		{name: "two strength days meet the strength target",
			sessions: []Session{{Date: day(0), Type: "strength", DurationMin: 30}, {Date: day(3), Type: "strength", DurationMin: 30}, {Date: day(3), Type: "strength", DurationMin: 10}},
			moderate: 70, equiv: 70, strengthDays: 2, meetsStr: true},
		{name: "150 moderate minutes meet the aerobic target",
			sessions: []Session{{Date: day(0), Type: "cycling", DurationMin: 150}}, moderate: 150, equiv: 150, meetsAerobic: true},
		{name: "75 vigorous minutes are the same",
			sessions: []Session{{Date: day(0), Type: "hiit", DurationMin: 75}}, hard: 75, equiv: 150, meetsAerobic: true},
		{name: "only the last seven days count",
			sessions: []Session{{Date: day(6), Type: "cycling", DurationMin: 10}, {Date: day(7), Type: "cycling", DurationMin: 500}, {Date: day(-1), Type: "cycling", DurationMin: 500}},
			moderate: 10, equiv: 10},
	}
	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			got := ComputeActivity(ActivityInput{Sessions: tc.sessions, Today: today, RestingHR: tc.rest, MaxHR: tc.max})
			if got.ModerateMin != tc.moderate || got.VigorousMin != tc.hard || got.ModerateEquivalentMin != tc.equiv ||
				got.StrengthDays != tc.strengthDays || got.MeetsAerobic != tc.meetsAerobic || got.MeetsStrength != tc.meetsStr {
				t.Fatalf("got %+v", got)
			}
			if got.Guideline != "WHO 2020" || got.AerobicTargetMinMin != 150 || got.AerobicTargetMaxMin != 300 || got.StrengthTargetDays != 2 {
				t.Fatalf("guideline = %+v", got)
			}
		})
	}
}

func TestHitRateAndComputeProtein(t *testing.T) {
	days := []ProteinDay{{TargetG: 100, Grams: 100}, {TargetG: 100, Grams: 99.9}, {TargetG: 120, Grams: 130}, {TargetG: 0, Grams: 50}}
	hit, total := HitRate(days)
	if hit != 2 || total != 3 {
		t.Fatalf("hit %d of %d, want 2 of 3 (a day without a target is not counted)", hit, total)
	}
	kg := 75.0
	p := ComputeProtein(110, &kg, days)
	if p.TargetG != 110 || p.SuggestedG == nil || *p.SuggestedG != 120 || p.HitRate7 == nil || *p.HitRate7 != 0.67 || p.PerKg != 1.6 {
		t.Fatalf("protein = %+v", p)
	}
	none := ComputeProtein(100, nil, nil)
	if none.HitRate7 != nil || none.SuggestedG != nil || none.Days7 != 0 {
		t.Fatalf("empty = %+v", none)
	}
}
