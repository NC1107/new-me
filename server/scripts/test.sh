#!/bin/sh
# Runs the real test suite, including the DB-backed handler tests, against a throwaway
# Postgres that is removed again whatever happens. Arguments pass through to `go test`:
#
#     server/scripts/test.sh ./internal/api/ -run TestHealth -v
set -e

cd "$(dirname "$0")/.."

CONTAINER=newme-test-postgres-$$
PORT=${NEWME_TEST_PG_PORT:-55433}
PASSWORD=test-$$

cleanup() {
  docker rm -f "$CONTAINER" >/dev/null 2>&1 || true
}
trap cleanup EXIT INT TERM

if ! command -v docker >/dev/null 2>&1; then
  echo "docker is required to run the DB-backed tests." >&2
  echo "To run only the pure-unit tests instead: NEWME_SKIP_DB_TESTS=1 go test ./..." >&2
  exit 1
fi

echo "starting a throwaway Postgres on port $PORT..." >&2
docker run -d --name "$CONTAINER" \
  -e POSTGRES_USER=newme \
  -e POSTGRES_PASSWORD="$PASSWORD" \
  -e POSTGRES_DB=newme_test \
  -p "$PORT":5432 postgres:16-alpine >/dev/null

i=0
# Probing over TCP skips the init-time server, which listens on the unix socket only and
# restarts before the real one comes up.
until docker exec "$CONTAINER" pg_isready -h 127.0.0.1 -U newme >/dev/null 2>&1; do
  i=$((i + 1))
  if [ "$i" -gt 60 ]; then
    echo "Postgres did not become ready in 60s" >&2
    exit 1
  fi
  sleep 1
done

# -race matches what CI runs.
if [ "$#" -eq 0 ]; then
  set -- ./...
fi
TESTDB_URL="postgres://newme:$PASSWORD@127.0.0.1:$PORT/newme_test?sslmode=disable" \
  go test -race "$@"
