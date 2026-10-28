package api

import (
	"context"
	"net/http"
	"testing"
	"time"
)

// seedSteps writes finished days of steps straight to the table, since the API only accepts
// today and yesterday. The first value is the day offset daysAgo before today, the next one a
// day earlier, and so on.
func (h *harness) seedSteps(p person, daysAgo int, perDay ...float64) {
	h.t.Helper()
	for i, v := range perDay {
		date := h.clock.Now().In(newYork).AddDate(0, 0, -(daysAgo + i)).Format(time.DateOnly)
		_, err := h.db.Pool.Exec(context.Background(), `
			INSERT INTO health_daily (user_id, local_date, metric, value, source, measured_at)
			VALUES ($1, $2::date, 'steps', $3, 'fake', now())`, p.ID, date, v)
		if err != nil {
			h.t.Fatalf("seed steps: %v", err)
		}
	}
}

func steady(v float64, n int) []float64 {
	out := make([]float64, n)
	for i := range out {
		out[i] = v
	}
	return out
}

func TestInsightsForANewPersonAreEmptyNotErrors(t *testing.T) {
	h := newHarness(t)
	nick := h.joinAdmin("Nick", "green")
	got := h.get("/api/insights", nick.Token).expect(http.StatusOK)
	if !got.isNull("steps.avg7") || !got.isNull("sleep.avg7Min") || got.str("steps.trend") != "flat" || !got.isNull("steps.best") ||
		!got.isNull("steps.suggestion") || got.num("steps.goal") != 8000 || got.num("steps.daysAtGoal30") != 0 {
		t.Fatalf("steps = %s", got.Body)
	}
	if !got.isNull("sleep.avgBedtime") || !got.isNull("sleep.avgWake") || !got.isNull("sleep.stages7") ||
		!got.isNull("sleep.lastNight") || got.length("sleep.nights") != 0 || got.num("sleep.targetMin") != 420 ||
		got.num("sleep.bedtimeSpreadMin") != 0 {
		t.Fatalf("sleep = %s", got.Body)
	}
	if got.num("workouts.week.count") != 0 || got.length("workouts.last30.byType") != 0 {
		t.Fatalf("workouts = %s", got.Body)
	}
}

func TestInsightsStepsWithSuggestionAgeAndGoal(t *testing.T) {
	h := newHarness(t)
	nick := h.joinAdmin("Nick", "green")
	h.seedSteps(nick, 1, 7400, 7400, 7400, 7400)
	if got := h.get("/api/insights", nick.Token).expect(http.StatusOK); !got.isNull("steps.suggestion") {
		t.Fatalf("four days must not produce a suggestion: %s", got.Body)
	}
	h.seedSteps(nick, 5, steady(7400, 10)...)
	h.seedSteps(nick, 15, steady(9000, 10)...)

	got := h.get("/api/insights", nick.Token).expect(http.StatusOK)
	if got.num("steps.avg7") != 7400 || got.num("steps.median14") != 7400 || got.str("steps.trend") != "flat" ||
		got.num("steps.avg30") != 8067 || got.num("steps.daysAtGoal30") != 10 {
		t.Fatalf("steps = %s", got.Body)
	}
	if got.num("steps.best.value") != 9000 || got.num("steps.suggestion.target") != 8500 ||
		got.num("steps.suggestion.bandLow") != 7000 || got.num("steps.suggestion.bandHigh") != 10000 ||
		got.flag("steps.suggestion.ageKnown") || got.num("steps.suggestion.median14") != 7400 {
		t.Fatalf("suggestion = %s", got.Body)
	}

	h.patch("/api/me", nick.Token, obj{"birthYear": 1960}).expect(http.StatusOK)
	older := h.get("/api/insights", nick.Token).expect(http.StatusOK)
	if older.num("steps.suggestion.target") != 8000 || older.num("steps.suggestion.bandLow") != 6000 ||
		older.num("steps.suggestion.bandHigh") != 8000 || !older.flag("steps.suggestion.ageKnown") {
		t.Fatalf("older suggestion = %s", older.Body)
	}

	h.patch("/api/me", nick.Token, obj{"questTemplates": []obj{{"key": "steps", "target": 7000}}}).expect(http.StatusOK)
	goal := h.get("/api/insights", nick.Token).expect(http.StatusOK)
	if goal.num("steps.goal") != 7000 || goal.num("steps.daysAtGoal30") != 24 {
		t.Fatalf("goal = %s", goal.Body)
	}
}

