package api

import (
	"fmt"
	"net/http"
	"testing"
	"time"
)

// seedSet stores a set on any date, past the closed-day rule the API enforces.
func (h *harness) seedSet(p person, key, date string, reps, seconds *int, loadKg *float64) {
	h.t.Helper()
	h.sql(`INSERT INTO exercise_sets (user_id, local_date, exercise_id, reps, seconds, load_kg, client_op_id)
		SELECT u.id, $3::date, e.id, $4, $5, $6, $7::uuid FROM users u, exercises e
		WHERE u.name = $1 AND e.key = $2`, p.Name, key, date, reps, seconds, loadKg, h.nextOp())
}

func floatp(f float64) *float64 { return &f }

func TestTrainingHistoryMonthAggregates(t *testing.T) {
	h := newHarness(t)
	nick, nadia := h.pair()
	h.seedSet(nick, "push_up", "2026-10-05", intp(12), nil, nil)
	h.seedSet(nick, "pull_up", "2026-10-05", intp(6), nil, nil)
	h.seedSet(nick, "goblet_squat", "2026-10-12", intp(8), nil, floatp(20))
	h.seedSet(nick, "push_up", "2026-09-30", intp(9), nil, nil)
	h.seedSet(nadia, "push_up", "2026-10-05", intp(30), nil, nil)
	h.sql(`INSERT INTO training_plans (user_id, starts_on, weeks, days) SELECT id, '2026-10-01', 4, '[]' FROM users WHERE name = 'Nick'`)
	h.sql(`INSERT INTO training_sessions (user_id, plan_id, local_date, day_index, completed_at)
		SELECT u.id, p.id, d.day::date, 0, d.done FROM users u JOIN training_plans p ON p.user_id = u.id,
		(VALUES ('2026-10-05', now()), ('2026-10-12', NULL::timestamptz)) AS d(day, done) WHERE u.name = 'Nick'`)
	h.sql(`INSERT INTO activity_logs (user_id, local_date, type, quantity, client_op_id)
		SELECT id, '2026-11-01', 'yoga_minutes', q, gen_random_uuid() FROM users, (VALUES (15), (10)) AS v(q) WHERE name = 'Nick'`)
	putWorkouts(h, nick,
		workout("w-yoga", "yoga", ny(2026, time.October, 20, 7, 0), 30),
		workout("w-run", "running", ny(2026, time.October, 20, 18, 0), 40),
		workout("w-run2", "running", ny(2026, time.October, 21, 18, 0), 20)).expect(http.StatusOK)

	oct := h.get("/api/training/history?month=2026-10", nick.Token).expect(http.StatusOK)
	if oct.str("month") != "2026-10" || oct.length("days") != 4 {
		t.Fatalf("october = %s", oct.Body)
	}
	if oct.str("days.0.date") != "2026-10-05" || oct.num("days.0.sets") != 2 || !oct.flag("days.0.sessionCompleted") ||
		oct.num("days.0.yogaMinutes") != 0 || oct.length("days.0.workoutTypes") != 0 ||
		oct.str("days.0.logged.0.exercise") != "push_up" || oct.num("days.0.logged.0.reps") != 12 {
		t.Fatalf("day one = %s", oct.Body)
	}
	if oct.str("days.1.date") != "2026-10-12" || oct.flag("days.1.sessionCompleted") ||
		oct.num("days.1.logged.0.loadKg") != 20 || oct.str("days.1.logged.0.name") != "Goblet squat" {
		t.Fatalf("uncompleted session day = %s", oct.Body)
	}
	if oct.str("days.2.date") != "2026-10-20" || oct.num("days.2.sets") != 0 || oct.num("days.2.yogaMinutes") != 30 ||
		oct.str("days.2.workoutTypes.0") != "running" || oct.str("days.2.workoutTypes.1") != "yoga" {
		t.Fatalf("workout day = %s", oct.Body)
	}
	if oct.str("days.3.date") != "2026-10-21" || oct.num("days.3.yogaMinutes") != 0 {
		t.Fatalf("run day = %s", oct.Body)
	}

	nov := h.get("/api/training/history?month=2026-11", nick.Token).expect(http.StatusOK)
	if nov.length("days") != 1 || nov.num("days.0.yogaMinutes") != 25 || nov.num("days.0.sets") != 0 {
		t.Fatalf("november = %s", nov.Body)
	}
	if h.get("/api/training/history?month=2026-12", nick.Token).expect(http.StatusOK).length("days") != 0 {
		t.Fatal("an empty month lists no days")
	}
	if got := h.get("/api/training/history?month=2026-10", nadia.Token).expect(http.StatusOK); got.length("days") != 1 {
		t.Fatalf("history must be per person: %s", got.Body)
	}
}

