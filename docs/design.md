# New Me - design (v1, "Season 0")

Status: draft for review, 2026-10-26.
Owner: Nick. Users: Nick and Nadia only.

## 1. Goal

One private iPhone app that nudges two people toward better daily habits with a shared score.
Season 0 is the basic app: daily quests, a scoreboard, calorie and macro logging, reading logs, HealthKit steps, profiles.
Everything else from the research (workout generation, bloodwork, screen time, alarms) comes later and must not shape v1 beyond leaving room in the schema.

## 2. Decisions already made

- iPhone only, built with Flutter 3.47.0 (pinned) and Riverpod 3.
- Go 1.27 server with chi, pgx and embedded SQL migrations, Postgres 16, one Docker image on GHCR.
- Deployed at `https://new-me.npc-server.top` on Nick's server behind Traefik with the Cloudflare cert resolver, compose project at `~/docker-server/npc_projects/new-me`, auto-updated by the existing label-mode watchtower.
- GitHub repo `NC1107/new-me` (public, like check-in, so macOS CI minutes are free). Releases on every push to `main`: conventional-commit version bump, git tag, GitHub Release, Docker image push, TestFlight upload.
- Distribution via TestFlight internal testing only. The CI pipeline is copied from check-in's `release.yml`, reusing the same Apple team (76S78SUWVM), a new bundle id `top.npcserver.newme`, and the same six iOS secrets.
- Claude API allowed server-side later (`claude-sonnet-4-6`). Not used in Season 0.
- No web UI for users. Flutter web builds exist only for local visual review.
- Dark-only "Onyx" visual language from check-in: near-black canvas, grey hairline-bordered cards, one accent, system font, weights for hierarchy, radii 10/12/14, restrained 200ms motion, haptics on actions.

## 3. Season and scoring model

### Vocabulary

- **Season**: a scoring period. Season 0 runs from first deploy to 2026-12-31. Season 1 starts 2027-01-01. Season boundaries live in the `seasons` table, so the Jan 1 reset is a row, not a code change. Totals are per season; history is kept forever.
- **Quest**: a per-user, per-day target for one metric, with a point value. Generated from the user's quest templates when a day is first viewed.
- **Day**: a local calendar day in the user's timezone (stored per user, default `America/New_York`). The day ends at midnight. Logs carry the local date they belong to, so late entries for yesterday are allowed until 04:00 and land on yesterday.

### Metrics in v1

| metric | source | unit |
|---|---|---|
| steps | HealthKit (foreground sync on open and resume; background shim in M4) | count |
| pushups | manual log (sets of N) | reps |
| reading | manual log, minutes or pages | minutes, pages |
| meals_logged | derived from meal logs | count |
| protein | derived from meal logs | grams |
| yoga | manual log, minutes | minutes |

### Quest templates (defaults, editable per user in Me > Quests)

| key | default target | points |
|---|---|---|
| steps | 8000 | 100 |
| pushups | 30 | 100 |
| reading | 20 minutes or 15 pages | 100 |
| meals_logged | 2 meals logged | 50 |
| protein | profile protein target | 50 |

Yoga ships as a loggable activity with its own optional quest (off by default for Nick, on for Nadia). Horse and walking quests are deferred. "Walk" is covered by steps.

### Points

- Quest progress `p = min(1, actual / target)`. Quest points `= round(points * p)`, plus a completion bonus of 20% when `p = 1`. Partial credit keeps a hard day worth logging.
- Day points `= sum of quest points`. Day max is the sum of `points * 1.2` over active quests. Day percent `= day points / day max`.
- **Streak**: a day counts when day percent is at least 70%. The streak increments once per counted day. One free "rest day" per ISO week is applied automatically: the first missed day of a week does not break the streak. Streaks are per user and shown on Today and the Board.
- **Scoreboard**: per user, today's points, this week's points (ISO week, Monday start), season points, current streak. Everyone starts at zero on deploy and at each season start.
- **Fairness**: targets are per person. The Board compares points, never raw steps or reps. A "Numbers" section on the Board shows raw totals (steps, pushups, pages) for bragging only. Capacity scaling and automatic baselines from the research are deferred; in Season 0 each person edits their own targets.

### Recompute rule

Scoring is a pure function `scoreDay(user, date) -> DayScore` over logs and health_daily rows. The server stores the result in `day_scores` whenever an input for that day changes and in a nightly job for the previous day. Reads come from `day_scores` for past days and are recomputed on read for today. This keeps the board fast and history stable while targets can change going forward (a target change applies from today on, never retroactively; quests are snapshotted per day).

## 4. Server

### Layout

```
server/
  cmd/server/main.go
  internal/api        chi router, handlers, middleware, scoring glue
  internal/config     NEWME_* env config
  internal/db         pgx pool, migration runner, queries
  internal/score      pure scoring functions, unit-tested without a DB
  internal/auth       token generation and hashing
  migrations/NNNN_name.sql (embedded)
  Dockerfile, scripts/test.sh
```

### Access control

Two layers, both cheap and good enough for a private app on a public host:

