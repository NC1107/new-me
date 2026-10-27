package api

import (
	"context"
	"net/http"
	"strings"
	"testing"

	"github.com/nc1107/new-me/server/internal/auth"
	"github.com/nc1107/new-me/server/internal/db"
)

func (h *harness) sql(query string, args ...any) {
	h.t.Helper()
	if _, err := h.db.Pool.Exec(context.Background(), query, args...); err != nil {
		h.t.Fatalf("sql %q: %v", query, err)
	}
}

func TestFirstJoinCreatesTheAdminWithoutACode(t *testing.T) {
	h := newHarness(t)
	got := h.post("/api/join", "", obj{"name": "  Nick ", "color": "green", "timezone": "America/New_York"}).
		expect(http.StatusCreated)
	if got.str("user.name") != "Nick" || !got.flag("user.isAdmin") || got.str("user.timezone") != "America/New_York" ||
		got.str("token") == "" {
		t.Fatalf("join = %s", got.Body)
	}
	info := h.get("/api/server-info", "").expect(http.StatusOK)
	if !info.flag("initialized") {
		t.Fatal("the first join must initialize the server")
	}
	h.get("/api/me", got.str("token")).expect(http.StatusOK)
}

func TestFirstJoinValidatesTheProfile(t *testing.T) {
	h := newHarness(t)
	valid := func() obj { return obj{"name": "Nick", "color": "green", "timezone": "America/New_York"} }
	cases := map[string]func(obj){
		"empty name":      func(b obj) { b["name"] = "   " },
		"long name":       func(b obj) { b["name"] = strings.Repeat("n", 41) },
		"unknown color":   func(b obj) { b["color"] = "chartreuse" },
		"missing zone":    func(b obj) { delete(b, "timezone") },
		"unknown zone":    func(b obj) { b["timezone"] = "Mars/Olympus" },
		"local zone":      func(b obj) { b["timezone"] = "Local" },
		"numeric garbage": func(b obj) { b["timezone"] = "UTC+5" },
	}
	for name, mutate := range cases {
		body := valid()
		mutate(body)
		got := h.post("/api/join", "", body).expect(http.StatusUnprocessableEntity)
		want := "invalid_request"
		if strings.Contains(name, "zone") || name == "numeric garbage" {
			want = "invalid_timezone"
		}
		if got.str("code") != want {
			t.Fatalf("%s: code = %s, want %s", name, got.str("code"), want)
		}
	}
	if h.get("/api/server-info", "").flag("initialized") {
		t.Fatal("a rejected join must not initialize the server")
	}
}

func TestSecondJoinNeedsACode(t *testing.T) {
	h := newHarness(t)
	nick := h.joinAdmin("Nick", "green")

	h.post("/api/join", "", obj{"name": "Nadia", "color": "violet", "timezone": "America/New_York"}).
		expect(http.StatusUnprocessableEntity).code("invalid_request")
	h.post("/api/join", "", obj{"code": "AAAA-AAAA-AAAA-AAAA", "name": "Nadia", "color": "violet",
		"timezone": "America/New_York"}).expect(http.StatusForbidden).code("invalid_code")
	h.post("/api/join", "", obj{"code": "short", "name": "Nadia", "color": "violet",
		"timezone": "America/New_York"}).expect(http.StatusForbidden).code("invalid_code")

	nadia := h.joinMember(h.invite(nick), "Nadia", "violet")
	if nadia.ID == nick.ID {
		t.Fatal("the member must be a new user")
	}
}

func TestInviteCodeIsSingleUseAndAcceptsLooseFormatting(t *testing.T) {
	h := newHarness(t, func(s *Server) { s.cfg.MaxUsers = 3 })
	nick := h.joinAdmin("Nick", "green")
	code := h.invite(nick)
	loose := strings.ToLower(strings.ReplaceAll(code, "-", " "))
	h.joinMember(loose, "Nadia", "violet")
	h.post("/api/join", "", obj{"code": code, "name": "Sam", "color": "amber", "timezone": "UTC"}).
		expect(http.StatusForbidden).code("invalid_code")
}

