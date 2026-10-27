package api

// DB-backed harness: the real chi router and handlers against a real Postgres. Isolation is
// a TRUNCATE between tests (dbtest.Reset) rather than a rolled-back transaction, because
// handlers open their own transactions through the shared pool; tests therefore must not call
// t.Parallel.

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"net/http/httptest"
	"strconv"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/nc1107/new-me/server/internal/config"
	"github.com/nc1107/new-me/server/internal/db"
	"github.com/nc1107/new-me/server/internal/dbtest"
	"github.com/nc1107/new-me/server/internal/ratelimit"
	"github.com/nc1107/new-me/server/internal/score"
)

const (
	testAppKey     = "test-app-key-0123456789"
	testServerName = "Test Me"
)

// newYork is the zone most fixtures live in.
var newYork = func() *time.Location {
	loc, err := time.LoadLocation("America/New_York")
	if err != nil {
		panic(err)
	}
	return loc
}()

// clock is the moment the server believes it is, movable between requests.
type clock struct {
	mu  sync.Mutex
	now time.Time
}

func (c *clock) Now() time.Time {
	c.mu.Lock()
	defer c.mu.Unlock()
	return c.now
}

func (c *clock) Set(t time.Time) {
	c.mu.Lock()
	defer c.mu.Unlock()
	c.now = t
}

// ny builds an instant from a New York wall clock reading.
func ny(year int, month time.Month, day, hour, minute int) time.Time {
	return time.Date(year, month, day, hour, minute, 0, 0, newYork)
}

// harness is one isolated server under test.
type harness struct {
	t     *testing.T
	db    *db.DB
	http  *httptest.Server
	srv   *Server
	clock *clock
	opSeq int
}

// newHarness starts a server whose clock reads Monday 2026-11-02 12:00 in New York, with the
// seasons pinned so every fixture date falls in a known one. Options adjust the Server before
// its router is built.
func newHarness(t *testing.T, opts ...func(*Server)) *harness {
	t.Helper()
	database := dbtest.Fresh(t)
	pinSeasons(t, database)
	if err := database.SeedServerName(context.Background(), testServerName); err != nil {
		t.Fatalf("seed server name: %v", err)
	}
	clk := &clock{now: ny(2026, time.November, 2, 12, 0)}
	srv := New(config.Config{AppKey: testAppKey, ServerName: testServerName, MinClientVersion: "1.0.0"}, database).
		WithVersion("9.9.9-test").WithClock(clk.Now)
	// Most tests pair several people in a row, so the join budget must not interfere with them.
	srv.limits.join = bigLimiter()
	srv.limits.device = bigLimiter()
	srv.limits.healthPut = bigLimiter()
	srv.limits.absLink = bigLimiter()
	for _, opt := range opts {
		opt(srv)
	}
	ts := httptest.NewServer(srv.Router())
	t.Cleanup(ts.Close)
	return &harness{t: t, db: database, http: ts, srv: srv, clock: clk}
}

// pinSeasons starts Season 0 at the beginning of 2026 for the test and restores the migration's
// value afterwards, since other packages' tests share the database.
func pinSeasons(t *testing.T, database *db.DB) {
	t.Helper()
	ctx := context.Background()
	var original string
	if err := database.Pool.QueryRow(ctx,
		`SELECT starts_on::text FROM seasons WHERE name = 'Season 0'`).Scan(&original); err != nil {
		t.Fatalf("read season: %v", err)
	}
	set := func(startsOn string) error {
		_, err := database.Pool.Exec(ctx, `UPDATE seasons SET starts_on = $1::date WHERE name = 'Season 0'`, startsOn)
		return err
	}
	if err := set("2026-01-01"); err != nil {
		t.Fatalf("pin season: %v", err)
	}
	t.Cleanup(func() {
		if err := set(original); err != nil {
			t.Errorf("restore season: %v", err)
		}
	})
}

// response is a completed call: status, headers and body, already read and closed.
type response struct {
	t      *testing.T
	Status int
	Header http.Header
	Body   []byte
	parsed any
}

// expect fails the test unless the status matches, quoting the body.
func (r *response) expect(status int) *response {
	r.t.Helper()
	if r.Status != status {
		r.t.Fatalf("status = %d, want %d; body: %s", r.Status, status, r.Body)
	}
	return r
}

