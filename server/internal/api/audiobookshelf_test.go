package api

import (
	"context"
	"net/http"
	"strings"
	"testing"
	"time"

	"github.com/nc1107/new-me/server/internal/abs/abstest"
	"github.com/nc1107/new-me/server/internal/listening"
	"github.com/nc1107/new-me/server/internal/ratelimit"
)

// withABS points the server at a fake Audiobookshelf that follows the harness clock.
func withABS(t *testing.T) (func(*Server), func() *abstest.Fake) {
	var fake *abstest.Fake
	var clk func() time.Time
	opt := func(s *Server) {
		clk = s.now
		fake = abstest.New(t, func() time.Time { return clk() })
		s.listen = listening.New(s.db, fake.URL)
		s.listen.Now = s.now
	}
	return opt, func() *abstest.Fake { return fake }
}

func TestAudiobookshelfIsOffWithoutAURL(t *testing.T) {
	h := newHarness(t)
	nick := h.joinAdmin("Nick", "green")

	if !h.get("/api/me", nick.Token).expect(http.StatusOK).isNull("audiobookshelf") {
		t.Fatal("audiobookshelf must be null when the feature is off")
	}
	h.put("/api/me/audiobookshelf", nick.Token, obj{"username": "nick", "password": "pw"}).
		expect(http.StatusNotFound).code("abs_disabled")
	h.delete("/api/me/audiobookshelf", nick.Token).expect(http.StatusNotFound).code("abs_disabled")
	if h.get("/api/today", nick.Token).num("listening.minutes") != 0 {
		t.Fatal("today must report zero listening minutes")
	}
}

func TestMeReportsAnUnlinkedAccountWhenTheFeatureIsOn(t *testing.T) {
	opt, _ := withABS(t)
	h := newHarness(t, opt)
	nick := h.joinAdmin("Nick", "green")

	got := h.get("/api/me", nick.Token).expect(http.StatusOK)
	if got.flag("audiobookshelf.linked") || !got.isNull("audiobookshelf.username") ||
		!got.isNull("audiobookshelf.syncedAt") {
		t.Fatalf("audiobookshelf = %s", got.Body)
	}
}

func TestLinkingStoresTokensNotThePasswordAndSyncsAtOnce(t *testing.T) {
	opt, fakeOf := withABS(t)
	h := newHarness(t, opt)
	fake := fakeOf()
	fake.AddUser("nick", "correct horse battery")
	fake.SetListening("nick", "2026-11-02", 25*60+30)
	nick := h.joinAdmin("Nick", "green")

	got := h.put("/api/me/audiobookshelf", nick.Token,
		obj{"username": "nick", "password": "correct horse battery"}).expect(http.StatusOK)
	if !got.flag("linked") || got.str("username") != "nick" || got.str("syncedAt") != "2026-11-02T17:00:00Z" ||
		!got.isNull("lastError") {
		t.Fatalf("link = %s", got.Body)
	}
	if fake.LoginHeaders.Get("x-return-tokens") != "true" {
		t.Fatal("the login must ask for the refresh token in the body")
	}

	var stored string
	err := h.db.Pool.QueryRow(context.Background(),
		`SELECT row_to_json(a)::text FROM audiobookshelf_accounts a`).Scan(&stored)
	if err != nil || strings.Contains(stored, "correct horse battery") || !strings.Contains(stored, "refresh-") {
		t.Fatalf("stored row = %s, %v", stored, err)
	}

	me := h.get("/api/me", nick.Token).expect(http.StatusOK)
	if !me.flag("audiobookshelf.linked") || me.str("audiobookshelf.username") != "nick" ||
		me.str("audiobookshelf.syncedAt") != "2026-11-02T17:00:00Z" {
		t.Fatalf("me = %s", me.Body)
	}
}

func TestListeningCountsTowardTheReadingQuest(t *testing.T) {
	opt, fakeOf := withABS(t)
	h := newHarness(t, opt)
	fake := fakeOf()
	fake.AddUser("nick", "pw")
	fake.SetListening("nick", "2026-11-02", 6*60)
	nick := h.joinAdmin("Nick", "green")
	h.logActivity(nick, "reading", "minutes", 12).expect(http.StatusCreated)
	h.logActivity(nick, "reading", "pages", 5).expect(http.StatusCreated)

	before := h.get("/api/today", nick.Token).expect(http.StatusOK)
	if before.num("quests.2.basePoints") != 93 {
		t.Fatalf("reading before linking = %s", before.Body)
	}

	h.put("/api/me/audiobookshelf", nick.Token, obj{"username": "nick", "password": "pw"}).expect(http.StatusOK)
	got := h.get("/api/today", nick.Token).expect(http.StatusOK)
	if got.num("listening.minutes") != 6 || got.num("quests.2.actual") != 18 || got.num("quests.2.actualAlt") != 5 ||
		got.num("quests.2.basePoints") != 100 || !got.flag("quests.2.done") {
		t.Fatalf("today = %s", got.Body)
	}
}

