package api

import (
	"context"
	"net/http"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/nc1107/new-me/server/internal/db"
	"github.com/nc1107/new-me/server/internal/push"
	"github.com/nc1107/new-me/server/internal/score"
	"github.com/nc1107/new-me/server/internal/together"
)

// seedChallenge stores the challenge of the week the harness clock is in, so a test does not
// depend on which kind the picker would choose.
func (h *harness) seedChallenge(kind string) {
	h.t.Helper()
	week := score.WeekStart(score.LocalToday(h.clock.Now(), newYork))
	_, err := db.InsertChallenge(context.Background(), h.db.Pool, db.Challenge{WeekStart: week, Kind: kind,
		Title: together.Title(kind, 0), Target: 1, PickReason: "seeded by the test"})
	if err != nil {
		h.t.Fatalf("seed challenge: %v", err)
	}
}

func (h *harness) exec(sql string, args ...any) {
	h.t.Helper()
	if _, err := h.db.Pool.Exec(context.Background(), sql, args...); err != nil {
		h.t.Fatalf("%s: %v", strings.Fields(sql)[0], err)
	}
}

func (h *harness) seedMeal(p person, date string, protein float64) {
	h.t.Helper()
	h.exec(`INSERT INTO meal_logs (user_id, local_date, name, kcal, protein_g, client_op_id)
		VALUES ($1, $2::date, 'meal', 500, $3, gen_random_uuid())`, p.ID, date, protein)
}

func (h *harness) seedSleep(p person, date string, asleepMin int) {
	h.t.Helper()
	h.exec(`INSERT INTO sleep_nights (user_id, local_date, bed_at, wake_at, asleep_min, deep_min, rem_min, core_min, awake_min, source)
		VALUES ($1, $2::date, $2::date + time '00:00', $2::date + time '08:00', $3, 60, 60, 60, 10, 'fake')`,
		p.ID, date, asleepMin)
}

func (h *harness) seedHabitMarks(p person, dates ...string) {
	h.t.Helper()
	var id int64
	if err := h.db.Pool.QueryRow(context.Background(), `
		INSERT INTO habits (user_id, name, icon, kind, slots)
		VALUES ($1, 'Stretch', 'self_improvement', 'check', '[{"label":"Morning","time":null}]'::jsonb)
		RETURNING id`, p.ID).Scan(&id); err != nil {
		h.t.Fatalf("seed habit: %v", err)
	}
	for _, d := range dates {
		h.exec(`INSERT INTO habit_marks (habit_id, local_date, slot) VALUES ($1, $2::date, 0)`, id, d)
	}
}

func days(from string, n int) []string {
	out := make([]string, n)
	for i := range out {
		out[i] = string(score.MustDate(from).AddDays(i))
	}
	return out
}

func TestEachNewChallengeKindMeasuresTheWeekFromStoredData(t *testing.T) {
	cases := []struct {
		kind     string
		seed     func(h *harness, nick, nadia person)
		progress int
		unitLike string
	}{
		{db.ChallengeSleepNights, func(h *harness, nick, _ person) {
			h.seedSleep(nick, "2026-11-02", 450)
			h.seedSleep(nick, "2026-11-03", 300)
			h.seedSleep(nick, "2026-11-04", 420)
		}, 2, "nights"},
		{db.ChallengeMealDays, func(h *harness, nick, _ person) {
			h.seedMeal(nick, "2026-11-02", 10)
			h.seedMeal(nick, "2026-11-02", 10)
			h.seedMeal(nick, "2026-11-04", 10)
		}, 2, "days"},
		{db.ChallengeProteinDays, func(h *harness, nick, _ person) {
			h.seedMeal(nick, "2026-11-02", 60)
			h.seedMeal(nick, "2026-11-02", 60)
			h.seedMeal(nick, "2026-11-03", 30)
		}, 1, "days"},
		{db.ChallengePushupReps, func(h *harness, nick, _ person) {
			h.logActivity(nick, "pushups", "reps", 30).expect(http.StatusCreated)
			h.logActivity(nick, "pushups", "reps", 25).expect(http.StatusCreated)
		}, 55, "push-ups"},
		{db.ChallengeYogaMinutes, func(h *harness, nick, _ person) {
			h.logActivity(nick, "yoga", "minutes", 20).expect(http.StatusCreated)
		}, 20, "min"},
		{db.ChallengeHabitMarks, func(h *harness, nick, _ person) {
			h.seedHabitMarks(nick, "2026-11-02", "2026-11-03", "2026-11-04")
		}, 3, "marks"},
		{db.ChallengeActiveDays, func(h *harness, nick, _ person) {
			start := ny(2026, time.November, 2, 8, 0)
			putWorkouts(h, nick, workout("a", "running", start, 30), workout("b", "yoga", start.Add(time.Hour), 30)).
				expect(http.StatusOK)
			h.logActivity(nick, "pushups", "reps", 10).expect(http.StatusCreated)
		}, 1, "days"},
	}
	for _, tc := range cases {
		t.Run(tc.kind, func(t *testing.T) {
			h := newHarness(t)
			nick, nadia := h.pair()
			h.seedChallenge(tc.kind)
			tc.seed(h, nick, nadia)
			got := h.get("/api/board", nick.Token).expect(http.StatusOK)
			if got.str("challenge.kind") != tc.kind || got.num("challenge.people.0.progress") != tc.progress ||
				got.num("challenge.people.1.progress") != 0 || got.flag("challenge.done") || got.flag("challenge.missed") {
				t.Fatalf("challenge = %s", got.Body)
			}
			if got.str("challenge.reason") != "seeded by the test" {
				t.Fatalf("the stored reason did not reach the app: %s", got.Body)
			}
			if !strings.Contains(got.str("challenge.title"), "together") || got.num("challenge.target") < 2 {
				t.Fatalf("title and target = %s", got.Body)
			}
		})
	}
}

