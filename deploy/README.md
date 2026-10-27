# Deploying New Me

The server runs as one Docker Compose project on Nick's home server.

1. Copy this directory to `~/docker-server/npc_projects/new-me`.
2. Copy `.env.example` to `.env` and set `POSTGRES_PASSWORD` and `NEWME_APP_KEY`.
3. Run `docker compose up -d`.

Traefik routes `new-me.npc-server.top` to the server container and issues the certificate through Cloudflare.
Watchtower in label mode pulls a new `ghcr.io/nc1107/new-me:latest` after every release, so merging to `main` is a deploy.
Migrations run when the server starts.
Database dumps land in `./backups` daily and are kept for 7 days, 4 weeks and 6 months.
The image `ghcr.io/nc1107/new-me` is a public GHCR package, so watchtower pulls it without credentials.
Watchtower (`scw-watchtower`, label mode) polls every 300 seconds, so a release is live within about five minutes of the image push.

Rollback: watchtower never rolls back, so set `NEWME_TAG` in `.env` to the previous `X.Y.Z` and run `docker compose up -d`.

## Backups and the restore drill

Take a backup on demand with `docker exec new-me-db-backup /backup.sh`; it writes `backups/last/newme-latest.sql.gz` and rotates the daily, weekly and monthly copies.

Prove a backup restores with the drill script, run from this directory:

```
./restore-drill.sh
```

It loads the newest dump into a throwaway `postgres:16-alpine` container, prints live and restored row counts per table side by side, and exits 0 only when they match.
Rows written after the dump was taken make the counts differ, so take a fresh backup right before the drill.
The live database is only read, never written.

Record each drill here.

| Date | Dump | Result |
| --- | --- | --- |
| 2026-10-27 | local stack copy | identical row counts in all 12 tables |

## Letting CI read the health endpoint

The release workflow polls `https://new-me.npc-server.top/api/health` until the new version is live.
Cloudflare serves a managed challenge to GitHub's runner IPs, so without a rule the job cannot read the version and only prints a warning.
In the Cloudflare dashboard, open the `npc-server.top` zone, go to Security, WAF, Custom rules, and add a rule with action Skip (all remaining custom rules, rate limiting and Bot Fight Mode) for:

```
(http.host eq "new-me.npc-server.top" and http.request.uri.path eq "/api/health")
```

The endpoint returns only `{"status":"ok","version":"x.y.z"}`, so skipping the challenge there exposes nothing.
