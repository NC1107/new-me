package db_test

import (
	"errors"
	"sync"
	"testing"
	"time"

	"github.com/jackc/pgx/v5"

	"github.com/nc1107/new-me/server/internal/db"
	"github.com/nc1107/new-me/server/internal/dbtest"
	"github.com/nc1107/new-me/server/internal/score"
)

func TestCreateUserSeedsTemplatesAndInitializes(t *testing.T) {
	database := dbtest.Fresh(t)
	u := join(t, database, "Nick", "green", true)
	if !u.IsAdmin || u.JoinedOn != "2026-10-26" {
		t.Fatalf("user = %+v", u)
	}
	templates, err := db.GetQuestTemplates(ctx, database.Pool, u.ID)
	if err != nil {
		t.Fatal(err)
	}
	if len(templates) != 6 {
		t.Fatalf("templates = %d, want 6", len(templates))
	}
	for _, tpl := range templates {
		if tpl.Enabled != (tpl.Key != db.QuestYoga) {
			t.Fatalf("%s enabled = %v; only yoga ships disabled", tpl.Key, tpl.Enabled)
		}
	}
	info, err := database.GetServerInfo(ctx)
	if err != nil || !info.Initialized {
		t.Fatalf("server info = %+v, %v", info, err)
	}
}

func TestCreateUserEnforcesRules(t *testing.T) {
	database := dbtest.Fresh(t)
	join(t, database, "Nick", "green", true)

	create := func(n db.NewUser, max int) error {
		return database.WithTx(ctx, func(tx pgx.Tx) error {
			n.Timezone, n.JoinedOn = "UTC", "2026-10-26"
			_, err := db.CreateUser(ctx, tx, n, max)
			return err
		})
	}
	tests := []struct {
		name string
		user db.NewUser
		max  int
		want error
	}{
		{"duplicate name ignoring case", db.NewUser{Name: "nick", Color: "sky"}, 2, db.ErrNameTaken},
		{"duplicate color", db.NewUser{Name: "Nadia", Color: "green"}, 2, db.ErrColorTaken},
		{"second admin", db.NewUser{Name: "Nadia", Color: "sky", IsAdmin: true}, 2, db.ErrAdminExists},
		{"over the cap", db.NewUser{Name: "Nadia", Color: "sky"}, 1, db.ErrServerFull},
	}
	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			if err := create(tc.user, tc.max); !errors.Is(err, tc.want) {
				t.Fatalf("err = %v, want %v", err, tc.want)
			}
		})
	}
	if err := create(db.NewUser{Name: "Nadia", Color: "sky"}, 2); err != nil {
		t.Fatalf("valid join: %v", err)
	}
}

func TestSimultaneousJoinsRespectTheCap(t *testing.T) {
	database := dbtest.Fresh(t)
	join(t, database, "Nick", "green", true)

	const attempts = 6
	colors := []string{"sky", "violet", "amber", "rose", "teal", "lime"}
	results := make(chan error, attempts)
	var wg sync.WaitGroup
	for i := 0; i < attempts; i++ {
		wg.Add(1)
		go func() {
			defer wg.Done()
			results <- database.WithTx(ctx, func(tx pgx.Tx) error {
				_, err := db.CreateUser(ctx, tx, db.NewUser{
					Name: "User" + colors[i], Color: colors[i], Timezone: "UTC", JoinedOn: "2026-10-26",
				}, 2)
				return err
			})
		}()
	}
	wg.Wait()
	close(results)
	joined := 0
	for err := range results {
		switch {
		case err == nil:
			joined++
		case !errors.Is(err, db.ErrServerFull):
			t.Fatalf("unexpected error: %v", err)
		}
	}
	if joined != 1 {
		t.Fatalf("%d simultaneous joins succeeded, want exactly 1 more than the admin", joined)
	}
	if n, _ := db.CountUsers(ctx, database.Pool); n != 2 {
		t.Fatalf("users = %d, want 2", n)
	}
}

