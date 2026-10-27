// Package dbtest gives DB-backed tests a shared, serialized, freshly reset Postgres. Test
// binaries for different packages run in parallel, so each one queues for a session lock
// before touching the database.
package dbtest

import (
	"context"
	"fmt"
	"os"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/jackc/pgx/v5"

	"github.com/nc1107/new-me/server/internal/db"
)

// URLEnv names the variable holding the connection string of a Postgres the tests may wipe.
// Unset means "no database here", not failure.
const URLEnv = "TESTDB_URL"

// SkipOptOutEnv lets a machine with no Postgres run what it can, deliberately.
const SkipOptOutEnv = "NEWME_SKIP_DB_TESTS"

// lockWait bounds how long a test binary waits for its turn on the database.
const lockWait = 20 * time.Minute

// suiteLockKey is held on a dedicated connection for the life of each test binary.
const suiteLockKey int64 = 4915012099

var (
	once    sync.Once
	shared  *db.DB
	openErr error
	// lockConn is never closed: process exit releases the suite lock.
	lockConn *pgx.Conn
)

// Require refuses to let a package run as a silent no-op: a skipped suite still prints "ok",
// so the skip has to be chosen explicitly. Call it from TestMain; it exits the process when the
// database is missing and the opt-out is unset.
func Require() {
	if os.Getenv(URLEnv) != "" || os.Getenv(SkipOptOutEnv) != "" {
		return
	}
	fmt.Fprintf(os.Stderr, `
%[1]s is not set, so the DB-backed tests would SKIP - and a skipped
suite still prints "ok".

Run the full suite (starts a throwaway Postgres in Docker, then removes it):

    server/scripts/test.sh

Or, to run only the pure-unit tests and accept that the rest are not running:

    %[2]s=1 go test ./...
`, URLEnv, SkipOptOutEnv)
	os.Exit(1)
}

// Open connects once per test binary and migrates exactly as cmd/server does. The pool is never
// closed: handler goroutines can outlive a test, and process exit reclaims it.
func Open(t testing.TB) *db.DB {
	t.Helper()
	url := os.Getenv(URLEnv)
	if url == "" {
		t.Skipf("%s is not set - skipping the DB-backed tests", URLEnv)
	}
	once.Do(func() {
		// Test binaries queue here for the whole run of the ones ahead of them, so the wait must
		// outlast the sum of the other packages' suites, not any single test.
		ctx, cancel := context.WithTimeout(context.Background(), lockWait)
		defer cancel()
		if lockConn, openErr = pgx.Connect(ctx, url); openErr != nil {
			return
		}
		if _, openErr = lockConn.Exec(ctx, `SELECT pg_advisory_lock($1)`, suiteLockKey); openErr != nil {
			return
		}
		if shared, openErr = db.Connect(ctx, url); openErr != nil {
			return
		}
		openErr = shared.Migrate(ctx)
	})
	if openErr != nil {
		t.Fatalf("test database: %v", openErr)
	}
	return shared
}

// preserved tables survive a reset: migrations own their rows.
var preserved = map[string]bool{
	"schema_migrations": true,
	"seasons":           true,
	"server_config":     true,
}

// Reset returns the database to a freshly migrated state. The table list comes from the catalog
// so a table added by a later migration cannot leak rows into the next test.
func Reset(t testing.TB, database *db.DB) {
	t.Helper()
	ctx := context.Background()
	rows, err := database.Pool.Query(ctx, `SELECT tablename FROM pg_tables WHERE schemaname = 'public'`)
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
		if !preserved[name] {
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

// Fresh opens the database and resets it.
func Fresh(t testing.TB) *db.DB {
	t.Helper()
	database := Open(t)
	Reset(t, database)
	return database
}
