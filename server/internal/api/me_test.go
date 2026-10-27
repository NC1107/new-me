package api

import (
	"net/http"
	"strconv"
	"testing"
	"time"
)

func TestGetMe(t *testing.T) {
	h := newHarness(t)
	nick := h.joinAdmin("Nick", "green")
	got := h.get("/api/me", nick.Token).expect(http.StatusOK)

	if got.str("user.name") != "Nick" || got.str("user.timezone") != "America/New_York" || !got.flag("user.isAdmin") {
		t.Fatalf("user = %s", got.Body)
	}
	for _, target := range []string{"kcal", "protein", "carbs", "fat"} {
		if !got.isNull("targets." + target) {
			t.Fatalf("target %s should start unset: %s", target, got.Body)
		}
	}
	if got.str("localToday") != "2026-11-02" || got.str("serverNow") != "2026-11-02T17:00:00Z" {
		t.Fatalf("clock fields = %s", got.Body)
	}
	if !got.isNull("backdateUntil") {
		t.Fatal("at noon the backdate window is closed")
	}
	if got.length("questTemplates") != 8 || got.str("questTemplates.0.key") != "steps" ||
		got.flag("questTemplates.5.enabled") || got.str("questTemplates.5.key") != "yoga" ||
		got.str("questTemplates.6.key") != "exercise" || !got.flag("questTemplates.6.enabled") ||
		got.num("questTemplates.6.target") != 30 || got.num("questTemplates.6.points") != 100 ||
		got.str("questTemplates.6.title") != "Exercise" || got.str("questTemplates.6.unit") != "min" ||
		got.str("questTemplates.7.key") != "sleep" || !got.flag("questTemplates.7.enabled") || got.num("questTemplates.7.target") != 420 ||
		got.num("questTemplates.7.points") != 50 || got.str("questTemplates.7.title") != "Sleep" {
		t.Fatalf("templates = %s", got.Body)
	}
	if got.num("questTemplates.2.targetAlt") != 15 || got.str("questTemplates.2.unitAlt") != "pages" {
		t.Fatalf("reading template = %s", got.Body)
	}
}

func TestBackdateUntilIsOnlyOfferedBeforeTheGraceHourAndAfterJoining(t *testing.T) {
	h := newHarness(t)
	h.clock.Set(ny(2026, time.November, 2, 22, 0))
	nick := h.joinAdmin("Nick", "green")

	h.clock.Set(ny(2026, time.November, 3, 8, 30))
	got := h.get("/api/me", nick.Token).expect(http.StatusOK)
	if got.str("backdateUntil") != "2026-11-03T15:00:00Z" {
		t.Fatalf("backdateUntil = %v", got.at("backdateUntil"))
	}
	if h.get("/api/today", nick.Token).str("backdateUntil") != "2026-11-03T15:00:00Z" {
		t.Fatal("today must report the same window")
	}

	// Yesterday predates the join on the join day itself.
	h2 := newHarness(t)
	h2.clock.Set(ny(2026, time.November, 2, 8, 0))
	other := h2.joinAdmin("Nick", "green")
	if !h2.get("/api/me", other.Token).isNull("backdateUntil") {
		t.Fatal("a day before the user joined is never writable")
	}
}

func TestPatchMeProfile(t *testing.T) {
	h := newHarness(t)
	nick, nadia := h.pair()

	got := h.patch("/api/me", nick.Token, obj{
		"name": "Nicholas", "color": "sky", "timezone": "Europe/London",
		"targets": obj{"kcal": 2200, "protein": 160, "carbs": 220, "fat": 70},
	}).expect(http.StatusOK)
	if got.str("user.name") != "Nicholas" || got.str("user.color") != "sky" || got.str("user.timezone") != "Europe/London" ||
		got.num("targets.kcal") != 2200 || got.num("targets.protein") != 160 || got.num("targets.fat") != 70 {
		t.Fatalf("patched me = %s", got.Body)
	}

	// null clears one target and an absent key leaves the others alone.
	got = h.patch("/api/me", nick.Token, obj{"targets": obj{"carbs": nil}}).expect(http.StatusOK)
	if !got.isNull("targets.carbs") || got.num("targets.kcal") != 2200 {
		t.Fatalf("after clearing carbs = %s", got.Body)
	}
	h.patch("/api/me", nick.Token, obj{}).expect(http.StatusOK)
	_ = nadia
}

func TestPatchMeRejectsBadValues(t *testing.T) {
	h := newHarness(t)
	nick, nadia := h.pair()
	cases := []struct {
		name   string
		body   obj
		status int
		code   string
	}{
		{"timezone", obj{"timezone": "Not/AZone"}, http.StatusUnprocessableEntity, "invalid_timezone"},
		{"color", obj{"color": "plaid"}, http.StatusUnprocessableEntity, "invalid_request"},
		{"empty name", obj{"name": ""}, http.StatusUnprocessableEntity, "invalid_request"},
		{"zero kcal", obj{"targets": obj{"kcal": 0}}, http.StatusUnprocessableEntity, "invalid_request"},
		{"huge protein", obj{"targets": obj{"protein": 1001}}, http.StatusUnprocessableEntity, "invalid_request"},
		{"name taken", obj{"name": "nadia"}, http.StatusConflict, "name_taken"},
		{"color taken", obj{"color": "violet"}, http.StatusConflict, "color_taken"},
		{"unknown quest", obj{"questTemplates": []obj{{"key": "flying", "enabled": true}}}, http.StatusUnprocessableEntity, "invalid_request"},
		{"target out of range", obj{"questTemplates": []obj{{"key": "pushups", "target": 501}}}, http.StatusUnprocessableEntity, "invalid_request"},
		{"alt on a single-target quest", obj{"questTemplates": []obj{{"key": "steps", "targetAlt": 5}}}, http.StatusUnprocessableEntity, "invalid_request"},
	}
	for _, c := range cases {
		h.patch("/api/me", nick.Token, c.body).expect(c.status).code(c.code)
	}
	// None of the failures changed anything.
	got := h.get("/api/me", nick.Token).expect(http.StatusOK)
	if got.str("user.name") != "Nick" || got.str("user.color") != "green" || got.num("questTemplates.1.target") != 30 {
		t.Fatalf("a rejected patch left changes behind: %s", got.Body)
	}
	_ = nadia
}