func TestUpdateAndSoftDeleteUser(t *testing.T) {
	database := dbtest.Fresh(t)
	nick := join(t, database, "Nick", "green", true)
	nadia := join(t, database, "Nadia", "sky", false)

	kcal := 2200
	nick.KcalTarget = &kcal
	if err := db.UpdateUser(ctx, database.Pool, nick); err != nil {
		t.Fatal(err)
	}
	got, err := db.GetUser(ctx, database.Pool, nick.ID)
	if err != nil || got.KcalTarget == nil || *got.KcalTarget != 2200 || got.Timezone != "America/New_York" {
		t.Fatalf("after update: %+v, %v", got, err)
	}

	nadia.Color = "green"
	if err := db.UpdateUser(ctx, database.Pool, nadia); !errors.Is(err, db.ErrColorTaken) {
		t.Fatalf("color clash err = %v", err)
	}

	if _, err := db.CreateDevice(ctx, database.Pool, nadia.ID, "hash-n", "phone"); err != nil {
		t.Fatal(err)
	}
	if err := database.WithTx(ctx, func(tx pgx.Tx) error { return db.SoftDeleteUser(ctx, tx, nadia.ID) }); err != nil {
		t.Fatal(err)
	}
	if _, err := db.GetUser(ctx, database.Pool, nadia.ID); !errors.Is(err, db.ErrNotFound) {
		t.Fatalf("deleted user err = %v", err)
	}
	if _, _, err := db.UserByTokenHash(ctx, database.Pool, "hash-n"); !errors.Is(err, db.ErrNotFound) {
		t.Fatalf("deleted user's token err = %v", err)
	}
	join(t, database, "Nadia", "sky", false)
}

func TestDeviceLookupThrottlesLastSeen(t *testing.T) {
	database := dbtest.Fresh(t)
	u := join(t, database, "Nick", "green", true)
	id, err := db.CreateDevice(ctx, database.Pool, u.ID, "hash-1", "phone")
	if err != nil {
		t.Fatal(err)
	}
	lastSeen := func() time.Time {
		var ts time.Time
		if err := database.Pool.QueryRow(ctx, `SELECT last_seen_at FROM devices WHERE id = $1`, id).Scan(&ts); err != nil {
			t.Fatal(err)
		}
		return ts
	}

	before := lastSeen()
	got, deviceID, err := db.UserByTokenHash(ctx, database.Pool, "hash-1")
	if err != nil || got.ID != u.ID || deviceID != id {
		t.Fatalf("lookup = %+v %d %v", got, deviceID, err)
	}
	if !lastSeen().Equal(before) {
		t.Fatal("a lookup inside the throttle window must not write last_seen_at")
	}

	if _, err := database.Pool.Exec(ctx,
		`UPDATE devices SET last_seen_at = now() - interval '10 minutes' WHERE id = $1`, id); err != nil {
		t.Fatal(err)
	}
	stale := lastSeen()
	if _, _, err := db.UserByTokenHash(ctx, database.Pool, "hash-1"); err != nil {
		t.Fatal(err)
	}
	if !lastSeen().After(stale) {
		t.Fatal("a lookup after the throttle window must refresh last_seen_at")
	}

	if _, _, err := db.UserByTokenHash(ctx, database.Pool, "nope"); !errors.Is(err, db.ErrNotFound) {
		t.Fatalf("unknown token err = %v", err)
	}
	if err := db.DeleteDevice(ctx, database.Pool, id); err != nil {
		t.Fatal(err)
	}
	if _, _, err := db.UserByTokenHash(ctx, database.Pool, "hash-1"); !errors.Is(err, db.ErrNotFound) {
		t.Fatalf("revoked token err = %v", err)
	}
	if err := db.DeleteDevice(ctx, database.Pool, id); !errors.Is(err, db.ErrNotFound) {
		t.Fatalf("second delete err = %v", err)
	}
}

func TestInviteLifecycle(t *testing.T) {
	database := dbtest.Fresh(t)
	pool := database.Pool

	if err := db.CreateInvite(ctx, pool, "code-a", nil, 15*time.Minute); err != nil {
		t.Fatal(err)
	}
	if err := db.CheckInvite(ctx, pool, "code-a"); err != nil {
		t.Fatalf("check: %v", err)
	}
	if err := db.CheckInvite(ctx, pool, "wrong"); !errors.Is(err, db.ErrInviteInvalid) {
		t.Fatalf("wrong code err = %v", err)
	}
	if err := db.ConsumeInvite(ctx, pool, "code-a"); err != nil {
		t.Fatalf("consume: %v", err)
	}
	if err := db.ConsumeInvite(ctx, pool, "code-a"); !errors.Is(err, db.ErrInviteInvalid) {
		t.Fatalf("second consume err = %v", err)
	}
}

