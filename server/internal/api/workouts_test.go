package api

import (
	"fmt"
	"net/http"
	"strings"
	"testing"
	"time"
)

// workout builds a valid item that started at the given New York wall clock.
func workout(id, typ string, start time.Time, minutes float64) obj {
	return obj{
		"id": id, "type": typ,
		"startedAt": start.UTC().Format(time.RFC3339), "endedAt": start.Add(time.Duration(minutes * float64(time.Minute))).UTC().Format(time.RFC3339),
		"durationMin": minutes, "kcal": 250.46, "distanceM": 5000.0, "avgHr": 142.0, "source": "Apple Watch",
	}
}

func putWorkouts(h *harness, p person, items ...obj) *response {
	return h.put("/api/health/workouts", p.Token, obj{"items": items})
}

func TestWorkoutsRoundTripNewestFirstWithNulls(t *testing.T) {
	h := newHarness(t)
	nick := h.joinAdmin("Nick", "green")
	bare := workout("w-bare", "yoga", ny(2026, time.November, 1, 9, 0), 30)
	bare["kcal"], bare["distanceM"], bare["avgHr"] = nil, nil, nil
	putWorkouts(h, nick,
		workout("w-run", "running", ny(2026, time.October, 31, 7, 0), 40.04), bare).
		expect(http.StatusOK)
	if got := putWorkouts(h, nick, workout("w-today", "strength", ny(2026, time.November, 2, 8, 0), 55)).
		expect(http.StatusOK); got.num("saved") != 1 {
		t.Fatalf("saved = %s", got.Body)
	}

	got := h.get("/api/workouts?days=14", nick.Token).expect(http.StatusOK)
	if got.length("workouts") != 3 || got.str("workouts.0.id") != "w-today" || got.str("workouts.1.id") != "w-bare" ||
		got.str("workouts.2.id") != "w-run" {
		t.Fatalf("workouts = %s", got.Body)
	}
	if got.str("workouts.2.type") != "running" || got.str("workouts.2.date") != "2026-10-31" ||
		got.str("workouts.2.startedAt") != "2026-10-31T11:00:00Z" || got.str("workouts.2.endedAt") != "2026-10-31T11:40:02Z" ||
		got.at("workouts.2.durationMin") != 40.0 || got.at("workouts.2.kcal") != 250.5 ||
		got.at("workouts.2.distanceM") != 5000.0 || got.at("workouts.2.avgHr") != 142.0 {
		t.Fatalf("running = %s", got.Body)
	}
	if !got.isNull("workouts.1.kcal") || !got.isNull("workouts.1.distanceM") || !got.isNull("workouts.1.avgHr") {
		t.Fatalf("nulls must stay null: %s", got.Body)
	}
	if got.num("week.count") != 1 || got.num("week.minutes") != 55 {
		t.Fatalf("week = %s", got.Body)
	}
}

func TestWorkoutsUpsertIsIdempotentAndUpdatesInPlace(t *testing.T) {
	h := newHarness(t)
	nick := h.joinAdmin("Nick", "green")
	start := ny(2026, time.November, 1, 7, 0)
	for range 3 {
		putWorkouts(h, nick, workout("same", "running", start, 30)).expect(http.StatusOK)
	}
	edited := workout("same", "cycling", start.Add(time.Hour), 60)
	edited["kcal"] = nil
	putWorkouts(h, nick, edited).expect(http.StatusOK)

	got := h.get("/api/workouts?days=7", nick.Token).expect(http.StatusOK)
	if got.length("workouts") != 1 || got.str("workouts.0.type") != "cycling" || got.num("workouts.0.durationMin") != 60 ||
		!got.isNull("workouts.0.kcal") {
		t.Fatalf("resend must update in place: %s", got.Body)
	}
}

func TestWorkoutsLocalDateFollowsTheCallersZone(t *testing.T) {
	h := newHarness(t)
	nick := h.joinAdmin("Nick", "green")
	// 22:30 on Nov 1 in New York is already Nov 2 in UTC.
	putWorkouts(h, nick, workout("late", "dance", ny(2026, time.November, 1, 22, 30), 45)).expect(http.StatusOK)
	got := h.get("/api/workouts?days=7", nick.Token).expect(http.StatusOK)
	if got.str("workouts.0.date") != "2026-11-01" || got.str("workouts.0.startedAt") != "2026-11-02T03:30:00Z" {
		t.Fatalf("date = %s", got.Body)
	}
}

