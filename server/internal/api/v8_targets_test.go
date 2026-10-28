package api

import (
	"net/http"
	"strings"
	"testing"
	"time"
)

// targetPath finds a target in a GET /api/targets answer, e.g. "targets.3".
func targetPath(t *testing.T, r *response, key string) string {
	t.Helper()
	for i := range r.length("targets") {
		if p := "targets." + itoa(i); r.str(p+".key") == key {
			return p
		}
	}
	t.Fatalf("no target %s: %s", key, r.Body)
	return ""
}

func inputPath(t *testing.T, r *response, key string) string {
	t.Helper()
	for i := range r.length("inputs") {
		if p := "inputs." + itoa(i); r.str(p+".key") == key {
			return p
		}
	}
	t.Fatalf("no input %s: %s", key, r.Body)
	return ""
}

func targetValue(t *testing.T, r *response, key string) int {
	t.Helper()
	return r.num(targetPath(t, r, key) + ".value")
}

// bodyProfile gives a person the inputs of the worked example: a 30-year-old man, 180 cm, 80 kg,
// averaging 8,000 steps. Mifflin-St Jeor gives 1,780 kcal.
func (h *harness) bodyProfile(p person) {
	h.t.Helper()
	h.patch("/api/me", p.Token, obj{"heightCm": 180, "sex": "male", "birthYear": 1996}).expect(http.StatusOK)
	h.putHealth(p, "2026-11-02", "weight_kg", 80).expect(http.StatusOK)
	h.seedSteps(p, 1, steady(8000, 14)...)
}

func TestProfileBodyInputsRoundTrip(t *testing.T) {
	h := newHarness(t)
	nick := h.joinAdmin("Nick", "green")
	me := h.get("/api/me", nick.Token).expect(http.StatusOK)
	if !me.isNull("user.heightCm") || !me.isNull("user.sex") || me.str("user.goal.kind") != "maintain" || me.num("user.goal.paceKgPerWeek") != 0 {
		t.Fatalf("defaults = %s", me.Body)
	}

	got := h.patch("/api/me", nick.Token, obj{"heightCm": 180.34, "sex": "male", "goal": obj{"kind": "lose", "paceKgPerWeek": 0.5}}).expect(http.StatusOK)
	approx(t, got, "user.heightCm", 180.3, 1e-9)
	if got.str("user.sex") != "male" || got.str("user.goal.kind") != "lose" {
		t.Fatalf("patch = %s", got.Body)
	}
	approx(t, got, "user.goal.paceKgPerWeek", 0.5, 1e-9)
	h.get("/api/me", nick.Token).expect(http.StatusOK).str("user.sex")

	h.patch("/api/me", nick.Token, obj{"goal": obj{"kind": "gain", "paceKgPerWeek": 0.4}}).expect(http.StatusOK)
	h.patch("/api/me", nick.Token, obj{"goal": obj{"kind": "maintain"}}).expect(http.StatusOK)
	cleared := h.patch("/api/me", nick.Token, obj{"heightCm": nil, "sex": nil}).expect(http.StatusOK)
	if !cleared.isNull("user.heightCm") || !cleared.isNull("user.sex") || cleared.str("user.goal.kind") != "maintain" {
		t.Fatalf("cleared = %s", cleared.Body)
	}

	for name, body := range map[string]obj{
		"height too short":     {"heightCm": 99},
		"height too tall":      {"heightCm": 251},
		"unknown sex":          {"sex": "x"},
		"lose pace too fast":   {"goal": obj{"kind": "lose", "paceKgPerWeek": 0.6}},
		"lose pace too slow":   {"goal": obj{"kind": "lose", "paceKgPerWeek": 0.1}},
		"lose without a pace":  {"goal": obj{"kind": "lose"}},
		"maintain with a pace": {"goal": obj{"kind": "maintain", "paceKgPerWeek": 0.25}},
		"gain too slow":        {"goal": obj{"kind": "gain", "paceKgPerWeek": 0.01}},
		"gain too fast":        {"goal": obj{"kind": "gain", "paceKgPerWeek": 1.2}},
		"gain without a pace":  {"goal": obj{"kind": "gain"}},
		"unknown goal":         {"goal": obj{"kind": "bulk", "paceKgPerWeek": 0.25}},
		"goal without a kind":  {"goal": obj{"paceKgPerWeek": 0.25}},
	} {
		if r := h.patch("/api/me", nick.Token, body); r.Status != http.StatusUnprocessableEntity {
			t.Errorf("%s: status %d, body %s", name, r.Status, r.Body)
		}
	}
}

