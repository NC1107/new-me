# New Me server

Go API for the New Me app.
chi router, pgx with hand-written SQL, embedded migrations applied on boot, Postgres 16.
Behaviour and scoring rules live in `docs/design.md`.

## Configuration

| variable | default | meaning |
|---|---|---|
| `NEWME_DATABASE_URL` | required | pgx connection string |
| `NEWME_APP_KEY` | required, at least 16 characters | shared value every request sends in `X-App-Key`; a missing or wrong key is a 403 |
| `NEWME_HTTP_ADDR` | `:8080` | listen address |
| `NEWME_SERVER_NAME` | `New Me` | name returned by `/api/server-info` until the first join |
| `NEWME_TRUSTED_PROXY_HOPS` | `1` | reverse proxies in front of the server, used to read the client IP for rate limits |
| `NEWME_MAX_USERS` | `2` | live user cap, enforced in the join transaction |
| `NEWME_MIN_CLIENT_VERSION` | `0.0.0` | oldest app version served; older ones get a 426 |
| `NEWME_DEV_CORS` | `false` | allows localhost browser origins for web review; never set in production |

## Pairing and invite codes

The first join on a fresh server creates the admin and needs no code.
Every later join, and every re-pair, redeems a single-use invite code.
Codes are 16 characters shown as `XXXX-XXXX-XXXX-XXXX`, last 15 minutes and lock after 5 wrong guesses.
The admin creates one in the app (`POST /api/invites`), or from the host:

```sh
docker exec new-me-server /app/server invite
```

The command prints only the code on stdout, so it can be piped.
It is the recovery path if the admin reinstalls the app.

## Running

- `server` runs the API and the day scheduler, which finalizes finished days every 5 minutes and catches up after restarts.
- `server invite` prints a fresh invite code and exits.
- `server -healthcheck` probes `127.0.0.1` on the configured port and exits 0 or 1, for the container healthcheck.
- The version reported by `/api/health` is set at build time: `docker build --build-arg VERSION=1.2.3 -t new-me-server .` or `go build -ldflags "-X main.version=1.2.3"`.

## Tests

`scripts/test.sh` starts a throwaway Postgres in Docker and runs `go test -race ./...`.
Arguments pass through: `scripts/test.sh ./internal/api -run TestBoard -v`.
Without Docker, `NEWME_SKIP_DB_TESTS=1 go test ./...` runs only the pure unit tests.
