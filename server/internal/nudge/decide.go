// Package nudge decides which push notifications a person should get right now. Decide is pure
// and takes the clock as part of its input, so every rule is table-tested; service.go gathers
// the facts and sends what Decide returns.
//
// Rules, all in the person's local time and each kind at most once a day:
//
//	behind pace   from 14:00 and from 18:30 (each a window of two hours): today's steps are under
//	              85% of the expected steps so far, and the steps quest is not done. Expected is
//	              the usual daily steps (14-day median, capped at the goal; the goal itself
//	              without history) times a curve of how much of a day is normally walked by
//	              each hour: 0% at 07:00, 25% at 10:00, 50% at 14:00, 80% at 18:30, 100% at
//	              22:00, linear in between.
//	close to done the day has not counted yet and finishing one open quest would make it count
//	morning plan  at the first notification of the day (wake time plus the person's offset), for
//	              three hours
//	wind down     45 minutes before the person's bedtime, until bedtime, only when last night was at
//	              least 30 minutes short, sleep is a quest or tracked, and the nudge falls in the evening
//
// The person's schedule sets the window: nothing is sent before the first notification of the day
// or from bedtime on. Budget: at most 2 automatic pushes (these kinds, the Sunday recap and the
// monthly look-back) per person per day. When it is tight the order is close to done, then behind
// pace, then wind down; the morning plan is only sent as the first push of the day. Behind pace
// and close to done are never sent when readiness is easy, and nothing is sent on an away day.
package nudge

import (
	"fmt"
	"strings"
	"time"

	"github.com/nc1107/new-me/server/internal/plan"
	"github.com/nc1107/new-me/server/internal/readiness"
	"github.com/nc1107/new-me/server/internal/score"
	"github.com/nc1107/new-me/server/internal/together"
)

// Clock constants, in minutes after local midnight.
const (
	afternoonWindow  = 14 * 60
	eveningWindow    = 18*60 + 30
	behindWindowLen  = 120
	morningWindowLen = 180
	windDownLead     = 45
	windDownEarliest = 18 * 60
	// DailyBudget is how many automatic pushes one person gets a day.
	DailyBudget = 2
	// behindFraction is how far under the expected steps counts as behind.
	behindFraction = 0.85
	// ShortNightMin is how far under the sleep target a night must be to trigger the wind down.
	ShortNightMin = 30
)

// curve is the share of a day's steps normally taken by each minute of the day.
var curve = []struct {
	minute int
	share  float64
}{{7 * 60, 0}, {10 * 60, 0.25}, {14 * 60, 0.50}, {18*60 + 30, 0.80}, {22 * 60, 1}}

// ExpectedShare is the share of a day's steps normally taken by the minute of the day.
func ExpectedShare(minute int) float64 {
	if minute <= curve[0].minute {
		return curve[0].share
	}
	for i := 1; i < len(curve); i++ {
		if minute <= curve[i].minute {
			lo, hi := curve[i-1], curve[i]
			return lo.share + (hi.share-lo.share)*float64(minute-lo.minute)/float64(hi.minute-lo.minute)
		}
	}
	return 1
}

// Prefs are the person's switches for the kinds Decide chooses between.
type Prefs struct {
	BehindPace, CloseToDone, WindDown, MorningPlan bool
}

// OpenQuest is an unfinished quest that could finish the day.
type OpenQuest struct {
	Key string
	// Finish completes "<Finish> finishes your day", e.g. "10 push-ups".
	Finish string
	// Missing is the base points still to earn on the quest.
	Missing int
}

// Facts is everything Decide reads.
type Facts struct {
	// Now is the current instant in the person's own zone.
	Now   time.Time
	Prefs Prefs
	// Sent holds the kinds already sent today, and SentCount how many automatic pushes that was.
	Sent      map[string]bool
	SentCount int
	// ReadinessEasy silences the nudges that push the person to do more.
	ReadinessEasy bool

	StepsTracked bool
	StepsGoal    int
	StepsDone    bool
	Steps        float64
	StepsUsual   float64

	Counted    bool
	BasePts    int
	MaxBase    int
	OpenQuests []OpenQuest

	SleepTargetMin int
	LastNightMin   *int
	SleepTracked   bool
	SleepQuest     bool

	// FirstMin and EndMin bound the day's notification window in minutes after midnight: the
	// first notification, and bedtime (or midnight when bedtime is after it). BedMin is the
	// bedtime itself as a clock reading.
	FirstMin, EndMin, BedMin int
	// Away silences everything on a day inside an away span.
	Away bool

	// Morning words the morning plan push; it is only called when that push is due.
	Morning func() (title, body string)
}

// Nudge is one push to send.
type Nudge struct {
	Kind  string
	Title string
	Body  string
}

func minuteOfDay(t time.Time) int { return t.Hour()*60 + t.Minute() }

