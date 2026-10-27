package score

import (
	"strings"
	"testing"
	"time"
)

// spec describes consecutive days from start, one letter each:
//
//	x counted        . missed, nothing recorded     _ no entry at all
//	n missed, settled with no reason                 f settled freeze      r settled repair
//	d settled readiness rest                         a away                X away but counted
//	c covered by the partner, unsettled             e missed, but the readiness morning was easy
func build(start Date, spec string) ([]DayFlag, map[Date]bool) {
	var days []DayFlag
	easy := map[Date]bool{}
	for i, c := range spec {
		d := start.AddDays(i)
		f := DayFlag{Date: d}
		switch c {
		case 'x':
			f.Counted = true
		case '.':
		case '_':
			continue
		case 'n':
			f.Settled = true
		case 'f':
			f.Settled, f.FrozenReason = true, ReasonFreeze
		case 'r':
			f.Settled, f.FrozenReason = true, ReasonRepair
		case 'd':
			f.Settled, f.FrozenReason = true, ReasonReadiness
		case 'a':
			f.Away = true
		case 'X':
			f.Away, f.Counted = true, true
		case 'c':
			f.Covered = true
		case 'e':
			easy[d] = true
		}
		days = append(days, f)
	}
	return days, easy
}

// outcomes writes the derived status of each date as one letter:
// x counted, f frozen, a away, m missed, p pending, o open.
func outcomes(r StreakResult, start Date, n int) string {
	letters := map[Status]string{StatusCounted: "x", StatusFrozen: "f", StatusAway: "a",
		StatusMissed: "m", StatusPending: "p", StatusOpen: "o"}
	var b strings.Builder
	for i := 0; i < n; i++ {
		b.WriteString(letters[r.Outcome(start.AddDays(i)).Status])
	}
	return b.String()
}

var monday = MustDate("2026-10-26")

