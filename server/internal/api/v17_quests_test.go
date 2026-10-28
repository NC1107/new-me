package api

import (
	"context"
	"fmt"
	"net/http"
	"strings"
	"testing"
	"time"

	"github.com/nc1107/new-me/server/migrations"
)

// v17Night is the night ending on the morning of the given day: in bed at bed (evening before
// when it is after noon) and up at wake, both New York clock times as hour*60+minute.
func v17Night(month time.Month, day, bed, wake int) obj {
	bedDay := day
	if bed >= 12*60 {
		bedDay--
	}
	bedAt := ny(2026, month, bedDay, bed/60, bed%60)
	wakeAt := ny(2026, month, day, wake/60, wake%60)
	asleep := int(wakeAt.Sub(bedAt).Minutes()) - 20
	return obj{
		"date": fmt.Sprintf("2026-%02d-%02d", int(month), day), "source": "Apple Watch",
		"bedAt": bedAt.UTC().Format(time.RFC3339), "wakeAt": wakeAt.UTC().Format(time.RFC3339),
		"asleepMin": asleep, "deepMin": 60, "remMin": 90, "coreMin": asleep - 150, "awakeMin": 20,
	}
}

// enableV17 turns the named quests on. The person joined today, so the edit re-snapshots today.
func enableV17(t *testing.T, h *harness, p person, keys ...string) {
	t.Helper()
	var patches []obj
	for _, k := range keys {
		patches = append(patches, obj{"key": k, "enabled": true})
	}
	h.patch("/api/me", p.Token, obj{"questTemplates": patches}).expect(http.StatusOK)
}

// routineNights are seven mornings, 26 October to 1 November, in bed at 22:30 and up at 06:30.
func routineNights() []obj {
	var out []obj
	for d := 26; d <= 31; d++ {
		out = append(out, v17Night(time.October, d, 22*60+30, 6*60+30))
	}
	return append(out, v17Night(time.November, 1, 22*60+30, 6*60+30))
}

func TestV17QuestsShipDisabledAndLeaveTodayAlone(t *testing.T) {
	h := newHarness(t)
	nick := h.joinAdmin("Nick", "green")

	me := h.get("/api/me", nick.Token).expect(http.StatusOK)
	want := []struct {
		key, unit, title string
		target           int
	}{
		{"sleep_regularity", "min", "Steady bedtime", 45},
		{"produce", "servings", "Fruit and vegetables", 5},
		{"breathing", "min", "Breathing", 5},
	}
	for i, w := range want {
		p := "questTemplates." + itoa(9+i)
		if me.str(p+".key") != w.key || me.flag(p+".enabled") || me.num(p+".target") != w.target ||
			me.str(p+".unit") != w.unit || me.num(p+".points") != 50 || me.str(p+".title") != w.title {
			t.Fatalf("template %d = %s", 9+i, me.Body)
		}
	}
	today := h.get("/api/today", nick.Token).expect(http.StatusOK)
	for _, w := range want {
		for i := range today.length("quests") {
			if today.str("quests."+itoa(i)+".key") == w.key {
				t.Fatalf("%s is on today without being chosen: %s", w.key, today.Body)
			}
		}
	}
	if today.num("day.maxBase") != 300 {
		t.Fatalf("the day's maximum changed: %s", today.Body)
	}
}

func TestLoggingProduceAndBreathingStoresTheirUnitsAndBounds(t *testing.T) {
	h := newHarness(t)
	nick := h.joinAdmin("Nick", "green")

	got := h.logActivity(nick, "produce", "servings", 2).expect(http.StatusCreated)
	if got.str("log.type") != "produce" || got.str("log.unit") != "servings" || got.num("log.quantity") != 2 {
		t.Fatalf("log = %s", got.Body)
	}
	h.logActivity(nick, "produce_servings", "", 30).expect(http.StatusCreated)
	h.logActivity(nick, "breathing", "minutes", 5).expect(http.StatusCreated)
	h.logActivity(nick, "breathing", "", 120).expect(http.StatusCreated)

	for _, bad := range []struct {
		typ, unit string
		quantity  int
	}{
		{"produce", "servings", 31}, {"produce", "servings", 0}, {"produce", "g", 2},
		{"breathing", "minutes", 121}, {"breathing", "minutes", 0}, {"breathing", "ml", 5},
	} {
		h.logActivity(nick, bad.typ, bad.unit, bad.quantity).expect(http.StatusUnprocessableEntity)
	}
	h.logActivity(nick, "produce", "servings", 1, obj{"name": "Apple"}).expect(http.StatusUnprocessableEntity)

	logs := h.get("/api/logs", nick.Token).expect(http.StatusOK)
	if logs.length("logs") != 4 || logs.str("logs.0.type") != "produce" || logs.str("logs.3.unit") != "minutes" {
		t.Fatalf("logs = %s", logs.Body)
	}
}