func TestNewKindSharesAreSizedFromEachPersonsOwnTwoWeeks(t *testing.T) {
	h := newHarness(t)
	nick, _ := h.pair()
	h.seedChallenge(db.ChallengePushupReps)
	// Nick did 100 reps last week and 40 the week before: 110% of the average of 70 is 77, so 75.
	for _, row := range []struct {
		date string
		reps int
	}{{"2026-10-27", 100}, {"2026-10-21", 40}} {
		h.exec(`INSERT INTO activity_logs (user_id, local_date, type, quantity, client_op_id)
			VALUES ($1, $2::date, 'pushups', $3, gen_random_uuid())`, nick.ID, row.date, row.reps)
	}
	got := h.get("/api/board", nick.Token).expect(http.StatusOK)
	if got.num("challenge.people.0.target") != 75 || got.num("challenge.people.1.target") != 5 ||
		got.num("challenge.target") != 80 || got.str("challenge.title") != "Do 80 push-ups together" {
		t.Fatalf("challenge = %s", got.Body)
	}
}

func TestThePickFavoursTheLowestAreaStoresItsReasonAndNeverRepeats(t *testing.T) {
	h := newHarness(t)
	nick, nadia := h.pair()
	// Both logged meals on ten days of the two weeks before, always under the protein target, and
	// counted on eight days.
	for _, p := range []person{nick, nadia} {
		for _, d := range days("2026-10-19", 10) {
			h.seedMeal(p, d, 20)
		}
		for _, d := range days("2026-10-19", 8) {
			h.storeScore(p, d, 300, 0, 400)
		}
	}
	got := h.get("/api/board", nick.Token).expect(http.StatusOK)
	if got.str("challenge.kind") != "protein_days" || got.num("challenge.target") != 2 ||
		!strings.Contains(got.str("challenge.reason"), "Protein was your lowest area") ||
		!strings.Contains(got.str("challenge.reason"), "0%") {
		t.Fatalf("challenge = %s", got.Body)
	}
	var stored string
	if err := h.db.Pool.QueryRow(context.Background(), `SELECT pick_reason FROM challenges`).Scan(&stored); err != nil ||
		stored != got.str("challenge.reason") {
		t.Fatalf("stored reason = %q, %v", stored, err)
	}

	h.clock.Set(ny(2026, time.November, 9, 12, 0))
	next := h.get("/api/board", nick.Token).expect(http.StatusOK)
	if next.str("challenge.kind") == "protein_days" || next.str("challenge.reason") == "" {
		t.Fatalf("the same kind came back the next week: %s", next.Body)
	}
}

