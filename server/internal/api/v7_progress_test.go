package api

import (
	"context"
	"math"
	"net/http"
	"testing"
	"time"
)

// approx asserts the number at path is within tol of want.
func approx(t *testing.T, r *response, path string, want, tol float64) {
	t.Helper()
	got, ok := r.at(path).(float64)
	if !ok || math.Abs(got-want) > tol {
		t.Fatalf("%s = %v, want %v; body: %s", path, r.at(path), want, r.Body)
	}
}

// metricOf finds a metric by key inside a person's list at base, e.g. "people.0.metrics".
func metricOf(t *testing.T, r *response, base, key string) string {
	t.Helper()
	for i := range r.length(base) {
		if r.str(base+"."+itoa(i)+".key") == key {
			return base + "." + itoa(i)
		}
	}
	t.Fatalf("no metric %s under %s: %s", key, base, r.Body)
	return ""
}

// historyPair is Nick and Nadia who joined 90 days before Monday 2026-11-02, with Nick's numbers
// improving in steps: 5,000 steps a day before day 60, 7,000 until day 30 and 9,000 since.
func historyPair(t *testing.T, opts ...func(*Server)) (*harness, person, person) {
	h := newHarness(t, opts...)
	h.clock.Set(ny(2026, time.August, 4, 12, 0))
	nick, nadia := h.pair()
	h.clock.Set(ny(2026, time.November, 2, 12, 0))

	seed := func(query string, args ...any) { h.sql(query, args...) }
	for _, p := range []person{nick} {
		seed(`INSERT INTO health_daily (user_id, local_date, metric, value, source, measured_at)
			SELECT $1, DATE '2026-11-02' - i, 'steps', CASE WHEN i < 30 THEN 9000 WHEN i < 60 THEN 7000 ELSE 5000 END, 'fake', now()
			FROM generate_series(0, 90) i`, p.ID)
		seed(`INSERT INTO health_daily (user_id, local_date, metric, value, source, measured_at)
			SELECT $1, DATE '2026-11-02' - i, 'body_fat_pct', CASE WHEN i < 30 THEN 22 WHEN i < 60 THEN 24 ELSE 26 END, 'fake', now()
			FROM generate_series(0, 90) i`, p.ID)
		seed(`INSERT INTO health_daily (user_id, local_date, metric, value, source, measured_at)
			SELECT $1, DATE '2026-11-02' - i, 'weight_kg', 80 + i / 18.0, 'fake', now()
			FROM generate_series(0, 90) i`, p.ID)
		seed(`INSERT INTO activity_logs (user_id, local_date, type, quantity, client_op_id)
			SELECT $1, DATE '2026-11-02' - i, 'pushups', CASE WHEN i < 30 THEN 40 ELSE 20 END, gen_random_uuid()
			FROM generate_series(0, 59) i`, p.ID)
		seed(`INSERT INTO activity_logs (user_id, local_date, type, quantity, client_op_id)
			SELECT $1, DATE '2026-11-02' - i, 'reading_minutes', CASE WHEN i < 30 THEN 24 WHEN i < 60 THEN 15 ELSE 11 END, gen_random_uuid()
			FROM generate_series(0, 90) i`, p.ID)
		seed(`INSERT INTO workouts (user_id, health_id, type, local_date, started_at, ended_at, duration_min, source)
			SELECT $1, 'w' || i, 'running', DATE '2026-11-02' - i, (DATE '2026-11-02' - i)::timestamp AT TIME ZONE 'America/New_York' + interval '8 hours',
			       (DATE '2026-11-02' - i)::timestamp AT TIME ZONE 'America/New_York' + interval '8 hours 30 minutes', 30, 'fake'
			FROM generate_series(0, 59) i WHERE (i < 30 AND i % 2 = 0) OR (i >= 30 AND i % 3 = 0)`, p.ID)
	}
	seed(`INSERT INTO health_daily (user_id, local_date, metric, value, source, measured_at)
		SELECT $1, DATE '2026-11-02' - i, 'steps', 6000, 'fake', now() FROM generate_series(0, 90) i`, nadia.ID)
	return h, nick, nadia
}