func TestProduceQuestCountsServingsFromTheLogOnceEnabled(t *testing.T) {
	h := newHarness(t)
	nick := h.joinAdmin("Nick", "green")
	enableV17(t, h, nick, "produce")

	empty := h.get("/api/today", nick.Token).expect(http.StatusOK)
	q := questIndex(t, empty, "produce")
	if empty.num(q+".target") != 5 || empty.num(q+".actual") != 0 || empty.num("day.maxBase") != 350 {
		t.Fatalf("a hand-logged quest is part of the day at once: %s", empty.Body)
	}

	h.logActivity(nick, "produce", "servings", 2).expect(http.StatusCreated)
	h.logActivity(nick, "produce", "servings", 1).expect(http.StatusCreated)
	today := h.get("/api/today", nick.Token).expect(http.StatusOK)
	q = questIndex(t, today, "produce")
	if today.num(q+".actual") != 3 || today.num(q+".basePoints") != 30 || today.flag(q+".done") {
		t.Fatalf("3 of 5 servings = %s", today.Body)
	}

	done := h.logActivity(nick, "produce", "servings", 2).expect(http.StatusCreated)
	q = questAt(t, done, "day.quests", "produce")
	if !done.flag(q+".done") || done.num(q+".basePoints") != 50 {
		t.Fatalf("5 of 5 servings = %s", done.Body)
	}
}

func TestBreathingTakesTheLargerOfHealthAndLoggedMinutes(t *testing.T) {
	h := newHarness(t)
	nick := h.joinAdmin("Nick", "green")
	enableV17(t, h, nick, "breathing")

	empty := h.get("/api/today", nick.Token).expect(http.StatusOK)
	q := questIndex(t, empty, "breathing")
	if empty.num(q+".target") != 5 || empty.num("day.maxBase") != 300 {
		t.Fatalf("breathing stays out of the maximum until it has data: %s", empty.Body)
	}

	h.putHealth(nick, "2026-11-02", "mindful_minutes", 3).expect(http.StatusOK)
	today := h.get("/api/today", nick.Token).expect(http.StatusOK)
	q = questIndex(t, today, "breathing")
	if today.num(q+".actual") != 3 || today.num("day.maxBase") != 350 {
		t.Fatalf("Health mindful minutes join the day: %s", today.Body)
	}

	h.logActivity(nick, "breathing", "minutes", 2).expect(http.StatusCreated)
	today = h.get("/api/today", nick.Token).expect(http.StatusOK)
	if got := today.num(questIndex(t, today, "breathing") + ".actual"); got != 3 {
		t.Fatalf("3 from Health and 2 logged counted as %d, want the larger 3: %s", got, today.Body)
	}

	h.logActivity(nick, "breathing", "minutes", 5).expect(http.StatusCreated)
	today = h.get("/api/today", nick.Token).expect(http.StatusOK)
	q = questIndex(t, today, "breathing")
	if today.num(q+".actual") != 7 || !today.flag(q+".done") {
		t.Fatalf("7 logged beats 3 from Health, never 10: %s", today.Body)
	}

	h.putHealth(nick, "2026-11-02", "mindful_minutes", 12).expect(http.StatusOK)
	today = h.get("/api/today", nick.Token).expect(http.StatusOK)
	if got := today.num(questIndex(t, today, "breathing") + ".actual"); got != 12 {
		t.Fatalf("12 from Health = %d: %s", got, today.Body)
	}
}

func TestBreathingLoggedByHandJoinsTheDayWithoutHealth(t *testing.T) {
	h := newHarness(t)
	nick := h.joinAdmin("Nick", "green")
	enableV17(t, h, nick, "breathing")
	logged := h.logActivity(nick, "breathing", "minutes", 5).expect(http.StatusCreated)
	q := questAt(t, logged, "day.quests", "breathing")
	if !logged.flag(q+".done") || logged.num("day.maxBase") != 350 {
		t.Fatalf("breathing = %s", logged.Body)
	}
}