func TestAnUnfinishedChallengeClosesAsMissedAtWeekEndWithoutAPenalty(t *testing.T) {
	h := newHarness(t)
	nick, nadia := h.pair()
	h.seedChallenge(together.KindWorkouts)
	start := ny(2026, time.November, 2, 8, 0)
	putWorkouts(h, nick, workout("a", "running", start, 30), workout("b", "yoga", start.Add(time.Hour), 30)).expect(http.StatusOK)
	mid := h.get("/api/board", nick.Token).expect(http.StatusOK)
	if mid.flag("challenge.missed") || !mid.isNull("lastChallenge") {
		t.Fatalf("a running week is not missed: %s", mid.Body)
	}
	pointsBefore := h.get("/api/board", nadia.Token).expect(http.StatusOK).num("users.0.season.points")

	h.clock.Set(ny(2026, time.November, 9, 12, 0))
	next := h.get("/api/board", nadia.Token).expect(http.StatusOK)
	if !next.flag("lastChallenge.missed") || next.flag("lastChallenge.done") || next.str("lastChallenge.kind") != "workouts" ||
		next.num("lastChallenge.people.0.progress") != 2 {
		t.Fatalf("last week = %s", next.Body)
	}
	if next.flag("challenge.missed") {
		t.Fatalf("the new week started missed: %s", next.Body)
	}
	var missed *time.Time
	var done *time.Time
	if err := h.db.Pool.QueryRow(context.Background(),
		`SELECT missed_at, completed_at FROM challenges WHERE week_start = '2026-11-02'`).Scan(&missed, &done); err != nil ||
		missed == nil || done != nil {
		t.Fatalf("missed_at = %v, completed_at = %v, %v", missed, done, err)
	}
	if after := h.get("/api/board", nadia.Token).expect(http.StatusOK).num("users.0.season.points"); after != pointsBefore {
		t.Fatalf("a missed challenge cost points: %d -> %d", pointsBefore, after)
	}

	again := h.get("/api/board", nick.Token).expect(http.StatusOK)
	var missedAgain *time.Time
	if err := h.db.Pool.QueryRow(context.Background(),
		`SELECT missed_at FROM challenges WHERE week_start = '2026-11-02'`).Scan(&missedAgain); err != nil ||
		!missedAgain.Equal(*missed) || !again.flag("lastChallenge.missed") {
		t.Fatalf("closing is not once: %v vs %v, %s", missedAgain, missed, again.Body)
	}

	// A week after that the miss is old news.
	h.clock.Set(ny(2026, time.November, 16, 12, 0))
	if later := h.get("/api/board", nick.Token).expect(http.StatusOK); later.str("lastChallenge.endsOn") != "2026-11-15" {
		t.Fatalf("only last week's miss is shown: %s", later.Body)
	}
}

func TestACompletedChallengeIsNeverMissed(t *testing.T) {
	h := newHarness(t)
	nick, nadia := h.pair()
	h.seedChallenge(together.KindWorkouts)
	start := ny(2026, time.November, 2, 8, 0)
	putWorkouts(h, nick, workout("a", "running", start, 30), workout("b", "yoga", start.Add(time.Hour), 30)).expect(http.StatusOK)
	putWorkouts(h, nadia, workout("c", "running", start, 30), workout("d", "yoga", start.Add(time.Hour), 30)).expect(http.StatusOK)
	if !h.get("/api/board", nick.Token).expect(http.StatusOK).flag("challenge.done") {
		t.Fatal("the challenge should be done")
	}
	h.clock.Set(ny(2026, time.November, 9, 12, 0))
	next := h.get("/api/board", nick.Token).expect(http.StatusOK)
	if !next.isNull("lastChallenge") {
		t.Fatalf("a finished challenge shows as last week's miss: %s", next.Body)
	}
	var missed *time.Time
	if err := h.db.Pool.QueryRow(context.Background(),
		`SELECT missed_at FROM challenges WHERE week_start = '2026-11-02'`).Scan(&missed); err != nil || missed != nil {
		t.Fatalf("missed_at = %v, %v", missed, err)
	}
}

func TestTheRecapSaysWhenTheChallengeWasMissed(t *testing.T) {
	h := newHarness(t)
	nick, _ := h.pair()
	h.seedChallenge(together.KindWorkouts)
	h.get("/api/board", nick.Token).expect(http.StatusOK)
	h.clock.Set(ny(2026, time.November, 9, 12, 0))
	h.get("/api/board", nick.Token).expect(http.StatusOK)
	got := h.get("/api/recap?week=2026-W45", nick.Token).expect(http.StatusOK)
	if !got.flag("challenge.missed") || got.flag("challenge.completed") || got.str("challenge.kind") != "workouts" {
		t.Fatalf("recap = %s", got.Body)
	}
}

