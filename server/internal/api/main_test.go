package api

import (
	"fmt"
	"os"
	"testing"
)

func TestMain(m *testing.M) {
	requireTestDB()
	os.Exit(m.Run())
}

// skipOptOutEnv lets a machine with no Postgres run what it can, deliberately.
const skipOptOutEnv = "NEWME_SKIP_DB_TESTS"

// requireTestDB refuses to run this package as a silent no-op: a skipped suite still prints
// "ok", so the skip has to be chosen explicitly. CI always sets TESTDB_URL.
func requireTestDB() {
	if os.Getenv(testDBEnv) != "" || os.Getenv(skipOptOutEnv) != "" {
		return
	}
	fmt.Fprintf(os.Stderr, `
%[1]s is not set, so the DB-backed handler tests would SKIP - and a skipped
suite still prints "ok".

Run the full suite (starts a throwaway Postgres in Docker, then removes it):

    server/scripts/test.sh

Or, to run only the pure-unit tests and accept that the rest are not running:

    %[2]s=1 go test ./...
`, testDBEnv, skipOptOutEnv)
	os.Exit(1)
}
