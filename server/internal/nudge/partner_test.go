package nudge

import (
	"strings"
	"testing"
	"time"

	"github.com/nc1107/new-me/server/internal/together"
)

// thursday returns a Thursday at the given hour in UTC.
func thursday(hour int) time.Time { return time.Date(2026, 11, 5, hour, 0, 0, 0, time.UTC) }

func baseFacts() PartnerFacts {
	return PartnerFacts{Now: thursday(18), Prefs: PartnerPrefs{Cover: true, Nudges: true}, PartnerName: "Sam"}
}

func TestDecidePartnerPrioritisesCoverThenCheerThenCheckIn(t *testing.T) {
	f := baseFacts()
	f.CoverOpen, f.Freezes = true, 2
	f.Hard = &HardQuest{Key: "steps", Actual: 10432}
	f.Challenge = &ChallengeFacts{Kind: together.KindSteps, Progress: 10000, Target: 60000}
	n, ok := DecidePartner(f)
	if !ok || n.Kind != together.EventPartnerCover {
		t.Fatalf("first = %+v, want the cover chance", n)
	}
	f.CoverOpen = false
	if n, ok = DecidePartner(f); !ok || n.Kind != together.EventPartnerCheer {
		t.Fatalf("second = %+v, want the cheer prompt", n)
	}
	f.Cheered = true
	if n, ok = DecidePartner(f); !ok || n.Kind != together.EventPartnerChallenge {
		t.Fatalf("third = %+v, want the check-in", n)
	}
	f.Challenge = nil
	if _, ok = DecidePartner(f); ok {
		t.Fatal("nothing is due, yet a nudge came back")
	}
}

func TestDecidePartnerCoverNeedsAFreezeAndTheCoverSwitch(t *testing.T) {
	f := baseFacts()
	f.CoverOpen, f.Freezes = true, 0
	if _, ok := DecidePartner(f); ok {
		t.Error("no freeze held, no cover chance")
	}
	f.Freezes = 1
	f.Prefs.Cover = false
	if _, ok := DecidePartner(f); ok {
		t.Error("the cover switch is off")
	}
	f.Prefs = PartnerPrefs{Cover: true}
	if n, ok := DecidePartner(f); !ok || n.Kind != together.EventPartnerCover {
		t.Errorf("cover alone should be enough: %+v", n)
	}
}

func TestDecidePartnerCheerNeedsTheNudgeSwitchAndNoCheerYet(t *testing.T) {
	f := baseFacts()
	f.Hard = &HardQuest{Key: "pushups", Actual: 30}
	f.Prefs = PartnerPrefs{Cover: true}
	if _, ok := DecidePartner(f); ok {
		t.Error("partner nudges are off")
	}
	f.Prefs.Nudges = true
	f.Cheered = true
	if _, ok := DecidePartner(f); ok {
		t.Error("already cheered today")
	}
}

func TestCheckInIsThursdayEveningAndBehindTheEvenPace(t *testing.T) {
	check := func(now time.Time, progress, target int) bool {
		f := baseFacts()
		f.Now = now
		f.Challenge = &ChallengeFacts{Kind: together.KindWorkouts, Progress: progress, Target: target}
		_, ok := DecidePartner(f)
		return ok
	}
	if !check(thursday(17), 1, 5) {
		t.Error("Thursday 17:00, 1 of 5, should check in")
	}
	if check(thursday(16), 1, 5) {
		t.Error("too early on Thursday")
	}
	if check(thursday(18).AddDate(0, 0, 1), 1, 5) {
		t.Error("Friday is not check-in day")
	}
	if check(thursday(18), 3, 5) {
		t.Error("3 of 5 by Thursday is on pace (4/7 of 5 is 2.9)")
	}
	if !check(thursday(18), 2, 5) {
		t.Error("2 of 5 by Thursday is behind pace")
	}
	if check(thursday(18), 5, 5) {
		t.Error("a finished share needs no check-in")
	}
	if check(thursday(18), 0, 0) {
		t.Error("no share, no check-in")
	}
}

func TestDaysLeftCountsTodayToSunday(t *testing.T) {
	cases := map[time.Weekday]int{time.Monday: 7, time.Thursday: 4, time.Saturday: 2, time.Sunday: 1}
	for day, want := range cases {
		// 2026-11-02 is a Monday.
		now := time.Date(2026, 11, 2, 12, 0, 0, 0, time.UTC).AddDate(0, 0, (int(day)+6)%7)
		if got := daysLeft(now); got != want {
			t.Errorf("%s: %d days left, want %d", day, got, want)
		}
	}
}

func TestPartnerWordsFollowTheRules(t *testing.T) {
	long := strings.Repeat("N", 60)
	var all []string
	for _, name := range []string{"Sam", long} {
		for _, freezes := range []int{1, 2, 3} {
			all = append(all, CoverWords(name, freezes))
		}
		for _, q := range []HardQuest{{Key: "steps", Actual: 10432}, {Key: "pushups", Actual: 30}, {Key: "pushups", Actual: 30, Noun: "squats"}, {Key: "reading", Actual: 45}, {Key: "exercise", Actual: 50}, {Key: "other", Actual: 1}} {
			all = append(all, CheerWords(name, q))
		}
	}
	for _, kind := range together.AllKinds() {
		for _, left := range []int{1, 3, 12000} {
			for _, days := range []int{1, 4} {
				all = append(all, CheckInWords(kind, left, days))
			}
		}
	}
	for _, text := range all {
		if !together.WordsOK(text) {
			t.Errorf("%q breaks the wording rules", text)
		}
	}
}

func TestPartnerWordsNeverReportTheirFailure(t *testing.T) {
	banned := []string{"miss", "fail", "behind", "lost", "broke", "skipped", "didn't", "did not"}
	cover := CoverWords("Sam", 1)
	cheer := CheerWords("Sam", HardQuest{Key: "steps", Actual: 9000})
	for _, text := range []string{cover, cheer, CheckInWords(together.KindSteps, 9000, 4)} {
		for _, word := range banned {
			if strings.Contains(strings.ToLower(text), word) {
				t.Errorf("%q mentions %q", text, word)
			}
		}
	}
}

func TestPartnerWordsCarryOnlyComputedFigures(t *testing.T) {
	cases := []struct{ got, want string }{
		{CoverWords("Sam", 1), "You hold 1 freeze. It could keep Sam's streak going."},
		{CoverWords("Sam", 2), "You hold 2 freezes. One could keep Sam's streak going."},
		{CheerWords("Sam", HardQuest{Key: "steps", Actual: 10432}), "Sam did 10,432 steps today. A cheer is one tap away."},
		{CheerWords("Sam", HardQuest{Key: "pushups", Actual: 30}), "Sam did 30 push-ups today. A cheer is one tap away."},
		{CheckInWords(together.KindSteps, 12000, 4), "12,000 steps left on your share, with 4 days to go."},
		{CheckInWords(together.KindSleepNights, 1, 1), "1 night left on your share, with 1 day to go."},
	}
	for _, tc := range cases {
		if tc.got != tc.want {
			t.Errorf("got %q, want %q", tc.got, tc.want)
		}
	}
}

func TestPartnerKindsCountAgainstTheSeparateBudget(t *testing.T) {
	if together.PartnerBudget != 1 {
		t.Fatalf("partner budget = %d, the design says one a day", together.PartnerBudget)
	}
	for _, kind := range []string{together.EventPartnerCover, together.EventPartnerCheer, together.EventPartnerChallenge} {
		for _, auto := range together.AutoKinds {
			if kind == auto {
				t.Errorf("%s must not share the automatic push budget", kind)
			}
		}
	}
}
