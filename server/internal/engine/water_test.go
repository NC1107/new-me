package engine

import (
	"testing"

	"github.com/nc1107/new-me/server/internal/db"
)

func waterQuest() db.DayQuest {
	return db.DayQuest{Key: db.QuestWater, Target: 2200, Unit: "ml", Points: 50}
}

func waterInputs(healthML float64, synced bool, loggedML int) db.DayInputs {
	in := db.DayInputs{Metrics: map[string]float64{}, Synced: map[string]bool{}, WaterLoggedML: loggedML}
	if synced {
		in.Synced[db.MetricWater] = true
	}
	if healthML > 0 {
		in.Metrics[db.MetricWater] = healthML
	}
	return in
}

func TestWaterProgressIsTheLargerOfHealthAndLoggedNotTheirSum(t *testing.T) {
	tests := []struct {
		name   string
		health float64
		logged int
		want   int
	}{
		{"health only", 1800, 0, 1800},
		{"logged only", 0, 1100, 1100},
		{"both, health larger", 1800, 1100, 1800},
		{"both, logged larger", 1100, 2000, 2000},
		{"the same water in both places", 1500, 1500, 1500},
		{"health fraction rounds down", 1499.9, 0, 1499},
	}
	for _, tt := range tests {
		in := waterInputs(tt.health, tt.health > 0, tt.logged)
		actual, target := progress(waterQuest(), in)
		if actual != tt.want || target != 2200 {
			t.Errorf("%s: progress = %d of %d, want %d of 2200", tt.name, actual, target, tt.want)
		}
		if shown, _ := Actuals(waterQuest(), in); shown != tt.want {
			t.Errorf("%s: shown actual = %d, want %d", tt.name, shown, tt.want)
		}
	}
}

func TestWaterQuestIsPartOfTheDayWhenEitherSourceHasData(t *testing.T) {
	quests := []db.DayQuest{waterQuest()}
	tests := []struct {
		name string
		in   db.DayInputs
		want int
	}{
		{"no source yet", waterInputs(0, false, 0), 0},
		{"logged by hand today", waterInputs(0, false, 250), 1},
		{"Health has synced water before", waterInputs(0, true, 0), 1},
		{"Health reading today", waterInputs(900, true, 0), 1},
	}
	for _, tt := range tests {
		if got := len(QuestResults(quests, tt.in)); got != tt.want {
			t.Errorf("%s: %d results, want %d", tt.name, got, tt.want)
		}
	}
}

func TestWaterQuestCompletesAtTheTargetFromEitherSource(t *testing.T) {
	for name, in := range map[string]db.DayInputs{
		"Health":     waterInputs(2200, true, 0),
		"the log":    waterInputs(0, false, 2200),
		"both, once": waterInputs(2200, true, 2200),
	} {
		results := QuestResults([]db.DayQuest{waterQuest()}, in)
		if len(results) != 1 || results[0].Actual < results[0].Target {
			t.Errorf("%s: results = %+v, want a finished quest", name, results)
		}
	}
	both := QuestResults([]db.DayQuest{waterQuest()}, waterInputs(1100, true, 1100))
	if both[0].Actual != 1100 {
		t.Errorf("1100 ml in both places counted as %d, want 1100", both[0].Actual)
	}
}