func TestInviteExpiresAndLocksAfterWrongGuesses(t *testing.T) {
	database := dbtest.Fresh(t)
	pool := database.Pool

	if err := db.CreateInvite(ctx, pool, "old", nil, -time.Minute); err != nil {
		t.Fatal(err)
	}
	if err := db.ConsumeInvite(ctx, pool, "old"); !errors.Is(err, db.ErrInviteInvalid) {
		t.Fatalf("expired code err = %v", err)
	}

	if err := db.CreateInvite(ctx, pool, "fresh", nil, time.Hour); err != nil {
		t.Fatal(err)
	}
	for i := 0; i < db.MaxInviteAttempts-1; i++ {
		if err := db.RecordInviteMiss(ctx, pool); err != nil {
			t.Fatal(err)
		}
	}
	if err := db.CheckInvite(ctx, pool, "fresh"); err != nil {
		t.Fatalf("still unlocked after %d misses: %v", db.MaxInviteAttempts-1, err)
	}
	if err := db.RecordInviteMiss(ctx, pool); err != nil {
		t.Fatal(err)
	}
	if err := db.ConsumeInvite(ctx, pool, "fresh"); !errors.Is(err, db.ErrInviteInvalid) {
		t.Fatalf("locked invite err = %v; even the right code must fail", err)
	}
}

func TestConsumeInviteRollsBackWithTheJoin(t *testing.T) {
	database := dbtest.Fresh(t)
	if err := db.CreateInvite(ctx, database.Pool, "code", nil, time.Hour); err != nil {
		t.Fatal(err)
	}
	boom := errors.New("join failed")
	err := database.WithTx(ctx, func(tx pgx.Tx) error {
		if err := db.ConsumeInvite(ctx, tx, "code"); err != nil {
			return err
		}
		return boom
	})
	if !errors.Is(err, boom) {
		t.Fatal(err)
	}
	if err := db.CheckInvite(ctx, database.Pool, "code"); err != nil {
		t.Fatalf("a failed join must give the code back: %v", err)
	}
}

func TestSeasonsSeedAndExclusion(t *testing.T) {
	database := dbtest.Open(t)
	seasons, err := db.ListSeasons(ctx, database.Pool)
	if err != nil {
		t.Fatal(err)
	}
	if len(seasons) != 2 || seasons[0].Name != "Season 0" || seasons[0].EndsOn == nil ||
		*seasons[0].EndsOn != "2026-12-31" || seasons[1].Name != "Season 1" || seasons[1].EndsOn != nil {
		t.Fatalf("seasons = %+v", seasons)
	}
	if got, ok := score.SeasonFor("2027-01-01", seasons); !ok || got.Name != "Season 1" {
		t.Fatalf("2027-01-01 -> %+v %v", got, ok)
	}

	for name, sql := range map[string]string{
		"overlapping range":  `INSERT INTO seasons (name, starts_on, ends_on) VALUES ('Dup', '2026-12-01', '2027-02-01')`,
		"inside an open one": `INSERT INTO seasons (name, starts_on) VALUES ('Open', '2030-01-01')`,
		"ends before start":  `INSERT INTO seasons (name, starts_on, ends_on) VALUES ('Bad', '2040-02-01', '2040-01-01')`,
	} {
		if _, err := database.Pool.Exec(ctx, sql); err == nil {
			t.Fatalf("%s must be rejected", name)
		}
	}
}

func TestQuestTemplateConstraints(t *testing.T) {
	database := dbtest.Fresh(t)
	u := join(t, database, "Nick", "green", true)

	for name, sql := range map[string]string{
		"points not a multiple of five": `UPDATE quest_templates SET points = 12 WHERE user_id = $1 AND key = 'steps'`,
		"target above the cap":          `UPDATE quest_templates SET target = 100001 WHERE user_id = $1 AND key = 'steps'`,
		"reading without pages":         `UPDATE quest_templates SET target_alt = NULL, unit_alt = NULL WHERE user_id = $1 AND key = 'reading'`,
		"pages on a steps quest":        `UPDATE quest_templates SET target_alt = 5, unit_alt = 'pages' WHERE user_id = $1 AND key = 'steps'`,
		"unknown key":                   `INSERT INTO quest_templates (user_id, key, target, unit, points) VALUES ($1, 'horse', 1, 'x', 5)`,
	} {
		if _, err := database.Pool.Exec(ctx, sql, u.ID); err == nil {
			t.Fatalf("%s must be rejected", name)
		}
	}
	if _, err := database.Pool.Exec(ctx,
		`INSERT INTO quest_templates (user_id, key, target, unit, points) VALUES ($1, 'steps', 1, 'steps', 5)`, u.ID); err == nil {
		t.Fatal("UNIQUE(user_id, key) must reject a second steps template")
	}
}