func TestMaxUsersIs409AndKeepsTheCode(t *testing.T) {
	h := newHarness(t)
	nick, _ := h.pair()
	code := h.invite(nick)

	h.post("/api/join", "", obj{"code": code, "name": "Sam", "color": "amber", "timezone": "UTC"}).
		expect(http.StatusConflict).code("server_full")
	h.post("/api/invites/check", "", obj{"code": code}).expect(http.StatusOK)
	if !h.post("/api/invites/check", "", obj{"code": code}).flag("valid") {
		t.Fatal("a join that failed on the cap must give the code back")
	}
}

func TestNameAndColorConflicts(t *testing.T) {
	h := newHarness(t, func(s *Server) { s.cfg.MaxUsers = 3 })
	nick := h.joinAdmin("Nick", "green")
	code := h.invite(nick)

	h.post("/api/join", "", obj{"code": code, "name": "nick", "color": "violet", "timezone": "UTC"}).
		expect(http.StatusConflict).code("name_taken")
	h.post("/api/join", "", obj{"code": code, "name": "Nadia", "color": "green", "timezone": "UTC"}).
		expect(http.StatusConflict).code("color_taken")
	// The failed attempts did not spend the code.
	h.joinMember(code, "Nadia", "violet")
}

func TestRepairIssuesANewDeviceAndSignsOutTheOldOne(t *testing.T) {
	h := newHarness(t)
	nick, nadia := h.pair()
	code := h.invite(nick)

	check := h.post("/api/invites/check", "", obj{"code": code}).expect(http.StatusOK)
	if !check.flag("valid") || check.length("users") != 2 || check.flag("canJoinNew") {
		t.Fatalf("check = %s", check.Body)
	}
	if check.str("users.0.name") != "Nick" || check.str("users.1.color") != "violet" {
		t.Fatalf("re-pair chips = %s", check.Body)
	}

	got := h.post("/api/join", "", obj{"code": code, "userId": nadia.ID}).expect(http.StatusCreated)
	if int64(got.num("user.id")) != nadia.ID || got.str("token") == nadia.Token {
		t.Fatalf("re-pair = %s", got.Body)
	}
	h.get("/api/me", nadia.Token).expect(http.StatusUnauthorized)
	h.get("/api/me", got.str("token")).expect(http.StatusOK)
	h.get("/api/me", nick.Token).expect(http.StatusOK)

	h.post("/api/join", "", obj{"code": code, "userId": nadia.ID}).expect(http.StatusForbidden).code("invalid_code")
}

func TestRepairOfAnUnknownUserKeepsTheCodeAndRejectsExtraFields(t *testing.T) {
	h := newHarness(t)
	nick, _ := h.pair()
	code := h.invite(nick)
	h.post("/api/join", "", obj{"code": code, "userId": 9999}).expect(http.StatusNotFound).code("not_found")
	h.post("/api/join", "", obj{"code": code, "userId": nick.ID, "name": "Other"}).
		expect(http.StatusUnprocessableEntity)
	h.post("/api/join", "", obj{"code": code, "userId": nick.ID}).expect(http.StatusCreated)
}

func TestCheckDoesNotSpendTheCode(t *testing.T) {
	h := newHarness(t)
	nick := h.joinAdmin("Nick", "green")
	code := h.invite(nick)
	for range 3 {
		if got := h.post("/api/invites/check", "", obj{"code": code}).expect(http.StatusOK); !got.flag("canJoinNew") {
			t.Fatalf("check = %s", got.Body)
		}
	}
	h.joinMember(code, "Nadia", "violet")
}

func TestCheckOfABadCodeIsInvalidWithNoUsers(t *testing.T) {
	h := newHarness(t)
	h.pair()
	got := h.post("/api/invites/check", "", obj{"code": "AAAA-AAAA-AAAA-AAAA"}).expect(http.StatusOK)
	if got.flag("valid") || got.length("users") != 0 {
		t.Fatalf("check = %s", got.Body)
	}
	h.post("/api/invites/check", "", obj{"code": ""}).expect(http.StatusOK)
}