func TestNewNotificationSwitchesDefaultOnAndPatchSeparately(t *testing.T) {
	h := newHarness(t)
	nick := h.joinAdmin("Nick", "green")
	me := h.get("/api/me", nick.Token).expect(http.StatusOK)
	for _, k := range []string{"partnerDone", "partnerNudges", "cover", "approvals", "cheers"} {
		if !me.flag("notifications." + k) {
			t.Fatalf("%s should default on: %s", k, me.Body)
		}
	}
	got := h.patch("/api/me", nick.Token, obj{"notifications": obj{"cover": false}}).expect(http.StatusOK)
	if got.flag("notifications.cover") || !got.flag("notifications.cheers") || !got.flag("notifications.partnerNudges") ||
		!got.flag("notifications.approvals") {
		t.Fatalf("patched = %s", got.Body)
	}
	got = h.patch("/api/me", nick.Token, obj{"notifications": obj{"partnerNudges": false, "approvals": false}}).expect(http.StatusOK)
	if got.flag("notifications.partnerNudges") || got.flag("notifications.approvals") || got.flag("notifications.cover") ||
		!got.flag("notifications.partnerDone") {
		t.Fatalf("patched = %s", got.Body)
	}
	if again := h.get("/api/me", nick.Token).expect(http.StatusOK); again.flag("notifications.cover") ||
		again.flag("notifications.approvals") {
		t.Fatalf("not persisted: %s", again.Body)
	}
}

func (h *harness) user(p person) db.User {
	h.t.Helper()
	u, err := db.GetUser(context.Background(), h.db.Pool, p.ID)
	if err != nil {
		h.t.Fatal(err)
	}
	return u
}

func TestCoverAndApprovalPushesFollowTheirOwnSwitches(t *testing.T) {
	n := &capture{}
	h := newHarness(t, withPush(n))
	nick, _ := h.pair()
	h.patch("/api/me", nick.Token, obj{"notifications": obj{"cheers": false}}).expect(http.StatusOK)
	svc := h.srv.together

	svc.Notify(h.user(nick), push.Message{Kind: together.EventCover, Title: "t", Body: "b"})
	svc.Notify(h.user(nick), push.Message{Kind: together.EventHabitProposal, Title: "t", Body: "b"})
	if len(n.of(together.EventCover, nick.ID)) != 1 || len(n.of(together.EventHabitProposal, nick.ID)) != 1 {
		t.Fatalf("cheers off must not silence cover or approvals: %+v", n.msgs)
	}

	h.patch("/api/me", nick.Token, obj{"notifications": obj{"cover": false}}).expect(http.StatusOK)
	svc.Notify(h.user(nick), push.Message{Kind: together.EventCover, Title: "t", Body: "b"})
	svc.Notify(h.user(nick), push.Message{Kind: together.EventHabitProposal, Title: "t", Body: "b"})
	if len(n.of(together.EventCover, nick.ID)) != 1 || len(n.of(together.EventHabitProposal, nick.ID)) != 2 {
		t.Fatalf("cover off must silence only cover: %+v", n.msgs)
	}

	h.patch("/api/me", nick.Token, obj{"notifications": obj{"approvals": false}}).expect(http.StatusOK)
	svc.Notify(h.user(nick), push.Message{Kind: together.EventHabitProposal, Title: "t", Body: "b"})
	if len(n.of(together.EventHabitProposal, nick.ID)) != 2 {
		t.Fatalf("approvals off still pushed: %+v", n.msgs)
	}

	h.patch("/api/me", nick.Token, obj{"notifications": obj{"partnerNudges": false}}).expect(http.StatusOK)
	svc.Notify(h.user(nick), push.Message{Kind: together.EventRewardProgress, Title: "t", Body: "b"})
	if len(n.of(together.EventRewardProgress, nick.ID)) != 0 {
		t.Fatalf("partner nudges off still pushed: %+v", n.msgs)
	}
}

func TestEveryNonSafetyPushWaitsForQuietHoursAndAwayDays(t *testing.T) {
	n := &capture{}
	h := newHarness(t, withPush(n))
	nick, nadia := h.pair()

	h.clock.Set(ny(2026, time.November, 3, 3, 0))
	h.cheer(nadia, nick, "fire").expect(http.StatusCreated)
	h.srv.together.Notify(h.user(nick), push.Message{Kind: together.EventMilestone, Title: "t", Body: "b"})
	h.srv.together.Notify(h.user(nick), push.Message{Kind: together.EventChallenge, Title: "t", Body: "b"})
	if n.count() != 0 {
		t.Fatalf("quiet hours were broken: %+v", n.msgs)
	}

	h.clock.Set(ny(2026, time.November, 3, 12, 0))
	h.cheer(nadia, nick, "heart").expect(http.StatusCreated)
	if len(n.of("cheer", nick.ID)) != 1 {
		t.Fatalf("a push at noon is fine: %+v", n.msgs)
	}

	if _, err := db.CreateAway(context.Background(), h.db.Pool, nick.ID, "2026-11-03", "2026-11-05", ""); err != nil {
		t.Fatal(err)
	}
	h.cheer(nadia, nick, "clap").expect(http.StatusCreated)
	h.srv.together.Notify(h.user(nick), push.Message{Kind: together.EventReward, Title: "t", Body: "b"})
	if len(n.of("cheer", nick.ID)) != 1 || len(n.of(together.EventReward, nick.ID)) != 0 {
		t.Fatalf("an away day was not silent: %+v", n.msgs)
	}
	// The partner is not away and still hears about it.
	h.cheer(nick, nadia, "clap").expect(http.StatusCreated)
	if len(n.of("cheer", nadia.ID)) != 1 {
		t.Fatalf("the partner should still be notified: %+v", n.msgs)
	}
}