func TestHealthHeightIsUsedWhenTheProfileHasNone(t *testing.T) {
	h := newHarness(t)
	nick := h.joinAdmin("Nick", "green")
	h.putHealth(nick, "2026-11-02", "height_cm", 99).expect(http.StatusUnprocessableEntity)
	h.putHealth(nick, "2026-11-02", "height_cm", 251).expect(http.StatusUnprocessableEntity)
	h.putHealth(nick, "2026-11-02", "height_cm", 175.3).expect(http.StatusOK)

	got := h.get("/api/targets", nick.Token).expect(http.StatusOK)
	p := inputPath(t, got, "heightCm")
	approx(t, got, p+".value", 175.3, 1e-9)
	if got.str(p+".source") != "health" {
		t.Fatalf("input = %s", got.Body)
	}

	h.patch("/api/me", nick.Token, obj{"heightCm": 180}).expect(http.StatusOK)
	got = h.get("/api/targets", nick.Token).expect(http.StatusOK)
	if p := inputPath(t, got, "heightCm"); got.num(p+".value") != 180 || got.str(p+".source") != "profile" {
		t.Fatalf("the profile wins: %s", got.Body)
	}
	h.patch("/api/me", nick.Token, obj{"heightCm": nil}).expect(http.StatusOK)
	got = h.get("/api/targets", nick.Token).expect(http.StatusOK)
	if p := inputPath(t, got, "heightCm"); got.str(p+".source") != "health" {
		t.Fatalf("cleared profile falls back to Health: %s", got.Body)
	}
}

func TestTargetsForANewPersonNameWhatIsMissingAndGuessNothing(t *testing.T) {
	h := newHarness(t)
	nick := h.joinAdmin("Nick", "green")
	h.get("/api/targets", "").expect(http.StatusUnauthorized)
	got := h.get("/api/targets", nick.Token).expect(http.StatusOK)

	for _, key := range []string{"weightKg", "heightCm", "age", "sex", "steps14"} {
		if p := inputPath(t, got, key); got.str(p+".source") != "missing" || !got.isNull(p+".value") {
			t.Errorf("input %s = %s", key, got.Body)
		}
	}
	if p := inputPath(t, got, "goal"); got.str(p+".source") != "profile" || got.str(p+".value.kind") != "maintain" {
		t.Errorf("goal input = %s", got.Body)
	}
	for _, key := range []string{"restingEnergy", "maintenance", "estimatedFromLogs", "calories", "protein", "fat", "saturatedFatMax", "carbs", "fiber", "pushups"} {
		p := targetPath(t, got, key)
		if !got.isNull(p+".value") || got.length(p+".missing") == 0 || !strings.Contains(got.str(p+".formula"), ".") {
			t.Errorf("target %s should be empty and say what is missing: %s", key, got.Body)
		}
	}
	missing := got.at(targetPath(t, got, "restingEnergy") + ".missing").([]any)
	if len(missing) != 4 {
		t.Errorf("resting energy missing = %v", missing)
	}
	// Sleep, activity and steps need no personal input.
	if targetValue(t, got, "sleep") != 450 || targetValue(t, got, "activity") != 150 || targetValue(t, got, "steps") != 7000 {
		t.Fatalf("defaults = %s", got.Body)
	}
	if got.str("sources.mifflin1990") != "Mifflin et al., Am J Clin Nutr 1990;51:241" ||
		got.str("sources.faowhounu2004") != "FAO/WHO/UNU 2004 (Human Energy Requirements)" ||
		got.str("sources.phillips2017") != "Phillips et al., Sci Rep 2017;7:3216" {
		t.Fatalf("sources = %s", got.Body)
	}
	if !strings.Contains(got.str("disclaimer"), "not medical advice") {
		t.Fatalf("disclaimer = %s", got.Body)
	}
}