func TestComputeStreakFreezeRules(t *testing.T) {
	tests := []struct {
		name    string
		spec    string
		today   int
		pending int
		spends  []int
		want    string
		count   int
		best    int
		freezes Freezes
	}{
		{name: "no days", spec: "", today: 0, want: "o", freezes: Freezes{Held: 2}},
		{name: "first days counted", spec: "xxx", today: 3, want: "xxxo", count: 3, best: 3, freezes: Freezes{Held: 2, EarnedTowardNext: 3}},
		{name: "today counted adds one", spec: "xxxx", today: 3, want: "xxxx", count: 4, best: 4, freezes: Freezes{Held: 2, EarnedTowardNext: 4}},
		{name: "today not yet counted is open", spec: "xxx.", today: 3, want: "xxxo", count: 3, best: 3, freezes: Freezes{Held: 2, EarnedTowardNext: 3}},
		{name: "a miss is frozen and adds no day", spec: "xx.x", today: 4, want: "xxfxo", count: 3, best: 3, freezes: Freezes{Held: 1, EarnedTowardNext: 3}},
		{name: "two misses use both freezes", spec: "x..x", today: 4, want: "xffxo", count: 2, best: 2, freezes: Freezes{Held: 0, EarnedTowardNext: 2}},
		{name: "a third miss breaks", spec: "x...x", today: 5, want: "xffmxo", count: 1, best: 1, freezes: Freezes{Held: 0, EarnedTowardNext: 2}},
		{name: "consecutive misses are no longer fatal", spec: "xxx..x", today: 6, want: "xxxffxo", count: 4, best: 4, freezes: Freezes{Held: 0, EarnedTowardNext: 4}},
		{name: "a miss with no streak spends nothing", spec: "..xx", today: 4, want: "mmxxo", count: 2, best: 2, freezes: Freezes{Held: 2, EarnedTowardNext: 2}},
		{name: "missing dates are misses", spec: "xx__x", today: 5, want: "xxffxo", count: 3, best: 3, freezes: Freezes{Held: 0, EarnedTowardNext: 3}},
		{name: "seven counted days earn a freeze after one is spent", spec: "xx.xxxxx", today: 8, want: "xxfxxxxxo", count: 7, best: 7, freezes: Freezes{Held: 2, EarnedTowardNext: 0}},
		{name: "progress waits at six while at the maximum", spec: "xxxxxxxxxxxxxx", today: 14, want: "xxxxxxxxxxxxxxo", count: 14, best: 14, freezes: Freezes{Held: 2, EarnedTowardNext: 6}},
		{name: "a spent freeze is earned back by the next counted day when progress waited", spec: "xxxxxxxxx.x", today: 11, want: "xxxxxxxxxfxo", count: 10, best: 10, freezes: Freezes{Held: 2, EarnedTowardNext: 0}},
		{name: "away neither breaks nor extends", spec: "xxaax", today: 5, want: "xxaaxo", count: 3, best: 3, freezes: Freezes{Held: 2, EarnedTowardNext: 3}},
		{name: "a counted away day does not extend", spec: "xXx", today: 3, want: "xaxo", count: 2, best: 2, freezes: Freezes{Held: 2, EarnedTowardNext: 2}},
		{name: "away uses no freeze", spec: "xaaa.x", today: 6, want: "xaaafxo", count: 2, best: 2, freezes: Freezes{Held: 1, EarnedTowardNext: 2}},
		{name: "away today stays away", spec: "xxa", today: 2, want: "xxa", count: 2, best: 2, freezes: Freezes{Held: 2, EarnedTowardNext: 2}},
		{name: "a recorded freeze spends one", spec: "xfx", today: 3, want: "xfxo", count: 2, best: 2, freezes: Freezes{Held: 1, EarnedTowardNext: 2}},
		{name: "a recorded repair spends none", spec: "xrx", today: 3, want: "xfxo", count: 2, best: 2, freezes: Freezes{Held: 2, EarnedTowardNext: 2}},
		{name: "a recorded readiness rest spends none", spec: "xdx", today: 3, want: "xfxo", count: 2, best: 2, freezes: Freezes{Held: 2, EarnedTowardNext: 2}},
		{name: "a recorded miss stays a miss with freezes held", spec: "xxnx", today: 4, want: "xxmxo", count: 1, best: 2, freezes: Freezes{Held: 2, EarnedTowardNext: 3}},
		{name: "an easy morning rests the day without a freeze", spec: "xex", today: 3, want: "xfxo", count: 2, best: 2, freezes: Freezes{Held: 2, EarnedTowardNext: 2}},
		{name: "an easy morning with no streak is still a rest day", spec: "e", today: 1, want: "fo", count: 0, best: 0, freezes: Freezes{Held: 2}},
		{name: "a covered day is frozen without a freeze", spec: "xcx", today: 3, want: "xfxo", count: 2, best: 2, freezes: Freezes{Held: 2, EarnedTowardNext: 2}},
		{name: "yesterday while open is pending", spec: "xx.", today: 3, pending: 2, want: "xxpo", count: 2, best: 2, freezes: Freezes{Held: 2, EarnedTowardNext: 2}},
		{name: "yesterday filled in counts", spec: "xxx", today: 3, pending: 2, want: "xxxo", count: 3, best: 3, freezes: Freezes{Held: 2, EarnedTowardNext: 3}},
		{name: "today counts while yesterday is pending", spec: "xx.x", today: 3, pending: 2, want: "xxpx", count: 3, best: 3, freezes: Freezes{Held: 2, EarnedTowardNext: 3}},
		{name: "a covered pending day is frozen at once", spec: "xxc", today: 3, pending: 2, want: "xxfo", count: 2, best: 2, freezes: Freezes{Held: 2, EarnedTowardNext: 2}},
		{name: "covering the partner spends one", spec: "xxx", today: 3, spends: []int{1}, want: "xxxo", count: 3, best: 3, freezes: Freezes{Held: 1, EarnedTowardNext: 3}},
		{name: "spends never go below zero", spec: "xxx", today: 3, spends: []int{0, 1, 2}, want: "xxxo", count: 3, best: 3, freezes: Freezes{Held: 0, EarnedTowardNext: 3}},
		{name: "a break keeps the best", spec: "xxxxn.x", today: 7, want: "xxxxmmxo", count: 1, best: 4, freezes: Freezes{Held: 2, EarnedTowardNext: 5}},
	}
	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			days, easy := build(monday, tc.spec)
			in := StreakInput{Days: days, Today: monday.AddDays(tc.today), Easy: easy}
			if tc.pending > 0 {
				in.PendingDate = monday.AddDays(tc.pending)
			}
			for _, i := range tc.spends {
				in.Spends = append(in.Spends, monday.AddDays(i))
			}
			got := ComputeStreak(in)
			if len(days) == 0 {
				if got.Count != 0 || got.Freezes != tc.freezes {
					t.Fatalf("empty: %+v", got)
				}
				return
			}
			if o := outcomes(got, monday, len(tc.want)); o != tc.want {
				t.Errorf("outcomes = %q, want %q", o, tc.want)
			}
			if got.Count != tc.count || got.Best != tc.best {
				t.Errorf("count/best = %d/%d, want %d/%d", got.Count, got.Best, tc.count, tc.best)
			}
			if got.Freezes != tc.freezes {
				t.Errorf("freezes = %+v, want %+v", got.Freezes, tc.freezes)
			}
		})
	}
}

