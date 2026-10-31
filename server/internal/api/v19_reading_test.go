package api

import (
	"context"
	"net/http"
	"os"
	"strings"
	"testing"
	"time"
)

func TestReadingPagesFollowTheMinutesUntilThePersonTypesTheirOwn(t *testing.T) {
	h := newHarness(t)
	nick := h.joinAdmin("Nick", "green")
	pages := func() int {
		return h.get("/api/me", nick.Token).expect(http.StatusOK).num("questTemplates.2.targetAlt")
	}
	if pages() != 20 {
		t.Fatalf("the default 20 minutes is 20 pages, got %d", pages())
	}

	h.patch("/api/me", nick.Token, obj{"questTemplates": []obj{{"key": "reading", "target": 30}}}).expect(http.StatusOK)
	if pages() != 30 {
		t.Fatalf("30 minutes is 30 pages, got %d", pages())
	}

	h.patch("/api/me", nick.Token, obj{"questTemplates": []obj{{"key": "reading", "targetAlt": 40}}}).expect(http.StatusOK)
	h.patch("/api/me", nick.Token, obj{"questTemplates": []obj{{"key": "reading", "target": 45}}}).expect(http.StatusOK)
	if pages() != 40 {
		t.Fatalf("a typed pages figure must survive a minutes change, got %d", pages())
	}

	h.patch("/api/me", nick.Token, obj{"questTemplates": []obj{{"key": "reading", "targetAlt": 45}}}).expect(http.StatusOK)
	h.patch("/api/me", nick.Token, obj{"questTemplates": []obj{{"key": "reading", "target": 60}}}).expect(http.StatusOK)
	if pages() != 60 {
		t.Fatalf("typing the derived figure goes back to following, got %d", pages())
	}
}

func TestReadingTargetIsCitedAndApplyingItFollowsTheMinutes(t *testing.T) {
	h := newHarness(t)
	nick := h.joinAdmin("Nick", "green")
	h.patch("/api/me", nick.Token, obj{"questTemplates": []obj{{"key": "reading", "target": 30}}}).expect(http.StatusOK)
	got := h.get("/api/targets", nick.Token).expect(http.StatusOK)

	p := targetPath(t, got, "reading")
	if got.num(p+".value") != 30 || got.num(p+".current") != 30 || got.str(p+".unit") != "pages" ||
		got.num(p+".details.pagesPerMinute") != 1 || got.num(p+".details.listeningMinutesPerMinute") != 2 ||
		got.num(p+".details.minutes") != 30 {
		t.Fatalf("reading = %s", got.Body)
	}
	if f := got.str(p + ".formula"); !strings.Contains(f, "30 minutes, or 30 pages") || !strings.Contains(f, "60 minutes of audiobook") || !strings.Contains(f, "238 words a minute") {
		t.Fatalf("formula = %s", f)
	}
	if !strings.Contains(got.str(p+".details.note"), "half a reading minute") || !strings.Contains(got.str(p+".why"), "a page for each minute") {
		t.Fatalf("copy = %s", got.Body)
	}
	for i, key := range []string{"brysbaert2019", "pagewords"} {
		if got.str(p+".sources."+itoa(i)) != key || got.str("sources."+key) == "" {
			t.Fatalf("source %s: %s", key, got.Body)
		}
	}

	h.patch("/api/me", nick.Token, obj{"questTemplates": []obj{{"key": "reading", "targetAlt": 12}}}).expect(http.StatusOK)
	applied := h.post("/api/targets/apply", nick.Token, obj{"keys": []string{"reading"}}).expect(http.StatusOK)
	if applied.num("questTemplates.2.targetAlt") != 30 {
		t.Fatalf("apply = %s", applied.Body)
	}
	h.patch("/api/me", nick.Token, obj{"questTemplates": []obj{{"key": "reading", "target": 10}}}).expect(http.StatusOK)
	if h.get("/api/me", nick.Token).num("questTemplates.2.targetAlt") != 10 {
		t.Fatal("applied pages must follow the minutes again")
	}
}

