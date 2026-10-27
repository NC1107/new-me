package nudge

import (
	"testing"
	"time"

	"github.com/nc1107/new-me/server/internal/together"
)

func at(h, m int) time.Time { return time.Date(2026, 11, 2, h, m, 0, 0, time.UTC) }

func ip(n int) *int { return &n }

func allOn() Prefs { return Prefs{true, true, true, true} }

func steps(now time.Time, got float64) Facts {
	return Facts{Now: now, Prefs: allOn(), StepsTracked: true, StepsGoal: 8000, Steps: got, StepsUsual: 8000, MaxBase: 400, BasePts: 100}
}

func kinds(ns []Nudge) []string {
	out := make([]string, len(ns))
	for i, n := range ns {
		out[i] = n.Kind
	}
	return out
}

func TestExpectedShareCurve(t *testing.T) {
	cases := map[int]float64{0: 0, 7 * 60: 0, 8*60 + 30: 0.125, 10 * 60: 0.25, 12 * 60: 0.375, 14 * 60: 0.5,
		18*60 + 30: 0.8, 20*60 + 15: 0.9, 22 * 60: 1, 23 * 60: 1}
	for minute, want := range cases {
		if got := ExpectedShare(minute); got < want-1e-9 || got > want+1e-9 {
			t.Errorf("share(%d) = %v, want %v", minute, got, want)
		}
	}
}

func TestBehindPaceWindows(t *testing.T) {
	cases := []struct {
		name  string
		now   time.Time
		steps float64
		edit  func(*Facts)
		want  []string
	}{
		{"behind at 14:00", at(14, 0), 3399, nil, []string{together.EventBehindPaceAfternoon}},
		{"on pace at 14:00 (85% of 4000)", at(14, 0), 3400, nil, nil},
		{"still inside the window at 15:59", at(15, 59), 100, nil, []string{together.EventBehindPaceAfternoon}},
		{"window over at 16:00", at(16, 0), 100, nil, nil},
		{"before the window", at(13, 59), 100, nil, nil},
		{"behind at 18:30", at(18, 30), 5439, nil, []string{together.EventBehindPaceEvening}},
		{"on pace at 18:30", at(18, 30), 5440, nil, nil},
		{"afternoon already sent", at(14, 5), 100, func(f *Facts) { f.Sent = map[string]bool{together.EventBehindPaceAfternoon: true} }, nil},
		{"evening still allowed after the afternoon one", at(18, 40), 100, func(f *Facts) { f.Sent = map[string]bool{together.EventBehindPaceAfternoon: true} }, []string{together.EventBehindPaceEvening}},
		{"never after the quest is done", at(14, 0), 8100, func(f *Facts) { f.StepsDone = true }, nil},
		{"preference off", at(14, 0), 100, func(f *Facts) { f.Prefs.BehindPace = false }, nil},
		{"steps never synced", at(14, 0), 0, func(f *Facts) { f.StepsTracked = false }, nil},
		{"no steps quest today", at(14, 0), 0, func(f *Facts) { f.StepsGoal = 0 }, nil},
		{"a low usual lowers the bar", at(14, 0), 1300, func(f *Facts) { f.StepsUsual = 3000 }, nil},
		{"a high usual is capped at the goal", at(14, 0), 3000, func(f *Facts) { f.StepsUsual = 20000 }, []string{together.EventBehindPaceAfternoon}},
		{"no history falls back to the goal", at(14, 0), 3000, func(f *Facts) { f.StepsUsual = 0 }, []string{together.EventBehindPaceAfternoon}},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			f := steps(tc.now, tc.steps)
			f.Counted = true // keep close-to-done out of the way
			if tc.edit != nil {
				tc.edit(&f)
			}
			if got := kinds(Decide(f)); !equal(got, tc.want) {
				t.Fatalf("got %v, want %v", got, tc.want)
			}
		})
	}
	f := steps(at(14, 0), 2100)
	f.Counted = true
	if got := Decide(f)[0]; got.Body != "5,900 steps to go. Even a 30-minute walk gets you most of the way." {
		t.Fatalf("body = %q", got.Body)
	}
}

func equal(a, b []string) bool {
	if len(a) != len(b) {
		return false
	}
	for i := range a {
		if a[i] != b[i] {
			return false
		}
	}
	return true
}

