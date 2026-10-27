package targets

import (
	"math"
	"testing"
	"time"

	"github.com/nc1107/new-me/server/internal/insights"
	"github.com/nc1107/new-me/server/internal/score"
)

var newYork = func() *time.Location {
	loc, err := time.LoadLocation("America/New_York")
	if err != nil {
		panic(err)
	}
	return loc
}()

func near(t *testing.T, name string, got, want, tol float64) {
	t.Helper()
	if math.Abs(got-want) > tol {
		t.Errorf("%s = %v, want %v", name, got, want)
	}
}

func TestRestingEnergyReproducesWorkedExamples(t *testing.T) {
	tests := []struct {
		name  string
		kg    float64
		cm    float64
		age   int
		sex   Sex
		want  float64
		check string
	}{
		// 10 x 80 + 6.25 x 180 - 5 x 30 + 5 = 800 + 1125 - 150 + 5.
		{"male 30y 80kg 180cm", 80, 180, 30, Male, 1780, "Mifflin et al. 1990 form"},
		// 10 x 65 + 6.25 x 165 - 5 x 40 - 161 = 650 + 1031.25 - 200 - 161.
		{"female 40y 65kg 165cm", 65, 165, 40, Female, 1320.25, ""},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			near(t, "resting", RestingEnergy(tt.kg, tt.cm, tt.age, tt.sex), tt.want, 1e-9)
		})
	}
}

func TestPALForStepsUsesTheBandEdges(t *testing.T) {
	tests := []struct {
		steps float64
		want  float64
	}{
		{0, 1.4}, {7499, 1.4}, {7500, 1.55}, {9999, 1.55}, {10000, 1.7}, {12499, 1.7}, {12500, 1.85}, {30000, 1.85},
	}
	for _, tt := range tests {
		if got := PALForSteps(tt.steps).Value; got != tt.want {
			t.Errorf("PAL(%v) = %v, want %v", tt.steps, got, tt.want)
		}
	}
}

func TestCaloriesAppliesPaceCapsRoundingAndFloor(t *testing.T) {
	tests := []struct {
		name        string
		in          CalorieInput
		want        int
		wantPace    float64
		wantCapped  bool
		wantFloored bool
	}{
		// 1,780 x 1.55 = 2,759.
		{"maintain rounds to 50", CalorieInput{Resting: 1780, PAL: 1.55, WeightKg: 80, Sex: Male, Kind: Maintain}, 2750, 0, false, false},
		// 0.5 x 7,700 / 7 = 550 -> 2,209 -> 2,200.
		{"lose 0.5", CalorieInput{Resting: 1780, PAL: 1.55, WeightKg: 80, Sex: Male, Kind: Lose, PaceKg: 0.5}, 2200, 0.5, false, false},
		// 275 -> 2,484 -> 2,500.
		{"lose 0.25", CalorieInput{Resting: 1780, PAL: 1.55, WeightKg: 80, Sex: Male, Kind: Lose, PaceKg: 0.25}, 2500, 0.25, false, false},
		// 0.5% of 80 kg = 0.4 kg; 440 -> 3,199 -> 3,200.
		{"gain at the cap", CalorieInput{Resting: 1780, PAL: 1.55, WeightKg: 80, Sex: Male, Kind: Gain, PaceKg: 0.4}, 3200, 0.4, false, false},
		// 0.5 asked, 0.4 allowed.
		{"gain above the cap is limited", CalorieInput{Resting: 1780, PAL: 1.55, WeightKg: 80, Sex: Male, Kind: Gain, PaceKg: 0.5}, 3200, 0.4, true, false},
		// 1% of 45 kg = 0.45 kg is allowed when 0.5 is asked: 1,700 x 1.4 = 2,380 - 495 = 1,885 -> 1,900.
		{"lose above 1 percent of body weight is limited", CalorieInput{Resting: 1700, PAL: 1.4, WeightKg: 45, Sex: Female, Kind: Lose, PaceKg: 0.5}, 1900, 0.45, true, false},
		// 1,139 x 1.4 = 1,594.6; minus 550 = 1,044.6; the floor is the larger of resting and 1,200.
		{"female floor", CalorieInput{Resting: 1139, PAL: 1.4, WeightKg: 80, Sex: Female, Kind: Lose, PaceKg: 0.5}, 1200, 0.5, false, true},
		// Resting 1,620 is above the male floor of 1,500, so the floor is resting rounded up to 50:
		// 1,620 x 1.2 = 1,944 - 550 = 1,394 -> 1,400, raised to 1,650.
		{"male floor follows resting energy", CalorieInput{Resting: 1620, PAL: 1.2, WeightKg: 90, Sex: Male, Kind: Lose, PaceKg: 0.5}, 1650, 0.5, false, true},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got := ComputeCalories(tt.in)
			if got.Target != tt.want || got.PaceCapped != tt.wantCapped || got.Floored != tt.wantFloored {
				t.Fatalf("got %+v, want target %d capped %v floored %v", got, tt.want, tt.wantCapped, tt.wantFloored)
			}
			near(t, "pace", got.PaceKg, tt.wantPace, 1e-9)
		})
	}
}