func TestInviteExpires(t *testing.T) {
	h := newHarness(t, func(s *Server) { s.cfg.MaxUsers = 3 })
	nick := h.joinAdmin("Nick", "green")
	code := h.invite(nick)
	h.sql(`UPDATE invites SET expires_at = now() - interval '1 second'`)

	if h.post("/api/invites/check", "", obj{"code": code}).flag("valid") {
		t.Fatal("an expired code must not check out")
	}
	h.post("/api/join", "", obj{"code": code, "name": "Nadia", "color": "violet", "timezone": "UTC"}).
		expect(http.StatusForbidden).code("invalid_code")
}

func TestInviteTTLIsFifteenMinutes(t *testing.T) {
	h := newHarness(t)
	nick := h.joinAdmin("Nick", "green")
	got := h.post("/api/invites", nick.Token, nil).expect(http.StatusCreated)
	if got.str("expiresAt") == "" {
		t.Fatalf("invite = %s", got.Body)
	}
	var minutes float64
	if err := h.db.Pool.QueryRow(context.Background(),
		`SELECT extract(epoch FROM expires_at - created_at) / 60 FROM invites`).Scan(&minutes); err != nil {
		t.Fatal(err)
	}
	if minutes != 15 {
		t.Fatalf("ttl = %v minutes, want 15", minutes)
	}
}

func TestWrongGuessesLockTheOutstandingInvite(t *testing.T) {
	h := newHarness(t, func(s *Server) { s.cfg.MaxUsers = 3 })
	nick := h.joinAdmin("Nick", "green")
	code := h.invite(nick)

	for range db.MaxInviteAttempts {
		h.post("/api/join", "", obj{"code": "AAAA-AAAA-AAAA-AAAA", "name": "Nadia", "color": "violet",
			"timezone": "UTC"}).expect(http.StatusForbidden)
	}
	h.post("/api/join", "", obj{"code": code, "name": "Nadia", "color": "violet", "timezone": "UTC"}).
		expect(http.StatusForbidden).code("invalid_code")
	if h.post("/api/invites/check", "", obj{"code": code}).flag("valid") {
		t.Fatal("a locked invite must not check out")
	}
}

func TestWrongChecksAlsoCountTowardTheLock(t *testing.T) {
	h := newHarness(t, func(s *Server) { s.cfg.MaxUsers = 3 })
	nick := h.joinAdmin("Nick", "green")
	code := h.invite(nick)
	for range db.MaxInviteAttempts {
		h.post("/api/invites/check", "", obj{"code": "BBBB-BBBB-BBBB-BBBB"}).expect(http.StatusOK)
	}
	if h.post("/api/invites/check", "", obj{"code": code}).flag("valid") {
		t.Fatal("guessing through the check endpoint must lock the invite too")
	}
}

func TestOnlyTheAdminCreatesInvites(t *testing.T) {
	h := newHarness(t)
	_, nadia := h.pair()
	h.post("/api/invites", nadia.Token, nil).expect(http.StatusForbidden).code("forbidden")
	h.post("/api/invites", "", nil).expect(http.StatusUnauthorized)
}

func TestInviteCodeShapeFromTheEndpoint(t *testing.T) {
	h := newHarness(t)
	nick := h.joinAdmin("Nick", "green")
	code := h.invite(nick)
	if auth.NormalizeInviteCode(code) == "" || strings.Count(code, "-") != 3 {
		t.Fatalf("code = %q", code)
	}
}

func TestLeavingTheServerRevokesTheDevice(t *testing.T) {
	h := newHarness(t)
	nick, nadia := h.pair()
	h.delete("/api/devices/me", nadia.Token).expect(http.StatusNoContent)
	h.get("/api/me", nadia.Token).expect(http.StatusUnauthorized)
	h.get("/api/me", nick.Token).expect(http.StatusOK)
}

func TestJoinScoresTheJoinDay(t *testing.T) {
	h := newHarness(t)
	nick := h.joinAdmin("Nick", "green")
	var n int
	if err := h.db.Pool.QueryRow(context.Background(),
		`SELECT count(*) FROM day_scores WHERE user_id = $1 AND local_date = '2026-11-02'`, nick.ID).Scan(&n); err != nil || n != 1 {
		t.Fatalf("day_scores rows for the join day = %d, %v", n, err)
	}
}