func TestComputeStreakDecidesOnlyUnrecordedDays(t *testing.T) {
	days, easy := build(monday, "x.fnec")
	got := ComputeStreak(StreakInput{Days: days, Today: monday.AddDays(6), Easy: easy})
	want := map[int]bool{1: true, 4: true, 5: true}
	for i := 0; i < 6; i++ {
		if got.Outcome(monday.AddDays(i)).Decided != want[i] {
			t.Errorf("day %d decided = %v, want %v", i, !want[i], want[i])
		}
	}
	if o := got.Outcome(monday.AddDays(1)); o.Reason != ReasonFreeze {
		t.Errorf("day 1 reason = %q, want freeze", o.Reason)
	}
	if o := got.Outcome(monday.AddDays(4)); o.Reason != ReasonReadiness {
		t.Errorf("day 4 reason = %q, want readiness", o.Reason)
	}
	if o := got.Outcome(monday.AddDays(5)); o.Reason != ReasonCover {
		t.Errorf("day 5 reason = %q, want cover", o.Reason)
	}
}

func TestComputeStreakRuleTransition(t *testing.T) {
	tests := []struct {
		name      string
		spec      string
		rulesFrom int
		today     int
		want      string
		count     int
		freezes   Freezes
	}{
		{name: "the old rule still forgives one miss", spec: "xx.xx", rulesFrom: 5, today: 5, want: "xxfxxo", count: 4, freezes: Freezes{Held: 2}},
		{name: "a second old miss in the week stays a break", spec: "xx.x.x", rulesFrom: 6, today: 6, want: "xxfxmxo", count: 1, freezes: Freezes{Held: 2}},
		{name: "two old misses in a row stay a break", spec: "xxx..x", rulesFrom: 6, today: 6, want: "xxxfmxo", count: 1, freezes: Freezes{Held: 2}},
		{name: "old days are not rescued by freezes", spec: "xxx..", rulesFrom: 5, today: 5, want: "xxxfmo", count: 0, freezes: Freezes{Held: 2}},
		{name: "new days start with two freezes", spec: "xx.xx..x", rulesFrom: 5, today: 8, want: "xxfxxffxo", count: 5, freezes: Freezes{Held: 0, EarnedTowardNext: 1}},
		{name: "the run carries across the change", spec: "xxxxxx", rulesFrom: 3, today: 6, want: "xxxxxxo", count: 6, freezes: Freezes{Held: 2, EarnedTowardNext: 3}},
		{name: "a rest day before the change and a freeze after", spec: "xx.xx.x", rulesFrom: 5, today: 7, want: "xxfxxfxo", count: 5, freezes: Freezes{Held: 1, EarnedTowardNext: 1}},
		{name: "a break before the change is not forgiven by the new rule", spec: "x..xx", rulesFrom: 3, today: 5, want: "xfmxxo", count: 2, freezes: Freezes{Held: 2, EarnedTowardNext: 2}},
	}
	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			days, easy := build(monday, tc.spec)
			got := ComputeStreak(StreakInput{Days: days, Today: monday.AddDays(tc.today),
				RulesFrom: monday.AddDays(tc.rulesFrom), Easy: easy})
			if o := outcomes(got, monday, len(tc.want)); o != tc.want {
				t.Errorf("outcomes = %q, want %q", o, tc.want)
			}
			if got.Count != tc.count {
				t.Errorf("count = %d, want %d", got.Count, tc.count)
			}
			if got.Freezes != tc.freezes {
				t.Errorf("freezes = %+v, want %+v", got.Freezes, tc.freezes)
			}
		})
	}
}

func TestComputeStreakLegacyRestReason(t *testing.T) {
	days, _ := build(monday, "xx.x")
	got := ComputeStreak(StreakInput{Days: days, Today: monday.AddDays(4), RulesFrom: monday.AddDays(4)})
	if o := got.Outcome(monday.AddDays(2)); o.Status != StatusFrozen || o.Reason != ReasonRest {
		t.Fatalf("old rest day = %+v, want frozen with reason rest", o)
	}
	if d, ok := got.LastFrozenIn(monday); !ok || d != monday.AddDays(2) {
		t.Fatalf("LastFrozenIn = %v %v", d, ok)
	}
	if _, ok := got.LastFrozenIn(monday.AddDays(7)); ok {
		t.Fatal("next week has no frozen day")
	}
}

func TestComputeStreakBackdatedFillRescuesGap(t *testing.T) {
	today := monday.AddDays(6)
	gap, _ := build(monday, "xx..xx")
	if got := ComputeStreak(StreakInput{Days: gap, Today: today}).Count; got != 4 {
		t.Fatalf("with the gap frozen: count = %d, want 4", got)
	}
	filled, _ := build(monday, "xxxxxx")
	if got := ComputeStreak(StreakInput{Days: filled, Today: today}).Count; got != 6 {
		t.Fatalf("after the backdated fill: count = %d, want 6", got)
	}
}