func TestMaxGainPaceRoundsToFiveHundredths(t *testing.T) {
	for kg, want := range map[float64]float64{80: 0.4, 60: 0.3, 100: 0.5, 72: 0.35, 66: 0.35, 50: 0.25} {
		near(t, "cap", MaxGainPace(kg), want, 1e-9)
	}
}

func TestProteinByGoalAndAdjustedWeightCap(t *testing.T) {
	h170, h180 := 170.0, 180.0
	tests := []struct {
		name   string
		kind   string
		kg     float64
		height *float64
		want   int
		capped bool
	}{
		{"maintain 1.6", Maintain, 80, &h180, 130, false},
		{"gain 1.8", Gain, 80, &h180, 145, false},
		{"lose 2.0", Lose, 80, &h180, 160, false},
		{"no height means no cap", Lose, 120, nil, 240, false},
		// BMI 41.5: the weight at BMI 25 is 72.25 kg, so the cap is 2.2 x 72.25 = 158.95 g.
		{"lose capped at BMI 30 or more", Lose, 120, &h170, 160, true},
		{"maintain capped at BMI 30 or more", Maintain, 120, &h170, 160, true},
		// BMI 29.4: below 30 the cap does not apply.
		{"BMI under 30 uncapped", Lose, 85, &h170, 170, false},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got := ComputeProtein(tt.kind, tt.kg, tt.height)
			if got.G != tt.want || got.Capped != tt.capped {
				t.Fatalf("got %+v, want %d capped %v", got, tt.want, tt.capped)
			}
		})
	}
	if got := ComputeProtein(Maintain, 80, &h180).PerMealG; got != 32 {
		t.Errorf("per meal = %d, want 0.4 x 80 = 32", got)
	}
}

func TestMacrosSumToTheCalorieTargetAndKeepTheFloors(t *testing.T) {
	tests := []struct {
		name             string
		kcal, protein    int
		fat, carbs, sat  int
		lowered, floored bool
	}{
		// 28% of 2,200 = 616 kcal = 68.4 g; carbohydrate (2,200 - 640 - 612) / 4 = 237.
		{"default split", 2200, 160, 68, 237, 24, false, false},
		// Remainder at 28% fat would be 120 g, so fat falls to (900 - 520) / 9 = 42 g and carbs to 131.
		{"fat lowered first", 1500, 150, 42, 131, 17, true, false},
		// Even at the 20% fat floor (27 g) carbohydrate is 39 g, so it sits at the 130 g floor.
		{"carbohydrate floor", 1200, 200, 27, 130, 13, true, true},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			m := ComputeMacros(tt.kcal, tt.protein)
			if m.FatG != tt.fat || m.CarbsG != tt.carbs || m.SatFatMaxG != tt.sat || m.FatLowered != tt.lowered || m.CarbsFloored != tt.floored {
				t.Fatalf("got %+v", m)
			}
			total := 4*tt.protein + 9*m.FatG + 4*m.CarbsG
			if !tt.floored && math.Abs(float64(total-tt.kcal)) > 3 {
				t.Errorf("macros add up to %d kcal, target %d", total, tt.kcal)
			}
		})
	}
}

func TestMacrosArithmeticAcrossManyTargets(t *testing.T) {
	for kcal := 1200; kcal <= 4500; kcal += 50 {
		for protein := 60; protein <= 260; protein += 5 {
			m := ComputeMacros(kcal, protein)
			if m.CarbsG < CarbsFloorG {
				t.Fatalf("%d kcal %d g protein: carbs %d under the floor", kcal, protein, m.CarbsG)
			}
			if m.FatG*9 < int(FatFloorShare*float64(kcal))-9 {
				t.Fatalf("%d kcal %d g protein: fat %d under 20%%", kcal, protein, m.FatG)
			}
			total := 4*protein + 9*m.FatG + 4*m.CarbsG
			if !m.CarbsFloored && math.Abs(float64(total-kcal)) > 3 {
				t.Fatalf("%d kcal %d g protein: adds up to %d", kcal, protein, total)
			}
		}
	}
}