func TestLinkRejectsBadCredentialsAndAnUnreachableServer(t *testing.T) {
	opt, fakeOf := withABS(t)
	h := newHarness(t, opt)
	fake := fakeOf()
	fake.AddUser("nick", "pw")
	nick := h.joinAdmin("Nick", "green")

	h.put("/api/me/audiobookshelf", nick.Token, obj{"username": "nick", "password": "wrong"}).
		expect(http.StatusUnprocessableEntity).code("abs_login_failed")
	if h.get("/api/me", nick.Token).flag("audiobookshelf.linked") {
		t.Fatal("a failed login must not link")
	}

	fake.SetDown(true)
	h.put("/api/me/audiobookshelf", nick.Token, obj{"username": "nick", "password": "pw"}).
		expect(http.StatusBadGateway).code("abs_unavailable")
}

func TestLinkValidatesTheBody(t *testing.T) {
	opt, _ := withABS(t)
	h := newHarness(t, opt)
	nick := h.joinAdmin("Nick", "green")

	for name, body := range map[string]obj{
		"empty username":   {"username": "", "password": "pw"},
		"empty password":   {"username": "nick", "password": ""},
		"control chars":    {"username": "ni\x00ck", "password": "pw"},
		"long username":    {"username": strings.Repeat("a", 201), "password": "pw"},
		"long password":    {"username": "nick", "password": strings.Repeat("a", 1001)},
		"missing username": {"password": "pw"},
	} {
		t.Run(name, func(t *testing.T) {
			h.put("/api/me/audiobookshelf", nick.Token, body).expect(http.StatusUnprocessableEntity).code("invalid_request")
		})
	}
	h.put("/api/me/audiobookshelf", nick.Token, obj{"username": "nick", "password": "pw", "extra": 1}).
		expect(http.StatusBadRequest).code("invalid_json")
}

func TestUnlinkRemovesTheLinkAndTheOpenDaysMinutes(t *testing.T) {
	opt, fakeOf := withABS(t)
	h := newHarness(t, opt)
	fake := fakeOf()
	fake.AddUser("nick", "pw")
	fake.SetListening("nick", "2026-11-02", 30*60)
	nick := h.joinAdmin("Nick", "green")
	h.put("/api/me/audiobookshelf", nick.Token, obj{"username": "nick", "password": "pw"}).expect(http.StatusOK)
	if !h.get("/api/today", nick.Token).flag("quests.2.done") {
		t.Fatal("30 listened minutes must complete reading")
	}

	h.delete("/api/me/audiobookshelf", nick.Token).expect(http.StatusNoContent)
	h.delete("/api/me/audiobookshelf", nick.Token).expect(http.StatusNoContent)
	me := h.get("/api/me", nick.Token).expect(http.StatusOK)
	if me.flag("audiobookshelf.linked") {
		t.Fatalf("me = %s", me.Body)
	}
	got := h.get("/api/today", nick.Token).expect(http.StatusOK)
	if got.num("listening.minutes") != 0 || got.flag("quests.2.done") || got.num("day.basePoints") != 0 {
		t.Fatalf("today after unlink = %s", got.Body)
	}
}

func TestRelinkingClearsAnEarlierSignInError(t *testing.T) {
	opt, fakeOf := withABS(t)
	h := newHarness(t, opt)
	fake := fakeOf()
	fake.AddUser("nick", "pw")
	nick := h.joinAdmin("Nick", "green")
	h.put("/api/me/audiobookshelf", nick.Token, obj{"username": "nick", "password": "pw"}).expect(http.StatusOK)

	fake.Revoke("nick")
	h.clock.Set(h.clock.Now().Add(2 * time.Hour))
	if err := h.srv.listen.SyncUser(context.Background(), nick.ID); err != nil {
		t.Fatal(err)
	}
	me := h.get("/api/me", nick.Token).expect(http.StatusOK)
	if !me.flag("audiobookshelf.linked") || me.str("audiobookshelf.lastError") != "auth_failed" {
		t.Fatalf("me after a rejected session = %s", me.Body)
	}

	h.put("/api/me/audiobookshelf", nick.Token, obj{"username": "nick", "password": "pw"}).
		expect(http.StatusOK)
	if !h.get("/api/me", nick.Token).isNull("audiobookshelf.lastError") {
		t.Fatal("relinking must clear the error")
	}
}

func TestLinkAttemptsAreRateLimited(t *testing.T) {
	opt, fakeOf := withABS(t)
	h := newHarness(t, opt, func(s *Server) { s.limits.absLink = ratelimit.New(1, 2) })
	fakeOf().AddUser("nick", "pw")
	nick := h.joinAdmin("Nick", "green")

	for range 2 {
		h.put("/api/me/audiobookshelf", nick.Token, obj{"username": "nick", "password": "nope"}).
			expect(http.StatusUnprocessableEntity)
	}
	h.put("/api/me/audiobookshelf", nick.Token, obj{"username": "nick", "password": "pw"}).
		expect(http.StatusTooManyRequests).code("rate_limited")
}