func TestProgressComparesWindowsWithThePreviousAndTheFirstMonth(t *testing.T) {
	h, nick, _ := historyPair(t)
	got := h.get("/api/progress?window=30", nick.Token).expect(http.StatusOK)
	if got.num("window") != 30 || got.str("today") != "2026-11-02" || got.length("people") != 2 ||
		int64(got.num("people.0.userId")) != nick.ID || got.str("people.0.joinedOn") != "2026-08-04" {
		t.Fatalf("progress = %s", got.Body)
	}
	if got.length("people.0.metrics") != 12 {
		t.Fatalf("metrics = %d", got.length("people.0.metrics"))
	}
	wantKeys := []string{"reading_minutes", "steps", "sleep_minutes", "workouts", "pushups", "protein_g", "habits_kept",
		"weight_kg", "body_fat_pct", "lean_mass_kg", "vo2max", "resting_hr"}
	for i, key := range wantKeys {
		if got.str("people.0.metrics."+itoa(i)+".key") != key {
			t.Fatalf("metric %d = %s, want %s", i, got.str("people.0.metrics."+itoa(i)+".key"), key)
		}
	}

	steps := metricOf(t, got, "people.0.metrics", "steps")
	approx(t, got, steps+".current", 9000, 0.01)
	approx(t, got, steps+".previous", 7000, 0.01)
	approx(t, got, steps+".first", 5000, 0.01)
	approx(t, got, steps+".changeFromPrevious.abs", 2000, 0.01)
	approx(t, got, steps+".changeFromPrevious.pct", 28.6, 0.05)
	approx(t, got, steps+".changeFromFirst.abs", 4000, 0.01)
	approx(t, got, steps+".changeFromFirst.pct", 80, 0.05)
	if !got.flag(steps+".changeFromPrevious.better") || !got.flag(steps+".changeFromFirst.better") ||
		got.str(steps+".goodDirection") != "up" ||
		got.str(steps+".summary") != "Steps: 9,000 steps a day, up from 5,000 in your first month" {
		t.Fatalf("steps = %s", got.Body)
	}
	// 14 Monday-start weeks since joining, the last one clipped to today.
	if got.length(steps+".series") != 14 || got.str(steps+".series.0.weekStart") != "2026-08-03" ||
		got.str(steps+".series.13.weekStart") != "2026-11-02" {
		t.Fatalf("series = %s", got.Body)
	}
	approx(t, got, steps+".series.13.value", 9000, 0.01)
	approx(t, got, steps+".series.0.value", 5000, 0.01)

	// Totals of what was done count the empty days: 40 reps on each of 30 days against none in the first month.
	pushups := metricOf(t, got, "people.0.metrics", "pushups")
	approx(t, got, pushups+".current", 40, 0.01)
	approx(t, got, pushups+".previous", 20, 0.01)
	approx(t, got, pushups+".first", 0, 0.01)
	if !got.isNull(pushups+".changeFromFirst.pct") || !got.flag(pushups+".changeFromFirst.better") {
		t.Fatalf("a change from zero has no percentage: %s", got.Body)
	}
	reading := metricOf(t, got, "people.0.metrics", "reading_minutes")
	approx(t, got, reading+".current", 24, 0.01)
	if got.str(reading+".summary") != "Reading: 24 min a day, up from 11 in your first month" {
		t.Fatalf("reading = %s", got.str(reading+".summary"))
	}

	// Workouts are events per week: 15 in 30 days and 10 in the 30 before.
	workouts := metricOf(t, got, "people.0.metrics", "workouts")
	approx(t, got, workouts+".current", 3.5, 0.01)
	approx(t, got, workouts+".previous", 2.33, 0.01)

	// A lower body fat is better, and weight has no good direction.
	fat := metricOf(t, got, "people.0.metrics", "body_fat_pct")
	approx(t, got, fat+".changeFromPrevious.abs", -2, 0.01)
	if !got.flag(fat+".changeFromPrevious.better") || got.str(fat+".goodDirection") != "down" {
		t.Fatalf("body fat = %s", got.Body)
	}
	weight := metricOf(t, got, "people.0.metrics", "weight_kg")
	if got.isNull(weight+".current") || !got.isNull(weight+".changeFromPrevious.better") || got.str(weight+".goodDirection") != "none" {
		t.Fatalf("weight = %s", got.Body)
	}
	// Nothing synced: no data, no change.
	sleep := metricOf(t, got, "people.0.metrics", "sleep_minutes")
	if !got.isNull(sleep+".current") || !got.isNull(sleep+".changeFromPrevious") || got.length(sleep+".series") != 14 {
		t.Fatalf("sleep = %s", got.Body)
	}

	// The partner is measured on their own numbers.
	nadiaSteps := metricOf(t, got, "people.1.metrics", "steps")
	approx(t, got, nadiaSteps+".current", 6000, 0.01)
	if !got.isNull(nadiaSteps + ".changeFromPrevious.better") {
		t.Fatalf("flat steps are not better: %s", got.Body)
	}
}

