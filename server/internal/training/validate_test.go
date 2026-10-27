package training

import (
	"slices"
	"testing"
)

var testCatalog = map[string]CatalogEntry{
	"push_up":      {Key: "push_up", PrimaryMuscles: []string{"chest"}},
	"pull_up":      {Key: "pull_up", PrimaryMuscles: []string{"back"}, Equipment: []string{"pullup_bar"}},
	"db_press":     {Key: "db_press", PrimaryMuscles: []string{"shoulders"}, Equipment: []string{"dumbbells"}},
	"split_squat":  {Key: "split_squat", PrimaryMuscles: []string{"quads", "glutes"}},
	"glute_bridge": {Key: "glute_bridge", PrimaryMuscles: []string{"glutes"}},
	"plank":        {Key: "plank", PrimaryMuscles: []string{"core"}, Timed: true},
}

func day(label string, weekday int, ex ...Prescription) PlanDay {
	return PlanDay{Label: label, Weekday: weekday, Exercises: ex}
}

func rx(key string, sets int) Prescription {
	return Prescription{Exercise: key, Sets: sets, Min: 6, Max: 10, RIR: 2, RestSec: 90}
}

// validPlan is a three-day full-body plan inside the beginner range.
func validPlan() Plan {
	full := func(label string, weekday int) PlanDay {
		return day(label, weekday, rx("push_up", 2), rx("pull_up", 2), rx("db_press", 2), rx("split_squat", 2))
	}
	return Plan{Weeks: 4, Days: []PlanDay{full("A", 1), full("B", 3), full("C", 5)}}
}

var beginner = Profile{DaysPerWeek: 3, SessionMinutes: 45, Experience: ExperienceNew,
	Equipment: []string{"pullup_bar", "dumbbells"}}

func rules(v []Violation) []string {
	var out []string
	for _, x := range v {
		out = append(out, x.Rule)
	}
	return out
}

func TestValidPlanPasses(t *testing.T) {
	if v := Validate(validPlan(), beginner, testCatalog); len(v) != 0 {
		t.Fatalf("violations: %+v", v)
	}
}

func TestValidateFlagsEachRule(t *testing.T) {
	cases := []struct {
		name   string
		edit   func(p *Plan, pr *Profile)
		expect string
	}{
		{"block too short", func(p *Plan, _ *Profile) { p.Weeks = 2 }, "weeks"},
		{"wrong day count", func(p *Plan, _ *Profile) { p.Days = p.Days[:2] }, "days"},
		{"shared weekday", func(p *Plan, _ *Profile) { p.Days[1].Weekday = 1 }, "weekday"},
		{"unknown exercise", func(p *Plan, _ *Profile) { p.Days[0].Exercises[0].Exercise = "levitation" }, "exercise"},
		{"missing equipment", func(_ *Plan, pr *Profile) { pr.Equipment = []string{"dumbbells"} }, "equipment"},
		{"too much reserve", func(p *Plan, _ *Profile) { p.Days[0].Exercises[0].RIR = 6 }, "prescription"},
		{"inverted range", func(p *Plan, _ *Profile) { p.Days[0].Exercises[0].Min = 12 }, "prescription"},
		{"over time", func(_ *Plan, pr *Profile) { pr.SessionMinutes = 15 }, "time"},
		{"too few strength days", func(p *Plan, pr *Profile) {
			p.Days[1].Exercises, p.Days[2].Exercises = nil, nil
		}, "strength_days"},
		{"volume too low", func(p *Plan, _ *Profile) {
			for i := range p.Days {
				p.Days[i].Exercises = p.Days[i].Exercises[:3]
			}
		}, "volume_low"},
		{"volume too high", func(p *Plan, _ *Profile) {
			p.Days[0].Exercises[0].Sets = 10
		}, "volume_high"},
	}
	for _, c := range cases {
		p, pr := validPlan(), beginner
		pr.Equipment = slices.Clone(beginner.Equipment)
		c.edit(&p, &pr)
		if got := rules(Validate(p, pr, testCatalog)); !slices.Contains(got, c.expect) {
			t.Errorf("%s: rules %v, want %s", c.name, got, c.expect)
		}
	}
}

func TestGymCoversAllEquipment(t *testing.T) {
	gym := beginner
	gym.Equipment = []string{"gym"}
	if v := Validate(validPlan(), gym, testCatalog); len(v) != 0 {
		t.Fatalf("violations: %+v", v)
	}
}

func TestHamstringsAndGlutesShareAGroup(t *testing.T) {
	// split squats count for glutes, so the posterior group is met without hamstring work.
	if slices.Contains(rules(Validate(validPlan(), beginner, testCatalog)), "volume_low") {
		t.Fatal("glute sets should satisfy the hamstrings and glutes group")
	}
}

func TestTimedPrescriptionsUseSeconds(t *testing.T) {
	p := validPlan()
	p.Days[0].Exercises = append(p.Days[0].Exercises, Prescription{Exercise: "plank", Sets: 2, Min: 2, Max: 30, RIR: 1, RestSec: 60})
	if !slices.Contains(rules(Validate(p, beginner, testCatalog)), "prescription") {
		t.Fatal("a 2 second plank should be rejected")
	}
}

func TestWeeklySetRangeByExperience(t *testing.T) {
	if r := WeeklySetRange(ExperienceExperienced); r.Min != 10 || r.Max != 20 {
		t.Fatalf("experienced = %+v", r)
	}
	if r := WeeklySetRange(ExperienceNew); r.Min != 4 || r.Max != 12 {
		t.Fatalf("new = %+v", r)
	}
}

func TestWeeklySetsCountsEveryPrimaryMuscle(t *testing.T) {
	got := WeeklySets(validPlan(), testCatalog)
	if got["chest"] != 6 || got["quads"] != 6 || got["glutes"] != 6 || got["core"] != 0 {
		t.Fatalf("weekly = %v", got)
	}
}
