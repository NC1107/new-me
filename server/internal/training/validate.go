package training

import (
	"fmt"
	"slices"
	"sort"
)

// Experience levels a training profile can hold.
const (
	ExperienceNew         = "new"
	ExperienceSome        = "some"
	ExperienceExperienced = "experienced"
)

// Profile is what a plan is built for.
type Profile struct {
	DaysPerWeek    int
	SessionMinutes int
	Experience     string
	// Equipment is what the person has; "gym" means everything.
	Equipment []string
}

// CatalogEntry is the part of an exercise validation reads.
type CatalogEntry struct {
	Key            string
	PrimaryMuscles []string
	Timed          bool
	Equipment      []string
	// Stretch marks mobility exercises, which belong to mobility sessions, not strength plans.
	Stretch bool
}

// PlanDay is one training day of a weekly plan.
type PlanDay struct {
	Label     string
	Weekday   int
	Exercises []Prescription
}

// Plan is a weekly template repeated across a block.
type Plan struct {
	Weeks int
	Days  []PlanDay
	Notes string
}

// Violation is one broken rule, worded so it can be sent back to the model and shown to a
// person.
type Violation struct {
	Rule    string `json:"rule"`
	Message string `json:"message"`
}

// SetRange is the weekly hard sets per muscle group the plan must stay within, with the source.
type SetRange struct {
	Min, Max int
	Label    string
}

// WeeklySetRange is from the dose-response meta-analysis of weekly sets and hypertrophy
// (Schoenfeld, Ogborn and Krieger, J Sports Sci 2017;35:1073): 10 or more sets a week for
// trained people, with lower volumes effective for beginners. The beginner and middle ranges
// are our convention inside that evidence.
func WeeklySetRange(experience string) SetRange {
	switch experience {
	case ExperienceExperienced:
		return SetRange{10, 20, "Schoenfeld 2017: 10 or more weekly sets per muscle"}
	case ExperienceSome:
		return SetRange{6, 16, "between the beginner and trained ranges (our convention, Schoenfeld 2017)"}
	}
	return SetRange{4, 12, "beginner range (our convention, Schoenfeld 2017)"}
}

// majorGroups must each get weekly work at the bottom of the range. Hamstrings and glutes are
// one group here because hinges and bridges train both.
var majorGroups = [][]string{{"chest"}, {"back"}, {"shoulders"}, {"quads"}, {"hamstrings", "glutes"}}

// Plan limits. Reps in reserve 0 to 4 follows the RIR-based scale (Zourdos et al., J Strength
// Cond Res 2016); 40 s per set is our convention for the work part of a set when estimating time.
const (
	MinWeeks, MaxWeeks     = 4, 6
	MaxRIR                 = 4
	MaxSetsPerExercise     = 10
	MaxRepsInRange         = 30
	MinSeconds, MaxSeconds = 5, 300
	MinRestSec, MaxRestSec = 30, 300
	WorkSecondsPerSet      = 40
	// TimeSlack lets a session run up to 10% over the requested minutes.
	TimeSlack = 1.10
	// MinStrengthDays is the WHO 2020 muscle-strengthening guideline.
	MinStrengthDays = 2
)

// WeeklySets counts each primary muscle's sets across the plan's days, the way Validate does.
func WeeklySets(p Plan, catalog map[string]CatalogEntry) map[string]int {
	weekly := map[string]int{}
	for _, d := range p.Days {
		for _, e := range d.Exercises {
			if catalog[e.Exercise].Stretch {
				continue
			}
			for _, m := range catalog[e.Exercise].PrimaryMuscles {
				weekly[m] += e.Sets
			}
		}
	}
	return weekly
}