func TestSteadyBedtimeIsJudgedFromStoredNights(t *testing.T) {
	h := newHarness(t)
	nick := h.joinAdmin("Nick", "green")
	enableV17(t, h, nick, "sleep_regularity")

	none := h.get("/api/today", nick.Token).expect(http.StatusOK)
	q := questIndex(t, none, "sleep_regularity")
	if none.num(q+".target") != 45 || none.num(q+".actual") != 0 || none.flag(q+".detail.measurable") ||
		none.num("day.maxBase") != 300 {
		t.Fatalf("without sleep the quest is out of the day: %s", none.Body)
	}

	putSleep(h, nick, routineNights()...).expect(http.StatusOK)
	baselineOnly := h.get("/api/today", nick.Token).expect(http.StatusOK)
	q = questIndex(t, baselineOnly, "sleep_regularity")
	if baselineOnly.flag(q+".detail.measurable") || baselineOnly.num("day.maxBase") != 300 {
		t.Fatalf("no night for today yet: %s", baselineOnly.Body)
	}

	// Bed at 23:00 (30 minutes late) and up at 06:15 (15 early): both inside 45.
	putSleep(h, nick, v17Night(time.November, 2, 23*60, 6*60+15)).expect(http.StatusOK)
	both := h.get("/api/today", nick.Token).expect(http.StatusOK)
	q = questIndex(t, both, "sleep_regularity")
	if !both.flag(q+".detail.measurable") || both.num(q+".actual") != 2 || !both.flag(q+".done") ||
		both.num(q+".basePoints") != 50 || both.num("day.maxBase") != 400 ||
		both.num(q+".detail.bedMedian") != 22*60+30 || both.num(q+".detail.wakeMedian") != 6*60+30 ||
		both.num(q+".detail.bedOffset") != 30 || both.num(q+".detail.wakeOffset") != -15 ||
		!both.flag(q+".detail.bedOk") || !both.flag(q+".detail.wakeOk") || both.num(q+".detail.windowMin") != 45 {
		t.Fatalf("both times inside the window: %s", both.Body)
	}

	// Bed at 00:00 is 90 minutes late: only the wake time counts, for half the quest.
	putSleep(h, nick, v17Night(time.November, 2, 0, 6*60+30)).expect(http.StatusOK)
	half := h.get("/api/today", nick.Token).expect(http.StatusOK)
	q = questIndex(t, half, "sleep_regularity")
	if half.num(q+".actual") != 1 || half.flag(q+".done") || half.num(q+".basePoints") != 25 ||
		half.flag(q+".detail.bedOk") || !half.flag(q+".detail.wakeOk") || half.num(q+".detail.bedOffset") != 90 {
		t.Fatalf("one time outside the window: %s", half.Body)
	}

	// Widening the window to 90 minutes from tomorrow is the person's choice; the template accepts it.
	h.patch("/api/me", nick.Token, obj{"questTemplates": []obj{{"key": "sleep_regularity", "target": 90}}}).expect(http.StatusOK)
	wide := h.get("/api/today", nick.Token).expect(http.StatusOK)
	q = questIndex(t, wide, "sleep_regularity")
	if wide.num(q+".detail.windowMin") != 90 || wide.num(q+".actual") != 2 {
		t.Fatalf("a 90 minute window forgives a 90 minute offset: %s", wide.Body)
	}
}

func TestSteadyBedtimeNeedsThreeEarlierNights(t *testing.T) {
	h := newHarness(t)
	nick := h.joinAdmin("Nick", "green")
	enableV17(t, h, nick, "sleep_regularity")
	putSleep(h, nick,
		v17Night(time.October, 31, 22*60+30, 6*60+30), v17Night(time.November, 1, 22*60+30, 6*60+30),
		v17Night(time.November, 2, 22*60+30, 6*60+30)).expect(http.StatusOK)
	two := h.get("/api/today", nick.Token).expect(http.StatusOK)
	q := questIndex(t, two, "sleep_regularity")
	if two.flag(q+".detail.measurable") || two.num(q+".detail.baselineNights") != 2 || two.num("day.maxBase") != 350 {
		t.Fatalf("two earlier nights are not a routine: %s", two.Body)
	}
	putSleep(h, nick, v17Night(time.October, 30, 22*60+30, 6*60+30)).expect(http.StatusOK)
	three := h.get("/api/today", nick.Token).expect(http.StatusOK)
	q = questIndex(t, three, "sleep_regularity")
	if !three.flag(q+".detail.measurable") || three.num(q+".actual") != 2 || three.num("day.maxBase") != 400 {
		t.Fatalf("three earlier nights are: %s", three.Body)
	}
}

func TestSleepRegularityIndexComesWithTheSleepInsights(t *testing.T) {
	h := newHarness(t)
	nick := h.joinAdmin("Nick", "green")

	few := h.get("/api/insights", nick.Token).expect(http.StatusOK)
	if !few.isNull("sleep.regularity.score") || few.length("sleep.regularity.missing") == 0 {
		t.Fatalf("no nights = %s", few.Body)
	}
	nights := append(routineNights(), v17Night(time.November, 2, 22*60+30, 6*60+30))
	putSleep(h, nick, nights...).expect(http.StatusOK)
	got := h.get("/api/insights", nick.Token).expect(http.StatusOK)
	if got.num("sleep.regularity.score") != 100 || got.num("sleep.regularity.nights") != 8 ||
		got.num("sleep.regularity.pairs") != 7 || got.num("sleep.regularity.windowDays") != 14 ||
		got.length("sleep.regularity.missing") != 0 {
		t.Fatalf("a perfectly regular fortnight scores 100: %s", got.Body)
	}
}

