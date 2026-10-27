package score

import "time"

// Status is what one local day did to a streak.
type Status string

const (
	// StatusCounted is a day that reached the counted line and added a day to the streak.
	StatusCounted Status = "counted"
	// StatusFrozen is a missed day that was forgiven. It keeps the streak and adds no day.
	StatusFrozen Status = "frozen"
	// StatusAway is a day inside an away span. It neither breaks nor extends a streak.
	StatusAway Status = "away"
	// StatusMissed broke the streak.
	StatusMissed Status = "missed"
	// StatusPending is yesterday while its grace window is open: it can still be filled in.
	StatusPending Status = "pending"
	// StatusOpen is today before it has counted.
	StatusOpen Status = "open"
)

// Why a day was frozen.
const (
	// ReasonFreeze is a freeze spent automatically when the day finalized.
	ReasonFreeze = "freeze"
	// ReasonReadiness is a rest day after an easy readiness morning; it spends no freeze.
	ReasonReadiness = "readiness"
	// ReasonRepair is a missed day repaired by reaching 100% the next day.
	ReasonRepair = "repair"
	// ReasonCover is a missed day covered by a freeze of the partner.
	ReasonCover = "cover"
	// ReasonRest is a weekly rest day of the rule that applied before freezes. It is derived,
	// never stored, and only appears on days finalized before the rule changed.
	ReasonRest = "rest"
)

const (
	// StartingFreezes is how many freezes a person starts with.
	StartingFreezes = 2
	// MaxFreezes is how many freezes can be held at once.
	MaxFreezes = 2
	// CountedDaysPerFreeze is how many counted days earn one more freeze.
	CountedDaysPerFreeze = 7
)

// DayFlag is what is known about one local day when the streak is derived.
type DayFlag struct {
	Date    Date
	Counted bool
	// Settled says the day finalized under the freeze rules, so FrozenReason and Away below are
	// the recorded outcome and a miss with no reason is a recorded break.
	Settled bool
	// FrozenReason is why the day was frozen, or "" when it was not.
	FrozenReason string
	// Away is whether the day is inside an away span.
	Away bool
	// Covered is whether the partner has spent a freeze on the day.
	Covered bool
}

// Freezes is a person's freeze balance.
type Freezes struct {
	Held int `json:"held"`
	// EarnedTowardNext is how many counted days of the 7 needed for the next freeze are done.
	// It waits at 6 while the person already holds the maximum.
	EarnedTowardNext int `json:"earnedTowardNext"`
}

// DayOutcome is how one day entered the streak.
type DayOutcome struct {
	Status Status
	// Reason is the FrozenReason of a frozen day.
	Reason string
	// Counted is whether the day reached the counted line, whatever else it was.
	Counted bool
	// Decided is true when the derivation chose this outcome because the day had none recorded
	// yet. Settling stores exactly these decisions.
	Decided bool
}

// StreakInput is everything the streak is derived from.
type StreakInput struct {
	// Days holds the flags of the person's days; a date with no entry is an unscored miss.
	Days  []DayFlag
	Today Date
	// PendingDate is yesterday while its grace window is open, and "" otherwise.
	PendingDate Date
	// RulesFrom is the first date the freeze rules apply to; "" means every day. Earlier days
	// follow the weekly rest rule they were finalized under.
	RulesFrom Date
	// Spends are the dates on which this person's own freeze covered the partner.
	Spends []Date
	// Easy marks the days whose readiness morning was easy, which only matters for a missed
	// day that is being decided now.
	Easy map[Date]bool
}

// StreakResult is the derived streak.
type StreakResult struct {
	Count   int
	Best    int
	Freezes Freezes
	// Days holds an outcome for every date from the first day through today.
	Days map[Date]DayOutcome
	// First is the earliest date given.
	First Date
}

// Outcome is the day's outcome, or an open one for a date the streak never saw.
func (r StreakResult) Outcome(d Date) DayOutcome {
	if o, ok := r.Days[d]; ok {
		return o
	}
	return DayOutcome{Status: StatusOpen}
}

// LastFrozenIn returns the latest frozen day in the ISO week starting on weekStart.
func (r StreakResult) LastFrozenIn(weekStart Date) (Date, bool) {
	var last Date
	for d := weekStart; d.Before(weekStart.AddDays(7)); d = d.AddDays(1) {
		if r.Days[d].Status == StatusFrozen {
			last = d
		}
	}
	return last, last != ""
}

// PendingDate is yesterday while its grace window is open, and "" once it has closed.
func PendingDate(now time.Time, loc *time.Location) Date {
	if _, open := BackdateUntil(now, loc); !open {
		return ""
	}
	return LocalToday(now, loc).AddDays(-1)
}