func TestTargetsWorkedExampleForAMaintainer(t *testing.T) {
	h := newHarness(t)
	nick := h.joinAdmin("Nick", "green")
	h.bodyProfile(nick)
	got := h.get("/api/targets", nick.Token).expect(http.StatusOK)

	// 10 x 80 + 6.25 x 180 - 5 x 30 + 5 = 1,780; x 1.55 (8,000 steps) = 2,759; rounded to 50 = 2,750.
	want := map[string]int{"restingEnergy": 1780, "maintenance": 2759, "calories": 2750, "protein": 130,
		"fat": 86, "saturatedFatMax": 31, "carbs": 364, "fiber": 39, "sleep": 450, "activity": 150,
		// The 14-day median of 8,000 is above 7,000, so the v4 age band applies: 8,000 + 1,000.
		"steps": 9000}
	for key, v := range want {
		if got := targetValue(t, got, key); got != v {
			t.Errorf("%s = %d, want %d", key, got, v)
		}
	}
	if kcal := 4*130 + 9*86 + 4*364; kcal < 2750-3 || kcal > 2750+3 {
		t.Errorf("macros add up to %d kcal, not 2,750", kcal)
	}

	resting := targetPath(t, got, "restingEnergy")
	if got.str(resting+".formula") != "Mifflin-St Jeor: 10 × 80 kg + 6.25 × 180 cm - 5 × 30 + 5 = 1,780 kcal." ||
		got.str(resting+".label") != "guideline" {
		t.Errorf("resting = %s", got.Body)
	}
	maint := targetPath(t, got, "maintenance")
	if f := got.str(maint + ".formula"); !strings.Contains(f, "our convention") || got.str(maint+".label") != "convention" {
		t.Errorf("the step-band mapping must say it is a convention: %s", f)
	}
	cal := targetPath(t, got, "calories")
	if got.str(cal+".label") != "derivation" || !strings.Contains(got.str(cal+".formula"), "2,750 kcal") || !got.isNull(cal+".current") {
		t.Errorf("calories = %s", got.Body)
	}
	if got.str(targetPath(t, got, "protein")+".label") != "guideline" ||
		got.str(targetPath(t, got, "fiber")+".formula") != "14 g per 1,000 kcal × 2.75 = 39 g. The adequate intake for your age and sex is 38 g, for context." {
		t.Errorf("targets = %s", got.Body)
	}
	if p := inputPath(t, got, "weightKg"); got.num(p+".value") != 80 || got.str(p+".source") != "health" {
		t.Errorf("weight input = %s", got.Body)
	}
	// Every source key a target cites has a citation.
	for i := range got.length("targets") {
		for j := range got.length("targets." + itoa(i) + ".sources") {
			key := got.str("targets." + itoa(i) + ".sources." + itoa(j))
			if cite, ok := got.at("sources").(map[string]any)[key].(string); !ok || cite == "" {
				t.Errorf("target %d cites %q with no citation", i, key)
			}
		}
	}
}

func TestTargetsFollowTheGoalAndItsPaceCaps(t *testing.T) {
	h := newHarness(t)
	nick := h.joinAdmin("Nick", "green")
	h.bodyProfile(nick)

	h.patch("/api/me", nick.Token, obj{"goal": obj{"kind": "lose", "paceKgPerWeek": 0.5}}).expect(http.StatusOK)
	got := h.get("/api/targets", nick.Token).expect(http.StatusOK)
	// 2,759 - 550 = 2,209 -> 2,200; protein 2.0 x 80 = 160; fat 616 kcal = 68 g; carbs (2,200 - 640 - 612) / 4 = 237.
	for key, v := range map[string]int{"calories": 2200, "protein": 160, "fat": 68, "carbs": 237, "saturatedFatMax": 24} {
		if got := targetValue(t, got, key); got != v {
			t.Errorf("lose %s = %d, want %d", key, got, v)
		}
	}
	if f := got.str(targetPath(t, got, "calories") + ".formula"); !strings.Contains(f, "0.5 kg a week × 7,700 kcal per kg / 7 days (550 kcal)") {
		t.Errorf("formula = %s", f)
	}

	// 80 kg may gain 0.4 kg a week; 0.5 is limited and says so.
	h.patch("/api/me", nick.Token, obj{"goal": obj{"kind": "gain", "paceKgPerWeek": 0.5}}).expect(http.StatusOK)
	got = h.get("/api/targets", nick.Token).expect(http.StatusOK)
	if targetValue(t, got, "calories") != 3200 || targetValue(t, got, "protein") != 145 {
		t.Errorf("gain = %s", got.Body)
	}
	if f := got.str(targetPath(t, got, "calories") + ".formula"); !strings.Contains(f, "limited to 0.4 kg a week, 0.5% of body weight") {
		t.Errorf("formula = %s", f)
	}
	approx(t, got, targetPath(t, got, "calories")+".details.paceOptions.gainMaxKgPerWeek", 0.4, 1e-9)
}