func TestAnAudiobookMinuteCountsHalfOnTheTodayCard(t *testing.T) {
	h := newHarness(t)
	nick := h.joinAdmin("Nick", "green")
	h.clock.Set(ny(2026, time.November, 3, 9, 0))
	h.patch("/api/me", nick.Token, obj{"questTemplates": []obj{{"key": "reading", "target": 30}}}).expect(http.StatusOK)
	if _, err := h.db.Pool.Exec(context.Background(),
		`INSERT INTO listening_daily (user_id, local_date, minutes, synced_at) VALUES ($1, '2026-11-03', 60, now())`, nick.ID); err != nil {
		t.Fatal(err)
	}
	h.logActivity(nick, "reading", "minutes", 5).expect(http.StatusCreated)

	got := h.get("/api/today", nick.Token).expect(http.StatusOK)
	if got.num("listening.minutes") != 60 {
		t.Fatalf("listening shows the time listened: %s", got.Body)
	}
	// 60 listened minutes count as 30 minutes of reading, plus 5 typed.
	if got.num("quests.2.actual") != 35 || got.num("quests.2.target") != 30 || got.num("quests.2.targetAlt") != 30 {
		t.Fatalf("reading = %s", got.Body)
	}
}

func TestMigrationBackfillsOnlyTemplatesStillOnTheOldFixedDefault(t *testing.T) {
	h := newHarness(t)
	nick, nadia := h.pair()
	ctx := context.Background()
	for _, c := range []struct {
		id        int64
		target, a int
	}{{nick.ID, 30, 15}, {nadia.ID, 30, 25}} {
		if _, err := h.db.Pool.Exec(ctx,
			`UPDATE quest_templates SET target = $2, target_alt = $3, target_alt_custom = false WHERE user_id = $1 AND key = 'reading'`,
			c.id, c.target, c.a); err != nil {
			t.Fatal(err)
		}
	}
	raw, err := os.ReadFile("../../migrations/0033_v19_reading_pages.sql")
	if err != nil {
		t.Fatal(err)
	}
	_, backfill, found := strings.Cut(string(raw), "ALTER TABLE quest_templates ADD COLUMN target_alt_custom BOOLEAN NOT NULL DEFAULT false;")
	if !found {
		t.Fatal("migration lost its ALTER statement")
	}
	if _, err := h.db.Pool.Exec(ctx, backfill); err != nil {
		t.Fatal(err)
	}
	var altNick, altNadia int
	var customNadia bool
	if err := h.db.Pool.QueryRow(ctx, `SELECT target_alt FROM quest_templates WHERE user_id = $1 AND key = 'reading'`, nick.ID).Scan(&altNick); err != nil {
		t.Fatal(err)
	}
	if err := h.db.Pool.QueryRow(ctx, `SELECT target_alt, target_alt_custom FROM quest_templates WHERE user_id = $1 AND key = 'reading'`, nadia.ID).Scan(&altNadia, &customNadia); err != nil {
		t.Fatal(err)
	}
	if altNick != 29 || altNadia != 25 || !customNadia {
		t.Fatalf("nick %d (want 29), nadia %d custom %v (want 25, true)", altNick, altNadia, customNadia)
	}

	// 0037 then moves a template that follows the minutes to a page a minute and leaves Nadia's own figure.
	raw, err = os.ReadFile("../../migrations/0037_v19_reading_page_a_minute.sql")
	if err != nil {
		t.Fatal(err)
	}
	if _, err := h.db.Pool.Exec(ctx, string(raw)); err != nil {
		t.Fatal(err)
	}
	if err := h.db.Pool.QueryRow(ctx, `SELECT target_alt FROM quest_templates WHERE user_id = $1 AND key = 'reading'`, nick.ID).Scan(&altNick); err != nil {
		t.Fatal(err)
	}
	if err := h.db.Pool.QueryRow(ctx, `SELECT target_alt FROM quest_templates WHERE user_id = $1 AND key = 'reading'`, nadia.ID).Scan(&altNadia); err != nil {
		t.Fatal(err)
	}
	if altNick != 30 || altNadia != 25 {
		t.Fatalf("after 0037: nick %d (want 30), nadia %d (want 25)", altNick, altNadia)
	}
}