func TestWorkoutsDaysWindowAndWeekAreSeparate(t *testing.T) {
	h := newHarness(t)
	nick := h.joinAdmin("Nick", "green")
	h.clock.Set(ny(2026, time.November, 5, 12, 0)) // Thursday
	putWorkouts(h, nick,
		workout("sun", "walking", ny(2026, time.November, 1, 9, 0), 20),
		workout("mon", "running", ny(2026, time.November, 2, 9, 0), 30),
		workout("thu", "yoga", ny(2026, time.November, 5, 9, 0), 40),
	).expect(http.StatusOK)

	one := h.get("/api/workouts?days=1", nick.Token).expect(http.StatusOK)
	if one.length("workouts") != 1 || one.str("workouts.0.id") != "thu" {
		t.Fatalf("days=1 = %s", one.Body)
	}
	if one.num("week.count") != 2 || one.num("week.minutes") != 70 {
		t.Fatalf("the week summary must not shrink with days: %s", one.Body)
	}
	if all := h.get("/api/workouts?days=365", nick.Token).expect(http.StatusOK); all.length("workouts") != 3 {
		t.Fatalf("days=365 = %s", all.Body)
	}
}

func TestWorkoutsAreScopedToTheCaller(t *testing.T) {
	h := newHarness(t)
	nick, nadia := h.pair()
	start := ny(2026, time.November, 2, 8, 0)
	putWorkouts(h, nick, workout("shared-id", "running", start, 30)).expect(http.StatusOK)
	putWorkouts(h, nadia, workout("shared-id", "yoga", start, 45)).expect(http.StatusOK)

	nicks := h.get("/api/workouts?days=7", nick.Token).expect(http.StatusOK)
	nadias := h.get("/api/workouts?days=7", nadia.Token).expect(http.StatusOK)
	if nicks.length("workouts") != 1 || nicks.str("workouts.0.type") != "running" ||
		nadias.length("workouts") != 1 || nadias.str("workouts.0.type") != "yoga" {
		t.Fatalf("nick = %s nadia = %s", nicks.Body, nadias.Body)
	}
}

func TestWorkoutsRequireSignIn(t *testing.T) {
	h := newHarness(t)
	h.joinAdmin("Nick", "green")
	h.put("/api/health/workouts", "", obj{"items": []obj{}}).expect(http.StatusUnauthorized).code("unauthorized")
	h.get("/api/workouts?days=7", "").expect(http.StatusUnauthorized).code("unauthorized")
}

func TestWorkoutValidation(t *testing.T) {
	h := newHarness(t)
	nick := h.joinAdmin("Nick", "green")
	start := ny(2026, time.November, 2, 8, 0)
	mutate := func(key string, value any) obj {
		item := workout("ok", "running", start, 30)
		item[key] = value
		return item
	}
	tests := []struct {
		name string
		item obj
	}{
		{"unknown type", mutate("type", "skiing")},
		{"empty id", mutate("id", "")},
		{"long id", mutate("id", strings.Repeat("x", 101))},
		{"control char in id", mutate("id", "a\x00b")},
		{"empty source", mutate("source", "")},
		{"long source", mutate("source", strings.Repeat("s", 33))},
		{"zero duration", mutate("durationMin", 0)},
		{"duration that rounds to zero", mutate("durationMin", 0.04)},
		{"duration over a day", mutate("durationMin", 1441)},
		{"negative kcal", mutate("kcal", -1)},
		{"kcal over bound", mutate("kcal", 20001)},
		{"negative distance", mutate("distanceM", -5)},
		{"distance over bound", mutate("distanceM", 1000001)},
		{"heart rate too low", mutate("avgHr", 19)},
		{"heart rate too high", mutate("avgHr", 251)},
		{"ends before it starts", mutate("endedAt", start.Add(-time.Minute).UTC().Format(time.RFC3339))},
		{"ends when it starts", mutate("endedAt", start.UTC().Format(time.RFC3339))},
		{"starts in the future", workout("ok", "running", h.clock.Now().Add(time.Hour), 30)},
		{"starts over 400 days ago", workout("ok", "running", h.clock.Now().AddDate(0, 0, -401), 30)},
		{"startedAt missing", mutate("startedAt", nil)},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got := putWorkouts(h, nick, tt.item)
			if got.Status == http.StatusBadRequest {
				got.code("invalid_json")
				return
			}
			got.expect(http.StatusUnprocessableEntity).code("invalid_request")
			if got.num("items.0.index") != 0 || got.str("items.0.code") != "invalid_request" {
				t.Fatalf("item detail = %s", got.Body)
			}
		})
	}
	if got := h.get("/api/workouts?days=365", nick.Token).expect(http.StatusOK); got.length("workouts") != 0 {
		t.Fatalf("a rejected workout was stored: %s", got.Body)
	}
}