func TestProgressWindowValidationAndShortHistory(t *testing.T) {
	h, nick, _ := historyPair(t)
	for _, bad := range []string{"6", "366", "abc", "-30", "0"} {
		h.get("/api/progress?window="+bad, nick.Token).expect(http.StatusUnprocessableEntity).code("invalid_request")
	}
	if def := h.get("/api/progress", nick.Token).expect(http.StatusOK); def.num("window") != 30 {
		t.Fatalf("default window = %s", def.Body)
	}
	// A 100 day window reaches back past the join day: the previous window is empty and the
	// first window is not over yet.
	long := h.get("/api/progress?window=100", nick.Token).expect(http.StatusOK)
	steps := metricOf(t, long, "people.0.metrics", "steps")
	if !long.isNull(steps+".previous") || long.isNull(steps+".current") || !long.isNull(steps+".first") {
		t.Fatalf("90 day window = %s", long.Body)
	}

	// A brand new person has no first month yet.
	fresh := newHarness(t)
	solo := fresh.joinAdmin("Solo", "green")
	got := fresh.get("/api/progress", solo.Token).expect(http.StatusOK)
	m := metricOf(t, got, "people.0.metrics", "steps")
	if !got.isNull(m+".first") || !got.isNull(m+".previous") || !got.isNull(m+".changeFromFirst") || got.length(m+".series") != 1 {
		t.Fatalf("fresh = %s", got.Body)
	}
}

func TestLookbackNamesTheBiggestImprovements(t *testing.T) {
	h, nick, nadia := historyPair(t)
	for _, d := range []string{"2026-10-05", "2026-10-06", "2026-10-07", "2026-10-08", "2026-10-09"} {
		h.storeScore(nick, d, 300, 0, 400)
	}
	for _, d := range []string{"2026-10-05", "2026-10-06"} {
		h.storeScore(nadia, d, 300, 0, 400)
	}
	got := h.get("/api/lookback", nick.Token).expect(http.StatusOK)
	if got.str("month") != "2026-10" || got.str("label") != "October 2026" || got.str("from") != "2026-10-01" ||
		got.str("to") != "2026-10-31" || !got.flag("complete") || got.length("people") != 2 {
		t.Fatalf("lookback = %s", got.Body)
	}
	if got.num("people.0.countedDays") != 5 || got.num("people.0.points") != 1500 || got.num("people.1.countedDays") != 2 ||
		got.num("couple.points") != 2100 || got.num("couple.bothCountedDays") != 2 {
		t.Fatalf("results = %s", got.Body)
	}

	steps := metricOf(t, got, "people.0.metrics", "steps")
	approx(t, got, steps+".value", (28*9000+3*7000)/31.0, 0.01)
	approx(t, got, steps+".previous", (27*7000+3*5000)/30.0, 0.01)
	approx(t, got, steps+".first", 5000, 0.01)
	if !got.flag(steps + ".changeFromPrevious.better") {
		t.Fatalf("steps = %s", got.Body)
	}

	if got.length("people.0.improvements") != 3 || got.str("people.0.improvements.0.key") != "pushups" {
		t.Fatalf("improvements = %s", got.Body)
	}
	last := 1e9
	for i := range 3 {
		pct := float64(got.num("people.0.improvements." + itoa(i) + ".pct"))
		if pct > last || pct <= 0 || got.str("people.0.improvements."+itoa(i)+".summary") == "" || got.str("people.0.improvements."+itoa(i)+".key") == "weight_kg" {
			t.Fatalf("improvement %d = %s", i, got.Body)
		}
		last = pct
	}
	// Nadia's only metric is steps and it did not move.
	if got.length("people.1.improvements") != 0 {
		t.Fatalf("nadia = %s", got.Body)
	}
	coupleSteps := metricOf(t, got, "couple.metrics", "steps")
	approx(t, got, coupleSteps+".value", ((28*9000+3*7000)/31.0+6000)/2, 0.01)
	if got.length("couple.improvements") == 0 {
		t.Fatalf("couple = %s", got.Body)
	}

	// Explicit months: the running month is allowed, the future and malformed ones are not.
	if cur := h.get("/api/lookback?month=2026-11", nick.Token).expect(http.StatusOK); cur.flag("complete") {
		t.Fatalf("the running month is not complete: %s", cur.Body)
	}
	if early := h.get("/api/lookback?month=2026-05", nick.Token).expect(http.StatusOK); early.length("people") != 2 ||
		!early.isNull(metricOf(t, early, "people.0.metrics", "steps")+".value") {
		t.Fatalf("a month before joining has no data: %s", early.Body)
	}
	for _, bad := range []string{"2026-12", "2026-13", "2026-1", "october", "2026-00"} {
		h.get("/api/lookback?month="+bad, nick.Token).expect(http.StatusUnprocessableEntity).code("invalid_request")
	}
}

