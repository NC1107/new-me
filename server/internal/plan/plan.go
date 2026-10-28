// Package plan builds the short, deterministic plan for a day from the quests and habits. It
// is pure: the caller passes the facts and the minute of the day, and the same facts always
// give the same words. Claude may reword the summary later, but never adds to these facts.
package plan

import (
	"fmt"
	"sort"
	"strconv"
	"strings"

	"github.com/nc1107/new-me/server/internal/db"
	"github.com/nc1107/new-me/server/internal/score"
)

const (
	// StepsPerMinute is the walking pace used to turn steps into minutes.
	StepsPerMinute = 100
	// walkRound is the granularity walking minutes are rounded to.
	walkRound = 5
	// longWalkMin is the walk length past which the plan suggests splitting it.
	longWalkMin = 60
	// maxHabitItems keeps the plan short on a day with many habits.
	maxHabitItems = 5
)

// Item kinds.
const (
	KindDone  = "done"
	KindTodo  = "todo"
	KindHabit = "habit"
)

// Quest is one quest of the day as the plan reads it.
type Quest struct {
	Key       string
	Target    int
	Actual    int
	TargetAlt *int
	ActualAlt *int
	Done      bool
	DoneBy    *score.DoneBy
}

// Slot is one time of day a check habit is done.
type Slot struct {
	Label string
	Time  *string
	Done  bool
}

// Habit is a habit due today. Check habits carry slots; count habits a target and count.
type Habit struct {
	ID     int64
	Name   string
	Check  bool
	Slots  []Slot
	Target int
	Count  int
}

// Input is everything the plan reads. NowMinute is the minute of the person's local day.
type Input struct {
	Quests    []Quest
	Habits    []Habit
	NowMinute int
}

// Item is one line of the plan.
type Item struct {
	Kind string `json:"kind"`
	// Key is the quest key, or "habit:<id>" for a habit.
	Key  string `json:"key"`
	Text string `json:"text"`
}

// Plan is the day's items and a one-paragraph summary.
type Plan struct {
	Items   []Item `json:"items"`
	Summary string `json:"summary"`
}

// Build writes the plan.
func Build(in Input) Plan {
	var done, todo []Item
	var next []candidate
	for _, q := range in.Quests {
		if q.Done {
			done = append(done, Item{KindDone, q.Key, doneText(q)})
			continue
		}
		if c, ok := finishing(q, in.NowMinute); ok {
			todo = append(todo, Item{KindTodo, q.Key, c.text})
			next = append(next, c)
		}
	}
	habits := habitItems(in.Habits)
	items := append(append(done, todo...), habits...)
	if items == nil {
		items = []Item{}
	}
	return Plan{Items: items, Summary: summary(in, len(done), next, habits)}
}

type candidate struct {
	text string
	// short finishes the sentence "<short> finishes your day".
	short string
	// remaining is the unfinished fraction in thousandths, so the closest quest sorts first.
	remaining int
}

