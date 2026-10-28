package nudge

import (
	"fmt"
	"time"

	"github.com/nc1107/new-me/server/internal/together"
)

// Partner nudges are gentle prompts about the other person, one at most per person per day on a
// budget of their own (together.PartnerBudget). Their words carry only computed figures, never
// say the partner failed, and keep to together.WordsOK. In order of priority:
//
//	cover chance       the partner missed yesterday, can still be covered, has no freeze of their
//	                   own, and you hold one
//	cheer prompt       the partner finished a hard quest (worth 100 points) today and you have
//	                   not cheered them yet
//	challenge check-in on Thursday from 17:00, your share of the weekly challenge is behind the
//	                   even pace of four days out of seven
//
// Reward progress is sent through together.Service.NotifyRewardProgress.

const (
	// HardQuestPoints is what a quest is worth for a finish to count as hard.
	HardQuestPoints = 100

	checkInWeekday = time.Thursday
	checkInFrom    = 17 * 60
	// evenPaceDays is how many of the week's days are done by the end of Thursday.
	evenPaceDays = 4
)

// PartnerPrefs are the switches partner nudges read: Cover for the cover chance, Nudges for the
// rest.
type PartnerPrefs struct {
	Cover, Nudges bool
}

// HardQuest is a hard quest the partner finished today.
type HardQuest struct {
	Key    string
	Actual int
}

// ChallengeFacts is the person's own standing in the week's challenge.
type ChallengeFacts struct {
	Kind     string
	Progress int
	Target   int
}

// PartnerFacts is everything DecidePartner reads.
type PartnerFacts struct {
	// Now is the current instant in the person's own zone.
	Now         time.Time
	Prefs       PartnerPrefs
	PartnerName string

	// CoverOpen is whether the partner's yesterday can be covered by this person, and Freezes
	// how many freezes they hold.
	CoverOpen bool
	Freezes   int

	// Hard is the partner's hard finished quest today, nil when there is none, and Cheered
	// whether this person already cheered them today.
	Hard    *HardQuest
	Cheered bool

	// Challenge is the person's standing, nil when the week has no challenge for them.
	Challenge *ChallengeFacts
}

// PartnerNudge is the push chosen by DecidePartner.
type PartnerNudge struct {
	Kind  string
	Title string
	Body  string
}

// DecidePartner returns the one partner nudge due now, if any.
func DecidePartner(f PartnerFacts) (PartnerNudge, bool) {
	switch {
	case f.Prefs.Cover && f.CoverOpen && f.Freezes > 0:
		return PartnerNudge{Kind: together.EventPartnerCover, Title: "A chance to help", Body: CoverWords(f.PartnerName, f.Freezes)}, true
	case f.Prefs.Nudges && f.Hard != nil && !f.Cheered:
		return PartnerNudge{Kind: together.EventPartnerCheer, Title: "Worth a cheer", Body: CheerWords(f.PartnerName, *f.Hard)}, true
	case f.Prefs.Nudges && checkInDue(f):
		c := f.Challenge
		return PartnerNudge{Kind: together.EventPartnerChallenge, Title: "Weekly challenge",
			Body: CheckInWords(c.Kind, c.Target-c.Progress, daysLeft(f.Now))}, true
	}
	return PartnerNudge{}, false
}

func checkInDue(f PartnerFacts) bool {
	c := f.Challenge
	if c == nil || c.Target <= 0 || c.Progress >= c.Target || f.Now.Weekday() != checkInWeekday {
		return false
	}
	if f.Now.Hour()*60+f.Now.Minute() < checkInFrom {
		return false
	}
	return c.Progress*7 < c.Target*evenPaceDays
}

// daysLeft counts the days of the week still ahead, today included, on a Monday-to-Sunday week.
func daysLeft(now time.Time) int {
	return int(time.Sunday-now.Weekday()+7)%7 + 1
}

// CoverWords words the cover chance with the number of freezes held.
func CoverWords(partner string, freezes int) string {
	hold := fmt.Sprintf("You hold %d freezes.", freezes)
	one := "One could"
	if freezes == 1 {
		hold, one = "You hold 1 freeze.", "It could"
	}
	return together.Fit(fmt.Sprintf("%s %s keep %s's streak going.", hold, one, partner),
		fmt.Sprintf("%s %s keep a streak going.", hold, one))
}

// CheerWords words the cheer prompt with what the partner did.
func CheerWords(partner string, q HardQuest) string {
	return together.Fit(fmt.Sprintf("%s did %s today. A cheer is one tap away.", partner, questFigure(q)),
		"A big quest got done today. A cheer is one tap away.")
}

func questFigure(q HardQuest) string {
	switch q.Key {
	case "steps":
		return fmt.Sprintf("%s steps", thousands(q.Actual))
	case "pushups":
		return fmt.Sprintf("%d push-ups", q.Actual)
	case "reading":
		return fmt.Sprintf("%d minutes of reading", q.Actual)
	case "exercise":
		return fmt.Sprintf("%d active minutes", q.Actual)
	}
	return "a big quest"
}

// CheckInWords words the Thursday check-in with what is left on the person's share.
func CheckInWords(kind string, left, days int) string {
	dayText := fmt.Sprintf("%d days to go", days)
	if days == 1 {
		dayText = "1 day to go"
	}
	return together.Fit(fmt.Sprintf("%s left on your share, with %s.", together.Phrase(kind, left), dayText),
		fmt.Sprintf("%d left on your share, with %s.", left, dayText))
}

func thousands(n int) string {
	s := fmt.Sprintf("%d", n)
	for i := len(s) - 3; i > 0; i -= 3 {
		s = s[:i] + "," + s[i:]
	}
	return s
}
