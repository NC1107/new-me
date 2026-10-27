package training

import "testing"

func TestTopUpFillsAShortGroupOnTheDayWithMostSpareTime(t *testing.T) {
	p := validPlan()
	p.Days[2].Exercises = p.Days[2].Exercises[1:] // chest drops to 4
	p.Days[0].Exercises[0].Sets = 1               // and to 3, one short
	before := p.Days[0].Exercises[0].Sets
	got, ok := TopUp(p, beginner, testCatalog)
	if !ok {
		t.Fatalf("expected a valid plan, violations %+v", Validate(got, beginner, testCatalog))
	}
	if WeeklySets(got, testCatalog)["chest"] != 4 {
		t.Fatalf("chest = %d", WeeklySets(got, testCatalog)["chest"])
	}
	if p.Days[0].Exercises[0].Sets != before {
		t.Fatal("the input plan must not change")
	}
}

func TestTopUpLeavesOtherViolationsAlone(t *testing.T) {
	p := validPlan()
	p.Days[0].Exercises[0].Sets = 1
	p.Weeks = 9
	if _, ok := TopUp(p, beginner, testCatalog); ok {
		t.Fatal("a plan with a non-volume violation goes back as rejected")
	}
}

func TestTopUpStopsAtTheTimeLimit(t *testing.T) {
	p := validPlan()
	for i := range p.Days {
		p.Days[i].Exercises[0].Sets = 1
	}
	tight := beginner
	tight.SessionMinutes = 10
	if _, ok := TopUp(p, tight, testCatalog); ok {
		t.Fatal("no time to add sets, so the plan stays rejected")
	}
}

func TestTopUpNeverPushesAMuscleOverTheMaximum(t *testing.T) {
	p := validPlan()
	for i := range p.Days {
		p.Days[i].Exercises[2].Sets = 1 // shoulders at 3, one short
	}
	got, ok := TopUp(p, beginner, testCatalog)
	if !ok || WeeklySets(got, testCatalog)["shoulders"] != 4 {
		t.Fatalf("ok=%v weekly=%v", ok, WeeklySets(got, testCatalog))
	}
	for m, n := range WeeklySets(got, testCatalog) {
		if n > WeeklySetRange(beginner.Experience).Max {
			t.Fatalf("%s over the maximum: %d", m, n)
		}
	}
}
