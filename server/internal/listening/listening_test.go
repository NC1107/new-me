package listening_test

import (
	"context"
	"errors"
	"os"
	"testing"
	"time"

	"github.com/jackc/pgx/v5"

	"github.com/nc1107/new-me/server/internal/abs"
	"github.com/nc1107/new-me/server/internal/abs/abstest"
	"github.com/nc1107/new-me/server/internal/db"
	"github.com/nc1107/new-me/server/internal/dbtest"
	"github.com/nc1107/new-me/server/internal/listening"
	"github.com/nc1107/new-me/server/internal/score"
)

func TestMain(m *testing.M) {
	dbtest.Require()
	os.Exit(m.Run())
}

var ctx = context.Background()

var newYork = func() *time.Location {
	loc, err := time.LoadLocation("America/New_York")
	if err != nil {
		panic(err)
	}
	return loc
}()

func at(day, hour, minute int) time.Time {
	return time.Date(2026, time.November, day, hour, minute, 0, 0, newYork)
}

type env struct {
	t     *testing.T
	db    *db.DB
	fake  *abstest.Fake
	syn   *listening.Syncer
	user  db.User
	clock time.Time
}

func (e *env) set(now time.Time) { e.clock = now }

// newEnv joins one user on 2026-11-02 and links them to a fake Audiobookshelf account.
func newEnv(t *testing.T, now time.Time) *env {
	t.Helper()
	database := dbtest.Fresh(t)
	e := &env{t: t, db: database, clock: now}
	e.fake = abstest.New(t, func() time.Time { return e.clock })
	e.fake.AddUser("nick", "pw")
	e.syn = listening.New(database, e.fake.URL)
	e.syn.Now = func() time.Time { return e.clock }
	err := database.WithTx(ctx, func(tx pgx.Tx) error {
		var err error
		e.user, err = db.CreateUser(ctx, tx, db.NewUser{Name: "Nick", Color: "green", Timezone: "America/New_York",
			IsAdmin: true, JoinedOn: score.MustDate("2026-11-02")}, 5)
		return err
	})
	if err != nil {
		t.Fatal(err)
	}
	return e
}

func (e *env) link() {
	e.t.Helper()
	sess, err := e.syn.ABS.Login(ctx, "nick", "pw")
	if err != nil {
		e.t.Fatal(err)
	}
	if _, err := e.syn.Link(ctx, e.user.ID, sess); err != nil {
		e.t.Fatal(err)
	}
}

func (e *env) minutes(date string) int {
	e.t.Helper()
	m, err := db.ListeningMinutes(ctx, e.db.Pool, e.user.ID, score.MustDate(date))
	if err != nil {
		e.t.Fatal(err)
	}
	return m
}

func (e *env) account() db.ABSAccount {
	e.t.Helper()
	a, err := db.GetABSAccount(ctx, e.db.Pool, e.user.ID)
	if err != nil {
		e.t.Fatal(err)
	}
	return a
}

func TestSyncStoresTheLastTwoOpenDaysAndRescoresThem(t *testing.T) {
	e := newEnv(t, at(3, 8, 0))
	e.fake.SetListening("nick", "2026-11-02", 20*60)
	e.fake.SetListening("nick", "2026-11-03", 45*60+59)
	e.link()

	if e.minutes("2026-11-02") != 20 || e.minutes("2026-11-03") != 45 {
		t.Fatalf("minutes = %d, %d", e.minutes("2026-11-02"), e.minutes("2026-11-03"))
	}
	row, err := db.GetDayScore(ctx, e.db.Pool, e.user.ID, score.MustDate("2026-11-02"))
	if err != nil || row.BasePoints == 0 {
		t.Fatalf("yesterday must be rescored with its listening: %+v %v", row, err)
	}
	if a := e.account(); a.SyncedAt == nil || a.LastError != nil {
		t.Fatalf("account = %+v", a)
	}
}