func TestUpsertTemplateKeepsPointsFixed(t *testing.T) {
	database := dbtest.Fresh(t)
	u := join(t, database, "Nick", "green", true)

	if err := db.UpsertQuestTemplate(ctx, database.Pool, u.ID, db.QuestTemplate{
		Key: db.QuestSteps, Target: 12000, Unit: "steps", Points: 500, Enabled: false,
	}); err != nil {
		t.Fatal(err)
	}
	templates, _ := db.GetQuestTemplates(ctx, database.Pool, u.ID)
	for _, tpl := range templates {
		if tpl.Key == db.QuestSteps && (tpl.Target != 12000 || tpl.Enabled || tpl.Points != 100) {
			t.Fatalf("steps template = %+v; target and enabled change, points do not", tpl)
		}
	}
}

func TestEnsureSnapshotIsStableAcrossTemplateEdits(t *testing.T) {
	database := dbtest.Fresh(t)
	u := join(t, database, "Nick", "green", true)
	day := score.MustDate("2026-10-27")

	for i := 0; i < 2; i++ {
		if err := db.EnsureSnapshot(ctx, database.Pool, u.ID, day); err != nil {
			t.Fatal(err)
		}
	}
	quests, err := db.GetDayQuests(ctx, database.Pool, u.ID, day)
	if err != nil || len(quests) != 5 {
		t.Fatalf("snapshot = %d quests (%v), want the 5 enabled ones", len(quests), err)
	}
	if quests[0].Key != db.QuestSteps || quests[2].Key != db.QuestReading || quests[2].TargetAlt == nil {
		t.Fatalf("snapshot order or reading target wrong: %+v", quests)
	}

	if err := db.UpsertQuestTemplate(ctx, database.Pool, u.ID, db.QuestTemplate{
		Key: db.QuestSteps, Target: 1000, Unit: "steps", Points: 100, Enabled: true,
	}); err != nil {
		t.Fatal(err)
	}
	if err := db.EnsureSnapshot(ctx, database.Pool, u.ID, day); err != nil {
		t.Fatal(err)
	}
	quests, _ = db.GetDayQuests(ctx, database.Pool, u.ID, day)
	if quests[0].Target != 8000 {
		t.Fatalf("a template edit rewrote an existing snapshot: target %d", quests[0].Target)
	}
	next := day.AddDays(1)
	if err := db.EnsureSnapshot(ctx, database.Pool, u.ID, next); err != nil {
		t.Fatal(err)
	}
	quests, _ = db.GetDayQuests(ctx, database.Pool, u.ID, next)
	if quests[0].Target != 1000 {
		t.Fatalf("the next day must pick up the edit, got %d", quests[0].Target)
	}
}

func TestEnsureSnapshotIgnoresTemplatesEnabledAfterwards(t *testing.T) {
	database := dbtest.Fresh(t)
	u := join(t, database, "Nick", "green", true)
	day := score.MustDate("2026-10-27")
	if err := db.EnsureSnapshot(ctx, database.Pool, u.ID, day); err != nil {
		t.Fatal(err)
	}
	if err := db.UpsertQuestTemplate(ctx, database.Pool, u.ID, db.QuestTemplate{
		Key: db.QuestYoga, Target: 20, Unit: "minutes", Points: 50, Enabled: true,
	}); err != nil {
		t.Fatal(err)
	}
	if err := db.EnsureSnapshot(ctx, database.Pool, u.ID, day); err != nil {
		t.Fatal(err)
	}
	if quests, _ := db.GetDayQuests(ctx, database.Pool, u.ID, day); len(quests) != 5 {
		t.Fatalf("enabling yoga added it to a day already in progress: %d quests", len(quests))
	}
	if err := db.EnsureSnapshot(ctx, database.Pool, u.ID, day.AddDays(1)); err != nil {
		t.Fatal(err)
	}
	if quests, _ := db.GetDayQuests(ctx, database.Pool, u.ID, day.AddDays(1)); len(quests) != 6 {
		t.Fatalf("the next day must include yoga, got %d quests", len(quests))
	}

	scored := day.AddDays(5)
	if _, err := db.UpsertDayScore(ctx, database.Pool, db.DayScoreRow{
		UserID: u.ID, LocalDate: scored, Detail: []byte("[]")}, false); err != nil {
		t.Fatal(err)
	}
	if err := db.EnsureSnapshot(ctx, database.Pool, u.ID, scored); err != nil {
		t.Fatal(err)
	}
	if quests, _ := db.GetDayQuests(ctx, database.Pool, u.ID, scored); len(quests) != 0 {
		t.Fatalf("a scored day must not be snapshotted afterwards: %d quests", len(quests))
	}
}