func TestQuietHoursFollowThePersonsOwnSchedule(t *testing.T) {
	n := &capture{}
	h := newHarness(t, withPush(n))
	nick, nadia := h.pair()
	h.patch("/api/me", nick.Token, obj{"schedule": obj{"workday": obj{"wake": "10:00", "bed": "22:00"}}}).expect(http.StatusOK)

	h.clock.Set(ny(2026, time.November, 3, 9, 0))
	h.cheer(nadia, nick, "fire").expect(http.StatusCreated)
	if n.count() != 0 {
		t.Fatalf("Nick sleeps until 10:10: %+v", n.msgs)
	}
	h.clock.Set(ny(2026, time.November, 3, 10, 30))
	h.cheer(nadia, nick, "heart").expect(http.StatusCreated)
	if len(n.of("cheer", nick.ID)) != 1 {
		t.Fatalf("Nick is up at 10:30: %+v", n.msgs)
	}
}

func TestPartnerCountedAnnouncementWaitsForTheMorningAndStillArrives(t *testing.T) {
	n := &capture{}
	h := newHarness(t, withPush(n))
	nick, nadia := h.pair()
	h.clock.Set(ny(2026, time.November, 2, 6, 0))
	h.logActivity(nadia, "pushups", "reps", 100).expect(http.StatusCreated)
	h.logActivity(nadia, "reading", "minutes", 30).expect(http.StatusCreated)
	h.storeScore(nadia, "2026-11-02", 300, 0, 400)
	if err := h.srv.together.Settle(context.Background()); err != nil {
		t.Fatal(err)
	}
	if len(n.of(together.EventPartnerDone, nick.ID)) != 0 {
		t.Fatalf("announced in quiet hours: %+v", n.msgs)
	}
	h.clock.Set(ny(2026, time.November, 2, 9, 0))
	if err := h.srv.together.Settle(context.Background()); err != nil {
		t.Fatal(err)
	}
	if len(n.of(together.EventPartnerDone, nick.ID)) != 1 {
		t.Fatalf("the announcement should arrive once the day opens: %+v", n.msgs)
	}
	if err := h.srv.together.Settle(context.Background()); err != nil {
		t.Fatal(err)
	}
	if len(n.of(together.EventPartnerDone, nick.ID)) != 1 {
		t.Fatalf("announced twice: %+v", n.msgs)
	}
}

// flaky refuses messages while refuse is set, like a dispatcher whose queue is full.
type flaky struct {
	mu     sync.Mutex
	refuse bool
	msgs   []push.Message
}

func (f *flaky) Enqueue(m push.Message) bool {
	f.mu.Lock()
	defer f.mu.Unlock()
	if f.refuse {
		return false
	}
	f.msgs = append(f.msgs, m)
	return true
}

func (f *flaky) set(refuse bool) {
	f.mu.Lock()
	defer f.mu.Unlock()
	f.refuse = refuse
}

func (f *flaky) of(kind string, user int64) []push.Message {
	f.mu.Lock()
	defer f.mu.Unlock()
	var out []push.Message
	for _, m := range f.msgs {
		if m.Kind == kind && m.UserID == user {
			out = append(out, m)
		}
	}
	return out
}