1. **App key**: every request must carry `X-App-Key: <NEWME_APP_KEY>`. The key is baked into the iOS build with `--dart-define=NEWME_APP_KEY=...` from a GitHub secret and set as an env var on the server. Requests without it get 401 before any routing. This is the "only the iPhone app can talk to it" rule Nick asked for.
2. **Device token**: after joining, each install holds an opaque 32-byte token (SHA-256 hash stored server-side, same as check-in). `Authorization: Bearer <token>` identifies the user. No passwords.

### Pairing and admin

- `GET /api/server-info` returns `{name, initialized, users: [{id, name, color}]}`.
- First install: `initialized` is false. `POST /api/join {name, color, timezone}` creates the user as admin and returns `{user, token}`.
- Second install: picks "I'm new here" and joins as a member, or picks an existing user from the list to re-pair after a reinstall. Re-pairing issues a fresh token and revokes nothing (two devices for one user are allowed; the board is per user, not per device).
- Admin can rename or remove users, edit anyone's quest templates, and start a new season early. In Season 0 admin is a flag with little behind it; it exists so the first installer is "the owner" as Nick asked.

### Endpoints (all under `/api`, JSON, `{"error": msg}` envelope)

```
GET  /health                       db ping
GET  /server-info                  public except for the app key
POST /join                         create user or re-pair; returns token
GET  /me                           user, profile, quest templates, targets
PATCH /me                          name, color, timezone, targets (kcal, protein, carbs, fat), quest templates
GET  /today?date=YYYY-MM-DD        quests with progress, day points, streak, health freshness
GET  /board                        both users: today, week, season, streak, raw numbers
GET  /history?from=&to=            day_scores for charts (Me > Progress)
POST /logs                         {type: pushups|reading|yoga|meal, date, payload}  idempotent via client_op_id
GET  /logs?date=                   the day's logs for editing
DELETE /logs/{id}
PUT  /health/daily                 [{date, metric, value, source}] upsert from HealthKit, idempotent
GET  /users (admin)                PATCH /users/{id}, DELETE /users/{id}
POST /seasons (admin)              start a new season
```

### Schema (migration 0001)

```
server_config(id=1 CHECK, name, initialized, created_at)
seasons(id, name, starts_on DATE, ends_on DATE NULL)
users(id, name, color, timezone, is_admin, kcal_target, protein_target, carbs_target, fat_target, created_at, deleted_at)
devices(id, user_id, token_hash UNIQUE, name, created_at, last_seen_at)
quest_templates(id, user_id, key, target NUMERIC, unit, points INT, enabled, position)
day_quests(id, user_id, local_date, key, target, unit, points, UNIQUE(user_id, local_date, key))   snapshot per day
activity_logs(id, user_id, local_date, type, quantity NUMERIC, unit, note, client_op_id UNIQUE, logged_at, deleted_at)
meal_logs(id, user_id, local_date, name, kcal, protein_g, carbs_g, fat_g, fiber_g, client_op_id UNIQUE, logged_at, deleted_at)
health_daily(user_id, local_date, metric, value NUMERIC, source, updated_at, PK(user_id, local_date, metric))
day_scores(user_id, local_date, points INT, max_points INT, percent NUMERIC, counted BOOL, streak INT, detail JSONB, computed_at, PK(user_id, local_date))
```

Conventions from check-in: `BIGINT GENERATED ALWAYS AS IDENTITY`, `TIMESTAMPTZ NOT NULL DEFAULT now()`, soft deletes where a user can undo, hand-written SQL, one transaction per migration file under an advisory lock.

### Jobs

One scheduler goroutine (ticker, recover, context timeout) runs at 00:10 server time: finalize yesterday's `day_scores` for every user in their own timezone, and purge expired devices (none expire in v1; the hook exists).

### Tests

Same harness as check-in: real Postgres through `TESTDB_URL`, truncate-all reset per test, httptest server over the production router, fluent `expect(status).decode()`. `internal/score` is tested without a database. `scripts/test.sh` starts a throwaway Postgres in Docker.

## 5. App

### Structure

```
app/lib/
  main.dart                 runZonedGuarded, portrait lock, root gate (paired ? HomeShell : OnboardingScreen)
  api/                      ApiClient (dio, X-App-Key, Bearer, X-Client-Version, 401 handling), models
  state/                    session (server url + token + user), today, board, me, health sync controllers (Riverpod Notifiers with seeded test seams)
  health/                   HealthSource interface; HealthKitSource (package:health, iOS) and FakeHealthSource (web, tests)
  features/onboarding/      server address, probe, join or re-pair, name and color
  features/today/           score ring, quest cards, health freshness, log shortcuts
  features/board/           both users side by side: today, week, season, streak, numbers
  features/log/             bottom sheet: pushups, reading, yoga, meal with macros
  features/me/              profile, targets, quest templates, Health connection, progress chart, about, admin
  theme/                    tokens.dart (Onyx), accent per user
  widgets/                  AppTextField, PrimaryButton, PillBadge, ScoreRing, QuestCard, Skeletons, EmptyState
```

### Navigation

Custom bottom bar as in check-in: Today, Board, (center accent FAB: Log), Me. Plain `Navigator` for pushes, no router package.

### Screens