// finishing words what is left of an unfinished quest and the easiest way to close it. Sleep
// has no suggestion because last night cannot be changed, and unknown quests are left out.
func finishing(q Quest, nowMinute int) (candidate, bool) {
	left := max(q.Target-q.Actual, 0)
	frac := 0
	if q.Target > 0 {
		frac = left * 1000 / q.Target
	}
	switch q.Key {
	case db.QuestSteps:
		walk := walkMinutes(left)
		text := fmt.Sprintf("Steps: %s to go. %s", Thousands(left), walkAdvice(walk, nowMinute))
		return candidate{text, Thousands(left) + " more steps", frac}, true
	case db.QuestPushups:
		return candidate{fmt.Sprintf("Push-ups: %d more %s finishes it.", left, plural(left, "rep", "reps")),
			fmt.Sprintf("%d push-ups", left), frac}, true
	case db.QuestReading:
		minutes := readingMinutesLeft(q)
		return candidate{fmt.Sprintf("Reading: %d more %s. An audiobook counts.", minutes, plural(minutes, "minute", "minutes")),
			fmt.Sprintf("%d minutes of reading", minutes), readingFraction(q)}, true
	case db.QuestMealsLogged:
		return candidate{fmt.Sprintf("Meals: log %d more %s.", left, plural(left, "meal", "meals")),
			fmt.Sprintf("logging %d more %s", left, plural(left, "meal", "meals")), frac}, true
	case db.QuestProtein:
		return candidate{fmt.Sprintf("Protein: %d g to go.", left), fmt.Sprintf("%d g more protein", left), frac}, true
	case db.QuestYoga:
		return candidate{fmt.Sprintf("Yoga: %d more %s.", left, plural(left, "minute", "minutes")),
			fmt.Sprintf("%d minutes of yoga", left), frac}, true
	case db.QuestWater:
		litres := litresText(left)
		return candidate{fmt.Sprintf("Water: %s to go.", litres), litres + " more water", frac}, true
	case db.QuestProduce:
		return candidate{fmt.Sprintf("Fruit and vegetables: %d more %s.", left, plural(left, "serving", "servings")),
			fmt.Sprintf("%d more %s of fruit and vegetables", left, plural(left, "serving", "servings")), frac}, true
	case db.QuestBreathing:
		return candidate{fmt.Sprintf("Breathing: %d more %s.", left, plural(left, "minute", "minutes")),
			fmt.Sprintf("%d minutes of breathing", left), frac}, true
	case db.QuestExercise:
		return candidate{fmt.Sprintf("Exercise: %d more %s.", left, plural(left, "minute", "minutes")),
			fmt.Sprintf("%d more minutes of exercise", left), frac}, true
	}
	return candidate{}, false
}

// FinishText is how to close an unfinished quest in a sentence like "<text> finishes your day".
func FinishText(q Quest) (string, bool) {
	c, ok := finishing(q, 0)
	return c.short, ok
}

// StepsNudge is the push line for someone behind on steps: what is left and the walk that covers it.
func StepsNudge(left int) string {
	walk := walkMinutes(left)
	if walk > longWalkMin/2 {
		return fmt.Sprintf("%s steps to go. Even a 30-minute walk gets you most of the way.", Thousands(left))
	}
	return fmt.Sprintf("%s steps to go. A %d-minute walk does it.", Thousands(left), walk)
}

// walkAdvice words the walk and, without an hourly pattern to go on, picks a generic moment
// from the time of day.
func walkAdvice(walkMin, nowMinute int) string {
	if walkMin > longWalkMin {
		return fmt.Sprintf("That is about %d minutes of walking: split it into two walks.", walkMin)
	}
	when := "around midday"
	switch {
	case nowMinute >= 17*60:
		when = "this evening"
	case nowMinute >= 11*60+30:
		when = "this afternoon"
	}
	return fmt.Sprintf("A %d-minute walk %s covers it.", walkMin, when)
}

func readingFraction(q Quest) int {
	if q.Target <= 0 {
		return 1000
	}
	progress := float64(q.Actual) / float64(q.Target)
	if q.TargetAlt != nil && q.ActualAlt != nil && *q.TargetAlt > 0 {
		progress += float64(*q.ActualAlt) / float64(*q.TargetAlt)
	}
	return max(0, int((1-progress)*1000))
}

func readingMinutesLeft(q Quest) int {
	return ceilDiv(readingFraction(q)*q.Target, 1000)
}

func doneText(q Quest) string {
	title := titles[q.Key]
	if title == "" {
		title = q.Key
	}
	if q.DoneBy != nil {
		return fmt.Sprintf("%s done by your %s workout, %d min", title, workoutTitle(q.DoneBy.Type), q.DoneBy.Minutes)
	}
	switch q.Key {
	case db.QuestSteps:
		return fmt.Sprintf("%s done: %s", title, Thousands(q.Actual))
	case db.QuestWater:
		return fmt.Sprintf("%s done: %s", title, litresText(q.Actual))
	case db.QuestReading, db.QuestYoga, db.QuestExercise, db.QuestBreathing:
		return fmt.Sprintf("%s done: %d min", title, q.Actual)
	case db.QuestProduce:
		return fmt.Sprintf("%s done: %d %s", title, q.Actual, plural(q.Actual, "serving", "servings"))
	}
	return title + " done"
}

// litresText words millilitres as litres with one decimal. The plan has no unit setting, so the
// water text stays in one unit that reads the same in both systems.
func litresText(ml int) string { return fmt.Sprintf("%.1f L", float64(ml)/1000) }

