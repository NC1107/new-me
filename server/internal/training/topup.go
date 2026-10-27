package training

import "slices"

// TopUp adds sets to a plan whose only problem is a major group short of its weekly minimum.
// For each short group it adds one set at a time to an exercise already training that group, on
// the day with the most spare time, as long as the exercise stays within MaxSetsPerExercise,
// the day within its time limit, and every muscle within the weekly maximum. It returns the
// topped-up plan and whether it now validates; the input plan is never modified.
func TopUp(p Plan, profile Profile, catalog map[string]CatalogEntry) (Plan, bool) {
	for _, v := range Validate(p, profile, catalog) {
		if v.Rule != "volume_low" {
			return p, false
		}
	}
	out := clonePlan(p)
	r := WeeklySetRange(profile.Experience)
	limit := int(float64(profile.SessionMinutes*60) * TimeSlack)
	for _, group := range majorGroups {
		for groupSets(WeeklySets(out, catalog), group) < r.Min {
			if !addOneSet(&out, group, r, limit, catalog) {
				return p, false
			}
		}
	}
	return out, len(Validate(out, profile, catalog)) == 0
}

func addOneSet(p *Plan, group []string, r SetRange, limit int, catalog map[string]CatalogEntry) bool {
	weekly := WeeklySets(*p, catalog)
	bestDay, bestEx, bestSpare := -1, -1, -1
	for di, d := range p.Days {
		spare := limit - daySeconds(d)
		for ei, e := range d.Exercises {
			muscles := catalog[e.Exercise].PrimaryMuscles
			if !slices.ContainsFunc(muscles, func(m string) bool { return slices.Contains(group, m) }) {
				continue
			}
			if e.Sets >= MaxSetsPerExercise || spare < WorkSecondsPerSet+e.RestSec {
				continue
			}
			if slices.ContainsFunc(muscles, func(m string) bool { return weekly[m] >= r.Max }) {
				continue
			}
			if spare > bestSpare {
				bestDay, bestEx, bestSpare = di, ei, spare
			}
		}
	}
	if bestDay < 0 {
		return false
	}
	p.Days[bestDay].Exercises[bestEx].Sets++
	return true
}

func groupSets(weekly map[string]int, group []string) int {
	sets := 0
	for _, m := range group {
		sets = max(sets, weekly[m])
	}
	return sets
}

func daySeconds(d PlanDay) int {
	secs := 0
	for _, e := range d.Exercises {
		secs += e.Sets * (WorkSecondsPerSet + e.RestSec)
	}
	return secs
}

func clonePlan(p Plan) Plan {
	out := p
	out.Days = make([]PlanDay, len(p.Days))
	for i, d := range p.Days {
		out.Days[i] = d
		out.Days[i].Exercises = slices.Clone(d.Exercises)
	}
	return out
}