- **Onboarding**: one screen, three steps in an `AnimatedSwitcher`. 1) server address with probe (prefilled `new-me.npc-server.top`), 2) "Who are you?" with existing users as avatar chips plus "I'm new", 3) name and accent swatch. Nothing persisted until join succeeds.
- **Today**: large score ring (animated sweep, number count-up) with day percent and points, streak pill, then quest cards: title, progress bar, actual/target, a "+" for manual metrics that opens the log sheet prefilled. Completing a quest plays a 220ms check animation and `mediumImpact`. A footer line says when Health last synced; pull to refresh triggers a sync.
- **Board**: two columns (one per user, accent-colored), rows for today, week, season, streak. Below, a 7-day bar strip per user and the raw "Numbers" list. Empty state on day one: both at zero with copy like "Nobody has moved yet."
- **Log** (sheet): segmented control pushups, reading, yoga, meal. Pushups: big number pad with quick chips 10, 15, 20, 25. Reading: minutes or pages toggle. Meal: name, kcal, protein, carbs, fat, fiber; recent meals as tappable chips (last 20) for repeat logging. Each entry has a date defaulting to today with a "yesterday" toggle.
- **Me**: avatar and name, accent swatch, timezone, targets (kcal and macros), quest templates with enable toggles and targets, Health connection card (connect, last sync, what is read), progress chart (day percent over the season), admin section for the first user, About with version and server address, and "Leave this server".

### HealthKit in v1

`package:health` 13.3.2 reads `STEPS` via `getTotalStepsInInterval` (Apple's deduplicated total) on app start, on resume, and on pull to refresh, then `PUT /health/daily`. Permission is requested from the Me > Health card and again from the Today empty state. Milestone M4 adds a Swift observer shim with background delivery for hourly updates while the app is closed; the API and schema already accept it (`source` column).

### Platform files

- iOS deployment target 15.0 (health needs iOS 14 minimum, Flutter template is 13). `NSHealthShareUsageDescription`, HealthKit capability and entitlement, portrait only, `ITSAppUsesNonExemptEncryption` false.
- Manual signing in Release with Apple Distribution for team 76S78SUWVM, profile name "New Me App Store Distribution", `ExportOptions.plist` copied from check-in with the new bundle id.
- App icon: generated once from an SVG with ImageMagick into `AppIcon.appiconset`. Dark canvas, accent glyph: two overlapping rounded rings, one for each person, forming a rising arc. Also used as the in-app logo.

### Tests

flutter_test only, hand-rolled fakes through provider overrides, `clientFactory` injection, secure storage channel mock. Widget tests for onboarding, Today scoring display, log sheet validation, and a version drift guard.

## 6. CI and release

- `ci.yml` on pull requests and non-main pushes: `server` job (gofmt, vet, build, test with Postgres service) and `app` job (format, analyze, test).
- `release.yml` on push to `main`, concurrency group `release`: tests -> version (conventional commits, tag, build number `run_number*100+run_attempt`) -> docker (ghcr.io/nc1107/new-me:latest and :X.Y.Z) and app-store (macos-15, Flutter 3.47.0, CocoaPods, manual signing, `flutter build ipa --dart-define=NEWME_APP_KEY`, altool upload) -> GitHub Release. Android and Play jobs removed. The release-notes gate is dropped.
- A scheduled monthly workflow re-runs the iOS build so the newest TestFlight build is never older than about 60 days (hard expiry 90). It fails loudly if secrets or Xcode drift.
- Watchtower on the server pulls `:latest` within its poll interval, so a merge to `main` is a deploy.

### Secrets

`IOS_CERTIFICATE_BASE64`, `IOS_CERTIFICATE_PASSWORD`, `IOS_PROVISIONING_PROFILE_BASE64`, `ASC_API_KEY_BASE64`, `ASC_KEY_ID`, `ASC_ISSUER_ID`, `NEWME_APP_KEY`.
The App Store Connect key, certificate and the new profile are created in a browser session where Nick logs in once; everything that the App Store Connect API can do afterwards (bundle id, capabilities, profile) is scripted.

## 7. Milestones

- **M0 skeleton**: repo, monorepo layout, CLAUDE.md, CI, lint, empty Flutter app that builds for iOS and web, Go server with health endpoint, compose, deployed to the server behind Traefik.
- **M1 server**: schema, pairing, logs, health upsert, quests, scoring, board, history, admin, tests.
- **M2 app**: theme, onboarding, Today, Board, Log, Me, HealthKit foreground sync, tests, visual review on web at phone width.
- **M3 release**: release workflow, Apple setup session, first TestFlight build on Nick's phone, Nadia added as internal tester.
- **M4 background steps**: Swift observer shim with background delivery.
- **Later**: Audiobookshelf listening sync, workouts, meals from Mealie, notifications, bloodwork, screen time.

## 8. Open items Nick left to me

- Day boundary midnight with a 04:00 grace for backdating. Timezone per user, default America/New_York.
- Public repo. Switch to private costs macOS minutes.
- Version bumps from conventional commits on main, as in check-in. If "release please" meant the release-please tool, swap the version job for it later.
- Quest defaults above. All editable in the app.