func TestTargetsFloorKeepsACutAboveRestingEnergyAndMinimum(t *testing.T) {
	h := newHarness(t)
	nadia := h.joinAdmin("Nadia", "violet")
	h.patch("/api/me", nadia.Token, obj{"heightCm": 160, "sex": "female", "birthYear": 1986,
		"goal": obj{"kind": "lose", "paceKgPerWeek": 0.5}}).expect(http.StatusOK)
	h.putHealth(nadia, "2026-11-02", "weight_kg", 50).expect(http.StatusOK)
	h.seedSteps(nadia, 1, steady(3000, 14)...)
	got := h.get("/api/targets", nadia.Token).expect(http.StatusOK)
	// 500 + 1,000 - 200 - 161 = 1,139; x 1.4 = 1,594.6; minus 550 -> 1,050, raised to the 1,200 floor.
	if targetValue(t, got, "restingEnergy") != 1139 || targetValue(t, got, "calories") != 1200 {
		t.Fatalf("targets = %s", got.Body)
	}
	if f := got.str(targetPath(t, got, "calories") + ".formula"); !strings.Contains(f, "raised to the floor of 1,200 kcal") {
		t.Errorf("formula = %s", f)
	}
	// 1,200 kcal with 100 g protein: fat falls to its floor first and carbohydrate holds the 130 g minimum.
	if targetValue(t, got, "carbs") < 130 {
		t.Errorf("carbs under the RDA floor: %s", got.Body)
	}
}

func (h *harness) seedWeights(p person, daysAgo, n int, kg float64) {
	h.t.Helper()
	for i := range n {
		h.sql(`INSERT INTO health_daily (user_id, local_date, metric, value, source, measured_at)
			VALUES ($1, DATE '2026-11-02' - $2::int, 'weight_kg', $3, 'fake', now())
			ON CONFLICT DO NOTHING`, p.ID, daysAgo+i, kg)
	}
}

func (h *harness) seedMealDays(p person, fromDaysAgo, n, kcal int) {
	h.t.Helper()
	for i := range n {
		h.sql(`INSERT INTO meal_logs (user_id, local_date, name, kcal, client_op_id)
			VALUES ($1, DATE '2026-11-02' - $2::int, 'seed', $3, $4::uuid)`, p.ID, fromDaysAgo+i, kcal, h.nextOp())
	}
}

func TestEstimatedFromLogsNeedsTheDocumentedHistory(t *testing.T) {
	h := newHarness(t)
	nick := h.joinAdmin("Nick", "green")
	h.bodyProfile(nick)
	got := h.get("/api/targets", nick.Token).expect(http.StatusOK)
	p := targetPath(t, got, "estimatedFromLogs")
	if !got.isNull(p+".value") || got.length(p+".missing") != 3 || got.str(p+".label") != "derivation" {
		t.Fatalf("estimate = %s", got.Body)
	}

	// 20 steady weigh-ins and 15 logged days: intake equals maintenance when the weight does not move.
	h.seedWeights(nick, 1, 19, 80)
	h.seedMealDays(nick, 1, 15, 2600)
	got = h.get("/api/targets", nick.Token).expect(http.StatusOK)
	p = targetPath(t, got, "estimatedFromLogs")
	if got.num(p+".value") != 2600 || got.length(p+".missing") != 0 || got.num(p+".details.loggedDays") != 15 ||
		!strings.Contains(got.str(p+".formula"), "under-reported") {
		t.Fatalf("estimate = %s", got.Body)
	}
	// The formula value stays the default.
	if targetValue(t, got, "maintenance") != 2759 {
		t.Errorf("maintenance = %s", got.Body)
	}
}

func (h *harness) seedNight(p person, date string, bedHour, bedMin, wakeHour, wakeMin, asleep int) {
	h.t.Helper()
	d, err := time.ParseInLocation(time.DateOnly, date, newYork)
	if err != nil {
		h.t.Fatal(err)
	}
	bed := time.Date(d.Year(), d.Month(), d.Day()-1, bedHour, bedMin, 0, 0, newYork)
	if bedHour < 12 {
		bed = time.Date(d.Year(), d.Month(), d.Day(), bedHour, bedMin, 0, 0, newYork)
	}
	wake := time.Date(d.Year(), d.Month(), d.Day(), wakeHour, wakeMin, 0, 0, newYork)
	h.sql(`INSERT INTO sleep_nights (user_id, local_date, bed_at, wake_at, asleep_min, deep_min, rem_min, core_min, awake_min, source)
		VALUES ($1, $2::date, $3, $4, $5, 0, 0, $5, 0, 'fake')`, p.ID, date, bed, wake, asleep)
}