func (r *response) decode(v any) *response {
	r.t.Helper()
	if err := json.Unmarshal(r.Body, v); err != nil {
		r.t.Fatalf("decode %T: %v; body: %s", v, err, r.Body)
	}
	return r
}

// at returns the value at a dotted path such as "day.percent" or "quests.0.key".
func (r *response) at(path string) any {
	r.t.Helper()
	if r.parsed == nil {
		r.decode(&r.parsed)
	}
	cur := r.parsed
	for _, part := range strings.Split(path, ".") {
		switch node := cur.(type) {
		case map[string]any:
			next, ok := node[part]
			if !ok {
				r.t.Fatalf("no %q on the way to %q; body: %s", part, path, r.Body)
			}
			cur = next
		case []any:
			i, err := strconv.Atoi(part)
			if err != nil || i < 0 || i >= len(node) {
				r.t.Fatalf("bad index %q on the way to %q; body: %s", part, path, r.Body)
			}
			cur = node[i]
		default:
			r.t.Fatalf("cannot descend into %v at %q on the way to %q", node, part, path)
		}
	}
	return cur
}

func (r *response) num(path string) int {
	r.t.Helper()
	f, ok := r.at(path).(float64)
	if !ok {
		r.t.Fatalf("%s = %v, want a number; body: %s", path, r.at(path), r.Body)
	}
	return int(f)
}

func (r *response) str(path string) string {
	r.t.Helper()
	s, ok := r.at(path).(string)
	if !ok {
		r.t.Fatalf("%s = %v, want a string; body: %s", path, r.at(path), r.Body)
	}
	return s
}

func (r *response) flag(path string) bool {
	r.t.Helper()
	b, ok := r.at(path).(bool)
	if !ok {
		r.t.Fatalf("%s = %v, want a bool; body: %s", path, r.at(path), r.Body)
	}
	return b
}

func (r *response) isNull(path string) bool {
	r.t.Helper()
	return r.at(path) == nil
}

func (r *response) length(path string) int {
	r.t.Helper()
	list, ok := r.at(path).([]any)
	if !ok {
		r.t.Fatalf("%s = %v, want a list; body: %s", path, r.at(path), r.Body)
	}
	return len(list)
}

// code asserts the error envelope's machine code.
func (r *response) code(want string) *response {
	r.t.Helper()
	if got := r.str("code"); got != want {
		r.t.Fatalf("code = %q, want %q; body: %s", got, want, r.Body)
	}
	return r
}

// do issues one request carrying the app key. Each edit runs against the built request, so
// a test can drop or replace a header.
func (h *harness) do(method, path, token string, body io.Reader, edits ...func(*http.Request)) *response {
	h.t.Helper()
	req, err := http.NewRequest(method, h.http.URL+path, body)
	if err != nil {
		h.t.Fatalf("build request: %v", err)
	}
	req.Header.Set("X-App-Key", testAppKey)
	if token != "" {
		req.Header.Set("Authorization", "Bearer "+token)
	}
	for _, edit := range edits {
		edit(req)
	}
	resp, err := h.http.Client().Do(req)
	if err != nil {
		h.t.Fatalf("%s %s: %v", method, path, err)
	}
	defer resp.Body.Close()
	raw, err := io.ReadAll(resp.Body)
	if err != nil {
		h.t.Fatalf("read %s %s: %v", method, path, err)
	}
	return &response{t: h.t, Status: resp.StatusCode, Header: resp.Header, Body: raw}
}

func (h *harness) get(path, token string, edits ...func(*http.Request)) *response {
	h.t.Helper()
	return h.do(http.MethodGet, path, token, nil, edits...)
}

func (h *harness) delete(path, token string) *response {
	h.t.Helper()
	return h.do(http.MethodDelete, path, token, nil)
}

func (h *harness) post(path, token string, body any) *response {
	h.t.Helper()
	return h.send(http.MethodPost, path, token, body)
}

func (h *harness) put(path, token string, body any) *response {
	h.t.Helper()
	return h.send(http.MethodPut, path, token, body)
}