func TestV17TargetsAreCitedAndApplyToTheTemplates(t *testing.T) {
	h := newHarness(t)
	nick := h.joinAdmin("Nick", "green")
	got := h.get("/api/targets", nick.Token).expect(http.StatusOK)

	p := targetPath(t, got, "produce")
	if got.num(p+".value") != 5 || got.num(p+".current") != 5 || got.str(p+".unit") != "servings" ||
		got.str(p+".label") != "guideline" || !got.flag(p+".applicable") ||
		!strings.Contains(got.str(p+".formula"), "400 g") || !strings.Contains(got.str(p+".formula"), "80 g") {
		t.Fatalf("produce = %s", got.Body)
	}
	for i, key := range []string{"who2003", "nhs5aday", "aune2017"} {
		if got.str(p+".sources."+itoa(i)) != key || got.str("sources."+key) == "" {
			t.Fatalf("produce source %s: %s", key, got.Body)
		}
	}
	p = targetPath(t, got, "breathing")
	if got.num(p+".value") != 5 || got.str(p+".unit") != "min" || got.str(p+".sources.0") != "balban2023" ||
		got.str("sources.balban2023") == "" || got.str("sources.zaccaro2018") == "" {
		t.Fatalf("breathing = %s", got.Body)
	}

	h.patch("/api/me", nick.Token, obj{"questTemplates": []obj{
		{"key": "produce", "target": 8}, {"key": "breathing", "target": 10}}}).expect(http.StatusOK)
	applied := h.post("/api/targets/apply", nick.Token, obj{"keys": []string{"produce", "breathing"}}).expect(http.StatusOK)
	if applied.num("questTemplates.10.target") != 5 || applied.num("questTemplates.11.target") != 5 ||
		applied.flag("questTemplates.10.enabled") {
		t.Fatalf("apply sets the target and does not switch the quest on: %s", applied.Body)
	}
}

func TestV17TargetRanges(t *testing.T) {
	h := newHarness(t)
	nick := h.joinAdmin("Nick", "green")
	ranges := map[string][4]int{
		"sleep_regularity": {14, 15, 120, 121},
		"produce":          {0, 1, 30, 31},
		"breathing":        {0, 1, 60, 61},
	}
	for key, r := range ranges {
		for i, target := range r {
			status := http.StatusOK
			if i == 0 || i == 3 {
				status = http.StatusUnprocessableEntity
			}
			h.patch("/api/me", nick.Token, obj{"questTemplates": []obj{{"key": key, "target": target}}}).expect(status)
		}
		h.patch("/api/me", nick.Token, obj{"questTemplates": []obj{{"key": key, "targetAlt": 5}}}).
			expect(http.StatusUnprocessableEntity)
	}
}

func TestMigrationBackfillsTheV17QuestsDisabled(t *testing.T) {
	h := newHarness(t)
	nick, nadia := h.pair()
	h.patch("/api/me", nadia.Token, obj{"questTemplates": []obj{{"key": "yoga", "enabled": true}}}).expect(http.StatusOK)

	raw, err := migrations.Files.ReadFile("0026_v17_quests.sql")
	if err != nil {
		t.Fatal(err)
	}
	sql := string(raw)
	backfill := sql[strings.Index(sql, "INSERT INTO quest_templates"):]
	ctx := context.Background()
	if _, err := h.db.Pool.Exec(ctx, `DELETE FROM quest_templates WHERE key IN ('sleep_regularity', 'produce', 'breathing')`); err != nil {
		t.Fatal(err)
	}
	for range 2 {
		if _, err := h.db.Pool.Exec(ctx, backfill); err != nil {
			t.Fatalf("backfill: %v", err)
		}
	}
	for _, p := range []person{nick, nadia} {
		me := h.get("/api/me", p.Token).expect(http.StatusOK)
		if me.length("questTemplates") != 12 {
			t.Fatalf("the backfill must add exactly three templates: %s", me.Body)
		}
		for i, key := range []string{"sleep_regularity", "produce", "breathing"} {
			path := "questTemplates." + itoa(9+i)
			if me.str(path+".key") != key || me.flag(path+".enabled") || me.num(path+".points") != 50 ||
				me.num(path+".position") != 9+i {
				t.Fatalf("backfilled %s = %s", key, me.Body)
			}
		}
	}
	nadiaMe := h.get("/api/me", nadia.Token).expect(http.StatusOK)
	if !nadiaMe.flag("questTemplates.5.enabled") {
		t.Fatalf("the backfill changed another quest: %s", nadiaMe.Body)
	}
	today := h.get("/api/today", nick.Token).expect(http.StatusOK)
	if today.length("quests") != 8 {
		t.Fatalf("a disabled quest joined an existing day: %s", today.Body)
	}
}