func TestAFailedEnqueueReleasesTheClaimSoTheNextPassRetries(t *testing.T) {
	f := &flaky{}
	h := newHarness(t, func(s *Server) { s.WithNotifier(f) })
	nick, nadia := h.pair()
	h.clock.Set(ny(2026, time.November, 2, 10, 0))
	h.logActivity(nadia, "pushups", "reps", 30).expect(http.StatusCreated)

	f.set(true)
	h.runNudges(ny(2026, time.November, 2, 10, 5))
	var claims int
	if err := h.db.Pool.QueryRow(context.Background(),
		`SELECT count(*) FROM notice_log WHERE user_id = $1 AND kind LIKE 'partner\_%'`, nick.ID).Scan(&claims); err != nil || claims != 0 {
		t.Fatalf("a refused push kept its claim: %d, %v", claims, err)
	}
	f.set(false)
	h.runNudges(ny(2026, time.November, 2, 10, 10))
	got := f.of(together.EventPartnerCheer, nick.ID)
	if len(got) != 1 || got[0].Body != "Nadia did 30 push-ups today. A cheer is one tap away." {
		t.Fatalf("the retry did not send: %+v", f.msgs)
	}
	h.runNudges(ny(2026, time.November, 2, 10, 15))
	if len(f.of(together.EventPartnerCheer, nick.ID)) != 1 {
		t.Fatalf("sent twice: %+v", f.msgs)
	}
}

func TestACheerPromptComesOnceAndNeverAfterACheer(t *testing.T) {
	n := &capture{}
	h := newHarness(t, withPush(n))
	nick, nadia := h.pair()
	h.clock.Set(ny(2026, time.November, 2, 10, 0))
	h.logActivity(nadia, "pushups", "reps", 30).expect(http.StatusCreated)

	h.runNudges(ny(2026, time.November, 2, 10, 5))
	got := n.of(together.EventPartnerCheer, nick.ID)
	if len(got) != 1 || got[0].Title != "Worth a cheer" ||
		got[0].Body != "Nadia did 30 push-ups today. A cheer is one tap away." {
		t.Fatalf("prompt = %+v", n.msgs)
	}
	if !together.WordsOK(got[0].Body) {
		t.Fatalf("the wording rules: %q", got[0].Body)
	}
	if len(n.of(together.EventPartnerCheer, nadia.ID)) != 0 {
		t.Fatalf("Nick did nothing worth a cheer: %+v", n.msgs)
	}
	h.runNudges(ny(2026, time.November, 2, 10, 10))
	if len(n.of(together.EventPartnerCheer, nick.ID)) != 1 {
		t.Fatalf("the prompt repeated: %+v", n.msgs)
	}

	// Next day: Nick already cheered Nadia, so there is nothing to prompt.
	h.clock.Set(ny(2026, time.November, 3, 10, 0))
	h.logActivity(nadia, "pushups", "reps", 30).expect(http.StatusCreated)
	h.cheer(nick, nadia, "fire").expect(http.StatusCreated)
	h.runNudges(ny(2026, time.November, 3, 10, 5))
	if len(n.of(together.EventPartnerCheer, nick.ID)) != 1 {
		t.Fatalf("prompted after a cheer: %+v", n.msgs)
	}
}

func TestPartnerNudgesHaveOneADayAndTheirOwnSwitches(t *testing.T) {
	n := &capture{}
	h := newHarness(t, withPush(n))
	nick, nadia := h.pair()
	h.seedChallenge(together.KindWorkouts)
	h.clock.Set(ny(2026, time.November, 5, 17, 30))
	h.logActivity(nadia, "pushups", "reps", 30).expect(http.StatusCreated)

	h.patch("/api/me", nick.Token, obj{"notifications": obj{"partnerNudges": false}}).expect(http.StatusOK)
	h.runNudges(ny(2026, time.November, 5, 17, 35))
	if len(n.of(together.EventPartnerCheer, nick.ID))+len(n.of(together.EventPartnerChallenge, nick.ID)) != 0 {
		t.Fatalf("partner nudges are off: %+v", n.msgs)
	}

	h.patch("/api/me", nick.Token, obj{"notifications": obj{"partnerNudges": true}}).expect(http.StatusOK)
	h.runNudges(ny(2026, time.November, 5, 17, 40))
	if len(n.of(together.EventPartnerCheer, nick.ID)) != 1 {
		t.Fatalf("expected the cheer prompt first: %+v", n.msgs)
	}
	// The check-in is also due, but the day's one partner nudge is spent.
	h.runNudges(ny(2026, time.November, 5, 18, 0))
	if len(n.of(together.EventPartnerChallenge, nick.ID)) != 0 {
		t.Fatalf("two partner nudges in a day: %+v", n.msgs)
	}
	// Nadia has nothing to cheer in Nick's day, so her one nudge is the check-in.
	got := n.of(together.EventPartnerChallenge, nadia.ID)
	if len(got) != 1 || got[0].Body != "2 workouts left on your share, with 4 days to go." {
		t.Fatalf("Nadia's check-in = %+v", n.msgs)
	}
}