func TestLookbackPushIsTheFirstNotificationOfTheFirst(t *testing.T) {
	n := &capture{}
	h, nick, nadia := historyPair(t, withPush(n))
	h.patch("/api/me", nadia.Token, obj{"notifications": obj{"lookback": false}}).expect(http.StatusOK)
	ctx := context.Background()
	push := func(at time.Time) {
		h.clock.Set(at)
		if err := h.srv.lookback.PushDue(ctx, at); err != nil {
			t.Fatal(err)
		}
	}

	push(ny(2026, time.October, 31, 12, 0))
	push(ny(2026, time.November, 1, 7, 9))
	if n.count() != 0 {
		t.Fatalf("before the first notification of the 1st: %+v", n.msgs)
	}
	push(ny(2026, time.November, 1, 7, 10))
	got := n.of("lookback", nick.ID)
	if len(got) != 1 || got[0].Title != "Your October 2026" || got[0].Body == "" {
		t.Fatalf("push = %+v", n.msgs)
	}
	if len(n.of("lookback", nadia.ID)) != 0 {
		t.Fatalf("nadia turned it off: %+v", n.msgs)
	}
	push(ny(2026, time.November, 1, 9, 0))
	if len(n.of("lookback", nick.ID)) != 1 {
		t.Fatal("once a month")
	}

	// It is the day's first automatic push, so the morning plan finds the slot taken.
	h.runNudges(ny(2026, time.November, 1, 7, 15))
	if len(n.of("nudge_morning_plan", nick.ID)) != 0 || len(n.of("nudge_morning_plan", nadia.ID)) != 1 {
		t.Fatalf("the look-back takes Nick's first slot; Nadia, who turned it off, still gets the plan: %+v", n.msgs)
	}
	h.sql(`DELETE FROM notice_log`)
	push(ny(2026, time.December, 1, 7, 10))
	h.runNudges(ny(2026, time.December, 1, 7, 10))
	if len(n.of("nudge_morning_plan", nick.ID)) != 0 || len(n.of("lookback", nick.ID)) != 2 {
		t.Fatalf("december: %+v", n.msgs)
	}

	// Not in quiet hours either.
	n.msgs = nil
	h.sql(`DELETE FROM notice_log`)
	push(ny(2027, time.January, 1, 23, 30))
	if n.count() != 0 {
		t.Fatalf("after bedtime: %+v", n.msgs)
	}
}

