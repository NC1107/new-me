package plan

import "testing"

func TestWaterReadsInLitres(t *testing.T) {
	if got := doneText(Quest{Key: "water", Target: 2200, Actual: 2300, Done: true}); got != "Water done: 2.3 L" {
		t.Errorf("doneText = %q", got)
	}
	p := Build(Input{NowMinute: 9 * 60, Quests: []Quest{{Key: "water", Target: 3000, Actual: 1000}}})
	if len(p.Items) == 0 || p.Items[0].Text != "Water: 2.0 L to go." {
		t.Errorf("plan = %v", texts(p))
	}
}