func TestSleepTargetBedtimeShortfallAndRegularity(t *testing.T) {
	h := newHarness(t)
	nick := h.joinAdmin("Nick", "green")
	got := h.get("/api/targets", nick.Token).expect(http.StatusOK)
	p := targetPath(t, got, "sleep")
	// Wake 07:00 - 7 h 30 - 15 min of sleep onset = 23:15.
	if got.num(p+".value") != 450 || got.str(p+".details.bedtime.workday") != "23:15" || got.str(p+".label") != "guideline" ||
		!got.isNull(p+".details.regularity.score") || got.num(p+".details.shortfall7.nights") != 0 {
		t.Fatalf("sleep = %s", got.Body)
	}

	h.patch("/api/me", nick.Token, obj{"schedule": obj{"workday": obj{"wake": "06:30"}}}).expect(http.StatusOK)
	for i, day := range []string{"2026-11-02", "2026-11-01", "2026-10-31", "2026-10-30"} {
		h.seedNight(nick, day, 23, 0, 7, 0, 400+i)
	}
	got = h.get("/api/targets", nick.Token).expect(http.StatusOK)
	p = targetPath(t, got, "sleep")
	// 06:30 - 7 h 30 - 15 min = 22:45; four nights are too few for the index.
	if got.str(p+".details.bedtime.workday") != "22:45" || !got.isNull(p+".details.regularity.score") ||
		got.str(p+".details.regularity.missing.0") != "nights" {
		t.Fatalf("sleep = %s", got.Body)
	}

	h.seedNight(nick, "2026-10-29", 23, 0, 7, 0, 404)
	got = h.get("/api/targets", nick.Token).expect(http.StatusOK)
	p = targetPath(t, got, "sleep")
	// 400 + 401 + 402 + 403 + 404 = 2,010 asleep of 5 x 450 = 2,250.
	approx(t, got, p+".details.regularity.score", 100, 1e-9)
	if got.num(p+".details.shortfall7.nights") != 5 || got.num(p+".details.shortfall7.shortfallMin") != 240 {
		t.Fatalf("sleep = %s", got.Body)
	}
	if got.str(p+".sources.2") != "ohayon2017" || got.str(targetPath(t, got, "sleep")+".details.regularity.advice") == "" {
		t.Errorf("sleep = %s", got.Body)
	}
}

func TestStepsTargetIsSevenThousandUnlessAlreadyAboveItThenTheAgeBand(t *testing.T) {
	h := newHarness(t)
	nick := h.joinAdmin("Nick", "green")
	h.patch("/api/me", nick.Token, obj{"birthYear": 1996}).expect(http.StatusOK)
	h.seedSteps(nick, 1, steady(5200, 14)...)
	if got := h.get("/api/targets", nick.Token).expect(http.StatusOK); targetValue(t, got, "steps") != 7000 ||
		got.num(targetPath(t, got, "steps")+".current") != 8000 {
		t.Fatalf("steps = %s", got.Body)
	}

	other := h.joinMember(h.invite(nick), "Nadia", "violet")
	h.patch("/api/me", other.Token, obj{"birthYear": 1996}).expect(http.StatusOK)
	h.seedSteps(other, 1, steady(8400, 14)...)
	got := h.get("/api/targets", other.Token).expect(http.StatusOK)
	insight := h.get("/api/insights", other.Token).expect(http.StatusOK)
	// The v4 suggestion for a median of 8,400 at age 30 (band 8,000 to 10,000) is 9,500.
	if targetValue(t, got, "steps") != 9500 || insight.num("steps.suggestion.target") != 9500 ||
		got.num(targetPath(t, got, "steps")+".details.bandLow") != 8000 {
		t.Fatalf("steps = %s", got.Body)
	}
}