// ComputeStreak derives the streak by walking the days from the first one through today.
//
// Under the freeze rules a counted day adds one, an away day changes nothing, and a missed day
// is forgiven while a freeze is held: it is frozen, keeps the streak and adds no day. With none
// held, a day covered by the partner, repaired, or rested after an easy readiness morning is
// still forgiven, and any other miss resets the streak. A person starts with two freezes and
// earns one for every seven counted days, never holding more than two. A day recorded by an
// earlier derivation is trusted over what the balance would decide now. Yesterday while its
// grace window is open, and today until it counts, change nothing yet.
//
// Days before RulesFrom follow the weekly rest rule they were finalized under: one miss a week
// is forgiven while a streak runs, never right after another miss.
func ComputeStreak(in StreakInput) StreakResult {
	byDate := make(map[Date]DayFlag, len(in.Days))
	var first Date
	for _, d := range in.Days {
		byDate[d.Date] = d
		if first == "" || d.Date.Before(first) {
			first = d.Date
		}
	}
	res := StreakResult{Days: map[Date]DayOutcome{}, Freezes: Freezes{Held: StartingFreezes}, First: first}
	if first == "" {
		return res
	}
	rulesFrom := in.RulesFrom
	if rulesFrom == "" || rulesFrom.Before(first) {
		rulesFrom = first
	}
	spent := make(map[Date]bool, len(in.Spends))
	for _, d := range in.Spends {
		spent[d] = true
	}

	w := walker{res: &res, today: in.Today}
	date := first
	for ; date.Before(rulesFrom) && date.Before(in.Today); date = date.AddDays(1) {
		f := byDate[date]
		f.Date = date
		w.legacyDay(f, in.PendingDate)
	}
	w.held, w.toward = StartingFreezes, 0
	for ; !date.After(in.Today); date = date.AddDays(1) {
		w.day(byDate[date], date, in)
		if spent[date] {
			w.held = max(w.held-1, 0)
		}
	}
	res.Freezes = Freezes{Held: w.held, EarnedTowardNext: w.toward}
	return res
}

// walker is the running state of one derivation.
type walker struct {
	res   *StreakResult
	today Date

	held, toward int

	// The weekly rest rule's state, used only before the freeze rules begin.
	restWeeks      map[Date]bool
	previousMissed bool
}

func (w *walker) add(d Date, o DayOutcome) { w.res.Days[d] = o }

func (w *walker) extend() {
	w.res.Count++
	w.res.Best = max(w.res.Best, w.res.Count)
}

// legacyDay applies the weekly rest rule to a day finalized before freezes existed.
func (w *walker) legacyDay(f DayFlag, pending Date) {
	if w.restWeeks == nil {
		w.restWeeks = map[Date]bool{}
	}
	switch {
	case f.Counted:
		w.extend()
		w.previousMissed = false
		w.add(f.Date, DayOutcome{Status: StatusCounted, Counted: true})
	case f.Date == pending:
		w.add(f.Date, DayOutcome{Status: StatusPending})
	default:
		week := WeekStart(f.Date)
		if w.res.Count > 0 && !w.restWeeks[week] && !w.previousMissed {
			w.restWeeks[week] = true
			w.add(f.Date, DayOutcome{Status: StatusFrozen, Reason: ReasonRest})
		} else {
			w.res.Count = 0
			w.add(f.Date, DayOutcome{Status: StatusMissed})
		}
		w.previousMissed = true
	}
}

// day applies the freeze rules to one day.
func (w *walker) day(f DayFlag, date Date, in StreakInput) {
	f.Date = date
	switch {
	case f.Away:
		w.add(date, DayOutcome{Status: StatusAway, Counted: f.Counted})
	case f.Counted:
		w.extend()
		w.earn()
		w.add(date, DayOutcome{Status: StatusCounted, Counted: true})
	case date == in.Today:
		w.add(date, DayOutcome{Status: StatusOpen})
	case f.Covered && !f.Settled && f.FrozenReason == "":
		w.add(date, DayOutcome{Status: StatusFrozen, Reason: ReasonCover, Decided: true})
	case date == in.PendingDate && !f.Settled:
		w.add(date, DayOutcome{Status: StatusPending})
	case f.FrozenReason != "":
		if f.FrozenReason == ReasonFreeze {
			w.held = max(w.held-1, 0)
		}
		w.add(date, DayOutcome{Status: StatusFrozen, Reason: f.FrozenReason})
	case f.Settled:
		w.res.Count = 0
		w.add(date, DayOutcome{Status: StatusMissed})
	case in.Easy[date]:
		w.add(date, DayOutcome{Status: StatusFrozen, Reason: ReasonReadiness, Decided: true})
	case w.held > 0 && w.res.Count > 0:
		w.held--
		w.add(date, DayOutcome{Status: StatusFrozen, Reason: ReasonFreeze, Decided: true})
	default:
		w.res.Count = 0
		w.add(date, DayOutcome{Status: StatusMissed, Decided: true})
	}
}

// earn moves a counted day toward the next freeze. At the maximum the progress waits one day
// short, so the next freeze arrives with the first counted day after one is spent.
func (w *walker) earn() {
	w.toward++
	if w.toward < CountedDaysPerFreeze {
		return
	}
	if w.held < MaxFreezes {
		w.held++
		w.toward = 0
		return
	}
	w.toward = CountedDaysPerFreeze - 1
}

// SharedResult is the couple's streak.
type SharedResult struct {
	Current int
	Best    int
}

// SharedStreak derives the couple streak from each person's day outcomes, over the dates from
// `from` (the later join date) through today. A day adds one when everyone counted, was frozen
// or was away, and at least one of them counted. A day on which anyone missed resets it. A day
// still undecided for anyone, and a day nobody counted, change nothing.
func SharedStreak(people []map[Date]DayOutcome, from, today Date) SharedResult {
	var res SharedResult
	if len(people) == 0 {
		return res
	}
	for d := from; !d.After(today); d = d.AddDays(1) {
		missed, undecided, counted := false, false, false
		for _, days := range people {
			o, ok := days[d]
			switch {
			case !ok, o.Status == StatusPending, o.Status == StatusOpen:
				undecided = true
			case o.Status == StatusMissed:
				missed = true
			}
			counted = counted || o.Counted
		}
		switch {
		case missed:
			res.Current = 0
		case undecided:
		case counted:
			res.Current++
			res.Best = max(res.Best, res.Current)
		}
	}
	return res
}
