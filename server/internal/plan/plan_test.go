package plan

import (
	"reflect"
	"testing"

	"github.com/nc1107/new-me/server/internal/score"
)

func ip(n int) *int       { return &n }
func sp(s string) *string { return &s }

func texts(p Plan) []string {
	out := make([]string, len(p.Items))
	for i, it := range p.Items {
		out[i] = it.Kind + "|" + it.Key + "|" + it.Text
	}
	return out
}

func TestBuildFullDay(t *testing.T) {
	p := Build(Input{
		NowMinute: 9 * 60,
		Quests: []Quest{
			{Key: "steps", Target: 8000, Actual: 4800},
			{Key: "pushups", Target: 30, Actual: 30, Done: true, DoneBy: &score.DoneBy{Kind: "workout", Type: "strength", Minutes: 42}},
			{Key: "reading", Target: 20, Actual: 6, TargetAlt: ip(15), ActualAlt: ip(0)},
			{Key: "meals_logged", Target: 2, Actual: 2, Done: true},
			{Key: "sleep", Target: 420, Actual: 380},
		},
		Habits: []Habit{
			{ID: 7, Name: "Stretch", Check: true, Slots: []Slot{{Label: "Night", Time: sp("21:00")}}},
			{ID: 3, Name: "Vitamins", Check: true, Slots: []Slot{{Label: "AM", Time: sp("08:00"), Done: true}, {Label: "PM", Time: sp("18:00")}}},
			{ID: 9, Name: "Water", Target: 8, Count: 3},
			{ID: 4, Name: "Floss", Check: true, Slots: []Slot{{Label: "AM", Done: true}}},
		},
	})
	want := []string{
		"done|pushups|Push-ups done by your Strength workout, 42 min",
		"done|meals_logged|Meals done",
		"todo|steps|Steps: 3,200 to go. A 30-minute walk around midday covers it.",
		"todo|reading|Reading: 14 more minutes. An audiobook counts.",
		"habit|habit:3|Vitamins at 18:00",
		"habit|habit:7|Stretch at 21:00",
		"habit|habit:9|Water: 3 of 8 so far",
	}
	if got := texts(p); !reflect.DeepEqual(got, want) {
		t.Fatalf("items:\n got %q\nwant %q", got, want)
	}
	// Reading is 30% done (6 of 20 minutes), steps 60%: steps is the closer finish.
	wantSummary := "2 of 5 quests done. Easiest next: Steps: 3,200 to go. A 30-minute walk around midday covers it. 3 habits are still due, starting with Vitamins at 18:00."
	if p.Summary != wantSummary {
		t.Fatalf("summary = %q", p.Summary)
	}
}

func TestStepsAdviceFollowsTheClockAndSplitsLongWalks(t *testing.T) {
	cases := []struct {
		minute, actual int
		want           string
	}{
		{8 * 60, 7000, "Steps: 1,000 to go. A 10-minute walk around midday covers it."},
		{13 * 60, 7000, "Steps: 1,000 to go. A 10-minute walk this afternoon covers it."},
		{19 * 60, 7901, "Steps: 99 to go. A 5-minute walk this evening covers it."},
		{9 * 60, 0, "Steps: 8,000 to go. That is about 80 minutes of walking: split it into two walks."},
	}
	for _, tc := range cases {
		p := Build(Input{NowMinute: tc.minute, Quests: []Quest{{Key: "steps", Target: 8000, Actual: tc.actual}}})
		if p.Items[0].Text != tc.want {
			t.Errorf("minute %d: %q, want %q", tc.minute, p.Items[0].Text, tc.want)
		}
	}
}

func TestAllDoneAndEmpty(t *testing.T) {
	p := Build(Input{Quests: []Quest{{Key: "steps", Target: 8000, Actual: 8412, Done: true}, {Key: "reading", Target: 20, Actual: 25, Done: true}}})
	if p.Summary != "All 2 quests are done. Nice work." || p.Items[0].Text != "Steps done: 8,412" || p.Items[1].Text != "Reading done: 25 min" {
		t.Fatalf("plan = %+v", p)
	}
	empty := Build(Input{})
	if empty.Items == nil || len(empty.Items) != 0 || empty.Summary != "No quests are set for today." {
		t.Fatalf("empty = %+v", empty)
	}
}

func TestSleepAndUnknownQuestsGetNoSuggestion(t *testing.T) {
	p := Build(Input{Quests: []Quest{{Key: "sleep", Target: 420, Actual: 300}}})
	if len(p.Items) != 0 || p.Summary != "0 of 1 quest done." {
		t.Fatalf("plan = %+v", p)
	}
}

func TestYogaDoneByWorkout(t *testing.T) {
	p := Build(Input{Quests: []Quest{{Key: "yoga", Target: 20, Actual: 25, Done: true, DoneBy: &score.DoneBy{Kind: "workout", Type: "yoga", Minutes: 25}}}})
	if p.Items[0].Text != "Yoga done by your Yoga workout, 25 min" {
		t.Fatalf("text = %q", p.Items[0].Text)
	}
}

func TestFinishText(t *testing.T) {
	cases := []struct {
		q    Quest
		want string
	}{
		{Quest{Key: "pushups", Target: 30, Actual: 20}, "10 push-ups"},
		{Quest{Key: "steps", Target: 8000, Actual: 5000}, "3,000 more steps"},
		{Quest{Key: "protein", Target: 100, Actual: 75}, "25 g more protein"},
		{Quest{Key: "meals_logged", Target: 2, Actual: 1}, "logging 1 more meal"},
	}
	for _, tc := range cases {
		if got, ok := FinishText(tc.q); !ok || got != tc.want {
			t.Errorf("%s: %q %v, want %q", tc.q.Key, got, ok, tc.want)
		}
	}
	if _, ok := FinishText(Quest{Key: "sleep", Target: 420}); ok {
		t.Error("sleep cannot be finished")
	}
}

func TestStepsNudge(t *testing.T) {
	if got := StepsNudge(2100); got != "2,100 steps to go. A 20-minute walk does it." {
		t.Errorf("got %q", got)
	}
	if got := StepsNudge(6200); got != "6,200 steps to go. Even a 30-minute walk gets you most of the way." {
		t.Errorf("got %q", got)
	}
}
