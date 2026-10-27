// Package goals proposes updated targets from what the person has actually been doing. It is
// pure: the caller passes the current target and the recent numbers.
//
// Rules:
//
//	steps  the insights suggestion for the last 14 days, when it differs from the goal by at least 500;
//	       a raise also needs the goal met on at least 10 of those 14 days, lowering is always allowed
//	exercise, sleep  a quest that is off is offered once, with its default target, unless the person
//	       dismissed the offer in the last four weeks
//	protein  when the current target is 20% or more away from 1.6 g/kg of the latest weight
//	sleep  when the 14-night average is 45 minutes or more under the target (and at least 5 nights
//	       are recorded), the target moves halfway toward the average, rounded to 15 minutes and
//	       never below 5 h
package goals

import (
	"fmt"
	"math"

	"github.com/nc1107/new-me/server/internal/insights"
	"github.com/nc1107/new-me/server/internal/plan"
	"github.com/nc1107/new-me/server/internal/readiness"
	"github.com/nc1107/new-me/server/internal/score"
)

// Thresholds.
const (
	// MinStepsChange is the smallest difference worth proposing for steps.
	MinStepsChange = 500
	// SleepGapMin is how far under its target the sleep average must be before a change is proposed.
	SleepGapMin = 45
	// RaiseMinDaysMet is on how many of the last 14 days the goal must have been met before a
	// proposal may raise it.
	RaiseMinDaysMet = 10
	// MinSleepNights is how many of the last 14 nights the sleep rule needs.
	MinSleepNights = 5
	// SleepFloorMin is the lowest sleep target ever proposed.
	SleepFloorMin = 300
	sleepRound    = 15
)

// Proposal kinds: a new target for a quest that is on, or switching a quest on.
const (
	KindTarget = "target"
	KindEnable = "enable"
)

// EnableDismissedDays is how long a dismissed offer to switch a quest on stays quiet.
const EnableDismissedDays = 28

// Proposal is one suggested target with its reason.
type Proposal struct {
	Key      string
	Kind     string
	Current  int
	Proposed int
	Reason   string
}

// Steps proposes the insights step suggestion when it meaningfully differs from the goal. daysMet
// is how many of the last 14 days reached the goal.
func Steps(goal int, suggestion *insights.Suggestion, daysMet int) *Proposal {
	if goal <= 0 || suggestion == nil {
		return nil
	}
	diff := suggestion.Target - goal
	if diff < MinStepsChange && diff > -MinStepsChange {
		return nil
	}
	if diff > 0 && daysMet < RaiseMinDaysMet {
		return nil
	}
	usual := plan.Thousands(suggestion.Median14)
	reason := fmt.Sprintf("You usually walk about %s steps a day. %s is a reachable step up.", usual, plan.Thousands(suggestion.Target))
	if diff < 0 {
		reason = fmt.Sprintf("You usually walk about %s steps a day. %s is a goal you can keep for now.", usual, plan.Thousands(suggestion.Target))
	}
	return &Proposal{Key: "steps", Kind: KindTarget, Current: goal, Proposed: suggestion.Target, Reason: reason}
}

// Sleep proposes a more realistic target when the person has been well under the current one.
func Sleep(target int, asleep []int) *Proposal {
	if target <= 0 || len(asleep) < MinSleepNights {
		return nil
	}
	sum := 0
	for _, m := range asleep {
		sum += m
	}
	avg := int(math.Round(float64(sum) / float64(len(asleep))))
	gap := target - avg
	if gap < SleepGapMin {
		return nil
	}
	proposed := int(math.Round((float64(avg)+float64(gap)/2)/sleepRound)) * sleepRound
	proposed = max(proposed, SleepFloorMin, avg)
	if proposed >= target {
		return nil
	}
	return &Proposal{Key: "sleep", Kind: KindTarget, Current: target, Proposed: proposed, Reason: fmt.Sprintf(
		"You averaged %s over the last %d nights, %s under your %s target. %s is a step toward it.",
		readiness.Duration(avg), len(asleep), readiness.Duration(gap), readiness.Duration(target), readiness.Duration(proposed))}
}

// Enable offers to switch a Health-fed quest on, keeping its current target. The quest only
// scores once its data arrives, so switching it on costs nothing before then.
func Enable(key string, target int) *Proposal {
	var reason string
	switch key {
	case "sleep":
		reason = fmt.Sprintf("A sleep quest of %s a night is scored from Apple Health and shows how rest drives the rest of your day.", readiness.Duration(target))
	case "exercise":
		reason = fmt.Sprintf("An exercise quest of %d minutes a day keeps training steady. It counts Health's exercise minutes and anything you log by hand.", target)
	default:
		return nil
	}
	return &Proposal{Key: key, Kind: KindEnable, Current: target, Proposed: target, Reason: reason}
}

// Protein proposes the per-kilogram target when the current one is 20% or more away from it.
func Protein(current int, weightKg float64) *Proposal {
	suggested := score.ProteinTarget(weightKg)
	if current <= 0 || suggested <= 0 || !score.ProteinOff(current, suggested) {
		return nil
	}
	return &Proposal{Key: "protein", Kind: KindTarget, Current: current, Proposed: suggested, Reason: fmt.Sprintf(
		"At %.1f kg, %.1f g per kilogram is %d g of protein a day. Your target is %d g.",
		weightKg, score.ProteinPerKg, suggested, current)}
}