func TestFiberScalesWithEnergyAndHasAgeSexContext(t *testing.T) {
	if got := FiberTarget(2200); got != 31 {
		t.Errorf("fiber(2200) = %d, want 14 x 2.2 = 30.8 -> 31", got)
	}
	tests := []struct {
		age  int
		sex  Sex
		want int
	}{{30, Male, 38}, {30, Female, 25}, {50, Male, 38}, {51, Male, 30}, {51, Female, 21}, {70, Female, 21}}
	for _, tt := range tests {
		if got := FiberAI(tt.age, tt.sex); got == nil || *got != tt.want {
			t.Errorf("AI(%d, %s) = %v, want %d", tt.age, tt.sex, got, tt.want)
		}
	}
	if FiberAI(17, Male) != nil || FiberAI(30, "") != nil {
		t.Error("no table below 19 or without a sex")
	}
}

func TestBedtimeIsWakeMinusTargetMinusOnsetAndWrapsMidnight(t *testing.T) {
	// 07:00 - 7 h 30 - 15 min = 23:15.
	if got := BedtimeMin(7*60, 450); got != 23*60+15 {
		t.Errorf("bedtime = %d", got)
	}
	// 08:00 - 9 h - 15 min = 22:45 the evening before.
	if got := BedtimeMin(8*60, 540); got != 22*60+45 {
		t.Errorf("bedtime = %d", got)
	}
	// 05:00 - 7 h - 15 min = 21:45.
	if got := BedtimeMin(5*60, 420); got != 21*60+45 {
		t.Errorf("bedtime = %d", got)
	}
}

func night(date string, bedHour, bedMin, wakeHour, wakeMin int) insights.Night {
	d := score.MustDate(date)
	prev := d.AddDays(-1).Time()
	cur := d.Time()
	bed := time.Date(prev.Year(), prev.Month(), prev.Day(), bedHour, bedMin, 0, 0, newYork)
	if bedHour < 12 {
		bed = time.Date(cur.Year(), cur.Month(), cur.Day(), bedHour, bedMin, 0, 0, newYork)
	}
	wake := time.Date(cur.Year(), cur.Month(), cur.Day(), wakeHour, wakeMin, 0, 0, newYork)
	return insights.Night{Date: d, BedAt: bed, WakeAt: wake, AsleepMin: int(wake.Sub(bed).Minutes())}
}

func TestSleepRegularityOnSyntheticSchedules(t *testing.T) {
	today := score.MustDate("2026-11-02")
	regular := func(n int) []insights.Night {
		var out []insights.Night
		for i := range n {
			out = append(out, night(string(today.AddDays(-i)), 23, 0, 7, 0))
		}
		return out
	}
	tests := []struct {
		name      string
		nights    []insights.Night
		want      float64
		wantNil   bool
		wantPairs int
	}{
		{"perfectly regular is 100", regular(7), 100, false, 6},
		{"five nights is enough", regular(5), 100, false, 4},
		{"four nights is not", regular(4), 0, true, 3},
		{
			// Every other night is one hour later at both ends: 120 of 1,080 minutes differ in each pair,
			// so the match is 960/1,080 and the index -100 + 200 x 0.8889 = 77.78.
			name: "alternating one hour shift",
			nights: []insights.Night{
				night("2026-11-02", 23, 0, 7, 0), night("2026-11-01", 0, 0, 8, 0), night("2026-10-31", 23, 0, 7, 0),
				night("2026-10-30", 0, 0, 8, 0), night("2026-10-29", 23, 0, 7, 0),
			},
			want: 77.78, wantPairs: 4,
		},
		{
			name: "nights without neighbours cannot be compared",
			nights: []insights.Night{
				night("2026-11-02", 23, 0, 7, 0), night("2026-10-31", 23, 0, 7, 0), night("2026-10-29", 23, 0, 7, 0),
				night("2026-10-27", 23, 0, 7, 0), night("2026-10-25", 23, 0, 7, 0),
			},
			wantNil: true, wantPairs: 0,
		},
		{
			name:    "nights outside the 14 day window are ignored",
			nights:  append(regular(4), night("2026-10-10", 23, 0, 7, 0), night("2026-10-09", 23, 0, 7, 0)),
			wantNil: true, wantPairs: 3,
		},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got := SleepRegularity(tt.nights, today, newYork)
			if got.Pairs != tt.wantPairs {
				t.Errorf("pairs = %d, want %d", got.Pairs, tt.wantPairs)
			}
			if tt.wantNil {
				if got.Score != nil || len(got.Missing) == 0 {
					t.Fatalf("score = %v missing %v, want none", got.Score, got.Missing)
				}
				return
			}
			if got.Score == nil {
				t.Fatalf("no score, missing %v", got.Missing)
			}
			near(t, "sri", *got.Score, tt.want, 0.01)
		})
	}
}