func TestMilestonesAreRecordedOnceShownAndPushed(t *testing.T) {
	n := &capture{}
	h := newHarness(t, withPush(n))
	nick, nadia := h.pair()
	for i := range 7 {
		d := ny(2026, time.November, 2+i, 12, 0).Format(time.DateOnly)
		h.storeScore(nick, d, 300, 0, 400)
	}
	h.clock.Set(ny(2026, time.November, 9, 12, 0))
	today := h.todayAfterPass("/api/today", nick.Token).expect(http.StatusOK)
	// Monday to Sunday all counted, so the first fully counted week is celebrated with it.
	if today.num("streak.current") != 7 || today.length("newMilestones") != 2 || today.str("newMilestones.0.kind") != "streak" ||
		today.str("newMilestones.1.kind") != "first_full_week" ||
		today.num("newMilestones.0.value") != 7 || today.str("newMilestones.0.title") != "7-day streak" ||
		today.flag("newMilestones.0.shared") || today.str("newMilestones.0.achievedOn") != "2026-11-09" {
		t.Fatalf("today = %s", today.Body)
	}
	got := n.of("milestone", nick.ID)
	if len(got) != 1 || got[0].Title != "7-day streak" {
		t.Fatalf("only the streak is announced: %+v", n.msgs)
	}
	h.todayAfterPass("/api/today", nick.Token).expect(http.StatusOK)
	h.get("/api/board", nick.Token).expect(http.StatusOK)
	if len(n.of("milestone", nick.ID)) != 1 {
		t.Fatalf("pushed again: %+v", n.msgs)
	}
	if other := h.todayAfterPass("/api/today", nadia.Token).expect(http.StatusOK); other.length("newMilestones") != 0 {
		t.Fatalf("nadia = %s", other.Body)
	}

	list := h.get("/api/milestones", nick.Token).expect(http.StatusOK)
	if list.length("milestones") != 2 || list.num("milestones.0.value") != 7 {
		t.Fatalf("list = %s", list.Body)
	}
	if empty := h.get("/api/milestones", nadia.Token).expect(http.StatusOK); empty.length("milestones") != 0 {
		t.Fatalf("nadia = %s", empty.Body)
	}

	// The day after, the celebration is no longer new but stays in the list. The next one is 14.
	h.clock.Set(ny(2026, time.November, 11, 12, 0))
	if later := h.todayAfterPass("/api/today", nick.Token).expect(http.StatusOK); later.length("newMilestones") != 0 {
		t.Fatalf("two days later = %s", later.Body)
	}
	for i := 7; i < 14; i++ {
		h.storeScore(nick, ny(2026, time.November, 2+i, 12, 0).Format(time.DateOnly), 300, 0, 400)
	}
	h.clock.Set(ny(2026, time.November, 16, 12, 0))
	h.todayAfterPass("/api/today", nick.Token).expect(http.StatusOK)
	if got := n.of("milestone", nick.ID); len(got) != 2 || got[1].Title != "14-day streak" {
		t.Fatalf("pushes = %+v", n.msgs)
	}
	if list := h.get("/api/milestones", nick.Token).expect(http.StatusOK); list.length("milestones") != 3 ||
		list.num("milestones.0.value") != 14 {
		t.Fatalf("list = %s", list.Body)
	}
}

func TestMilestoneBatchAnnouncesOnlyTheHighestAndRespectsQuietHoursAndPreference(t *testing.T) {
	n := &capture{}
	h := newHarness(t, withPush(n))
	nick := h.joinAdmin("Nick", "green")
	for i := range 15 {
		h.storeScore(nick, ny(2026, time.November, 2+i, 12, 0).Format(time.DateOnly), 300, 0, 400)
	}
	// The first look finds 7 and 14 at once, late in the evening.
	h.clock.Set(ny(2026, time.November, 17, 23, 30))
	h.todayAfterPass("/api/today", nick.Token).expect(http.StatusOK)
	if n.count() != 0 {
		t.Fatalf("after bedtime nothing is sent: %+v", n.msgs)
	}
	if list := h.get("/api/milestones", nick.Token).expect(http.StatusOK); list.length("milestones") != 3 {
		t.Fatalf("7, 14 and the first full week are recorded: %s", list.Body)
	}
	h.clock.Set(ny(2026, time.November, 18, 8, 0))
	h.todayAfterPass("/api/today", nick.Token).expect(http.StatusOK)
	if got := n.of("milestone", nick.ID); len(got) != 1 || got[0].Title != "14-day streak" {
		t.Fatalf("only the highest of the batch: %+v", n.msgs)
	}

	n2 := &capture{}
	h2 := newHarness(t, withPush(n2))
	other := h2.joinAdmin("Other", "sky")
	h2.patch("/api/me", other.Token, obj{"notifications": obj{"milestones": false}}).expect(http.StatusOK)
	for i := range 8 {
		h2.storeScore(other, ny(2026, time.November, 2+i, 12, 0).Format(time.DateOnly), 300, 0, 400)
	}
	h2.clock.Set(ny(2026, time.November, 10, 12, 0))
	if got := h2.todayAfterPass("/api/today", other.Token).expect(http.StatusOK); got.length("newMilestones") != 1 {
		t.Fatalf("recorded anyway: %s", got.Body)
	}
	if len(n2.of("milestone", other.ID)) != 0 {
		t.Fatalf("preference off: %+v", n2.msgs)
	}
}

