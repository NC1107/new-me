package api

// DB-backed harness: the real chi router and handlers against a real Postgres. Isolation is
// a TRUNCATE between tests rather than a rolled-back transaction, because handlers open their
// own transactions through the shared pool; tests therefore must not call t.Parallel.

import (
	"bytes"
	"context"
	"encoding/json"
	"io"
	"net/http"
	"net/http/httptest"
	"os"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/nc1107/new-me/server/internal/config"
	"github.com/nc1107/new-me/server/internal/db"
)

// testDBEnv names the variable holding the connection string of a Postgres the tests may
// wipe. Unset means "no database here", not failure.
const testDBEnv = "TESTDB_URL"

const (
	testAppKey     = "test-app-key-0123456789"
	testServerName = "Test Me"
)

var (
	testDBOnce sync.Once
	testDB     *db.DB
	testDBErr  error
)

// openTestDB connects once per test binary and migrates exactly as cmd/server does. The pool
// is never closed: handler goroutines can outlive a test, and process exit reclaims it.
func openTestDB(t *testing.T) *db.DB {
	t.Helper()
	url := os.Getenv(testDBEnv)
	if url == "" {
		t.Skipf("%s is not set - skipping the DB-backed integration tests", testDBEnv)
	}
	testDBOnce.Do(func() {
		ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
		defer cancel()
		if testDB, testDBErr = db.Connect(ctx, url); testDBErr != nil {
			return
		}
		testDBErr = testDB.Migrate(ctx)
	})
	if testDBErr != nil {
		t.Fatalf("test database: %v", testDBErr)
	}
	return testDB
}

// preservedTables survive a reset: migrations own their rows.
var preservedTables = map[string]bool{
	"schema_migrations": true,
	"seasons":           true,
	"server_config":     true,
}

// resetDB returns the database to a freshly migrated state. The table list comes from the
// catalog so a table added by a later migration cannot leak rows into the next test.
func resetDB(t *testing.T, database *db.DB) {
	t.Helper()
	ctx := context.Background()
	rows, err := database.Pool.Query(ctx,
		`SELECT tablename FROM pg_tables WHERE schemaname = 'public'`)
	if err != nil {
		t.Fatalf("list tables: %v", err)
	}
	var tables []string
	for rows.Next() {
		var name string
		if err := rows.Scan(&name); err != nil {
			rows.Close()
			t.Fatalf("scan table name: %v", err)
		}
		if !preservedTables[name] {
			tables = append(tables, `"`+name+`"`)
		}
	}
	rows.Close()
	if err := rows.Err(); err != nil {
		t.Fatalf("list tables: %v", err)
	}
	if len(tables) > 0 {
		if _, err := database.Pool.Exec(ctx,
			"TRUNCATE "+strings.Join(tables, ", ")+" RESTART IDENTITY CASCADE"); err != nil {
			t.Fatalf("truncate: %v", err)
		}
	}
	if _, err := database.Pool.Exec(ctx,
		`UPDATE server_config SET name = 'New Me', initialized = false WHERE id = 1`); err != nil {
		t.Fatalf("reseed server_config: %v", err)
	}
}

// harness is one isolated server under test.
type harness struct {
	t    *testing.T
	db   *db.DB
	http *httptest.Server
	srv  *Server
}

func newHarness(t *testing.T) *harness {
	t.Helper()
	database := openTestDB(t)
	resetDB(t, database)
	if err := database.SeedServerName(context.Background(), testServerName); err != nil {
		t.Fatalf("seed server name: %v", err)
	}
	srv := New(config.Config{AppKey: testAppKey, ServerName: testServerName}, database)
	ts := httptest.NewServer(srv.Router())
	t.Cleanup(ts.Close)
	return &harness{t: t, db: database, http: ts, srv: srv}
}

// response is a completed call: status, headers and body, already read and closed.
type response struct {
	t      *testing.T
	Status int
	Header http.Header
	Body   []byte
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
