package api

import (
	"context"
	"net/http"
	"strings"
	"testing"

	"github.com/nc1107/new-me/server/migrations"
)

// questIndex finds a quest in a day answer by key.
func questIndex(t *testing.T, r *response, key string) string { return questAt(t, r, "quests", key) }

// questAt finds a quest by key in the list at the path.
func questAt(t *testing.T, r *response, list, key string) string {
	t.Helper()
	for i := range r.length(list) {
		if p := list + "." + itoa(i); r.str(p+".key") == key {
			return p
		}
	}
	t.Fatalf("no quest %s: %s", key, r.Body)
	return ""
}

func TestLoggingWaterStoresMillilitresAndRejectsWhatDoesNotFit(t *testing.T) {
	h := newHarness(t)
	nick := h.joinAdmin("Nick", "green")

	got := h.logActivity(nick, "water", "ml", 250).expect(http.StatusCreated)
	if got.str("log.type") != "water" || got.str("log.unit") != "ml" || got.num("log.quantity") != 250 {
		t.Fatalf("log = %s", got.Body)
	}
	h.logActivity(nick, "water_ml", "", 500).expect(http.StatusCreated)
	h.logActivity(nick, "water", "ml", 5000).expect(http.StatusCreated)

	h.logActivity(nick, "water", "ml", 5001).expect(http.StatusUnprocessableEntity)
	h.logActivity(nick, "water", "ml", 0).expect(http.StatusUnprocessableEntity)
	h.logActivity(nick, "water", "oz", 8).expect(http.StatusUnprocessableEntity)
	h.logActivity(nick, "water", "ml", 250, obj{"name": "Tea"}).expect(http.StatusUnprocessableEntity)

	logs := h.get("/api/logs", nick.Token).expect(http.StatusOK)
	if logs.length("logs") != 3 || logs.str("logs.0.type") != "water" || logs.str("logs.0.unit") != "ml" {
		t.Fatalf("logs = %s", logs.Body)
	}
}

func TestWaterQuestIsOnByDefaultAndJoinsTheDayOnceItHasData(t *testing.T) {
	h := newHarness(t)
	nick := h.joinAdmin("Nick", "green")

	me := h.get("/api/me", nick.Token).expect(http.StatusOK)
	if me.str("questTemplates.8.key") != "water" || !me.flag("questTemplates.8.enabled") ||
		me.num("questTemplates.8.target") != 2200 || me.str("questTemplates.8.unit") != "ml" ||
		me.num("questTemplates.8.points") != 50 || me.str("questTemplates.8.title") != "Water" {
		t.Fatalf("template = %s", me.Body)
	}

	empty := h.get("/api/today", nick.Token).expect(http.StatusOK)
	q := questIndex(t, empty, "water")
	if empty.num(q+".target") != 2200 || empty.num(q+".actual") != 0 || empty.num("day.maxBase") != 300 {
		t.Fatalf("water stays out of the day's maximum until it has data: %s", empty.Body)
	}

	logged := h.logActivity(nick, "water", "ml", 1100).expect(http.StatusCreated)
	q = questAt(t, logged, "day.quests", "water")
	if logged.num(q+".actual") != 1100 || logged.num("day.maxBase") != 350 {
		t.Fatalf("logged water joins the day: %s", logged.Body)
	}
	today := h.get("/api/today", nick.Token).expect(http.StatusOK)
	q = questIndex(t, today, "water")
	if today.num(q+".actual") != 1100 || today.num(q+".basePoints") != 25 || today.flag(q+".done") {
		t.Fatalf("water = %s", today.Body)
	}
}

func TestHealthWaterCountsAndTheLargerSourceWinsNeverTheSum(t *testing.T) {
	h := newHarness(t)
	nick := h.joinAdmin("Nick", "green")

	h.putHealth(nick, "2026-11-02", "water_ml", 1800).expect(http.StatusOK)
	today := h.get("/api/today", nick.Token).expect(http.StatusOK)
	q := questIndex(t, today, "water")
	if today.num(q+".actual") != 1800 || today.num("day.maxBase") != 350 {
		t.Fatalf("Health water = %s", today.Body)
	}

	h.logActivity(nick, "water", "ml", 1100).expect(http.StatusCreated)
	today = h.get("/api/today", nick.Token).expect(http.StatusOK)
	if got := today.num(questIndex(t, today, "water") + ".actual"); got != 1800 {
		t.Fatalf("1800 from Health and 1100 logged counted as %d, want the larger 1800: %s", got, today.Body)
	}

	h.logActivity(nick, "water", "ml", 900).expect(http.StatusCreated)
	today = h.get("/api/today", nick.Token).expect(http.StatusOK)
	q = questIndex(t, today, "water")
	if today.num(q+".actual") != 2000 || today.flag(q+".done") {
		t.Fatalf("2000 logged now exceeds 1800 from Health, never 3800: %s", today.Body)
	}

	h.putHealth(nick, "2026-11-02", "water_ml", 2300).expect(http.StatusOK)
	today = h.get("/api/today", nick.Token).expect(http.StatusOK)
	q = questIndex(t, today, "water")
	if today.num(q+".actual") != 2300 || !today.flag(q+".done") {
		t.Fatalf("Health water reaching the target finishes the quest: %s", today.Body)
	}
}