func TestCloseToDone(t *testing.T) {
	base := func() Facts {
		return Facts{Now: at(16, 0), Prefs: allOn(), MaxBase: 400, BasePts: 240,
			OpenQuests: []OpenQuest{{Key: "pushups", Finish: "10 push-ups", Missing: 40}}}
	}
	cases := []struct {
		name string
		edit func(*Facts)
		want string
	}{
		{"one quest finishes the day", nil, "One quest left: 10 push-ups finishes your day."},
		{"already counted", func(f *Facts) { f.Counted = true }, ""},
		{"not close enough", func(f *Facts) { f.BasePts = 200 }, ""},
		{"exactly 70 percent after the quest", func(f *Facts) { f.BasePts = 240; f.OpenQuests[0].Missing = 40 }, "One quest left: 10 push-ups finishes your day."},
		{"69.75 percent is not enough", func(f *Facts) { f.OpenQuests[0].Missing = 39 }, ""},
		{"several open quests: the one that closes the gap", func(f *Facts) {
			f.OpenQuests = []OpenQuest{{Key: "steps", Finish: "3,000 more steps", Missing: 50}, {Key: "meals", Finish: "logging 1 more meal", Missing: 25}}
			f.BasePts = 230
		}, "3,000 more steps would make today count."},
		{"sent today", func(f *Facts) { f.Sent = map[string]bool{together.EventCloseToDone: true} }, ""},
		{"preference off", func(f *Facts) { f.Prefs.CloseToDone = false }, ""},
		{"no quests", func(f *Facts) { f.MaxBase = 0 }, ""},
		{"quiet hours", func(f *Facts) { f.Now = at(21, 30) }, ""},
		{"quiet hours early", func(f *Facts) { f.Now = at(7, 29) }, ""},
		{"just after quiet hours", func(f *Facts) { f.Now = at(7, 30) }, "One quest left: 10 push-ups finishes your day."},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			f := base()
			if tc.edit != nil {
				tc.edit(&f)
			}
			var body string
			for _, n := range Decide(f) {
				if n.Kind == together.EventCloseToDone {
					body = n.Body
				}
			}
			if body != tc.want {
				t.Fatalf("body = %q, want %q", body, tc.want)
			}
		})
	}
}

func TestMorningPlanTiming(t *testing.T) {
	morning := func() (string, string) { return "You're ready today", "plan words" }
	cases := []struct {
		name string
		now  time.Time
		wake *int
		sent bool
		want bool
	}{
		{"08:00 without wake data", at(8, 0), nil, false, true},
		{"07:59 is too early", at(7, 59), nil, false, false},
		{"early riser still waits for 08:00", at(8, 0), ip(6 * 60), false, true},
		{"late riser waits for wake plus 30", at(9, 0), ip(8*60 + 45), false, false},
		{"late riser at wake plus 30", at(9, 15), ip(8*60 + 45), false, true},
		{"window ends after three hours", at(11, 0), nil, false, false},
		{"just inside the window", at(10, 59), nil, false, true},
		{"already sent", at(8, 30), nil, true, false},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			f := Facts{Now: tc.now, Prefs: allOn(), AvgWakeMin: tc.wake, Morning: morning}
			if tc.sent {
				f.Sent = map[string]bool{together.EventMorningPlan: true}
			}
			ns := Decide(f)
			if got := len(ns) == 1 && ns[0].Kind == together.EventMorningPlan; got != tc.want {
				t.Fatalf("got %v (%v), want %v", got, ns, tc.want)
			}
			if tc.want && (ns[0].Title != "You're ready today" || ns[0].Body != "plan words") {
				t.Fatalf("nudge = %+v", ns[0])
			}
		})
	}
	off := Facts{Now: at(8, 0), Prefs: Prefs{BehindPace: true}, Morning: morning}
	if len(Decide(off)) != 0 {
		t.Fatal("preference off must stay silent")
	}
	if got := Decide(Facts{Now: at(8, 0), Prefs: allOn()}); len(got) != 1 || got[0].Body != "Open New Me to see today's plan." {
		t.Fatalf("default words = %+v", got)
	}
}