func TestTemplateEditsApplyFromTomorrow(t *testing.T) {
	h := newHarness(t)
	nick := h.joinAdmin("Nick", "green")
	// The join day follows edits, so test on the day after. Its snapshot may not exist yet when
	// the edit arrives; the edit must not leak into it.
	h.clock.Set(ny(2026, time.November, 3, 9, 0))
	got := h.patch("/api/me", nick.Token, obj{
		"questTemplates": []obj{
			{"key": "pushups", "target": 10},
			{"key": "meals_logged", "enabled": false},
			{"key": "yoga", "enabled": true, "target": 15},
			{"key": "reading", "target": 30, "targetAlt": 25},
		},
		"targets": obj{"protein": 140},
	}).expect(http.StatusOK)
	if got.num("questTemplates.1.target") != 10 || got.flag("questTemplates.3.enabled") ||
		got.num("questTemplates.2.targetAlt") != 25 {
		t.Fatalf("templates after edit = %s", got.Body)
	}

	today := h.get("/api/today", nick.Token).expect(http.StatusOK)
	if today.num("day.maxBase") != 300 {
		t.Fatalf("today's maximum changed after the edit: %s", today.Body)
	}
	byKey := questsByKey(today)
	if byKey["pushups"].target != 30 || byKey["protein"].target != 100 || byKey["meals_logged"].target != 2 || byKey["yoga"].target != 0 {
		t.Fatalf("today's snapshot picked up the edit: %s", today.Body)
	}

	h.clock.Set(ny(2026, time.November, 4, 9, 0))
	tomorrow := h.get("/api/today", nick.Token).expect(http.StatusOK)
	byKey = questsByKey(tomorrow)
	if byKey["pushups"].target != 10 || byKey["protein"].target != 140 || byKey["yoga"].target != 15 ||
		byKey["meals_logged"].target != 0 || byKey["reading"].target != 30 {
		t.Fatalf("tomorrow's snapshot ignored the edit: %s", tomorrow.Body)
	}
	if tomorrow.num("quests.2.targetAlt") != 25 {
		t.Fatalf("reading pages target = %s", tomorrow.Body)
	}
}

type questView struct {
	target, actual, points, base, bonus int
	done                                bool
}

func questsByKey(r *response) map[string]questView {
	r.t.Helper()
	out := map[string]questView{}
	for i := range r.length("quests") {
		p := "quests." + itoa(i) + "."
		out[r.str(p+"key")] = questView{
			target: r.num(p + "target"), actual: r.num(p + "actual"), points: r.num(p + "points"),
			base: r.num(p + "basePoints"), bonus: r.num(p + "bonusPoints"), done: r.flag(p + "done"),
		}
	}
	return out
}

func itoa(i int) string { return strconv.Itoa(i) }

func TestBirthYearIsOptionalEditableAndClearable(t *testing.T) {
	h := newHarness(t)
	nick := h.joinAdmin("Nick", "green")
	if got := h.get("/api/me", nick.Token).expect(http.StatusOK); !got.isNull("user.birthYear") {
		t.Fatalf("birthYear should start unset: %s", got.Body)
	}

	got := h.patch("/api/me", nick.Token, obj{"birthYear": 1990}).expect(http.StatusOK)
	if got.num("user.birthYear") != 1990 {
		t.Fatalf("patch answer = %s", got.Body)
	}
	if h.get("/api/me", nick.Token).expect(http.StatusOK).num("user.birthYear") != 1990 {
		t.Fatal("birthYear did not persist")
	}

	// An unrelated patch leaves it alone.
	if h.patch("/api/me", nick.Token, obj{"name": "Nicholas"}).expect(http.StatusOK).num("user.birthYear") != 1990 {
		t.Fatal("an absent birthYear must not clear it")
	}
	if !h.patch("/api/me", nick.Token, obj{"birthYear": nil}).expect(http.StatusOK).isNull("user.birthYear") {
		t.Fatal("null must clear birthYear")
	}
}

func TestBirthYearBounds(t *testing.T) {
	h := newHarness(t)
	nick := h.joinAdmin("Nick", "green")
	for _, year := range []int{1899, 2027, 0, -5} {
		h.patch("/api/me", nick.Token, obj{"birthYear": year}).expect(http.StatusUnprocessableEntity).code("invalid_request")
	}
	h.patch("/api/me", nick.Token, obj{"birthYear": "1990"}).expect(http.StatusBadRequest).code("invalid_json")
	for _, year := range []int{1900, 2026} {
		h.patch("/api/me", nick.Token, obj{"birthYear": year}).expect(http.StatusOK)
	}
	if h.get("/api/me", nick.Token).expect(http.StatusOK).num("user.birthYear") != 2026 {
		t.Fatal("the last valid year should stick")
	}
}

func TestBirthYearIsPerPerson(t *testing.T) {
	h := newHarness(t)
	nick, nadia := h.pair()
	h.patch("/api/me", nick.Token, obj{"birthYear": 1980}).expect(http.StatusOK)
	if !h.get("/api/me", nadia.Token).expect(http.StatusOK).isNull("user.birthYear") {
		t.Fatal("Nadia must not inherit Nick's birth year")
	}
}