func TestTheThursdayCheckInIsForThoseBehindTheirShareAfterFive(t *testing.T) {
	n := &capture{}
	h := newHarness(t, withPush(n))
	nick, nadia := h.pair()
	h.seedChallenge(together.KindWorkouts)
	start := ny(2026, time.November, 2, 8, 0)
	putWorkouts(h, nick, workout("a", "running", start, 30), workout("b", "yoga", start.Add(time.Hour), 30)).expect(http.StatusOK)

	h.runNudges(ny(2026, time.November, 5, 16, 30))
	if len(n.of(together.EventPartnerChallenge, nadia.ID)) != 0 {
		t.Fatalf("too early on Thursday: %+v", n.msgs)
	}
	h.runNudges(ny(2026, time.November, 5, 17, 30))
	if len(n.of(together.EventPartnerChallenge, nick.ID)) != 0 {
		t.Fatalf("Nick finished his share: %+v", n.msgs)
	}
	if len(n.of(together.EventPartnerChallenge, nadia.ID)) != 1 {
		t.Fatalf("Nadia is under her share: %+v", n.msgs)
	}
	h.runNudges(ny(2026, time.November, 6, 17, 30))
	if len(n.of(together.EventPartnerChallenge, nadia.ID)) != 1 {
		t.Fatalf("the check-in is Thursday only: %+v", n.msgs)
	}
}

func TestACoverChanceAnswersWhenThePartnerMissedYesterdayAndYouHoldAFreeze(t *testing.T) {
	n := &capture{}
	h, nick, nadia := coverScene(t)
	h.srv.WithNotifier(n)
	h.srv.together.Notifier = n

	h.runNudges(ny(2026, time.November, 7, 9, 0))
	got := n.of(together.EventPartnerCover, nick.ID)
	if len(got) != 1 || got[0].Body != "You hold 2 freezes. One could keep Nadia's streak going." {
		t.Fatalf("cover chance = %+v", n.msgs)
	}
	if len(n.of(together.EventPartnerCover, nadia.ID)) != 0 {
		t.Fatalf("Nadia holds no freeze, so she has nothing to offer: %+v", n.msgs)
	}
	for _, word := range []string{"missed", "failed", "broke"} {
		if strings.Contains(strings.ToLower(got[0].Body), word) {
			t.Fatalf("the nudge reports the failure: %q", got[0].Body)
		}
	}

	// Cover switched off: no chance is announced, the cover itself still works.
	h2, nick2, _ := coverScene(t)
	n2 := &capture{}
	h2.srv.together.Notifier = n2
	h2.patch("/api/me", nick2.Token, obj{"notifications": obj{"cover": false}}).expect(http.StatusOK)
	h2.runNudges(ny(2026, time.November, 7, 9, 0))
	if len(n2.of(together.EventPartnerCover, nick2.ID)) != 0 {
		t.Fatalf("cover is off: %+v", n2.msgs)
	}
}

func TestNoCoverChanceWhenThePartnerHasAFreezeOfTheirOwn(t *testing.T) {
	n := &capture{}
	h, nick, nadia := coverScene(t)
	h.srv.together.Notifier = n
	// Nadia counted every day but Friday, so a freeze of her own deals with Friday.
	for _, d := range append(days("2026-10-26", 8), "2026-11-03", "2026-11-04") {
		h.storeScore(nadia, d, 300, 0, 400)
	}
	h.runNudges(ny(2026, time.November, 7, 9, 0))
	if got := n.of(together.EventPartnerCover, nick.ID); len(got) != 0 {
		t.Fatalf("Nadia can cover herself: %+v", got)
	}
}

