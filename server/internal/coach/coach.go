// Package coach gathers the facts about a person's day, once, for everything that talks about
// it: the readiness and plan on Today and the nudges the scheduler pushes. The rules
// themselves live in the pure readiness, plan and nudge packages.
package coach

import (
	"context"
	"strconv"
	"strings"
	"time"

	"github.com/nc1107/new-me/server/internal/db"
	"github.com/nc1107/new-me/server/internal/engine"
	"github.com/nc1107/new-me/server/internal/insights"
	"github.com/nc1107/new-me/server/internal/plan"
	"github.com/nc1107/new-me/server/internal/readiness"
	"github.com/nc1107/new-me/server/internal/score"
)

const (
	// DefaultSleepTargetMin applies while the sleep quest is off.
	DefaultSleepTargetMin = engine.DefaultSleepTargetMin
	// minSleepNights is how many recorded nights a bedtime or wake time estimate needs.
	minSleepNights = 4
)

// Day is everything known about one person's day at one moment.
type Day struct {
	Readiness *readiness.Result
	Plan      plan.Plan
	Quests    []plan.Quest
	Habits    []plan.Habit

	// StepsUsual is the median of the last 14 days of steps, or 0 without enough history.
	StepsUsual float64
	// StepsGoal is the steps quest target, or 0 when the quest is not on today.
	StepsGoal int
	// Steps is today's count so far and StepsTracked whether Health has reported steps today.
	Steps        float64
	StepsTracked bool

	SleepTargetMin int
	// AvgWakeMin is the average wake time as minutes after midnight, nil without enough nights.
	AvgWakeMin *int
	// LastNightMin is minutes asleep for the night ending this morning, nil if unrecorded.
	LastNightMin *int
	SleepTracked bool
	// SleepQuest is whether the sleep quest is enabled.
	SleepQuest bool

	// Base, Max and Counted summarize the day's score.
	Base, Max int
	Counted   bool
	QuestRows []QuestScore
}

// QuestScore is a quest with the points it is worth and has earned.
type QuestScore struct {
	Quest  plan.Quest
	Points int
	Base   int
}

// Load assembles the day for the person's local today.
func Load(ctx context.Context, q db.Querier, user db.User, loc *time.Location, scored engine.Scored,
	habits []db.HabitState, now time.Time) (Day, error) {
	today := score.LocalToday(now, loc)
	var d Day
	earned := map[string]score.QuestScore{}
	for _, qs := range scored.Score.Quests {
		earned[qs.Key] = qs
	}
	for _, dq := range scored.Quests {
		qs, scoredToday := earned[dq.Key]
		if !scoredToday {
			continue
		}
		actual, alt := engine.Actuals(dq, scored.Inputs)
		pq := plan.Quest{Key: dq.Key, Exercise: dq.Exercise, Target: dq.Target, Actual: actual, TargetAlt: dq.TargetAlt, ActualAlt: alt, Done: qs.Complete}
		if qs.Complete {
			pq.DoneBy = engine.DoneBy(dq, scored.Inputs)
		}
		d.Quests = append(d.Quests, pq)
		d.QuestRows = append(d.QuestRows, QuestScore{Quest: pq, Points: dq.Points, Base: qs.Base})
		if dq.Key == db.QuestSteps {
			d.StepsGoal = dq.Target
		}
	}
	d.Base, d.Max, d.Counted = scored.Score.BasePoints, scored.Score.MaxBase, scored.Score.Counted
	d.Steps = scored.Inputs.Metric(db.MetricSteps)
	// A nudge about steps needs today's reading: without one the Health sync is simply behind.
	_, d.StepsTracked = scored.Inputs.Metrics[db.MetricSteps]
	for _, st := range habits {
		d.Habits = append(d.Habits, planHabit(st))
	}

	templates, err := db.GetQuestTemplates(ctx, q, user.ID)
	if err != nil {
		return d, err
	}
	d.SleepTargetMin = DefaultSleepTargetMin
	for _, t := range templates {
		if t.Key == db.QuestSleep {
			d.SleepQuest = t.Enabled
			if t.Enabled {
				d.SleepTargetMin = t.Target
			}
		}
	}
	if err := d.loadHistory(ctx, q, user, loc, scored, today); err != nil {
		return d, err
	}
	d.Plan = plan.Build(plan.Input{Quests: d.Quests, Habits: d.Habits, NowMinute: minuteOfDay(now, loc)})
	return d, nil
}

func (d *Day) loadHistory(ctx context.Context, q db.Querier, user db.User, loc *time.Location,
	scored engine.Scored, today score.Date) error {
	stepPoints, err := db.HealthSeries(ctx, q, user.ID, db.MetricSteps, today.AddDays(-29), today)
	if err != nil {
		return err
	}
	days := make([]insights.StepDay, len(stepPoints))
	for i, p := range stepPoints {
		days[i] = insights.StepDay{Date: p.Date, Steps: p.Value}
	}
	steps := insights.ComputeSteps(insights.StepInput{Days: days, Today: today, Goal: d.StepsGoal, BirthYear: user.BirthYear})
	if steps.Suggestion != nil {
		d.StepsUsual = float64(steps.Median14)
	}

	stored, err := db.ListSleepNights(ctx, q, user.ID, today.AddDays(-13), today)
	if err != nil {
		return err
	}
	nights := make([]insights.Night, len(stored))
	for i, n := range stored {
		nights[i] = insights.Night{Date: n.Date, BedAt: n.BedAt, WakeAt: n.WakeAt, AsleepMin: n.AsleepMin}
		if n.Date == today && n.AsleepMin > 0 {
			asleep := n.AsleepMin
			d.LastNightMin = &asleep
		}
	}
	sleep := insights.ComputeSleep(insights.SleepInput{Nights: nights, Today: today, TargetMin: d.SleepTargetMin, Loc: loc})
	d.SleepTracked = len(sleep.Nights) >= minSleepNights
	if d.SleepTracked && sleep.AvgWake != nil {
		if m, ok := clockMinutes(*sleep.AvgWake); ok {
			d.AvgWakeMin = &m
		}
	}
	if d.LastNightMin == nil {
		if m := int(scored.Inputs.Metric(db.MetricSleep)); m > 0 {
			d.LastNightMin = &m
		}
	}

	d.Readiness, err = engine.ReadinessFor(ctx, q, user.ID, today, d.LastNightMin, d.SleepTargetMin, scored.Inputs.Metrics)
	return err
}

func planHabit(st db.HabitState) plan.Habit {
	h := plan.Habit{ID: st.Habit.ID, Name: st.Habit.Name, Check: st.Habit.Kind == db.HabitCheck, Count: st.Count}
	if st.Habit.Target != nil {
		h.Target = *st.Habit.Target
	}
	for i, slot := range st.Habit.Slots {
		h.Slots = append(h.Slots, plan.Slot{Label: slot.Label, Time: slot.Time, Done: i < len(st.Done) && st.Done[i]})
	}
	return h
}

func minuteOfDay(t time.Time, loc *time.Location) int {
	local := t.In(loc)
	return local.Hour()*60 + local.Minute()
}

func clockMinutes(hhmm string) (int, bool) {
	h, m, ok := strings.Cut(hhmm, ":")
	if !ok {
		return 0, false
	}
	hours, errH := strconv.Atoi(h)
	minutes, errM := strconv.Atoi(m)
	if errH != nil || errM != nil {
		return 0, false
	}
	return hours*60 + minutes, true
}