// Validate checks a plan against the profile, the catalog and the evidence limits.
func Validate(p Plan, profile Profile, catalog map[string]CatalogEntry) []Violation {
	var out []Violation
	add := func(rule, format string, args ...any) {
		out = append(out, Violation{Rule: rule, Message: fmt.Sprintf(format, args...)})
	}
	if p.Weeks < MinWeeks || p.Weeks > MaxWeeks {
		add("weeks", "the block must last %d to %d weeks, not %d", MinWeeks, MaxWeeks, p.Weeks)
	}
	if len(p.Days) != profile.DaysPerWeek {
		add("days", "the plan must have exactly %d training days a week, not %d", profile.DaysPerWeek, len(p.Days))
	}
	weekdays := map[int]bool{}
	strengthDays := 0
	weekly := WeeklySets(p, catalog)
	for _, d := range p.Days {
		if d.Weekday < 1 || d.Weekday > 7 || weekdays[d.Weekday] {
			add("weekday", "%q needs its own weekday from 1 (Monday) to 7", d.Label)
		}
		weekdays[d.Weekday] = true
		if len(d.Exercises) > 0 {
			strengthDays++
		}
		seconds := 0
		for _, e := range d.Exercises {
			entry, ok := catalog[e.Exercise]
			if !ok {
				add("exercise", "%q is not in the exercise catalog", e.Exercise)
				continue
			}
			if entry.Stretch {
				add("exercise", "%q is a stretch; strength plans use strength exercises only", e.Exercise)
				continue
			}
			if !hasEquipment(profile.Equipment, entry.Equipment) {
				add("equipment", "%q needs equipment the person does not have", e.Exercise)
			}
			out = append(out, checkPrescription(e, entry)...)
			seconds += e.Sets * (WorkSecondsPerSet + e.RestSec)
		}
		if limit := float64(profile.SessionMinutes*60) * TimeSlack; float64(seconds) > limit {
			add("time", "%q takes about %d minutes, over the %d requested", d.Label, (seconds+59)/60, profile.SessionMinutes)
		}
	}
	if strengthDays < MinStrengthDays {
		add("strength_days", "muscle-strengthening work is needed on at least %d days a week (WHO 2020)", MinStrengthDays)
	}
	r := WeeklySetRange(profile.Experience)
	for _, group := range majorGroups {
		sets := 0
		for _, m := range group {
			sets = max(sets, weekly[m])
		}
		if sets < r.Min {
			add("volume_low", "%s gets %d weekly sets, %d short of the %d minimum (%s)", groupName(group), sets,
				r.Min-sets, r.Min, r.Label)
		}
	}
	muscles := make([]string, 0, len(weekly))
	for m := range weekly {
		muscles = append(muscles, m)
	}
	sort.Strings(muscles)
	for _, m := range muscles {
		if weekly[m] > r.Max {
			add("volume_high", "%s gets %d weekly sets, %d over the %d maximum (%s)", m, weekly[m], weekly[m]-r.Max,
				r.Max, r.Label)
		}
	}
	return out
}

func checkPrescription(e Prescription, entry CatalogEntry) []Violation {
	var out []Violation
	add := func(format string, args ...any) {
		out = append(out, Violation{Rule: "prescription", Message: fmt.Sprintf(format, args...)})
	}
	if e.Sets < 1 || e.Sets > MaxSetsPerExercise {
		add("%q needs 1 to %d sets", e.Exercise, MaxSetsPerExercise)
	}
	if entry.Timed {
		if e.Min < MinSeconds || e.Max > MaxSeconds || e.Min > e.Max {
			add("%q needs a seconds range within %d to %d", e.Exercise, MinSeconds, MaxSeconds)
		}
	} else if e.Min < 1 || e.Max > MaxRepsInRange || e.Min > e.Max {
		add("%q needs a rep range within 1 to %d", e.Exercise, MaxRepsInRange)
	}
	if e.RIR < 0 || e.RIR > MaxRIR {
		add("%q needs 0 to %d reps in reserve", e.Exercise, MaxRIR)
	}
	if e.RestSec < MinRestSec || e.RestSec > MaxRestSec {
		add("%q needs %d to %d seconds of rest", e.Exercise, MinRestSec, MaxRestSec)
	}
	return out
}

func hasEquipment(have, need []string) bool {
	if slices.Contains(have, "gym") {
		return true
	}
	for _, n := range need {
		if !slices.Contains(have, n) {
			return false
		}
	}
	return true
}

func groupName(group []string) string {
	if len(group) == 2 {
		return group[0] + " and " + group[1]
	}
	return group[0]
}