func TestRewardProgressHookTellsEachPersonOncePerThresholdWithinTheirPartnerBudget(t *testing.T) {
	n := &capture{}
	h := newHarness(t, withPush(n))
	nick, nadia := h.pair()
	svc := h.srv.together
	ctx := context.Background()

	if err := svc.NotifyRewardProgress(ctx, 7, "Trip to Rome", 30); err != nil || n.count() != 0 {
		t.Fatalf("below the first threshold: %v %+v", err, n.msgs)
	}
	if err := svc.NotifyRewardProgress(ctx, 7, "Trip to Rome", 55); err != nil {
		t.Fatal(err)
	}
	for _, p := range []person{nick, nadia} {
		got := n.of(together.EventRewardProgress, p.ID)
		if len(got) != 1 || got[0].Body != "Trip to Rome is 50% of the way there." {
			t.Fatalf("%s: %+v", p.Name, n.msgs)
		}
	}
	// Repeated calls and the same day's second threshold stay quiet.
	_ = svc.NotifyRewardProgress(ctx, 7, "Trip to Rome", 56)
	_ = svc.NotifyRewardProgress(ctx, 7, "Trip to Rome", 92)
	if len(n.of(together.EventRewardProgress, nick.ID)) != 1 {
		t.Fatalf("budget or once-per-threshold broken: %+v", n.msgs)
	}
	// The next day the 90 percent threshold goes out, and 50 is not repeated.
	h.clock.Set(ny(2026, time.November, 3, 12, 0))
	_ = svc.NotifyRewardProgress(ctx, 7, "Trip to Rome", 92)
	_ = svc.NotifyRewardProgress(ctx, 7, "Trip to Rome", 92)
	got := n.of(together.EventRewardProgress, nick.ID)
	if len(got) != 2 || got[1].Body != "Trip to Rome is 90% of the way there." {
		t.Fatalf("nick: %+v", n.msgs)
	}
	// Ready, on a third day. A different reward starts fresh.
	h.clock.Set(ny(2026, time.November, 4, 12, 0))
	_ = svc.NotifyRewardProgress(ctx, 7, "Trip to Rome", 100)
	if got := n.of(together.EventRewardProgress, nick.ID); len(got) != 3 || got[2].Body != "Trip to Rome is ready to enjoy." {
		t.Fatalf("ready: %+v", got)
	}
	h.clock.Set(ny(2026, time.November, 5, 12, 0))
	_ = svc.NotifyRewardProgress(ctx, 8, "Movie night", 51)
	if got := n.of(together.EventRewardProgress, nick.ID); len(got) != 4 || got[3].Body != "Movie night is 50% of the way there." {
		t.Fatalf("second reward: %+v", got)
	}
}

func TestRewardProgressSharesNoBudgetWithTheAutomaticPushes(t *testing.T) {
	n := &capture{}
	h := newHarness(t, withPush(n))
	nick, _ := h.pair()
	ctx := context.Background()
	today := score.MustDate("2026-11-02")
	for _, kind := range []string{together.EventBehindPaceAfternoon, together.EventMorningPlan} {
		if _, err := db.ClaimNotice(ctx, h.db.Pool, kind, nick.ID, today); err != nil {
			t.Fatal(err)
		}
	}
	if err := h.srv.together.NotifyRewardProgress(ctx, 1, "Spa", 50); err != nil {
		t.Fatal(err)
	}
	if len(n.of(together.EventRewardProgress, nick.ID)) != 1 {
		t.Fatalf("a spent automatic budget blocked the partner budget: %+v", n.msgs)
	}
}

func TestPartnerDoneDoesNotSpendThePartnerBudget(t *testing.T) {
	h := newHarness(t, withPush(&capture{}))
	nick, _ := h.pair()
	ctx := context.Background()
	today := score.MustDate("2026-11-02")
	if _, err := db.ClaimNotice(ctx, h.db.Pool, together.EventPartnerDone, nick.ID, today); err != nil {
		t.Fatal(err)
	}
	room, err := h.srv.together.PartnerRoom(ctx, nick.ID, today)
	if err != nil || !room {
		t.Fatalf("partner_done spent the finisher's partner budget: room=%v err=%v", room, err)
	}
	if _, err := db.ClaimNotice(ctx, h.db.Pool, together.EventPartnerCheer, nick.ID, today); err != nil {
		t.Fatal(err)
	}
	if room, _ = h.srv.together.PartnerRoom(ctx, nick.ID, today); room {
		t.Fatal("a cheer nudge should spend the budget")
	}
}

func TestPartnerNudgeClaimsNeedThePartnerPrefix(t *testing.T) {
	h := newHarness(t, withPush(&capture{}))
	nick, _ := h.pair()
	_, err := h.srv.together.SendPartnerNudge(context.Background(), h.user(nick), "2026-11-02", "cheer",
		push.Message{Kind: together.EventPartnerCheer, Title: "t", Body: "b"})
	if err == nil {
		t.Fatal("a claim outside the partner budget must be refused")
	}
}

func TestNudgeRunnerSurvivesAPairOfOne(t *testing.T) {
	n := &capture{}
	h := newHarness(t, withPush(n))
	h.joinAdmin("Nick", "green")
	h.runNudges(ny(2026, time.November, 2, 10, 0))
	for _, m := range n.msgs {
		if strings.HasPrefix(m.Kind, together.PartnerClaimPrefix) {
			t.Fatalf("nobody to nudge about: %+v", n.msgs)
		}
	}
}