func TestSnapshotProteinFollowsProfileTarget(t *testing.T) {
	database := dbtest.Fresh(t)
	u := join(t, database, "Nick", "green", true)
	proteinTarget := func(day score.Date) int {
		if err := db.EnsureSnapshot(ctx, database.Pool, u.ID, day); err != nil {
			t.Fatal(err)
		}
		quests, _ := db.GetDayQuests(ctx, database.Pool, u.ID, day)
		for _, q := range quests {
			if q.Key == db.QuestProtein {
				return q.Target
			}
		}
		t.Fatal("no protein quest")
		return 0
	}
	if got := proteinTarget("2026-10-27"); got != db.DefaultProteinTarget {
		t.Fatalf("unset profile target snapshots %d, want %d", got, db.DefaultProteinTarget)
	}
	protein := 150
	u.ProteinTarget = &protein
	if err := db.UpdateUser(ctx, database.Pool, u); err != nil {
		t.Fatal(err)
	}
	if got := proteinTarget("2026-10-28"); got != 150 {
		t.Fatalf("profile target snapshots %d, want 150", got)
	}
}

func TestStagedTimezoneSwitchesOnlyWhenNoDateRepeatsOrIsSkipped(t *testing.T) {
	database := dbtest.Fresh(t)
	nick := join(t, database, "Nick", "green", true)
	london, err := time.LoadLocation("Europe/London")
	if err != nil {
		t.Fatal(err)
	}
	from := score.MustDate("2026-10-27")
	if err := db.StageTimezone(ctx, database.Pool, nick.ID, "Europe/London", from); err != nil {
		t.Fatal(err)
	}
	staged, err := db.GetUser(ctx, database.Pool, nick.ID)
	if err != nil || staged.Timezone != "America/New_York" || staged.ChosenTimezone() != "Europe/London" {
		t.Fatalf("staged user = %+v, %v", staged, err)
	}

	// New York is still on the 26th, so the switch must wait.
	early := time.Date(2026, 10, 26, 23, 0, 0, 0, london)
	if got, err := db.SwitchTimezoneIfDue(ctx, database.Pool, staged, early); err != nil || got.Timezone != "America/New_York" {
		t.Fatalf("switched early: %+v, %v", got, err)
	}
	// Once New York reaches the 27th, London is on the 27th too.
	due := time.Date(2026, 10, 27, 6, 0, 0, 0, london)
	got, err := db.SwitchTimezoneIfDue(ctx, database.Pool, staged, due)
	if err != nil || got.Timezone != "Europe/London" || got.PendingTimezone != nil || got.PendingFrom != nil {
		t.Fatalf("not switched when due: %+v, %v", got, err)
	}
	// A stale copy of the user, as a racing request holds, switches nothing twice.
	if again, err := db.SwitchTimezoneIfDue(ctx, database.Pool, staged, due); err != nil || again.Timezone != "Europe/London" {
		t.Fatalf("second switch: %+v, %v", again, err)
	}

	if err := db.StageTimezone(ctx, database.Pool, nick.ID, "Asia/Tokyo", score.MustDate("2026-10-30")); err != nil {
		t.Fatal(err)
	}
	if err := db.StageTimezone(ctx, database.Pool, nick.ID, "Europe/London", score.MustDate("2026-10-30")); err != nil {
		t.Fatal(err)
	}
	cleared, err := db.GetUser(ctx, database.Pool, nick.ID)
	if err != nil || cleared.PendingTimezone != nil || cleared.ChosenTimezone() != "Europe/London" {
		t.Fatalf("choosing the zone in force must cancel the staged one: %+v, %v", cleared, err)
	}
}

func TestWithTxReleasesTheConnectionWhenTheBodyPanics(t *testing.T) {
	database := dbtest.Fresh(t)
	func() {
		defer func() {
			if recover() == nil {
				t.Fatal("the panic must still propagate to the recoverer")
			}
		}()
		_ = database.WithTx(ctx, func(tx pgx.Tx) error {
			if _, err := tx.Exec(ctx, `SELECT pg_advisory_xact_lock(1, 1)`); err != nil {
				return err
			}
			panic("boom")
		})
	}()
	if n := database.Pool.Stat().AcquiredConns(); n != 0 {
		t.Fatalf("%d connections still held after the panic, with their locks", n)
	}
}