func TestInsightsStepsAreTheCallersOwn(t *testing.T) {
	h := newHarness(t)
	nick, nadia := h.pair()
	h.seedSteps(nick, 1, steady(12000, 14)...)
	h.seedSteps(nadia, 1, steady(5000, 14)...)
	if got := h.get("/api/insights", nick.Token).expect(http.StatusOK); got.num("steps.avg7") != 12000 {
		t.Fatalf("nick = %s", got.Body)
	}
	if got := h.get("/api/insights", nadia.Token).expect(http.StatusOK); got.num("steps.avg7") != 5000 {
		t.Fatalf("nadia = %s", got.Body)
	}
}

func TestInsightsSleepTargetFollowsTheQuest(t *testing.T) {
	h := newHarness(t)
	nick := h.joinAdmin("Nick", "green")
	h.patch("/api/me", nick.Token, obj{"questTemplates": []obj{{"key": "sleep", "target": 480, "enabled": false}}}).expect(http.StatusOK)
	if got := h.get("/api/insights", nick.Token).expect(http.StatusOK); got.num("sleep.targetMin") != 420 {
		t.Fatalf("a disabled sleep quest keeps the default: %s", got.Body)
	}
	h.patch("/api/me", nick.Token, obj{"questTemplates": []obj{{"key": "sleep", "enabled": true}}}).expect(http.StatusOK)
	if got := h.get("/api/insights", nick.Token).expect(http.StatusOK); got.num("sleep.targetMin") != 480 {
		t.Fatalf("an enabled sleep quest sets the target: %s", got.Body)
	}
}

func TestInsightsSleepStatisticsAcrossMidnight(t *testing.T) {
	h := newHarness(t)
	nick := h.joinAdmin("Nick", "green")
	night := func(day int, bedHour, bedMin, asleep int) obj {
		bed := ny(2026, time.November, day-1, bedHour, bedMin)
		if bedHour < 12 {
			bed = ny(2026, time.November, day, bedHour, bedMin)
		}
		n := sleepNight(day, time.November, asleep)
		n["bedAt"] = bed.UTC().Format(time.RFC3339)
		n["wakeAt"] = bed.Add(time.Duration(asleep+30) * time.Minute).UTC().Format(time.RFC3339)
		return n
	}
	// The first night spans the clocks going back on Nov 1, so it wakes at 05:30 local rather
	// than 06:30 and the average wake is 07:00.
	putSleep(h, nick, night(1, 23, 0, 420), night(2, 1, 0, 420)).expect(http.StatusOK)

	got := h.get("/api/insights", nick.Token).expect(http.StatusOK)
	if got.str("sleep.avgBedtime") != "00:00" || got.num("sleep.bedtimeSpreadMin") != 60 || got.str("sleep.avgWake") != "07:00" {
		t.Fatalf("sleep = %s", got.Body)
	}
	if got.num("sleep.stages7.deepMin") != 60 || got.num("sleep.stages7.remMin") != 90 || got.num("sleep.stages7.coreMin") != 270 ||
		got.num("sleep.stages7.awakeMin") != 30 {
		t.Fatalf("stages = %s", got.Body)
	}
}

func TestInsightsWorkoutSummaries(t *testing.T) {
	h := newHarness(t)
	nick, nadia := h.pair()
	h.clock.Set(ny(2026, time.November, 5, 12, 0))
	putWorkouts(h, nick,
		workout("a", "running", ny(2026, time.November, 5, 7, 0), 30),
		workout("b", "running", ny(2026, time.November, 3, 7, 0), 45),
		workout("c", "yoga", ny(2026, time.November, 1, 7, 0), 60),
		workout("d", "hiit", ny(2026, time.October, 10, 7, 0), 20),
		workout("old", "swimming", ny(2026, time.September, 20, 7, 0), 20),
	).expect(http.StatusOK)
	putWorkouts(h, nadia, workout("n", "dance", ny(2026, time.November, 4, 7, 0), 10)).expect(http.StatusOK)

	got := h.get("/api/insights", nick.Token).expect(http.StatusOK)
	if got.num("workouts.week.count") != 2 || got.num("workouts.week.minutes") != 75 ||
		got.num("workouts.last30.count") != 4 || got.num("workouts.last30.minutes") != 155 ||
		got.length("workouts.last30.byType") != 3 || got.str("workouts.last30.byType.0.type") != "running" ||
		got.num("workouts.last30.byType.0.count") != 2 || got.num("workouts.last30.byType.0.minutes") != 75 ||
		got.str("workouts.last30.byType.1.type") != "yoga" || got.str("workouts.last30.byType.2.type") != "hiit" {
		t.Fatalf("workouts = %s", got.Body)
	}
}

func TestInsightsRequireSignIn(t *testing.T) {
	h := newHarness(t)
	h.get("/api/insights", "").expect(http.StatusUnauthorized).code("unauthorized")
}