func TestWaterTargetFollowsSexAndAppliesFromTheTargetsPage(t *testing.T) {
	h := newHarness(t)
	nick := h.joinAdmin("Nick", "green")

	got := h.get("/api/targets", nick.Token).expect(http.StatusOK)
	p := targetPath(t, got, "water")
	if got.num(p+".value") != 2200 || got.num(p+".current") != 2200 || got.str(p+".unit") != "ml" ||
		!got.flag(p+".applicable") || got.length(p+".missing") != 0 || got.str(p+".label") != "guideline" ||
		!strings.Contains(got.str(p+".formula"), "About you") || got.flag(p+".details.personalized") {
		t.Fatalf("no sex = %s", got.Body)
	}
	if got.str(p+".sources.0") != "nasem2005" || got.str(p+".sources.1") != "efsa2010" ||
		!strings.Contains(got.str("sources.nasem2005"), "National Academies") || got.str("sources.efsa2010") == "" {
		t.Fatalf("sources = %s", got.Body)
	}

	h.patch("/api/me", nick.Token, obj{"sex": "male"}).expect(http.StatusOK)
	got = h.get("/api/targets", nick.Token).expect(http.StatusOK)
	p = targetPath(t, got, "water")
	if got.num(p+".value") != 3000 || !got.flag(p+".details.personalized") ||
		strings.Contains(got.str(p+".formula"), "About you") || !strings.Contains(got.str(p+".formula"), "3.0 L") {
		t.Fatalf("male = %s", got.Body)
	}

	applied := h.post("/api/targets/apply", nick.Token, obj{"keys": []string{"water"}}).expect(http.StatusOK)
	if applied.str("applied.0") != "water" || applied.num("questTemplates.8.target") != 3000 {
		t.Fatalf("apply = %s", applied.Body)
	}
	got = h.get("/api/targets", nick.Token).expect(http.StatusOK)
	if p = targetPath(t, got, "water"); got.num(p+".current") != 3000 {
		t.Fatalf("applied target = %s", got.Body)
	}

	h.patch("/api/me", nick.Token, obj{"sex": "female", "units": "imperial"}).expect(http.StatusOK)
	got = h.get("/api/targets", nick.Token).expect(http.StatusOK)
	p = targetPath(t, got, "water")
	if got.num(p+".value") != 2200 || !strings.Contains(got.str(p+".formula"), "74 fl oz") {
		t.Fatalf("female, imperial = %s", got.Body)
	}
	applied = h.post("/api/targets/apply", nick.Token, obj{"keys": []string{"water"}}).expect(http.StatusOK)
	if applied.num("questTemplates.8.target") != 2200 {
		t.Fatalf("apply female = %s", applied.Body)
	}
}

func TestWaterTargetRange(t *testing.T) {
	h := newHarness(t)
	nick := h.joinAdmin("Nick", "green")
	for target, status := range map[int]int{249: http.StatusUnprocessableEntity, 250: http.StatusOK,
		6000: http.StatusOK, 6001: http.StatusUnprocessableEntity} {
		h.patch("/api/me", nick.Token, obj{"questTemplates": []obj{{"key": "water", "target": target}}}).expect(status)
	}
	h.patch("/api/me", nick.Token, obj{"questTemplates": []obj{{"key": "water", "targetAlt": 5}}}).
		expect(http.StatusUnprocessableEntity)
}

// backfillSQL is the part of the migration that adds the quest for people who already exist.
func backfillSQL(t *testing.T) string {
	t.Helper()
	raw, err := migrations.Files.ReadFile("0025_v16_water.sql")
	if err != nil {
		t.Fatal(err)
	}
	sql := string(raw)
	i := strings.Index(sql, "INSERT INTO quest_templates")
	if i < 0 {
		t.Fatal("the migration no longer backfills quest_templates")
	}
	return sql[i:]
}

func TestMigrationBackfillsWaterForExistingPeopleBySex(t *testing.T) {
	h := newHarness(t)
	nick, nadia := h.pair()
	h.patch("/api/me", nick.Token, obj{"sex": "male"}).expect(http.StatusOK)
	h.patch("/api/me", nadia.Token, obj{"sex": "female", "questTemplates": []obj{{"key": "exercise", "enabled": false}}}).
		expect(http.StatusOK)

	// Put both people back to how they were before the migration ran.
	ctx := context.Background()
	if _, err := h.db.Pool.Exec(ctx, `DELETE FROM quest_templates WHERE key = 'water'`); err != nil {
		t.Fatal(err)
	}
	for range 2 {
		if _, err := h.db.Pool.Exec(ctx, backfillSQL(t)); err != nil {
			t.Fatalf("backfill: %v", err)
		}
	}

	for _, tc := range []struct {
		p      person
		target int
	}{{nick, 3000}, {nadia, 2200}} {
		me := h.get("/api/me", tc.p.Token).expect(http.StatusOK)
		if me.length("questTemplates") != 9 {
			t.Fatalf("the backfill must add exactly one water template: %s", me.Body)
		}
		last := "questTemplates.8"
		if me.str(last+".key") != "water" || !me.flag(last+".enabled") || me.num(last+".target") != tc.target ||
			me.str(last+".unit") != "ml" || me.num(last+".points") != 50 || me.num(last+".position") != 8 {
			t.Fatalf("backfilled template = %s", me.Body)
		}
	}
	nadiaMe := h.get("/api/me", nadia.Token).expect(http.StatusOK)
	if nadiaMe.flag("questTemplates.6.enabled") {
		t.Fatalf("the backfill changed another quest: %s", nadiaMe.Body)
	}
}