func (h *harness) patch(path, token string, body any) *response {
	h.t.Helper()
	return h.send(http.MethodPatch, path, token, body)
}

func (h *harness) send(method, path, token string, body any) *response {
	h.t.Helper()
	raw, err := json.Marshal(body)
	if err != nil {
		h.t.Fatalf("encode body: %v", err)
	}
	return h.do(method, path, token, bytes.NewReader(raw), func(r *http.Request) {
		r.Header.Set("Content-Type", "application/json")
	})
}

// person is a paired user and the token of their device.
type person struct {
	ID    int64
	Name  string
	Token string
}

type obj = map[string]any

// joinAdmin performs the first join, which needs no code.
func (h *harness) joinAdmin(name, color string) person {
	h.t.Helper()
	return h.finishJoin(h.post("/api/join", "", obj{"name": name, "color": color, "timezone": "America/New_York"}))
}

// invite has the admin mint a code.
func (h *harness) invite(admin person) string {
	h.t.Helper()
	return h.post("/api/invites", admin.Token, nil).expect(http.StatusCreated).str("code")
}

// joinMember redeems a code as a new member.
func (h *harness) joinMember(code, name, color string) person {
	h.t.Helper()
	return h.finishJoin(h.post("/api/join", "", obj{
		"code": code, "name": name, "color": color, "timezone": "America/New_York"}))
}

func (h *harness) finishJoin(r *response) person {
	h.t.Helper()
	r.expect(http.StatusCreated)
	return person{ID: int64(r.num("user.id")), Name: r.str("user.name"), Token: r.str("token")}
}

// pair joins Nick as admin and Nadia as a member.
func (h *harness) pair() (nick, nadia person) {
	h.t.Helper()
	nick = h.joinAdmin("Nick", "green")
	nadia = h.joinMember(h.invite(nick), "Nadia", "violet")
	return nick, nadia
}

// nextOp returns a fresh clientOpId.
func (h *harness) nextOp() string {
	h.opSeq++
	return h.opID(h.opSeq)
}

// opID is the clientOpId numbered n, for tests that need to name one.
func (h *harness) opID(n int) string { return fmt.Sprintf("00000000-0000-4000-8000-%012d", n) }

func (h *harness) logActivity(p person, typ, unit string, quantity int, extra ...obj) *response {
	h.t.Helper()
	body := obj{"clientOpId": h.nextOp(), "kind": "activity", "type": typ, "unit": unit, "quantity": quantity}
	for _, e := range extra {
		for k, v := range e {
			body[k] = v
		}
	}
	return h.post("/api/logs", p.Token, body)
}

func (h *harness) logMeal(p person, name string, kcal int, protein float64, extra ...obj) *response {
	h.t.Helper()
	body := obj{"clientOpId": h.nextOp(), "kind": "meal", "name": name, "kcal": kcal, "protein": protein}
	for _, e := range extra {
		for k, v := range e {
			body[k] = v
		}
	}
	return h.post("/api/logs", p.Token, body)
}

// putHealth sends one health reading measured at the harness clock.
func (h *harness) putHealth(p person, date, metric string, value float64) *response {
	h.t.Helper()
	return h.put("/api/health/daily", p.Token, obj{"items": []obj{{
		"date": date, "metric": metric, "value": value, "source": "fake",
		"measuredAt": h.clock.Now().UTC().Format(time.RFC3339),
	}}})
}

// storeScore writes a finished day's score straight to the table, for fixtures that need many
// days without logging each one.
func (h *harness) storeScore(p person, date string, base, bonus, maxBase int) {
	h.t.Helper()
	percent := 0
	if maxBase > 0 {
		percent = min(100, base*100/maxBase)
	}
	_, err := db.UpsertDayScore(context.Background(), h.db.Pool, db.DayScoreRow{
		UserID: p.ID, LocalDate: score.MustDate(date), BasePoints: base, BonusPoints: bonus, MaxBase: maxBase,
		Percent: percent, Counted: maxBase > 0 && base*100 >= 70*maxBase, Detail: []byte("[]"),
	}, true)
	if err != nil {
		h.t.Fatalf("store score %s: %v", date, err)
	}
}

func bigLimiter() *ratelimit.Limiter { return ratelimit.New(100000, 100000) }