func TestSyncNeverTouchesAFinalizedDay(t *testing.T) {
	e := newEnv(t, at(3, 9, 0))
	e.fake.SetListening("nick", "2026-11-02", 20*60)
	e.link()
	if e.minutes("2026-11-02") != 20 {
		t.Fatal("yesterday is still open at 9:00")
	}

	e.set(at(3, 10, 0))
	e.fake.SetListening("nick", "2026-11-02", 90*60)
	e.fake.SetListening("nick", "2026-11-03", 5*60)
	if err := e.syn.SyncUser(ctx, e.user.ID); err != nil {
		t.Fatal(err)
	}
	if e.minutes("2026-11-02") != 20 || e.minutes("2026-11-03") != 5 {
		t.Fatalf("minutes = %d, %d; a finalized day must keep what it was scored with",
			e.minutes("2026-11-02"), e.minutes("2026-11-03"))
	}
}

func TestSyncSkipsDaysBeforeTheUserJoined(t *testing.T) {
	e := newEnv(t, at(2, 12, 0))
	e.fake.SetListening("nick", "2026-11-01", 60*60)
	e.link()
	if e.minutes("2026-11-01") != 0 {
		t.Fatal("a day before joining must not be stored")
	}
}

func TestSyncDoesNotRescoreAnUnchangedDay(t *testing.T) {
	e := newEnv(t, at(2, 12, 0))
	e.fake.SetListening("nick", "2026-11-02", 10*60)
	e.link()
	first, err := db.GetDayScore(ctx, e.db.Pool, e.user.ID, score.MustDate("2026-11-02"))
	if err != nil {
		t.Fatal(err)
	}
	e.set(at(2, 12, 15))
	if err := e.syn.SyncUser(ctx, e.user.ID); err != nil {
		t.Fatal(err)
	}
	second, _ := db.GetDayScore(ctx, e.db.Pool, e.user.ID, score.MustDate("2026-11-02"))
	if !second.ComputedAt.Equal(first.ComputedAt) {
		t.Fatal("an unchanged poll must not rescore")
	}
	if a := e.account(); a.SyncedAt == nil || !a.SyncedAt.Equal(at(2, 12, 15)) {
		t.Fatalf("syncedAt = %v, want the poll time", a.SyncedAt)
	}
}

func TestSyncLowersMinutesWhenAudiobookshelfReportsLess(t *testing.T) {
	e := newEnv(t, at(2, 12, 0))
	e.fake.SetListening("nick", "2026-11-02", 30*60)
	e.link()
	e.fake.SetListening("nick", "2026-11-02", 10*60)
	if err := e.syn.SyncUser(ctx, e.user.ID); err != nil {
		t.Fatal(err)
	}
	if e.minutes("2026-11-02") != 10 {
		t.Fatalf("minutes = %d, want 10", e.minutes("2026-11-02"))
	}
}

func TestSyncRefreshesATokenThatIsAboutToExpire(t *testing.T) {
	e := newEnv(t, at(2, 12, 0))
	e.link()
	before := e.account()

	e.set(at(2, 12, 0).Add(59 * time.Minute))
	e.fake.SetListening("nick", "2026-11-02", 5*60)
	if err := e.syn.SyncUser(ctx, e.user.ID); err != nil {
		t.Fatal(err)
	}
	_, refreshes, _ := e.fake.Counts()
	after := e.account()
	if refreshes != 1 || after.RefreshToken == before.RefreshToken || after.AccessToken == before.AccessToken {
		t.Fatalf("refreshes = %d, tokens must rotate and be stored: %+v -> %+v", refreshes, before, after)
	}
	if e.minutes("2026-11-02") != 5 {
		t.Fatal("the poll must still read listening after refreshing")
	}
}

func TestSyncRefreshesOnceWhenTheAccessTokenIsRejected(t *testing.T) {
	e := newEnv(t, at(2, 12, 0))
	e.link()
	e.fake.ExpireAccessToken("nick")
	e.fake.SetListening("nick", "2026-11-02", 7*60)

	if err := e.syn.SyncUser(ctx, e.user.ID); err != nil {
		t.Fatal(err)
	}
	if _, refreshes, _ := e.fake.Counts(); refreshes != 1 || e.minutes("2026-11-02") != 7 {
		t.Fatalf("refreshes = %d, minutes = %d", refreshes, e.minutes("2026-11-02"))
	}
}

