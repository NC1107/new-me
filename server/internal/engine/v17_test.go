package engine

import (
	"testing"
	"time"

	"github.com/nc1107/new-me/server/internal/db"
	"github.com/nc1107/new-me/server/internal/score"
)

func breathingQuest() db.DayQuest {
	return db.DayQuest{Key: db.QuestBreathing, Target: 5, Unit: "min", Points: 50}
}

func produceQuest() db.DayQuest {
	return db.DayQuest{Key: db.QuestProduce, Target: 5, Unit: "servings", Points: 50}
}

func TestBreathingProgressIsTheLargerOfMindfulMinutesAndLoggedNotTheirSum(t *testing.T) {
	tests := []struct {
		name   string
		health float64
		logged int
		want   int
	}{
		{"health only", 3, 0, 3},
		{"logged only", 0, 5, 5},
		{"both, health larger", 8, 5, 8},
		{"both, logged larger", 3, 5, 5},
		{"the same session in both places", 5, 5, 5},
		{"health fraction rounds down", 4.9, 0, 4},
	}
	for _, tt := range tests {
		in := db.DayInputs{Metrics: map[string]float64{}, Synced: map[string]bool{}, BreathingLoggedMin: tt.logged}
		if tt.health > 0 {
			in.Metrics[db.MetricMindful], in.Synced[db.MetricMindful] = tt.health, true
		}
		actual, target := progress(breathingQuest(), in)
		if actual != tt.want || target != 5 {
			t.Errorf("%s: progress = %d of %d, want %d of 5", tt.name, actual, target, tt.want)
		}
		if shown, _ := Actuals(breathingQuest(), in); shown != tt.want {
			t.Errorf("%s: shown = %d, want %d", tt.name, shown, tt.want)
		}
	}
}

func TestBreathingIsPartOfTheDayWhenEitherSourceHasData(t *testing.T) {
	quests := []db.DayQuest{breathingQuest()}
	synced := db.DayInputs{Synced: map[string]bool{db.MetricMindful: true}}
	tests := []struct {
		name string
		in   db.DayInputs
		want int
	}{
		{"no source yet", db.DayInputs{}, 0},
		{"logged by hand", db.DayInputs{BreathingLoggedMin: 5}, 1},
		{"Health has synced mindful minutes before", synced, 1},
	}
	for _, tt := range tests {
		if got := len(QuestResults(quests, tt.in)); got != tt.want {
			t.Errorf("%s: %d results, want %d", tt.name, got, tt.want)
		}
	}
}

func TestProduceCountsLoggedServingsAndIsAlwaysPartOfTheDay(t *testing.T) {
	results := QuestResults([]db.DayQuest{produceQuest()}, db.DayInputs{ProduceServings: 3})
	if len(results) != 1 || results[0].Actual != 3 || results[0].Target != 5 {
		t.Fatalf("results = %+v", results)
	}
	if empty := QuestResults([]db.DayQuest{produceQuest()}, db.DayInputs{}); len(empty) != 1 || empty[0].Actual != 0 {
		t.Fatalf("a hand-logged quest counts from the start of the day: %+v", empty)
	}
}

func steadyQuest(window int) db.DayQuest {
	return db.DayQuest{Key: db.QuestSleepRegularity, Target: window, Unit: "min", Points: 50}
}

func steadyInputs(t *testing.T, tonightBed, tonightWake time.Duration, earlier int) db.DayInputs {
	t.Helper()
	loc, err := time.LoadLocation("America/New_York")
	if err != nil {
		t.Fatal(err)
	}
	date := score.Date("2026-11-10")
	in := db.DayInputs{Date: date, Loc: loc}
	night := func(d score.Date, bed, wake time.Duration) db.SleepNight {
		morning := d.Time()
		midnight := time.Date(morning.Year(), morning.Month(), morning.Day(), 0, 0, 0, 0, loc)
		return db.SleepNight{Date: d, BedAt: midnight.Add(bed), WakeAt: midnight.Add(wake), AsleepMin: 400}
	}
	for i := 1; i <= earlier; i++ {
		in.SleepNights = append(in.SleepNights, night(date.AddDays(-i), -90*time.Minute, 6*time.Hour+30*time.Minute))
	}
	in.SleepNights = append(in.SleepNights, night(date, tonightBed, tonightWake))
	return in
}

func TestSteadyBedtimeScoresOnePointPerTimeInsideTheWindow(t *testing.T) {
	tests := []struct {
		name      string
		bed, wake time.Duration
		hits      int
	}{
		{"both on the routine", -90 * time.Minute, 6*time.Hour + 30*time.Minute, 2},
		{"both at the edge", -45 * time.Minute, 6*time.Hour + 75*time.Minute, 2},
		{"bed outside", -30 * time.Minute, 6*time.Hour + 30*time.Minute, 1},
		{"both outside", 30 * time.Minute, 9 * time.Hour, 0},
	}
	for _, tt := range tests {
		in := steadyInputs(t, tt.bed, tt.wake, 5)
		actual, target := progress(steadyQuest(45), in)
		if target != 2 || actual != tt.hits {
			t.Errorf("%s: progress = %d of %d, want %d of 2", tt.name, actual, target, tt.hits)
		}
		if shown, _ := Actuals(steadyQuest(45), in); shown != tt.hits {
			t.Errorf("%s: shown = %d, want %d", tt.name, shown, tt.hits)
		}
	}
}

func TestSteadyBedtimeIsOnlyPartOfTheDayOnceThereIsARoutineAndANight(t *testing.T) {
	quests := []db.DayQuest{steadyQuest(45)}
	if got := len(QuestResults(quests, steadyInputs(t, -90*time.Minute, 6*time.Hour, 3))); got != 1 {
		t.Errorf("three earlier nights and tonight: %d results, want 1", got)
	}
	if got := len(QuestResults(quests, steadyInputs(t, -90*time.Minute, 6*time.Hour, 2))); got != 0 {
		t.Errorf("two earlier nights: %d results, want 0", got)
	}
	if got := len(QuestResults(quests, db.DayInputs{Synced: map[string]bool{db.MetricSleep: true}})); got != 0 {
		t.Errorf("Health sleep minutes alone say nothing about timing: %d results, want 0", got)
	}
	noNight := steadyInputs(t, 0, time.Hour, 5)
	noNight.SleepNights = noNight.SleepNights[:5]
	if got := len(QuestResults(quests, noNight)); got != 0 {
		t.Errorf("no night for the day: %d results, want 0", got)
	}
}

func TestSteadyBedtimeIgnoresNightsWithoutSleep(t *testing.T) {
	in := steadyInputs(t, -90*time.Minute, 6*time.Hour+30*time.Minute, 3)
	for i := range in.SleepNights[:2] {
		in.SleepNights[i].AsleepMin = 0
	}
	if got := len(QuestResults([]db.DayQuest{steadyQuest(45)}, in)); got != 0 {
		t.Errorf("a night with no recorded sleep is not a routine: %d results, want 0", got)
	}
}