func (f Facts) quiet(minute int) bool { return minute < f.FirstMin || minute >= f.EndMin }

func inWindow(minute, start, length int) bool { return minute >= start && minute < start+length }

// Decide returns the nudges due now, in the order they should be sent, within the daily budget.
func Decide(f Facts) []Nudge {
	room := DailyBudget - f.SentCount
	if room <= 0 || f.Away {
		return nil
	}
	minute := minuteOfDay(f.Now)
	quiet := f.quiet(minute)
	if quiet {
		return nil
	}
	var out []Nudge
	if f.SentCount == 0 {
		if n, ok := morningPlan(f, minute); ok {
			out = append(out, n)
			room--
		}
	}
	var ranked []Nudge
	if !f.ReadinessEasy {
		if n, ok := closeToDone(f); ok {
			ranked = append(ranked, n)
		}
		if n, ok := behindPace(f, minute); ok {
			ranked = append(ranked, n)
		}
	}
	if n, ok := windDown(f, minute); ok {
		ranked = append(ranked, n)
	}
	return append(out, ranked[:min(len(ranked), max(room, 0))]...)
}

func behindPace(f Facts, minute int) (Nudge, bool) {
	kind := ""
	switch {
	case inWindow(minute, afternoonWindow, behindWindowLen):
		kind = together.EventBehindPaceAfternoon
	case inWindow(minute, eveningWindow, behindWindowLen):
		kind = together.EventBehindPaceEvening
	}
	if kind == "" || !f.Prefs.BehindPace || f.Sent[kind] || !f.StepsTracked || f.StepsGoal <= 0 || f.StepsDone {
		return Nudge{}, false
	}
	usual := float64(f.StepsGoal)
	if f.StepsUsual > 0 {
		usual = min(f.StepsUsual, usual)
	}
	if f.Steps >= behindFraction*ExpectedShare(minute)*usual {
		return Nudge{}, false
	}
	left := f.StepsGoal - int(f.Steps)
	return Nudge{Kind: kind, Title: "Steps to go", Body: plan.StepsNudge(left)}, true
}

func closeToDone(f Facts) (Nudge, bool) {
	if !f.Prefs.CloseToDone || f.Sent[together.EventCloseToDone] || f.Counted || f.MaxBase <= 0 || len(f.OpenQuests) == 0 {
		return Nudge{}, false
	}
	var best *OpenQuest
	for i, q := range f.OpenQuests {
		if (f.BasePts+q.Missing)*100 < 70*f.MaxBase {
			continue
		}
		if best == nil || q.Missing < best.Missing {
			best = &f.OpenQuests[i]
		}
	}
	if best == nil {
		return Nudge{}, false
	}
	body := fmt.Sprintf("%s would make today count.", capitalize(best.Finish))
	if len(f.OpenQuests) == 1 {
		body = fmt.Sprintf("One quest left: %s finishes your day.", best.Finish)
	}
	return Nudge{Kind: together.EventCloseToDone, Title: "Almost there", Body: body}, true
}

func morningPlan(f Facts, minute int) (Nudge, bool) {
	if !f.Prefs.MorningPlan || f.Sent[together.EventMorningPlan] || !inWindow(minute, f.FirstMin, morningWindowLen) {
		return Nudge{}, false
	}
	n := Nudge{Kind: together.EventMorningPlan, Title: "Today's plan", Body: "Open New Me to see today's plan."}
	if f.Morning != nil {
		n.Title, n.Body = f.Morning()
	}
	return n, true
}

// WindDownAt is the minute of the evening the wind down nudge starts, 45 minutes before the
// bedtime. It is false when that falls before 18:00, which covers a bedtime after midnight: such
// a nudge is skipped rather than moved to another day.
func WindDownAt(bedMin int) (int, bool) {
	at := bedMin - windDownLead
	return at, at >= windDownEarliest
}

func windDown(f Facts, minute int) (Nudge, bool) {
	if !f.Prefs.WindDown || f.Sent[together.EventWindDown] || f.LastNightMin == nil ||
		!(f.SleepQuest || f.SleepTracked) || f.SleepTargetMin <= 0 {
		return Nudge{}, false
	}
	if f.SleepTargetMin-*f.LastNightMin < ShortNightMin {
		return Nudge{}, false
	}
	at, ok := WindDownAt(f.BedMin)
	if !ok || !inWindow(minute, at, windDownLead) {
		return Nudge{}, false
	}
	return Nudge{Kind: together.EventWindDown, Title: "Wind down",
		Body: fmt.Sprintf("Bed by %s for %s.", score.FormatClock(f.BedMin), readiness.Duration(f.SleepTargetMin))}, true
}

func capitalize(s string) string {
	if s == "" {
		return s
	}
	return strings.ToUpper(s[:1]) + s[1:]
}