func TestSharedStreakMilestoneAndFirsts(t *testing.T) {
	n := &capture{}
	h := newHarness(t, withPush(n))
	nick, nadia := h.pair()
	// A 10,000-step day and a day with every quest done. The Health write rescores the day it
	// lands on, so it comes before the stored scores.
	h.putHealth(nick, "2026-11-02", "steps", 10000).expect(http.StatusOK)
	for i := range 7 {
		d := ny(2026, time.November, 2+i, 12, 0).Format(time.DateOnly)
		h.storeScore(nick, d, 400, 0, 400)
		h.storeScore(nadia, d, 300, 0, 400)
	}
	h.sql(`UPDATE day_scores SET detail = '[{"key":"steps","complete":true}]' WHERE user_id = $1 AND local_date = '2026-11-03'`, nick.ID)
	h.clock.Set(ny(2026, time.November, 9, 12, 0))
	list := h.get("/api/milestones", nick.Token).expect(http.StatusOK)
	kinds := map[string]bool{}
	for i := range list.length("milestones") {
		kinds[list.str("milestones."+itoa(i)+".kind")] = true
	}
	for _, want := range []string{"streak", "shared_streak", "first_10k_steps", "first_all_quests", "first_full_week"} {
		if !kinds[want] {
			t.Fatalf("missing %s: %s", want, list.Body)
		}
	}
	for i := range list.length("milestones") {
		if list.str("milestones."+itoa(i)+".kind") == "shared_streak" && !list.flag("milestones."+itoa(i)+".shared") {
			t.Fatalf("shared flag: %s", list.Body)
		}
	}
	// Nadia sees the shared one and her own streak, not Nick's firsts.
	theirs := h.get("/api/milestones", nadia.Token).expect(http.StatusOK)
	got := map[string]bool{}
	for i := range theirs.length("milestones") {
		got[theirs.str("milestones."+itoa(i)+".kind")] = true
	}
	if !got["shared_streak"] || !got["streak"] || got["first_10k_steps"] {
		t.Fatalf("nadia = %s", theirs.Body)
	}
	if len(n.of("milestone", nadia.ID)) == 0 || len(n.of("milestone", nick.ID)) == 0 {
		t.Fatalf("pushes = %+v", n.msgs)
	}
}

func TestInsightsSmoothedWeightWithWeeklyRate(t *testing.T) {
	h := newHarness(t)
	h.clock.Set(ny(2026, time.October, 5, 12, 0))
	nick := h.joinAdmin("Nick", "green")
	h.clock.Set(ny(2026, time.November, 2, 12, 0))
	if got := h.get("/api/insights", nick.Token).expect(http.StatusOK); !got.isNull("weight") {
		t.Fatalf("no weigh-in: %s", got.Body)
	}
	// Weekly weigh-ins of 80, 79, 78, 77 and 76 kg: the trend (alpha 0.1) is 80, 79.9, 79.71, 79.439, 79.0951.
	for i, kg := range []float64{80, 79, 78, 77, 76} {
		date := time.Date(2026, time.October, 5+7*i, 0, 0, 0, 0, time.UTC).Format(time.DateOnly)
		h.sql(`INSERT INTO health_daily (user_id, local_date, metric, value, source, measured_at)
			VALUES ($1, $2::date, 'weight_kg', $3, 'fake', now())`, nick.ID, date, kg)
	}
	got := h.get("/api/insights", nick.Token).expect(http.StatusOK)
	approx(t, got, "weight.latestKg", 76, 0.001)
	approx(t, got, "weight.smoothedKg", 79.1, 0.006)
	approx(t, got, "weight.weeklyRateKg", (79.0951-80)/28*7, 0.01)
	if got.length("weight.points") != 5 {
		t.Fatalf("points = %s", got.Body)
	}
	approx(t, got, "weight.points.1.smoothed", 79.9, 0.001)
	approx(t, got, "weight.points.3.smoothed", 79.44, 0.006)

	// With less than a week of weigh-ins there is no rate yet.
	h2 := newHarness(t)
	solo := h2.joinAdmin("Solo", "green")
	h2.putHealth(solo, "2026-11-02", "weight_kg", 81).expect(http.StatusOK)
	short := h2.get("/api/insights", solo.Token).expect(http.StatusOK)
	approx(t, short, "weight.smoothedKg", 81, 0.001)
	if !short.isNull("weight.weeklyRateKg") {
		t.Fatalf("one weigh-in: %s", short.Body)
	}
}

