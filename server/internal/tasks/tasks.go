// Package tasks holds the pure rules of agreed tasks: a chore worth gems that its assignee earns
// by finishing before the deadline, and loses by missing it only if they chose to. See
// docs/design-v21-tasks.md.
package tasks

import "github.com/nc1107/new-me/server/internal/score"

// Task statuses. Proposed, declined and agreed are open; done, missed and withdrawn are final.
const (
	Proposed  = "proposed"
	Declined  = "declined"
	Agreed    = "agreed"
	Done      = "done"
	Missed    = "missed"
	Withdrawn = "withdrawn"
)

const (
	// MaxStake is the most a task may put at risk, the same ceiling as a reward price.
	MaxStake = 100000
	// MaxTitle is the longest task title, in characters.
	MaxTitle = 60
	// MaxOpenPerPerson caps the open tasks one person has created.
	MaxOpenPerPerson = 30
	// MaxDaysAhead is how far in the future a deadline may be.
	MaxDaysAhead = 366
	// HistoryLimit is how many finished tasks the list returns.
	HistoryLimit = 50
)

// Overdue reports whether the deadline day has fully passed on the assignee's calendar: a task
// due Tuesday is still on time at 23:59 Tuesday and missed from Wednesday 00:00.
func Overdue(deadline, today score.Date) bool { return today.After(deadline) }

// Verdict is what settling does with an open task on the assignee's current day.
type Verdict int

const (
	// Keep leaves the task as it is.
	Keep Verdict = iota
	// MarkMissed turns an agreed task whose deadline passed into a missed one.
	MarkMissed
	// Lapse withdraws a proposal nobody agreed to before its deadline; no gems move.
	Lapse
)

// Judge decides what settling does with a task on the assignee's day. Only an agreed task can
// be missed, so a proposal that goes stale is dropped.
func Judge(status string, deadline, today score.Date) Verdict {
	if !Overdue(deadline, today) {
		return Keep
	}
	switch status {
	case Agreed:
		return MarkMissed
	case Proposed, Declined:
		return Lapse
	}
	return Keep
}

// CanFinish reports whether an agreed task can still be marked done on the assignee's day.
func CanFinish(status string, deadline, today score.Date) bool {
	return status == Agreed && !Overdue(deadline, today)
}

// CanAnswer reports whether the other person can still agree: a proposal whose deadline has
// passed is moot.
func CanAnswer(status string, deadline, today score.Date) bool {
	return status == Proposed && !Overdue(deadline, today)
}
