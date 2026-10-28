package plan

import "testing"

func TestV17QuestsHaveFinishAndDoneText(t *testing.T) {
	cases := []struct {
		q    Quest
		want string
	}{
		{Quest{Key: "produce", Target: 5, Actual: 3}, "2 more servings of fruit and vegetables"},
		{Quest{Key: "produce", Target: 5, Actual: 4}, "1 more serving of fruit and vegetables"},
		{Quest{Key: "breathing", Target: 5, Actual: 2}, "3 minutes of breathing"},
	}
	for _, tc := range cases {
		if got, ok := FinishText(tc.q); !ok || got != tc.want {
			t.Errorf("FinishText(%v) = %q, %v, want %q", tc.q.Key, got, ok, tc.want)
		}
	}
	if _, ok := FinishText(Quest{Key: "sleep_regularity", Target: 45, Actual: 1}); ok {
		t.Error("last night's bedtime cannot be fixed, so it has no suggestion")
	}
	if got := doneText(Quest{Key: "produce", Target: 5, Actual: 5, Done: true}); got != "Fruit and vegetables done: 5 servings" {
		t.Errorf("doneText = %q", got)
	}
	if got := doneText(Quest{Key: "breathing", Target: 5, Actual: 6, Done: true}); got != "Breathing done: 6 min" {
		t.Errorf("doneText = %q", got)
	}
	if got := doneText(Quest{Key: "sleep_regularity", Done: true}); got != "Steady bedtime done" {
		t.Errorf("doneText = %q", got)
	}
}