func TestInsightsWeeklyActivityAgainstTheWHOGuideline(t *testing.T) {
	h := newHarness(t)
	h.clock.Set(ny(2026, time.October, 1, 12, 0))
	nick := h.joinAdmin("Nick", "green")
	h.clock.Set(ny(2026, time.November, 2, 12, 0))
	h.patch("/api/me", nick.Token, obj{"birthYear": 1990}).expect(http.StatusOK)
	h.putHealth(nick, "2026-11-02", "resting_hr", 60).expect(http.StatusOK)
	session := func(id, typ string, daysAgo int, minutes, avgHR float64) {
		h.sql(`INSERT INTO workouts (user_id, health_id, type, local_date, started_at, ended_at, duration_min, avg_hr, source)
			VALUES ($1, $2, $3, DATE '2026-11-02' - $4::int, now() - interval '1 day', now() - interval '23 hours', $5, $6, 'fake')`,
			nick.ID, id, typ, daysAgo, minutes, avgHR)
	}
	// Max heart rate 184, reserve 124: 160 bpm is 81% (vigorous), 120 bpm is 48% (moderate).
	session("a", "running", 1, 40, 160)
	session("b", "strength", 2, 30, 120)
	session("c", "strength", 4, 30, 120)
	session("old", "running", 9, 500, 160)
	got := h.get("/api/insights", nick.Token).expect(http.StatusOK)
	if got.str("activity.guideline") != "WHO 2020" || got.num("activity.moderateMin") != 60 || got.num("activity.vigorousMin") != 40 ||
		got.num("activity.moderateEquivalentMin") != 140 || got.num("activity.strengthDays") != 2 ||
		got.flag("activity.meetsAerobic") || !got.flag("activity.meetsStrength") || !got.flag("activity.heartRateIntensityUsed") ||
		got.num("activity.aerobicTargetMinMin") != 150 || got.num("activity.aerobicTargetMaxMin") != 300 {
		t.Fatalf("activity = %s", got.Body)
	}
	// There is no load ratio and no lighter-week proposal.
	if _, ok := got.parsedMap()["load"]; ok {
		t.Fatalf("load must not exist: %s", got.Body)
	}
}

func TestInsightsProteinHitRate(t *testing.T) {
	h := newHarness(t)
	h.clock.Set(ny(2026, time.October, 20, 12, 0))
	nick := h.joinAdmin("Nick", "green")
	h.clock.Set(ny(2026, time.November, 2, 12, 0))
	for i := 1; i <= 7; i++ {
		grams := 100.0
		if i > 4 {
			grams = 60
		}
		h.sql(`INSERT INTO day_quests (user_id, local_date, key, target, unit, points, position)
			VALUES ($1, DATE '2026-11-02' - $2::int, 'protein', 100, 'g', 50, 4)`, nick.ID, i)
		h.sql(`INSERT INTO meal_logs (user_id, local_date, name, kcal, protein_g, client_op_id)
			VALUES ($1, DATE '2026-11-02' - $2::int, 'Meal', 500, $3, gen_random_uuid())`, nick.ID, i, grams)
	}
	h.putHealth(nick, "2026-11-02", "weight_kg", 75).expect(http.StatusOK)
	got := h.get("/api/insights", nick.Token).expect(http.StatusOK)
	if got.num("protein.daysHit7") != 4 || got.num("protein.days7") != 7 || got.num("protein.suggestedG") != 120 ||
		got.num("protein.targetG") != 120 {
		t.Fatalf("protein = %s", got.Body)
	}
	approx(t, got, "protein.hitRate7", 0.57, 0.005)
	approx(t, got, "protein.perKg", 1.6, 0.0001)
}

// parsedMap is the top-level object of the response.
func (r *response) parsedMap() map[string]any {
	var m map[string]any
	r.decode(&m)
	return m
}