func TestSyncKeepsTheLinkWhenTheSessionIsRevoked(t *testing.T) {
	e := newEnv(t, at(2, 12, 0))
	e.fake.SetListening("nick", "2026-11-02", 12*60)
	e.link()
	e.fake.Revoke("nick")
	e.fake.ExpireAccessToken("nick")

	e.set(at(2, 12, 15))
	if err := e.syn.SyncUser(ctx, e.user.ID); err != nil {
		t.Fatalf("a rejected session is recorded, not returned: %v", err)
	}
	a := e.account()
	if a.LastError == nil || *a.LastError != db.ABSErrorAuth || a.SyncedAt == nil || !a.SyncedAt.Equal(at(2, 12, 0)) {
		t.Fatalf("account = %+v; the link and last good sync must stay", a)
	}
	if e.minutes("2026-11-02") != 12 {
		t.Fatal("earlier minutes must stay")
	}
}

func TestSyncRecordsAnUnreachableServerAndRecovers(t *testing.T) {
	e := newEnv(t, at(2, 12, 0))
	e.link()
	e.fake.SetDown(true)

	err := e.syn.SyncUser(ctx, e.user.ID)
	if !errors.Is(err, abs.ErrUnavailable) {
		t.Fatalf("err = %v, want unavailable", err)
	}
	if a := e.account(); a.LastError == nil || *a.LastError != db.ABSErrorUnreachable {
		t.Fatalf("account = %+v", a)
	}

	e.fake.SetDown(false)
	if err := e.syn.SyncUser(ctx, e.user.ID); err != nil {
		t.Fatal(err)
	}
	if a := e.account(); a.LastError != nil {
		t.Fatalf("a good poll must clear the error: %+v", a)
	}
}

func TestSyncAllSkipsUnlinkedUsersAndHandlesNoAccounts(t *testing.T) {
	e := newEnv(t, at(2, 12, 0))
	if err := e.syn.SyncAll(ctx); err != nil {
		t.Fatal(err)
	}
	e.link()
	e.fake.SetListening("nick", "2026-11-02", 3*60)
	e.set(at(2, 12, 15))
	if err := e.syn.SyncAll(ctx); err != nil || e.minutes("2026-11-02") != 3 {
		t.Fatalf("err = %v, minutes = %d", err, e.minutes("2026-11-02"))
	}
}

func TestSyncIgnoresAccountsOfDeletedUsers(t *testing.T) {
	e := newEnv(t, at(2, 12, 0))
	e.link()
	err := e.db.WithTx(ctx, func(tx pgx.Tx) error { return db.SoftDeleteUser(ctx, tx, e.user.ID) })
	if err != nil {
		t.Fatal(err)
	}
	if _, err := db.GetABSAccount(ctx, e.db.Pool, e.user.ID); !errors.Is(err, db.ErrNotFound) {
		t.Fatalf("a deleted user's tokens must be removed: %v", err)
	}
}

func TestMinutesFromSeconds(t *testing.T) {
	for _, c := range []struct {
		seconds float64
		want    int
	}{{0, 0}, {-5, 0}, {59.9, 0}, {60, 1}, {119, 1}, {3600, 60}, {1e9, 1440}} {
		if got := listening.MinutesFromSeconds(c.seconds); got != c.want {
			t.Errorf("MinutesFromSeconds(%v) = %d, want %d", c.seconds, got, c.want)
		}
	}
}

func TestOpenDates(t *testing.T) {
	joined := score.MustDate("2026-11-02")
	for _, c := range []struct {
		name string
		now  time.Time
		want []score.Date
	}{
		{"join day", at(2, 12, 0), []score.Date{"2026-11-02"}},
		{"before the grace hour", at(3, 9, 59), []score.Date{"2026-11-02", "2026-11-03"}},
		{"at the grace hour", at(3, 10, 0), []score.Date{"2026-11-03"}},
	} {
		got := listening.OpenDates(joined, c.now, newYork)
		if len(got) != len(c.want) {
			t.Fatalf("%s: %v, want %v", c.name, got, c.want)
		}
		for i := range got {
			if got[i] != c.want[i] {
				t.Fatalf("%s: %v, want %v", c.name, got, c.want)
			}
		}
	}
}