func TestWindDown(t *testing.T) {
	base := func() Facts {
		return Facts{Now: at(22, 0), Prefs: allOn(), SleepTargetMin: 450, AvgWakeMin: ip(7*60 + 10),
			LastNightMin: ip(380), SleepTracked: true, Counted: true}
	}
	// Wake 07:10 minus 7 h 30 is bed 23:40, so the nudge starts at 22:55.
	cases := []struct {
		name string
		edit func(*Facts)
		want string
	}{
		{"before the nudge time", func(f *Facts) { f.Now = at(22, 54) }, ""},
		{"at the nudge time, inside quiet hours", func(f *Facts) { f.Now = at(22, 55) }, "Bed by 23:40 for 7 h 30."},
		{"window of 90 minutes", func(f *Facts) { f.Now = at(24-1, 24) }, "Bed by 23:40 for 7 h 30."},
		{"window over", func(f *Facts) {
			f.Now = at(22, 45)
			f.AvgWakeMin = ip(300)
			f.SleepTargetMin = 420
			f.LastNightMin = ip(300)
		}, ""},
		{"last minute of the window", func(f *Facts) {
			f.Now = at(22, 44)
			f.AvgWakeMin = ip(300)
			f.SleepTargetMin = 420
			f.LastNightMin = ip(300)
		}, "Bed by 22:00 for 7 h."},
		{"last night fine", func(f *Facts) { f.Now = at(22, 55); f.LastNightMin = ip(425) }, ""},
		{"last night 30 short counts", func(f *Facts) { f.Now = at(22, 55); f.LastNightMin = ip(420) }, "Bed by 23:40 for 7 h 30."},
		{"29 short does not", func(f *Facts) { f.Now = at(22, 55); f.LastNightMin = ip(421) }, ""},
		{"no sleep recorded last night", func(f *Facts) { f.Now = at(22, 55); f.LastNightMin = nil }, ""},
		{"sleep untracked and no quest", func(f *Facts) { f.Now = at(22, 55); f.SleepTracked = false }, ""},
		{"sleep quest enough", func(f *Facts) { f.Now = at(22, 55); f.SleepTracked = false; f.SleepQuest = true }, "Bed by 23:40 for 7 h 30."},
		{"no wake time", func(f *Facts) { f.Now = at(22, 55); f.AvgWakeMin = nil }, ""},
		{"sent", func(f *Facts) { f.Now = at(22, 55); f.Sent = map[string]bool{together.EventWindDown: true} }, ""},
		{"preference off", func(f *Facts) { f.Now = at(22, 55); f.Prefs.WindDown = false }, ""},
		{"after midnight bedtimes are skipped", func(f *Facts) { f.Now = at(23, 30); f.AvgWakeMin = ip(9 * 60) }, ""},
		{"bedtime rounds to five minutes", func(f *Facts) { f.Now = at(22, 55); f.AvgWakeMin = ip(7*60 + 12) }, "Bed by 23:40 for 7 h 30."},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			f := base()
			tc.edit(&f)
			var body string
			for _, n := range Decide(f) {
				if n.Kind == together.EventWindDown {
					body = n.Body
				}
			}
			if body != tc.want {
				t.Fatalf("body = %q, want %q", body, tc.want)
			}
		})
	}
}

func TestWindDownTime(t *testing.T) {
	at, bed, ok := WindDownTime(7*60+10, 450)
	if !ok || at != 22*60+55 || bed != 23*60+40 {
		t.Fatalf("got %d %d %v", at, bed, ok)
	}
	if at, bed, ok := WindDownTime(6*60, 480); !ok || at != 21*60+15 || bed != 22*60 {
		t.Fatalf("22:00 bedtime: %d %d %v", at, bed, ok)
	}
	if _, _, ok := WindDownTime(9*60, 480); ok {
		t.Fatal("a 01:00 bedtime has no evening nudge")
	}
}

func TestDailyBudgetAndPriority(t *testing.T) {
	// 14:05, behind on steps and one quest from counting, wind down also possible is covered below.
	busy := func() Facts {
		f := steps(at(14, 5), 100)
		f.OpenQuests = []OpenQuest{{Key: "pushups", Finish: "10 push-ups", Missing: 100}}
		f.BasePts, f.MaxBase = 250, 400
		return f
	}
	cases := []struct {
		name string
		edit func(*Facts)
		want []string
	}{
		{"fresh day sends both, close to done first", nil, []string{together.EventCloseToDone, together.EventBehindPaceAfternoon}},
		{"one slot left: close to done wins", func(f *Facts) { f.SentCount = 1 }, []string{together.EventCloseToDone}},
		{"one slot left, not close: behind pace", func(f *Facts) { f.SentCount = 1; f.BasePts = 0 }, []string{together.EventBehindPaceAfternoon}},
		{"budget spent", func(f *Facts) { f.SentCount = 2 }, nil},
		{"easy readiness silences both", func(f *Facts) { f.ReadinessEasy = true }, nil},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			f := busy()
			if tc.edit != nil {
				tc.edit(&f)
			}
			if got := kinds(Decide(f)); !equal(got, tc.want) {
				t.Fatalf("got %v, want %v", got, tc.want)
			}
		})
	}

	// Wind down ranks last and yields to the others when only one slot is left.
	wd := Facts{Now: at(22, 0), Prefs: allOn(), SleepTargetMin: 450, AvgWakeMin: ip(7*60 + 10), LastNightMin: ip(380), SleepTracked: true}
	wd.Now = at(22, 55)
	if got := kinds(Decide(wd)); !equal(got, []string{together.EventWindDown}) {
		t.Fatalf("wind down alone = %v", got)
	}
	wd.SentCount = 2
	if len(Decide(wd)) != 0 {
		t.Fatal("wind down must respect the budget")
	}
}

func TestMorningPlanIsOnlyTheFirstPush(t *testing.T) {
	f := Facts{Now: at(9, 0), Prefs: allOn(), SentCount: 1}
	if len(Decide(f)) != 0 {
		t.Fatal("morning plan after another push")
	}
	f.SentCount = 0
	got := Decide(f)
	if len(got) != 1 || got[0].Kind != together.EventMorningPlan {
		t.Fatalf("got %v", got)
	}
}

func TestEasyReadinessKeepsMorningPlanAndWindDown(t *testing.T) {
	f := Facts{Now: at(9, 0), Prefs: allOn(), ReadinessEasy: true}
	if len(Decide(f)) != 1 {
		t.Fatal("the morning plan is how an easy day is announced")
	}
}