func TestSleepRegularityOfOppositeScheduleIsNegative(t *testing.T) {
	today := score.MustDate("2026-11-02")
	var nights []insights.Night
	for i := range 6 {
		d := string(today.AddDays(-i))
		// A night owl day swaps to an early sleeper the next; both cover the same span but never agree.
		if i%2 == 0 {
			nights = append(nights, night(d, 18, 0, 2, 0))
		} else {
			nights = append(nights, night(d, 2, 0, 12, 0))
		}
	}
	got := SleepRegularity(nights, today, newYork)
	if got.Score == nil || *got.Score >= 0 {
		t.Fatalf("score = %v, want negative", got.Score)
	}
}

func TestSevenNightShortfallIsInformation(t *testing.T) {
	today := score.MustDate("2026-11-02")
	nights := []insights.Night{
		{Date: "2026-11-02", AsleepMin: 400}, {Date: "2026-11-01", AsleepMin: 480},
		{Date: "2026-10-31", AsleepMin: 420}, {Date: "2026-10-20", AsleepMin: 100},
	}
	got := SevenNightShortfall(nights, today, 450)
	// Three nights in the window: 1,300 asleep of 1,350.
	if got.Nights != 3 || got.AsleepMin != 1300 || got.TargetMin != 1350 || got.Min != 50 {
		t.Fatalf("got %+v", got)
	}
	if over := SevenNightShortfall([]insights.Night{{Date: "2026-11-02", AsleepMin: 600}}, today, 450); over.Min != 0 {
		t.Errorf("a surplus is no shortfall: %+v", over)
	}
}

func TestPushupTargetFromTheLatestMax(t *testing.T) {
	tests := []struct {
		name            string
		max, current    int
		days            int
		perSet, low, hi int
		daily           int
		progressed      bool
	}{
		{"40 max", 40, 0, 0, 30, 28, 32, 90, false},
		{"odd max rounds", 23, 0, 0, 17, 16, 18, 51, false},
		{"max of one still has a rep", 1, 0, 0, 1, 1, 1, 3, false},
		// 30 x 5% = 1.5 -> 2 reps, so 32.
		{"progress after 5 of 7 days", 40, 30, 5, 32, 28, 32, 96, true},
		{"4 days is not enough", 40, 30, 4, 30, 28, 32, 90, false},
		// 10 x 5% = 0.5 -> at least 1 rep, 11, which is still under 75% of the max.
		{"progress below the derived value changes nothing", 40, 10, 6, 30, 28, 32, 90, false},
		{"at least one rep", 40, 12, 7, 30, 28, 32, 90, false},
		{"small reps rise by one", 8, 5, 5, 6, 6, 6, 18, false},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got := ComputePushups(tt.max, tt.current, tt.days)
			if got.RepsPerSet != tt.perSet || got.Low != tt.low || got.High != tt.hi || got.Daily() != tt.daily || got.Progressed != tt.progressed {
				t.Fatalf("got %+v", got)
			}
		})
	}
	if got := ProgressedReps(2); got != 3 {
		t.Errorf("progressed(2) = %d, want at least +1", got)
	}
}

func TestDayCompletedNeedsEverySet(t *testing.T) {
	tests := []struct {
		sets   []int
		perSet int
		want   bool
	}{
		{[]int{30, 30, 30}, 30, true}, {[]int{31, 40, 30, 5}, 30, true}, {[]int{30, 30}, 30, false},
		{[]int{30, 30, 29}, 30, false}, {nil, 30, false}, {[]int{1, 1, 1}, 0, false},
	}
	for _, tt := range tests {
		if got := DayCompleted(tt.sets, tt.perSet); got != tt.want {
			t.Errorf("DayCompleted(%v, %d) = %v", tt.sets, tt.perSet, got)
		}
	}
}

