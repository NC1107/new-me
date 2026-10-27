# Deploying New Me

The server runs as one Docker Compose project on Nick's home server.

1. Copy this directory to `~/docker-server/npc_projects/new-me`.
2. Copy `.env.example` to `.env` and set `POSTGRES_PASSWORD` and `NEWME_APP_KEY`.
3. Run `docker compose up -d`.

Traefik routes `new-me.npc-server.top` to the server container and issues the certificate through Cloudflare.
Watchtower in label mode pulls a new `ghcr.io/nc1107/new-me:latest` after every release, so merging to `main` is a deploy.
Migrations run when the server starts.
Database dumps land in `./backups` daily and are kept for 7 days, 4 weeks and 12 months.