func TestPushupMaxRecordsAndSizesTheDailyTarget(t *testing.T) {
	h := newHarness(t)
	nick := h.joinAdmin("Nick", "green")
	h.post("/api/pushups/max", "", obj{"reps": 40}).expect(http.StatusUnauthorized)
	got := h.get("/api/targets", nick.Token).expect(http.StatusOK)
	p := targetPath(t, got, "pushups")
	if !got.isNull(p+".value") || got.str(p+".missing.0") != "pushupMax" || got.str(p+".label") != "derivation" ||
		!strings.Contains(got.str(p+".formula"), "derivation") {
		t.Fatalf("pushups = %s", got.Body)
	}

	for name, body := range map[string]obj{
		"zero reps": {"reps": 0}, "too many": {"reps": 1001}, "future date": {"reps": 40, "date": "2026-11-03"},
		"bad date": {"reps": 40, "date": "yesterday"}, "unknown field": {"reps": 40, "sets": 3},
	} {
		if r := h.post("/api/pushups/max", nick.Token, body); r.Status < 400 || r.Status >= 500 {
			t.Errorf("%s: status %d", name, r.Status)
		}
	}
	rec := h.post("/api/pushups/max", nick.Token, obj{"reps": 40}).expect(http.StatusCreated)
	if rec.str("date") != "2026-11-02" || rec.num("reps") != 40 {
		t.Fatalf("record = %s", rec.Body)
	}
	got = h.get("/api/targets", nick.Token).expect(http.StatusOK)
	p = targetPath(t, got, "pushups")
	// 3 sets x 75% of 40 = 30 reps; the 70 to 80% range is 28 to 32.
	if got.num(p+".value") != 90 || got.num(p+".details.repsPerSet") != 30 || got.num(p+".details.rangePerSet.0") != 28 ||
		got.num(p+".details.rangePerSet.1") != 32 || got.num(p+".details.latestMax") != 40 || got.num(p+".current") != 30 {
		t.Fatalf("pushups = %s", got.Body)
	}

	// A second test the same day replaces the first; the newest day wins.
	h.post("/api/pushups/max", nick.Token, obj{"reps": 44}).expect(http.StatusCreated)
	// Early morning, while yesterday is still open for entries.
	h.clock.Set(ny(2026, time.November, 3, 8, 0))
	h.post("/api/pushups/max", nick.Token, obj{"reps": 36}).expect(http.StatusCreated)
	if v := targetValue(t, h.get("/api/targets", nick.Token).expect(http.StatusOK), "pushups"); v != 81 {
		t.Fatalf("3 x round(0.75 x 36) = 81, got %d", v)
	}
	h.post("/api/pushups/max", nick.Token, obj{"reps": 50, "date": "2026-11-02"}).expect(http.StatusCreated)
	if v := targetValue(t, h.get("/api/targets", nick.Token).expect(http.StatusOK), "pushups"); v != 81 {
		t.Fatalf("a backdated test must not outrank the newest day, got %d", v)
	}
	h.clock.Set(ny(2026, time.November, 3, 12, 0))
	h.post("/api/pushups/max", nick.Token, obj{"reps": 50, "date": "2026-11-02"}).expect(http.StatusUnprocessableEntity).code("date_closed")
}

func TestPushupProgressionAfterFiveOfSevenCompleteDays(t *testing.T) {
	h := newHarness(t)
	nick := h.joinAdmin("Nick", "green")
	h.post("/api/pushups/max", nick.Token, obj{"reps": 40}).expect(http.StatusCreated)
	h.post("/api/targets/apply", nick.Token, obj{"keys": []string{"pushups"}}).expect(http.StatusOK)
	if got := templateTarget(h.get("/api/me", nick.Token).expect(http.StatusOK), "pushups"); got != 90 {
		t.Fatalf("pushups template = %d", got)
	}

	// Five days with all three sets of 30 reps, each a log entry; one day is short a set.
	for day := 3; day <= 8; day++ {
		h.clock.Set(ny(2026, time.November, day, 12, 0))
		sets := 3
		if day == 5 {
			sets = 2
		}
		for range sets {
			h.logActivity(nick, "pushups", "reps", 30).expect(http.StatusCreated)
		}
	}
	h.clock.Set(ny(2026, time.November, 9, 12, 0))
	got := h.get("/api/targets", nick.Token).expect(http.StatusOK)
	p := targetPath(t, got, "pushups")
	// Days Nov 2 to 8: Nov 3, 4, 6, 7, 8 are complete (5 of 7); 30 + 5% (1.5 -> 2) = 32 per set.
	if got.num(p+".value") != 96 || got.num(p+".details.repsPerSet") != 32 || !got.flag(p+".details.progressed") ||
		got.num(p+".details.daysCompleted7") != 5 || !strings.Contains(got.str(p+".formula"), "raised by 5%") {
		t.Fatalf("pushups = %s", got.Body)
	}

	// Two days later the window (Nov 4 to 10) holds only 4 complete days and the progression is gone.
	h.clock.Set(ny(2026, time.November, 11, 12, 0))
	got = h.get("/api/targets", nick.Token).expect(http.StatusOK)
	if got.flag(targetPath(t, got, "pushups")+".details.progressed") || got.num(targetPath(t, got, "pushups")+".value") != 90 {
		t.Fatalf("Nov 4 to 10 holds only 4 complete days: %s", got.Body)
	}
}