func TestEstimateFromLogs(t *testing.T) {
	today := score.MustDate("2026-11-02")
	weighIns := func(n int, daily func(i int) float64) []insights.Reading {
		var out []insights.Reading
		for i := 0; i < n; i++ {
			out = append(out, insights.Reading{Date: today.AddDays(-(n - 1) + i), Value: daily(i)})
		}
		return out
	}
	intake := func(from, to int, kcal float64) map[score.Date]float64 {
		out := map[score.Date]float64{}
		for i := from; i <= to; i++ {
			out[today.AddDays(-i)] = kcal
		}
		return out
	}

	t.Run("steady weight means intake is maintenance", func(t *testing.T) {
		got := EstimateFromLogs(BalanceInput{Today: today, Readings: weighIns(20, func(int) float64 { return 80 }), IntakeKcal: intake(1, 19, 2500)})
		if got.Kcal == nil || *got.Kcal != 2500 {
			t.Fatalf("got %+v", got)
		}
	})
	t.Run("a falling trend adds the deficit back", func(t *testing.T) {
		readings := weighIns(20, func(i int) float64 { return 82 - 0.1*float64(i) })
		smoothed := insights.Smooth(readings)
		change := smoothed[19].Smoothed - smoothed[0].Smoothed
		want := int(math.Round(2200 - change*7700/19))
		got := EstimateFromLogs(BalanceInput{Today: today, Readings: readings, IntakeKcal: intake(1, 19, 2200)})
		if got.Kcal == nil || *got.Kcal != want || *got.Kcal <= 2200 {
			t.Fatalf("got %+v, want %d above intake", got, want)
		}
		if got.SpanDays != 19 || got.WeighIns != 20 || got.LoggedDays != 19 {
			t.Fatalf("got %+v", got)
		}
	})
	t.Run("requirements", func(t *testing.T) {
		flat := func(int) float64 { return 80 }
		tests := []struct {
			name    string
			in      BalanceInput
			missing []string
		}{
			{"too few weigh-ins", BalanceInput{Today: today, Readings: []insights.Reading{
				{Date: today.AddDays(-20), Value: 80}, {Date: today.AddDays(-10), Value: 80}, {Date: today, Value: 80}}, IntakeKcal: intake(1, 19, 2500)}, []string{"weighIns"}},
			{"span under 14 days", BalanceInput{Today: today, Readings: weighIns(13, flat), IntakeKcal: intake(1, 12, 2500)}, []string{"spanDays"}},
			{"under 10 logged days", BalanceInput{Today: today, Readings: weighIns(20, flat), IntakeKcal: intake(1, 9, 2500)}, []string{"loggedDays"}},
			{"nothing at all", BalanceInput{Today: today}, []string{"weighIns", "spanDays", "loggedDays"}},
		}
		for _, tt := range tests {
			got := EstimateFromLogs(tt.in)
			if got.Kcal != nil || len(got.Missing) != len(tt.missing) {
				t.Errorf("%s: got %+v", tt.name, got)
				continue
			}
			for i, m := range tt.missing {
				if got.Missing[i] != m {
					t.Errorf("%s: missing %v, want %v", tt.name, got.Missing, tt.missing)
				}
			}
		}
	})
	t.Run("weigh-ins older than four weeks are not used", func(t *testing.T) {
		readings := append([]insights.Reading{{Date: today.AddDays(-60), Value: 95}}, weighIns(20, func(int) float64 { return 80 })...)
		got := EstimateFromLogs(BalanceInput{Today: today, Readings: readings, IntakeKcal: intake(1, 19, 2500)})
		if got.WeighIns != 20 || got.Kcal == nil {
			t.Fatalf("got %+v", got)
		}
	})
}

func TestAverageStepsCountsCompleteDaysOnly(t *testing.T) {
	today := score.MustDate("2026-11-02")
	days := []insights.StepDay{
		{Date: "2026-11-02", Steps: 1000}, {Date: "2026-11-01", Steps: 8000}, {Date: "2026-10-31", Steps: 10000},
		{Date: "2026-10-18", Steps: 6000}, {Date: "2026-10-19", Steps: 0},
	}
	avg, n := AverageSteps(days, today)
	// Today is unfinished, 10-19 has no steps and 10-18 is 15 days back.
	if n != 2 || avg != 9000 {
		t.Fatalf("avg = %v over %d", avg, n)
	}
}

func TestEveryCitedSourceKeyHasACitation(t *testing.T) {
	for key, cite := range Sources {
		if cite == "" {
			t.Errorf("source %q has no citation", key)
		}
	}
}