func TestWorkoutBoundaryValuesAreAccepted(t *testing.T) {
	h := newHarness(t)
	nick := h.joinAdmin("Nick", "green")
	start := h.clock.Now().Add(-25 * time.Hour)
	max := workout("max", "other", start, 1440)
	max["kcal"], max["distanceM"], max["avgHr"] = 20000.0, 1000000.0, 250.0
	min := workout("min", "hiking", start, 0.1)
	min["kcal"], min["distanceM"], min["avgHr"] = 0, 0, 20
	putWorkouts(h, nick, max, min).expect(http.StatusOK)
}

func TestWorkoutBatchIsAllOrNothingWithPerItemErrors(t *testing.T) {
	h := newHarness(t)
	nick := h.joinAdmin("Nick", "green")
	start := ny(2026, time.November, 2, 8, 0)
	items := []obj{workout("good", "running", start, 30), workout("bad-type", "nope", start, 30),
		workout("good-too", "yoga", start, 30)}
	items[2]["durationMin"] = 0
	got := h.put("/api/health/workouts", nick.Token, obj{"items": items}).expect(http.StatusUnprocessableEntity).code("invalid_request")
	if got.length("items") != 2 || got.num("items.0.index") != 1 || got.num("items.1.index") != 2 {
		t.Fatalf("items = %s", got.Body)
	}
	if list := h.get("/api/workouts?days=7", nick.Token).expect(http.StatusOK); list.length("workouts") != 0 {
		t.Fatalf("nothing may apply when any item is bad: %s", list.Body)
	}
}

func TestWorkoutBatchSizeLimits(t *testing.T) {
	h := newHarness(t)
	nick := h.joinAdmin("Nick", "green")
	start := ny(2026, time.November, 2, 8, 0)
	putWorkouts(h, nick).expect(http.StatusUnprocessableEntity).code("invalid_request")

	hundred := make([]obj, 100)
	for i := range hundred {
		hundred[i] = workout(fmt.Sprintf("w%d", i), "walking", start, 10)
	}
	if got := putWorkouts(h, nick, hundred...).expect(http.StatusOK); got.num("saved") != 100 {
		t.Fatalf("saved = %s", got.Body)
	}
	putWorkouts(h, nick, append(hundred, workout("w100", "walking", start, 10))...).
		expect(http.StatusUnprocessableEntity).code("invalid_request")
}

func TestWorkoutRequestShapeErrors(t *testing.T) {
	h := newHarness(t)
	nick := h.joinAdmin("Nick", "green")
	h.put("/api/health/workouts", nick.Token, obj{"items": []obj{{"id": "x", "bogus": 1}}}).
		expect(http.StatusBadRequest).code("invalid_json")
	h.put("/api/health/workouts", nick.Token, obj{"nope": 1}).expect(http.StatusBadRequest).code("invalid_json")
	for _, days := range []string{"0", "366", "abc", ""} {
		h.get("/api/workouts?days="+days, nick.Token).expect(http.StatusUnprocessableEntity).code("invalid_request")
	}
}

func TestBoardShowsWorkoutsThisWeekPerPerson(t *testing.T) {
	h := newHarness(t)
	nick, nadia := h.pair()
	h.clock.Set(ny(2026, time.November, 5, 12, 0)) // Thursday of the week of Nov 2
	putWorkouts(h, nick,
		workout("prev-sun", "running", ny(2026, time.November, 1, 20, 0), 30),
		workout("mon", "running", ny(2026, time.November, 2, 7, 0), 30),
		workout("wed", "yoga", ny(2026, time.November, 4, 7, 0), 30),
		workout("thu", "walking", ny(2026, time.November, 5, 7, 0), 30),
	).expect(http.StatusOK)

	got := h.get("/api/board", nadia.Token).expect(http.StatusOK)
	if got.str("users.0.name") != "Nadia" || got.num("users.0.workoutsThisWeek") != 0 ||
		got.str("users.1.name") != "Nick" || got.num("users.1.workoutsThisWeek") != 3 {
		t.Fatalf("board = %s", got.Body)
	}
}