func TestComputeStreakAcrossDSTTransitions(t *testing.T) {
	for _, start := range []Date{MustDate("2026-03-06"), MustDate("2026-11-01")} {
		days, _ := build(start, "xxxxx")
		if got := ComputeStreak(StreakInput{Days: days, Today: start.AddDays(5)}).Count; got != 5 {
			t.Fatalf("from %s: count = %d, want 5 across the clock change", start, got)
		}
	}
}

func TestComputeStreakIgnoresInputOrder(t *testing.T) {
	days, _ := build(monday, "xxxxx")
	days[0], days[4] = days[4], days[0]
	if got := ComputeStreak(StreakInput{Days: days, Today: monday.AddDays(3)}).Count; got != 4 {
		t.Fatalf("count = %d, want 4 (three past days and today counted)", got)
	}
}

func TestPendingDate(t *testing.T) {
	loc := mustLoc(t, "America/New_York")
	if got := PendingDate(time.Date(2026, 10, 30, 9, 59, 0, 0, loc), loc); got != MustDate("2026-10-29") {
		t.Fatalf("before the grace hour: %q", got)
	}
	if got := PendingDate(time.Date(2026, 10, 30, 10, 0, 0, 0, loc), loc); got != "" {
		t.Fatalf("at the grace hour: %q, want none", got)
	}
}

func TestSharedStreak(t *testing.T) {
	st := map[rune]DayOutcome{
		'x': {Status: StatusCounted, Counted: true}, 'f': {Status: StatusFrozen}, 'a': {Status: StatusAway},
		'A': {Status: StatusAway, Counted: true}, 'm': {Status: StatusMissed},
		'p': {Status: StatusPending}, 'o': {Status: StatusOpen},
	}
	people := func(a, b string) []map[Date]DayOutcome {
		out := []map[Date]DayOutcome{{}, {}}
		for i, c := range a {
			out[0][monday.AddDays(i)] = st[c]
		}
		for i, c := range b {
			out[1][monday.AddDays(i)] = st[c]
		}
		return out
	}
	tests := []struct {
		name         string
		a, b         string
		current, big int
	}{
		{name: "both counted", a: "xxx", b: "xxx", current: 3, big: 3},
		{name: "one frozen with the other counted", a: "xfx", b: "xxx", current: 3, big: 3},
		{name: "one away with the other counted", a: "xax", b: "xxx", current: 3, big: 3},
		{name: "a counted day while away still counts for the couple", a: "xAx", b: "xfx", current: 3, big: 3},
		{name: "both away adds nothing and breaks nothing", a: "xaax", b: "xaax", current: 2, big: 2},
		{name: "frozen and away adds nothing and breaks nothing", a: "xfx", b: "xax", current: 2, big: 2},
		{name: "one missed breaks it", a: "xxmx", b: "xxxx", current: 1, big: 2},
		{name: "both missed breaks it once", a: "xmx", b: "xmx", current: 1, big: 1},
		{name: "the partner still open is undecided", a: "xxx", b: "xxo", current: 2, big: 2},
		{name: "yesterday pending is undecided", a: "xxp", b: "xxx", current: 2, big: 2},
		{name: "a person with no entry for a day is undecided", a: "xxx", b: "xx", current: 2, big: 2},
		{name: "the best survives a break", a: "xxxxmx", b: "xxxxxx", current: 1, big: 4},
		{name: "no one counted", a: "aa", b: "ff", current: 0, big: 0},
	}
	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			n := max(len(tc.a), len(tc.b))
			got := SharedStreak(people(tc.a, tc.b), monday, monday.AddDays(n-1))
			if got.Current != tc.current || got.Best != tc.big {
				t.Fatalf("shared = %+v, want current %d best %d", got, tc.current, tc.big)
			}
		})
	}
	if got := SharedStreak(nil, monday, monday); got != (SharedResult{}) {
		t.Fatalf("nobody: %+v", got)
	}
}

func TestMilestonesReached(t *testing.T) {
	tests := map[int][]int{0: nil, 6: nil, 7: {7}, 13: {7}, 14: {7, 14}, 49: {7, 14, 30}, 50: {7, 14, 30, 50},
		365: {7, 14, 30, 50, 100, 200, 365}, 1000: {7, 14, 30, 50, 100, 200, 365}}
	for current, want := range tests {
		got := MilestonesReached(current)
		if len(got) != len(want) {
			t.Fatalf("%d: got %v, want %v", current, got, want)
		}
		for i := range want {
			if got[i] != want[i] {
				t.Fatalf("%d: got %v, want %v", current, got, want)
			}
		}
	}
}

func mustLoc(t *testing.T, name string) *time.Location {
	t.Helper()
	loc, err := time.LoadLocation(name)
	if err != nil {
		t.Fatalf("load %s: %v", name, err)
	}
	return loc
}