func TestApplyTargetsSetsFoodTargetsAndQuestTemplatesThroughTheProfilePaths(t *testing.T) {
	h := newHarness(t)
	nick := h.joinAdmin("Nick", "green")
	h.bodyProfile(nick)
	h.post("/api/pushups/max", nick.Token, obj{"reps": 40}).expect(http.StatusCreated)

	// The join day follows what is applied right away.
	applied := h.post("/api/targets/apply", nick.Token, obj{"keys": []string{"calories", "protein", "fat", "carbs", "steps", "pushups", "sleep"}}).
		expect(http.StatusOK)
	if applied.num("targets.kcal") != 2750 || applied.num("targets.protein") != 130 || applied.num("targets.fat") != 86 ||
		applied.num("targets.carbs") != 364 || applied.length("applied") != 7 {
		t.Fatalf("apply = %s", applied.Body)
	}
	if templateTarget(applied, "steps") != 9000 || templateTarget(applied, "pushups") != 90 || templateTarget(applied, "sleep") != 450 {
		t.Fatalf("templates = %s", applied.Body)
	}
	today := questsByKey(h.get("/api/today", nick.Token).expect(http.StatusOK))
	if today["steps"].target != 9000 || today["pushups"].target != 90 || today["protein"].target != 130 {
		t.Fatalf("the join day follows the applied targets: %+v", today)
	}
	// What was applied shows as the current setting.
	got := h.get("/api/targets", nick.Token).expect(http.StatusOK)
	if got.num(targetPath(t, got, "calories")+".current") != 2750 || got.num(targetPath(t, got, "steps")+".current") != 9000 {
		t.Fatalf("current = %s", got.Body)
	}

	// A later day keeps the next-day rule: today's snapshot is frozen, tomorrow follows.
	h.clock.Set(ny(2026, time.November, 3, 12, 0))
	before := questsByKey(h.get("/api/today", nick.Token).expect(http.StatusOK))
	h.post("/api/pushups/max", nick.Token, obj{"reps": 60}).expect(http.StatusCreated)
	h.post("/api/targets/apply", nick.Token, obj{"keys": []string{"pushups"}}).expect(http.StatusOK)
	after := questsByKey(h.get("/api/today", nick.Token).expect(http.StatusOK))
	if after["pushups"].target != before["pushups"].target || before["pushups"].target != 90 {
		t.Fatalf("today must keep its target: before %+v after %+v", before["pushups"], after["pushups"])
	}
	h.clock.Set(ny(2026, time.November, 4, 12, 0))
	if tomorrow := questsByKey(h.get("/api/today", nick.Token).expect(http.StatusOK)); tomorrow["pushups"].target != 135 {
		t.Fatalf("tomorrow = %+v, want 3 x 45", tomorrow["pushups"])
	}
}

func TestApplyTargetsRejectsWhatItCannotApplyAndChangesNothing(t *testing.T) {
	h := newHarness(t)
	nick := h.joinAdmin("Nick", "green")
	h.bodyProfile(nick)
	h.post("/api/targets/apply", "", obj{"keys": []string{"calories"}}).expect(http.StatusUnauthorized)

	for name, body := range map[string]obj{
		"no keys":            {"keys": []string{}},
		"unknown key":        {"keys": []string{"calories", "bogus"}},
		"fiber is context":   {"keys": []string{"fiber"}},
		"activity is advice": {"keys": []string{"activity"}},
		"no value yet":       {"keys": []string{"calories", "pushups"}},
		"extra field":        {"keys": []string{"calories"}, "all": true},
	} {
		if r := h.post("/api/targets/apply", nick.Token, body); r.Status != http.StatusUnprocessableEntity && r.Status != http.StatusBadRequest {
			t.Errorf("%s: status %d, body %s", name, r.Status, r.Body)
		}
	}
	me := h.get("/api/me", nick.Token).expect(http.StatusOK)
	if !me.isNull("targets.kcal") {
		t.Fatalf("a rejected apply must change nothing: %s", me.Body)
	}
	// Repeating a key is harmless.
	h.post("/api/targets/apply", nick.Token, obj{"keys": []string{"calories", "calories"}}).expect(http.StatusOK).str("applied.0")
}

// proposalIndex is the position of a proposal in the answer, or -1.
func proposalIndex(r *response, key string) int {
	for i := range r.length("proposals") {
		if r.str("proposals."+itoa(i)+".key") == key {
			return i
		}
	}
	return -1
}

