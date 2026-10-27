#!/usr/bin/env bash
# Proves the newest backup restores: loads it into a throwaway Postgres container and compares
# per-table row counts with the live database. Nothing touches the live data.
#
# Run from the compose directory (where .env and backups/ live):
#   ./restore-drill.sh            # uses backups/last/<db>-latest.sql.gz
#   ./restore-drill.sh <file.gz>  # or a specific dump
# Env overrides for other stacks: DB_CONTAINER (default new-me-db).
set -euo pipefail

set -a
# shellcheck disable=SC1091
. ./.env
set +a

db_container="${DB_CONTAINER:-new-me-db}"
dump="${1:-backups/last/${POSTGRES_DB}-latest.sql.gz}"
scratch="newme-restore-drill-$$"

[ -f "$dump" ] || { echo "no dump at $dump" >&2; exit 1; }

cleanup() { docker rm -f "$scratch" >/dev/null 2>&1 || true; }
trap cleanup EXIT

docker run -d --name "$scratch" \
  -e POSTGRES_USER="$POSTGRES_USER" -e POSTGRES_PASSWORD=drill -e POSTGRES_DB="$POSTGRES_DB" \
  postgres:16-alpine >/dev/null

for _ in $(seq 1 60); do
  # pg_isready passes during the image's init restart, so also require a real query.
  if docker exec "$scratch" psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -Atc 'select 1' >/dev/null 2>&1; then
    break
  fi
  sleep 1
done
sleep 2

gunzip -c "$dump" | docker exec -i "$scratch" psql -q -v ON_ERROR_STOP=1 \
  -U "$POSTGRES_USER" -d "$POSTGRES_DB" >/dev/null

counts() {
  local container="$1"
  docker exec "$container" psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -Atc \
    "select tablename from pg_tables where schemaname = 'public' order by 1" |
    while read -r table; do
      printf '%s %s\n' "$table" "$(docker exec "$container" psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -Atc "select count(*) from \"$table\"")"
    done
}

live="$(counts "$db_container")"
restored="$(counts "$scratch")"

echo "table rows(live) rows(restored)"
join <(echo "$live") <(echo "$restored") -a1 -a2 -e MISSING -o 0,1.2,2.2 | column -t

if [ "$live" = "$restored" ]; then
  echo "OK: $dump restores with identical row counts"
else
  # Rows written after the dump was taken show up here too, so compare against its timestamp.
  echo "DIFFERENT: counts differ (expected only for writes made after the dump)" >&2
  exit 2
fi
