#!/bin/sh
# Runs the real test suite, including the DB-backed handler tests, against a throwaway
# Postgres that is removed again whatever happens. Arguments pass through to `go test`:
#
#     server/scripts/test.sh ./internal/api/ -run TestHealth -v
set -e

cd "$(dirname "$0")/.."

CONTAINER=newme-test-postgres-$$
# Docker picks a free port unless one is given, so runs from several checkouts at once never
# collide on a fixed port.
PORT=${NEWME_TEST_PG_PORT:-}
PASSWORD=test-$$

cleanup() {
  # -v drops the anonymous data volume the postgres image declares, which would otherwise leak.
  docker rm -f -v "$CONTAINER" >/dev/null 2>&1 || true
}
trap cleanup EXIT INT TERM

if ! command -v docker >/dev/null 2>&1; then
  echo "docker is required to run the DB-backed tests." >&2
  echo "To run only the pure-unit tests instead: NEWME_SKIP_DB_TESTS=1 go test ./..." >&2
  exit 1
fi

docker run -d --name "$CONTAINER" \
  -e POSTGRES_USER=newme \
  -e POSTGRES_PASSWORD="$PASSWORD" \
  -e POSTGRES_DB=newme_test \
  -p "127.0.0.1:$PORT:5432" postgres:16-alpine >/dev/null
PORT=$(docker port "$CONTAINER" 5432/tcp | head -n 1 | sed 's/.*://')
echo "started a throwaway Postgres on port $PORT" >&2

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