func TestMondayProposalsOfferCaloriesOnlyWhenAnInputMovedTheFormula(t *testing.T) {
	h := newHarness(t)
	nick := h.joinAdmin("Nick", "green")
	h.bodyProfile(nick)
	h.post("/api/targets/apply", nick.Token, obj{"keys": []string{"calories", "protein"}}).expect(http.StatusOK)

	h.clock.Set(ny(2026, time.November, 9, 12, 0))
	if got := h.get("/api/goals/proposals", nick.Token).expect(http.StatusOK); got.length("proposals") != 0 {
		t.Fatalf("nothing moved, so nothing is proposed: %s", got.Body)
	}

	// Choosing a goal changes an input: maintenance 2,759 - 550 = 2,200, a 550 kcal move.
	h.patch("/api/me", nick.Token, obj{"goal": obj{"kind": "lose", "paceKgPerWeek": 0.5}}).expect(http.StatusOK)
	got := h.get("/api/goals/proposals", nick.Token).expect(http.StatusOK)
	cal := proposalIndex(got, "calories")
	if cal < 0 {
		t.Fatalf("proposals = %s", got.Body)
	}
	pc := "proposals." + itoa(cal) + "."
	if got.num(pc+"current") != 2750 || got.num(pc+"proposed") != 2200 || got.str(pc+"unit") != "kcal" || got.str(pc+"title") != "Calories" ||
		!strings.Contains(got.str(pc+"reason"), "Your goal changed") || !strings.Contains(got.str(pc+"reason"), "Maintenance 2,759 kcal") {
		t.Fatalf("calories proposal = %s", got.Body)
	}
	// 160 g is 23% above the 130 g target in force, and the formula moved more than 5%.
	if i := proposalIndex(got, "protein"); i < 0 || got.num("proposals."+itoa(i)+".proposed") != 160 {
		t.Fatalf("protein proposal = %s", got.Body)
	}

	accepted := h.post("/api/goals/proposals/calories/accept", nick.Token, nil).expect(http.StatusOK)
	if accepted.num("targets.kcal") != 2200 {
		t.Fatalf("accept = %s", accepted.Body)
	}
	// The baseline moved with the accept, so the same value is not offered again, even next week.
	h.clock.Set(ny(2026, time.November, 16, 12, 0))
	h.seedSteps(nick, 1, steady(8000, 14)...)
	if again := h.get("/api/goals/proposals", nick.Token).expect(http.StatusOK); proposalIndex(again, "calories") >= 0 {
		t.Fatalf("calories came back: %s", again.Body)
	}
}

func TestDismissedCalorieProposalWaitsForTheNextMove(t *testing.T) {
	h := newHarness(t)
	nick := h.joinAdmin("Nick", "green")
	h.bodyProfile(nick)
	// A target typed by hand has no baseline until the proposals are first looked at.
	h.patch("/api/me", nick.Token, obj{"targets": obj{"kcal": 2750}}).expect(http.StatusOK)
	h.clock.Set(ny(2026, time.November, 9, 12, 0))
	h.get("/api/goals/proposals", nick.Token).expect(http.StatusOK).length("proposals")

	h.patch("/api/me", nick.Token, obj{"goal": obj{"kind": "gain", "paceKgPerWeek": 0.25}}).expect(http.StatusOK)
	got := h.get("/api/goals/proposals", nick.Token).expect(http.StatusOK)
	if i := proposalIndex(got, "calories"); i < 0 || got.num("proposals."+itoa(i)+".proposed") != 3050 {
		t.Fatalf("2,759 + 275 = 3,034 -> 3,050: %s", got.Body)
	}
	h.post("/api/goals/proposals/calories/dismiss", nick.Token, nil).expect(http.StatusNoContent)

	h.clock.Set(ny(2026, time.November, 16, 12, 0))
	h.seedSteps(nick, 1, steady(8000, 14)...)
	if got := h.get("/api/goals/proposals", nick.Token).expect(http.StatusOK); proposalIndex(got, "calories") >= 0 {
		t.Fatalf("a dismissed value is the new baseline: %s", got.Body)
	}
	h.patch("/api/me", nick.Token, obj{"goal": obj{"kind": "gain", "paceKgPerWeek": 0.15}}).expect(http.StatusOK)
	// 2,759 + 165 = 2,924 -> 2,900, 150 under the dismissed 3,050.
	got = h.get("/api/goals/proposals", nick.Token).expect(http.StatusOK)
	if i := proposalIndex(got, "calories"); i < 0 || got.num("proposals."+itoa(i)+".proposed") != 2900 {
		t.Fatalf("proposals = %s", got.Body)
	}
}

func TestUnitsAndImperialPaces(t *testing.T) {
	h := newHarness(t)
	nick := h.joinAdmin("Nick", "green")
	if got := h.get("/api/me", nick.Token).expect(http.StatusOK); !got.isNull("user.units") {
		t.Fatalf("default units = %s", got.Body)
	}
	got := h.patch("/api/me", nick.Token, obj{"units": "imperial",
		"goal": obj{"kind": "lose", "paceKgPerWeek": 0.45}}).expect(http.StatusOK)
	if got.str("user.units") != "imperial" || got.at("user.goal.paceKgPerWeek").(float64) != 0.45 {
		t.Fatalf("imperial = %s", got.Body)
	}
	h.patch("/api/me", nick.Token, obj{"goal": obj{"kind": "gain", "paceKgPerWeek": 0.11}}).expect(http.StatusOK)
	h.patch("/api/me", nick.Token, obj{"units": "furlongs"}).expect(http.StatusUnprocessableEntity)
}