var titles = map[string]string{
	db.QuestSteps: "Steps", db.QuestPushups: "Push-ups", db.QuestReading: "Reading", db.QuestMealsLogged: "Meals",
	db.QuestProtein: "Protein", db.QuestYoga: "Yoga", db.QuestExercise: "Exercise", db.QuestSleep: "Sleep", db.QuestWater: "Water",
	db.QuestSleepRegularity: "Steady bedtime", db.QuestProduce: "Fruit and vegetables", db.QuestBreathing: "Breathing",
}

func workoutTitle(t string) string {
	switch t {
	case score.WorkoutHIIT:
		return "HIIT"
	case "":
		return "workout"
	}
	return strings.ToUpper(t[:1]) + t[1:]
}

type dueHabit struct {
	item Item
	// sortMinute orders habits by when they are next due; untimed habits sort last.
	sortMinute int
	name       string
}

func habitItems(habits []Habit) []Item {
	var due []dueHabit
	for _, h := range habits {
		key := "habit:" + strconv.FormatInt(h.ID, 10)
		if !h.Check {
			if h.Target > 0 && h.Count < h.Target {
				due = append(due, dueHabit{Item{KindHabit, key, fmt.Sprintf("%s: %d of %d so far", h.Name, h.Count, h.Target)}, 24 * 60, h.Name})
			}
			continue
		}
		var times []string
		pending, first := 0, 24*60
		for _, s := range h.Slots {
			if s.Done {
				continue
			}
			pending++
			if s.Time != nil {
				times = append(times, *s.Time)
				first = min(first, minuteOf(*s.Time))
			}
		}
		if pending == 0 {
			continue
		}
		sort.Strings(times)
		text := h.Name
		if len(times) > 0 {
			text += " at " + strings.Join(times, " and ")
		}
		due = append(due, dueHabit{Item{KindHabit, key, text}, first, h.Name})
	}
	sort.SliceStable(due, func(a, b int) bool {
		if due[a].sortMinute != due[b].sortMinute {
			return due[a].sortMinute < due[b].sortMinute
		}
		return due[a].name < due[b].name
	})
	out := make([]Item, 0, len(due))
	for _, d := range due[:min(len(due), maxHabitItems)] {
		out = append(out, d.item)
	}
	return out
}

func minuteOf(hhmm string) int {
	if len(hhmm) != 5 {
		return 24 * 60
	}
	h, errH := strconv.Atoi(hhmm[:2])
	m, errM := strconv.Atoi(hhmm[3:])
	if errH != nil || errM != nil {
		return 24 * 60
	}
	return h*60 + m
}

func summary(in Input, doneCount int, next []candidate, habits []Item) string {
	total := len(in.Quests)
	var parts []string
	switch {
	case total == 0:
		parts = append(parts, "No quests are set for today.")
	case doneCount == total:
		parts = append(parts, fmt.Sprintf("All %d %s done. Nice work.", total, plural(total, "quest is", "quests are")))
	default:
		parts = append(parts, fmt.Sprintf("%d of %d %s done.", doneCount, total, plural(total, "quest", "quests")))
	}
	if len(next) > 0 {
		best := next[0]
		for _, c := range next[1:] {
			if c.remaining < best.remaining {
				best = c
			}
		}
		parts = append(parts, "Easiest next: "+best.text)
	}
	if len(habits) > 0 {
		parts = append(parts, fmt.Sprintf("%d %s still due, starting with %s.", len(habits), plural(len(habits), "habit is", "habits are"), habits[0].Text))
	}
	return strings.Join(parts, " ")
}

// Thousands writes 8400 as "8,400".
func Thousands(n int) string {
	s := strconv.Itoa(n)
	for i := len(s) - 3; i > 0; i -= 3 {
		s = s[:i] + "," + s[i:]
	}
	return s
}

func plural(n int, one, many string) string {
	if n == 1 {
		return one
	}
	return many
}

func ceilDiv(a, b int) int { return (a + b - 1) / b }

// walkMinutes is the walking time for the steps, to the nearest five minutes and at least five.
func walkMinutes(steps int) int {
	minutes := (steps + StepsPerMinute/2) / StepsPerMinute
	return max((minutes+walkRound/2)/walkRound*walkRound, walkRound)
}