func TestTrainingHistoryValidatesMonthAndAuth(t *testing.T) {
	h := newHarness(t)
	nick := h.joinAdmin("Nick", "green")
	for _, month := range []string{"", "2026-13", "2026-1", "October", "2026-10-01"} {
		h.get("/api/training/history?month="+month, nick.Token).expect(http.StatusUnprocessableEntity)
	}
	h.get("/api/training/history?month=2026-10", "").expect(http.StatusUnauthorized)
}

func TestExerciseHistoryChartsMetricPerExerciseKind(t *testing.T) {
	h := newHarness(t)
	nick, nadia := h.pair()
	h.seedSet(nick, "bench_press", "2026-10-01", intp(5), nil, floatp(60))
	h.seedSet(nick, "bench_press", "2026-10-01", intp(8), nil, floatp(60))
	h.seedSet(nick, "bench_press", "2026-10-20", intp(3), nil, floatp(80))
	h.seedSet(nick, "bench_press", "2026-10-21", intp(15), nil, floatp(30))
	h.seedSet(nick, "bench_press", "2026-03-01", intp(5), nil, floatp(50))
	h.seedSet(nadia, "bench_press", "2026-10-02", intp(5), nil, floatp(100))

	got := h.get("/api/exercises/bench_press/history", nick.Token).expect(http.StatusOK)
	if got.str("metric") != "e1rm_kg" || !got.flag("estimated") || got.num("days") != 180 || got.length("points") != 2 ||
		got.str("points.0.date") != "2026-10-01" || got.at("points.0.value") != 76.0 ||
		got.str("points.1.date") != "2026-10-20" || got.at("points.1.value") != 88.0 {
		t.Fatalf("bench = %s", got.Body)
	}
	wide := h.get("/api/exercises/bench_press/history?days=365", nick.Token).expect(http.StatusOK)
	if wide.length("points") != 3 || wide.str("points.0.date") != "2026-03-01" {
		t.Fatalf("365 days = %s", wide.Body)
	}

	h.seedSet(nick, "goblet_squat", "2026-10-10", intp(12), nil, floatp(20))
	volume := h.get("/api/exercises/goblet_squat/history", nick.Token).expect(http.StatusOK)
	if volume.str("metric") != "volume_kg" || volume.flag("estimated") || volume.at("points.0.value") != 240.0 {
		t.Fatalf("goblet = %s", volume.Body)
	}

	h.seedSet(nick, "pull_up", "2026-10-10", intp(4), nil, nil)
	h.seedSet(nick, "pull_up", "2026-10-17", intp(6), nil, nil)
	h.post("/api/exercises/pull_up/max", nick.Token, obj{"reps": 7}).expect(http.StatusCreated)
	reps := h.get("/api/exercises/pull_up/history", nick.Token).expect(http.StatusOK)
	if reps.str("metric") != "reps" || reps.flag("estimated") || reps.length("points") != 2 || reps.at("points.1.value") != 6.0 ||
		reps.length("maxTests") != 1 || reps.str("maxTests.0.date") != "2026-11-02" || reps.num("maxTests.0.reps") != 7 ||
		!reps.isNull("maxTests.0.seconds") {
		t.Fatalf("pull-up = %s", reps.Body)
	}

	h.seedSet(nick, "plank", "2026-10-10", nil, intp(40), nil)
	h.seedSet(nick, "plank", "2026-10-10", nil, intp(55), nil)
	hold := h.get("/api/exercises/plank/history", nick.Token).expect(http.StatusOK)
	if hold.str("metric") != "seconds" || hold.length("points") != 1 || hold.at("points.0.value") != 55.0 {
		t.Fatalf("plank = %s", hold.Body)
	}

	empty := h.get("/api/exercises/deadlift/history", nick.Token).expect(http.StatusOK)
	if empty.length("points") != 0 || empty.length("maxTests") != 0 {
		t.Fatalf("no sets = %s", empty.Body)
	}
}

func TestExerciseHistoryValidation(t *testing.T) {
	h := newHarness(t)
	nick, nadia := h.pair()
	h.get("/api/exercises/nope/history", nick.Token).expect(http.StatusNotFound)
	for _, days := range []string{"0", "731", "x", "-5"} {
		h.get(fmt.Sprintf("/api/exercises/push_up/history?days=%s", days), nick.Token).expect(http.StatusUnprocessableEntity)
	}
	custom := h.post("/api/exercises", nick.Token, obj{"name": "Mine", "primaryMuscles": []string{"core"},
		"measure": "reps", "load": "bodyweight"}).expect(http.StatusCreated)
	h.get("/api/exercises/"+custom.str("exercise.key")+"/history", nadia.Token).expect(http.StatusNotFound)
	h.get("/api/exercises/push_up/history", "").expect(http.StatusUnauthorized)
}
