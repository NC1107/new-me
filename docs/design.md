# New Me - design (v2, "Season 0", post-review)

Status: single source of truth after the design review of 2026-10-26.
Owner: Nick.
Users: Nick and Nadia only.
This document replaces v1 and `design-review-accepted.md` for every behaviour it describes.

## 1.
Goal

One private iPhone app that nudges two people toward better daily habits with a shared score.
Season 0 is the basic app: daily quests, a scoreboard, calorie and macro logging, reading logs, HealthKit steps and active energy, profiles.
Everything else from the research (workout generation, bloodwork, screen time, alarms) comes later and must not shape v1 beyond leaving room in the schema.

Cut from v1 and not to be rebuilt without a new decision:

- `GET /history` and the Me progress chart.
- Admin user management (list, rename, remove users) and `POST /seasons`.
- The Board "Numbers" list of raw totals.
- The bootstrap code for the first join.
- Editable quest points, cross-user meal logging, a local write queue, a target calculator.

## 2.
Decisions

- iPhone only, built with Flutter 3.47.0 (pinned) and Riverpod 3.
- Go 1.26 server with chi, pgx and embedded SQL migrations, Postgres 16, one Docker image on GHCR.
- Deployed at `https://new-me.npc-server.top` on Nick's server behind Traefik with the Cloudflare cert resolver, compose project at `~/docker-server/npc_projects/new-me`, auto-updated by the existing label-mode watchtower.
- GitHub repo `NC1107/new-me`, public like check-in so macOS CI minutes are free.
- Releases on every push to `main`: conventional-commit version bump, git tag, GitHub Release, Docker image push, TestFlight upload.
- Distribution via TestFlight internal testing only.
- The CI pipeline is adapted from check-in's `release.yml`, reusing the same Apple team (76S78SUWVM) and a new bundle id `top.npcserver.newme`.
- Five of the iOS secrets are shared with check-in, two are new per app (section 6).
- Claude API allowed server-side later (`claude-sonnet-4-6`).
  Not used in Season 0.
- No web UI for users.
  Flutter web builds exist only for local visual review.
- Dark-only "Onyx" visual language from check-in: near-black canvas, grey hairline-bordered cards, one accent per person, system font, weights for hierarchy, radii 10/12/14, restrained 200ms motion, haptics on actions.
- JSON is camelCase everywhere.
  Dates are `YYYY-MM-DD` strings, instants are RFC 3339 UTC.
- No local write queue.
  The server is the only source of truth for scores; the app never recomputes points or percent.
- `docs/research` is not part of the repository (it is git-ignored).

## 3.
Season and scoring model

### Vocabulary

- **Season**: a scoring period.
  Migration 0001 seeds two rows: Season 0 (`starts_on = current_date` of the migration run, `ends_on = 2026-12-31`) and Season 1 (`starts_on = 2027-01-01`, `ends_on = NULL`).
  Season lookup is by `local_date`.
  Season rows never overlap (exclusion constraint, migration 0002).
  Points reset by season, history is kept forever, streaks are continuous across seasons.
- **Week**: Monday-start week clipped to the current season.
  The week containing 2027-01-01 therefore shows only 2027 days.
- **Quest**: a per-user, per-day target for one metric with a fixed point value.
  The day's quests are a snapshot of the user's enabled templates, taken by `ensureSnapshot`.
- **Day**: a local calendar day in the user's timezone.
  The server decides the date, never the client.

### Day window (10:00 grace)

- `GRACE_HOURS = 10`, a constant in `internal/score`.
- With `localToday` and `localNow` computed in the user's timezone, a date `d` is writable when `d == localToday`, or when `d == localToday - 1` and `localNow < 10:00`.
- Dates before the user's `first_local_date` and future dates are never writable.
- Anything else returns 422 `{"error": "...", "code": "date_closed"}`.
- The rule applies to log creation, log deletion (by the log's `local_date`) and health upserts.
- The app defaults every entry to today.
  It shows an "Add to yesterday" toggle only when `backdateUntil` from `/me` or `/today` is non-null and the app clock is before it.
- A day is finalized once `now in tz >= date + 1 day + 10:00`.
- A timezone change never rewrites existing `local_date` values.
  `PATCH /me` stores it as `pending_timezone` with `pending_from = localToday + 1`.
  The switch is applied inside the next transaction that resolves the user's day once the old zone's date is at least `pending_from` and the new zone's date is at least the old zone's date, so a date is never repeated or skipped.
  `GET /me` and `PATCH /me` report the chosen zone as `user.timezone` while the old one stays in force for date arithmetic.
- `time.LoadLocation` validates timezone names (`PATCH /me` and join return 422 `invalid_timezone` otherwise).
  The server imports `_ "time/tzdata"` so zones resolve in the distroless image.
  All day arithmetic uses `time.Date(y, m, d+n, h, 0, 0, 0, loc)` so DST days are 23 or 25 hours without special cases.

### Metrics in v1

| metric | source | actual used by scoring |
|---|---|---|
| steps | HealthKit, `health_daily` metric `steps` | `floor(value)` |
| pushups | manual log, sets of reps | sum of `quantity` of `pushups` logs |
| reading | manual log, minutes or pages, plus Audiobookshelf listening | minutes `m` (manual minutes plus that day's `listening_daily` minutes) and pages `g`, summed separately |
| meals_logged | derived from meal logs | count of meals with `kcal > 0` |
| protein | derived from meal logs | sum of `protein_g` in tenths of a gram |
| yoga | manual log, minutes | sum of `quantity` of `yoga` logs |
| exercise | HealthKit, `health_daily` metric `exercise_minutes` | `floor(value)` |
| sleep | HealthKit, `health_daily` metric `sleep_minutes` | `floor(value)` |
| active_energy | HealthKit, `health_daily` metric `active_energy` | not scored; shown on Today as "burned N" |

`health_daily` holds 17 metrics, each with a per-day bound enforced by a CHECK and by `PUT /health/daily`.
Steps, active_energy, basal_energy, distance_m and water_ml are 0 to 200000, 20000, 20000, 200000 and 20000.
exercise_minutes, workout_minutes, sleep_minutes and mindful_minutes are 0 to 1440.
flights is 0 to 1000, workouts 0 to 50, hrv_ms 0 to 500 and vo2max 0 to 100.
resting_hr is 20 to 250, weight_kg 20 to 400, body_fat_pct 1 to 80 and lean_mass_kg 10 to 300.
Only steps, exercise_minutes, sleep_minutes and active_energy feed scoring or the Today screen; the rest are served through `GET /today` `health` and `GET /health/trends`.

### Quest templates

Points are fixed and not editable.
Every `points` value is a multiple of 5 (CHECK), because the bonus is `points / 5`.
Users edit only `enabled` and `target`, and edits take effect from the next local day.

| key | default target | points | default |
|---|---|---|---|
| steps | 8000 steps | 100 | enabled |
| pushups | 30 reps | 100 | enabled |
| reading | 20 minutes plus 15 pages | 100 | enabled |
| meals_logged | 2 meals | 50 | enabled |
| protein | profile protein target, 100 g when unset | 50 | enabled |
| yoga | 20 minutes | 50 | disabled |
| exercise | 30 min | 100 | disabled |
| sleep | 420 min | 50 | disabled |

Yoga is a template and an activity log type that ship disabled.
Exercise and sleep are automatic like steps, take no manual logs, and ship disabled with positions 6 and 7.
Their target bounds are exercise 5 to 300 minutes and sleep 240 to 720 minutes.
The Log sheet shows the yoga segment only while the template is enabled.
Horse and walking quests are deferred; walking is covered by steps.
Targets are per person.
The Board compares points and percent, never raw steps or reps.

### Points (integer math only)

For each quest in the day snapshot, define a numerator `num` and a denominator `den`:

| quest | num | den |
|---|---|---|
| steps, pushups, meals_logged, yoga | `min(actual, target)` | `target` |
| protein | `min(actualTenths, target * 10)` | `target * 10` |
| reading | `min(m * targetAlt + g * target, target * targetAlt)` | `target * targetAlt` |

For reading, `target` is the minutes target (20) and `targetAlt` the pages target (15), so progress is `min(1, minutes/20 + pages/15)`.

Then, with integer division throughout:

- Base points: `base = (points * num + den / 2) / den`.
- Done: `num == den`.
- Bonus: `bonus = points / 5` when done, otherwise 0.
- Day base: `dayBase = sum(base)` over included quests.
- Day max: `dayMax = sum(points)` over included quests.
- Day bonus: `dayBonus = sum(bonus)`.
- Day points: `dayPoints = dayBase + dayBonus`.
- Day percent: `percent = min(100, dayBase * 100 / dayMax)`, floor division, and 0 when `dayMax == 0`.
- Counted day: `dayBase * 100 >= 70 * dayMax` and `dayMax > 0`.
  This is exactly `percent >= 70`.

Bonus points count toward displayed day, week and season points on the Board, but not toward percent or the streak.
The server sends points and percent; the app never recomputes them.

A Health-fed quest (steps, exercise, sleep) is excluded from `dayMax` and `dayBase` (state `needs_health`) while the user has never had a row for its own metric (`steps`, `exercise_minutes`, `sleep_minutes`) on or before that day.
The first sync of that metric includes the quest from that moment, for the current and open days only.
Finalized days are never rewritten.

Worked example: steps 5000 of 8000 gives `(100*5000 + 4000) / 8000 = 63`.
Pushups 30 of 30 gives 100 plus bonus 20.
Reading 12 minutes and 5 pages gives `num = 12*15 + 5*20 = 280`, `den = 300`, base `(28000 + 150) / 300 = 93`.
Two meals give 50 plus bonus 10, and protein 0.
`dayMax = 400`, `dayBase = 306`, `percent = 76`, counted, `dayPoints = 336`.

### Streak

`internal/score.Streak(days, today, todayCounted)` is a pure function.
The streak is never stored; it is derived at read time from `day_scores.counted`.

Input: the user's `first_local_date`, a map of `local_date -> counted` from `day_scores`, `today`, and whether today is already counted.

Steps:

1.
   Let `n = 0`, `prevBreak = false`, and an empty set `restUsed` keyed by the Monday date of an ISO week.
2.
   Iterate every date `d` from `first_local_date` through `today - 1` ascending.
   Dates before join are never visited.
   A date with no `day_scores` row is a miss.
3.
   If `d` is counted: `n = n + 1`, `prevBreak = false`.
4.
   If `d` is a miss, let `wk` be the Monday of `d`'s ISO week.
   - If `n > 0` and `wk` is not in `restUsed` and `prevBreak` is false: add `wk` to `restUsed`, flag `d` as a rest day, keep `n` unchanged, set `prevBreak = true`.
   - Otherwise: set `n = 0` and `prevBreak = true`.
     A miss when `n == 0` consumes nothing.
5.
   Displayed streak is `n`, plus 1 if today is already counted.
   Today is never treated as a miss.

Consequences:

- Two consecutive misses always break the streak, including across the Sunday/Monday boundary.
- The allowance is one rest day per ISO week and unused rest does not carry over.
- Backdating a counted day into an open window changes the derived result immediately, since nothing is cached.

Table tests cover: first week, a three-day gap, Sunday plus Monday misses, a backdated fill rescuing a gap, and a DST day.

Presentation: the streak pill reads "Day 1" when the streak is 0.
Today shows a rest chip, "Rest day ready" or "Rest day used Tue".
The 7-day strip shows a hollow dot on a rest day.

### Scoreboard

Per user: today's points, percent and counted flag, week points, season points, streak, a 7-day strip, and the last Health sync time.
Week points sum `day_scores.points` from `max(Monday of localToday, season.starts_on)` through today.
Season points sum from `season.starts_on` through today.
Everyone starts at zero at deploy and at each season start.

### Recompute rule

Scoring is a pure function `scoreDay(snapshot, inputs) -> DayScore` in `internal/score`, tested without a database.

Every write path runs in one transaction:

1. `pg_advisory_xact_lock(user_id, dateInt)` where `dateInt` is the number of days since 1970-01-01 as int4.
   Multi-date writes lock dates ascending.
2. `ensureSnapshot(tx, user, date)`.
3.
   The write itself.
4. `scoreDay(user, date)`.
5.
   Upsert the result into `day_scores`.

Write paths: `POST /logs`, `DELETE /logs/{id}`, `PUT /health/daily`, and the quest edits in `PATCH /me` (which snapshot today before applying the edit, so edits only affect the next day).
`GET /today` and `GET /board` run the same lock, snapshot and score steps for today so reads are always fresh.

`ensureSnapshot(tx, user, date)` is `INSERT INTO day_quests ... SELECT FROM quest_templates WHERE user_id = $1 AND enabled ON CONFLICT (user_id, local_date, key) DO NOTHING`.
The protein row snapshots `COALESCE(users.protein_target, 100)`.
It is called by every path that reads or writes a day and by the scheduler.
At join, the snapshot is taken for every writable date.
Every log read filters `deleted_at IS NULL` through shared query helpers backed by partial indexes.

## 4.
Server

### Layout

```
server/
  cmd/server/main.go          flags: -healthcheck; subcommand: invite
  internal/api                chi router, handlers, middleware
  internal/config             NEWME_* env config
  internal/db                 pgx pool, migration runner, queries (shared helpers filter deleted rows)
  internal/score              pure scoring and streak functions
  internal/auth               token and invite code generation and hashing
  internal/ratelimit          limiter and trusted-proxy client IP, from check-in
  internal/sched              scheduler goroutine
  migrations/NNNN_name.sql    embedded
  Dockerfile, scripts/test.sh
```

### Configuration

| variable | default | meaning |
|---|---|---|
| `NEWME_DATABASE_URL` | required | pgx connection string |
| `NEWME_APP_KEY` | required, at least 16 chars | single shared value |
| `NEWME_HTTP_ADDR` | `:8080` | listen address |
| `NEWME_SERVER_NAME` | `New Me` | name returned by `/server-info` |
| `NEWME_TRUSTED_PROXY_HOPS` | `1` | proxies in front of the server |
| `NEWME_MAX_USERS` | `2` | live user cap |
| `NEWME_MIN_CLIENT_VERSION` | `0.0.0` | lowest accepted app version |
| `NEWME_ABS_URL` | empty | Audiobookshelf base URL; empty turns listening sync off |
| `NEWME_DEV_CORS` | `false` | local web review only, never set in production |

There is no bootstrap code and no season-start variable; the Season 0 start is the migration date.

### Access model

The app key is an abuse filter, not authentication.
The device token is the real authentication.

Middleware order: recoverer, request id, `Timeout(30s)`, 1 MB `MaxBytesReader`, app key, client version, rate limit, token auth.

- **App key**: every request except `GET /api/health` must carry `X-App-Key`, compared with `subtle.ConstantTimeCompare` against the single `NEWME_APP_KEY`.
  A missing or wrong key returns **403** `{"error": "...", "code": "bad_app_key"}`, never 401, so the app does not sign the user out.
  The key is baked into the iOS build with `--dart-define=NEWME_APP_KEY=...` from a GitHub secret.
  Rotation is an `.env` change plus a rebuild; both users reinstall.
- **Device token**: an opaque 32-byte random token, SHA-256 hash stored in `devices`.
  `Authorization: Bearer <token>` identifies the user.
  401 `{"code": "unauthorized"}` is reserved for a bad or revoked token and is the only status that signs the app out.
  `devices.last_seen_at` is written at most once per 5 minutes per device.
- **Client version**: `X-Client-Version` below `minClientVersion` returns **426** `{"error": "...", "code": "update_required", "minClientVersion": "x.y.z"}`.
  `/api/health` and `/api/server-info` are exempt so the app can read the minimum and show its blocking screen.
- **Invite codes**: every join after the first, and every re-pair, needs a single-use code.
  - 16 characters of Crockford base32 (80 bits), shown as `XXXX-XXXX-XXXX-XXXX`, input normalised to upper case without separators.
  - Only the SHA-256 hash is stored.
    TTL 15 minutes.
    Single use.
  - A wrong code increments `attempts` on every live invite.
    An invite with 5 attempts is dead.
  - Codes are created by the admin in Me (`POST /invites`) or by the CLI: `docker exec new-me-server /app/server invite` prints a fresh code and exits.
    The CLI is the recovery path if Nick reinstalls.
- **First join**: while `server_config.initialized` is false, `POST /join` needs no code and creates the admin.
  Operational rule: Nick joins before the TestFlight link is shared.
- **Max users**: `NEWME_MAX_USERS` (2) is enforced inside the join transaction under a global advisory lock.
  A single live admin is enforced in the same transaction and by a partial unique index.
- **Names and colors**: unique case-insensitive name among live users, distinct colors, otherwise 409 (`name_taken`, `color_taken`).
- **Re-pair**: `{code, userId}` issues a fresh device token and revokes that user's other devices, since the code proves control of the account.
- **Rate limits**, using check-in's `ratelimit.go` with trusted-proxy client IP (not RealIP):
  - `POST /join` and `POST /invites/check`: 5 per minute per IP, one shared bucket.
  - Authenticated routes: 120 per minute per device, applied immediately after token auth resolves the device.
  - `PUT /health/daily`: an additional 30 per minute per device.
  - Exceeded limits return 429 with `Retry-After` and `{"code": "rate_limited"}`.
- Other headers: nosniff, frame deny, no referrer, `default-src 'none'`.
- Dev CORS: with `NEWME_DEV_CORS=true`, localhost origins are allowed with the headers `X-App-Key`, `Authorization`, `X-Client-Version` and `Content-Type`.

### Error envelope

`{"error": "message", "code": "machine_code"}`; `code` is present for the cases below.

| status | code | when |
|---|---|---|
| 401 | `unauthorized` | bad or revoked device token |
| 403 | `bad_app_key` | missing or wrong app key |
| 403 | `invalid_code` | unknown, used, expired or locked invite code |
| 403 | `forbidden` | admin-only route |
| 400 | `invalid_json` | malformed body or a field the endpoint does not know |
| 404 | `not_found` | unknown route or resource |
| 405 | `method_not_allowed` | wrong method on a known route |
| 409 | `name_taken`, `color_taken`, `server_full`, `server_initialized` | join conflicts |
| 413 | `payload_too_large` | body over 1 MB |
| 422 | `date_closed` | date outside the day window |
| 422 | `invalid_timezone`, `invalid_request` | validation, with per-item errors where relevant |
| 422 | `abs_login_failed` | Audiobookshelf rejected the username or password |
| 404 | `abs_disabled` | `NEWME_ABS_URL` is not set |
| 502 | `abs_unavailable` | Audiobookshelf could not be reached while linking |
| 426 | `update_required` | client older than `minClientVersion`, which the body repeats |
| 429 | `rate_limited` | limiter, with `Retry-After` |
| 500 | `internal` | anything unexpected |

### Endpoints

All routes are under `/api`.
Groups: public (`health`, `server-info`), authLimited (`join`, `invites/check`), requireAuth, requireAdmin.
Caps enforced with 422: reps at most 500 per set, pages at most 2000, minutes at most 1440, kcal at most 10000.

```
GET    /health
  200 {status: "ok", version}                        cached DB ping, exempt from the app key
  503 {status: "unavailable", version}

GET    /server-info
  200 {name, initialized, joinOpen, minClientVersion}
  joinOpen = !initialized || liveUsers < maxUsers; no user list is ever returned here

POST   /invites/check
  req {code}
  200 {valid, users: [{id, name, color}], canJoinNew}   never spends the code
  an unusable code is 200 with valid false, no users and canJoinNew false, and counts as a wrong attempt

POST   /join
  first install (initialized = false), no code:   {name, color, timezone}
  new member:                                     {code, name, color, timezone}
  re-pair:                                        {code, userId}, no other field
  201 {user: {id, name, color, timezone, isAdmin}, token}

DELETE /devices/me                                  204, revokes the calling device

POST   /invites                                     admin
  201 {code, expiresAt}

GET    /me
  200 {user: {id, name, color, timezone, isAdmin},
       targets: {kcal, protein, carbs, fat},          integers or null
       questTemplates: [{key, title, enabled, target, unit, targetAlt, unitAlt, points, position}],
       localToday, backdateUntil, serverNow,
       audiobookshelf: {linked, username, syncedAt, lastError} | null}
                                                         null when NEWME_ABS_URL is unset; linked false with null fields until the person links
                                                         lastError is "auth_failed" (sign in again), "unreachable" or null

PUT    /me/audiobookshelf
  req {username, password}                               the password is used once to sign in to Audiobookshelf and never stored
  200 {linked: true, username, syncedAt, lastError}      links, then syncs once before answering, so syncedAt is normally set; linking again replaces the account
  404 abs_disabled, 422 abs_login_failed, 502 abs_unavailable, 429 after 5 attempts a minute per device

DELETE /me/audiobookshelf
  204 deletes the stored tokens and the listening minutes of still-open days, then rescores them; idempotent

PATCH  /me
  req any of {name, color, timezone,
              targets: {kcal, protein, carbs, fat},      null clears a target
              questTemplates: [{key, enabled, target, targetAlt}]}
  200 same body as GET /me
  template edits are snapshot-first and apply from the next local day
  on the person's join day (local today equals the join date) template and target edits instead re-snapshot today and rescore it, so onboarding choices count from Day 1; logs and Health readings already made stay

GET    /today?date=YYYY-MM-DD
  200 {date, localToday, backdateUntil, serverNow,
       quests: [QuestScore],
       day: {basePoints, bonusPoints, points, maxBase, percent, counted, streakLine},
       streak: {current, restAvailable, restUsedOn},
       food: {kcal, protein, carbs, fat, fiber, burned,
              targets: {kcal, protein, carbs, fat}},
       health: {stepsEverSynced, syncedAt,
                metrics: {<metric key>: number},         the day's readings, only keys that have one
                latest: {<key>: {value, date}}},
       listening: {minutes}}                             Audiobookshelf minutes already counted in the reading quest, 0 when none
                                                         latest: weight_kg, body_fat_pct, lean_mass_kg, vo2max: newest on or before the day, omitted when none
  date defaults to localToday and must fall between the join date and today
  backdateUntil is the instant yesterday closes while it is open, otherwise null
  burned is the day's active energy; reads rescore, so they are never stale

GET    /board
  200 {season: {name, startsOn, endsOn}, serverNow,
       users: [{id, name, color,
                today: {points, percent, counted},
                week: {points}, season: {points}, streak: {current},
                last7: [{date, percent, counted, rest}],
                syncedAt,
                highlights: {steps, exercise_minutes, sleep_minutes}}]}
                                                         the caller first, each person on their own local today
                                                         highlights are that person's local-today readings, each key omitted when there is no row

POST   /logs                                            201 first time, 200 with the same body on replay
  req {clientOpId, kind: "activity", type: "pushups"|"reading"|"yoga",
       quantity, unit: "reps"|"minutes"|"pages", date}
   or {clientOpId, kind: "meal", name, kcal, protein, carbs, fat, fiber, date}
  date is optional and defaults to localToday
  200/201 {log: Log, day: DayDetail}

GET    /logs?date=YYYY-MM-DD
  200 {date, logs: [Log]}                                the caller's logs, oldest first

DELETE /logs/{id}
  200 {day: DayDetail}                                   obeys the day window; takes no other parameter

GET    /meals/recent?limit=20
  200 {meals: [{name, kcal, protein, carbs, fat, fiber}]}
  distinct across both users, newest first

PUT    /health/daily
  req {items: [{date, metric: one of the 17 keys, value, source, measuredAt}]}
  200 {days: [DayDetail]}                                every affected date, oldest first, so the app skips GET /today
  422 {code, error, items: [{index, code, error}]}       code is date_closed when every bad item is, else invalid_request

GET    /health/trends?metric=<key>&days=<1..365>
  200 {metric, points: [{date, value}]}                  the caller's own readings, ascending, the last N local days ending today; days with no reading are absent
  422 invalid_request                                    unknown metric, or days missing, not an integer or outside 1 to 365
```

Wire types:

- `Log` is a tagged union.
  Activity: `{id, kind: "activity", type, quantity, unit, localDate, loggedAt}`.
  Meal: `{id, kind: "meal", name, kcal, protein, carbs, fat, fiber, localDate, loggedAt}`.
- `DayDetail`: `{date, basePoints, bonusPoints, points, maxBase, percent, counted, streakLine, quests: [QuestScore]}`.
  `points` is base plus bonus, `percent` is on base points, and `streakLine` is the percent a day needs to count.
- `QuestScore`: `{key, title, target, unit, targetAlt, unitAlt, actual, actualAlt, points, basePoints, bonusPoints, done}`.
  `points` is the quest's full base value; `basePoints` and `bonusPoints` are what has been earned.
  Health-fed quests (steps, exercise, sleep) are listed before their metric has synced, with nothing earned and outside `maxBase`.
- Log ids come from one shared sequence across both log tables, so `DELETE /logs/{id}` is unambiguous.
- The app's contract tests replay recordings of these bodies, captured by `app/tool/capture_contract.mjs` into `app/test/contract`.

Behaviour rules:

- `POST /logs` idempotency is `UNIQUE(user_id, client_op_id)`.
  A replay returns the stored row with 200.
  A replay of a deleted row does not undelete it.
  Undo of a delete is a new `POST` with a fresh `clientOpId`.
- `PUT /health/daily` accepts at most 50 items in one transaction.
  Each item is validated for window, whitelist, finiteness and range (each metric against its own bounds, listed under Metrics in v1).
  Any invalid item fails the whole request with per-item errors.
- The upsert is `ON CONFLICT (user_id, local_date, metric) DO UPDATE SET value = EXCLUDED.value, measured_at = EXCLUDED.measured_at, ... WHERE health_daily.measured_at <= EXCLUDED.measured_at`, so a stale retry or a second device cannot lower a count.
- API changes inside a release are additive.
  Removals wait one release.
- `/api/health` returns `{status, version}`.
  The binary supports `-healthcheck`, which calls `127.0.0.1:8080/api/health` and exits 0 or 1; the compose healthcheck uses it.
- Version is built in with `-ldflags -X main.version=$VERSION`.

### Schema

Migration 0001 already exists and is never edited.
It creates `server_config` (singleton row, `initialized`) and `seasons`, and seeds Season 0 and Season 1.

Migration 0002 `core.sql` creates everything else.
Conventions: `BIGINT GENERATED ALWAYS AS IDENTITY`, `TIMESTAMPTZ NOT NULL DEFAULT now()`, soft deletes where a user can undo, hand-written SQL, one transaction per migration file under an advisory lock.
Quantities are `INTEGER` with CHECKs, macros are `NUMERIC(6,1)` (queries select `::float8`), `health_daily.value` is `DOUBLE PRECISION`.

```sql
CREATE EXTENSION IF NOT EXISTS btree_gist;

ALTER TABLE seasons
    ADD CONSTRAINT seasons_range_ok CHECK (ends_on IS NULL OR ends_on >= starts_on),
    ADD CONSTRAINT seasons_no_overlap EXCLUDE USING gist (
        daterange(starts_on, COALESCE(ends_on, 'infinity'::date), '[]') WITH &&);

CREATE SEQUENCE log_ids;

CREATE TABLE users (
    id               BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    name             TEXT NOT NULL CHECK (char_length(name) BETWEEN 1 AND 40),
    color            TEXT NOT NULL CHECK (color IN ('green','sky','violet','amber','rose','teal')),
    timezone         TEXT NOT NULL,
    pending_timezone TEXT,
    pending_from     DATE,
    is_admin         BOOLEAN NOT NULL DEFAULT false,
    first_local_date DATE NOT NULL,
    kcal_target      INTEGER CHECK (kcal_target BETWEEN 1 AND 10000),
    protein_target   INTEGER CHECK (protein_target BETWEEN 1 AND 1000),
    carbs_target     INTEGER CHECK (carbs_target BETWEEN 1 AND 1000),
    fat_target       INTEGER CHECK (fat_target BETWEEN 1 AND 1000),
    created_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
    deleted_at       TIMESTAMPTZ
);
CREATE UNIQUE INDEX users_name_live ON users (lower(name)) WHERE deleted_at IS NULL;
CREATE UNIQUE INDEX users_color_live ON users (color) WHERE deleted_at IS NULL;
CREATE UNIQUE INDEX users_one_admin ON users (is_admin) WHERE is_admin AND deleted_at IS NULL;

CREATE TABLE devices (
    id           BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    user_id      BIGINT NOT NULL REFERENCES users (id),
    token_hash   TEXT NOT NULL UNIQUE,
    name         TEXT NOT NULL DEFAULT '',
    created_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
    last_seen_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX devices_user ON devices (user_id);

CREATE TABLE invites (
    id         BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    code_hash  TEXT NOT NULL UNIQUE,
    created_by BIGINT REFERENCES users (id),
    expires_at TIMESTAMPTZ NOT NULL,
    used_at    TIMESTAMPTZ,
    used_by    BIGINT REFERENCES users (id),
    attempts   INTEGER NOT NULL DEFAULT 0,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE quest_templates (
    id         BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    user_id    BIGINT NOT NULL REFERENCES users (id),
    key        TEXT NOT NULL CHECK (key IN ('steps','pushups','reading','meals_logged','protein','yoga','exercise','sleep')),
    target     INTEGER NOT NULL CHECK (target > 0 AND target <= 200000),
    unit       TEXT NOT NULL CHECK (unit IN ('steps','reps','minutes','meals','g')),
    target_alt INTEGER CHECK (target_alt > 0 AND target_alt <= 2000),
    unit_alt   TEXT CHECK (unit_alt = 'pages'),
    points     INTEGER NOT NULL CHECK (points > 0 AND points % 5 = 0),
    enabled    BOOLEAN NOT NULL,
    position   INTEGER NOT NULL,
    UNIQUE (user_id, key),
    CHECK ((target_alt IS NULL) = (unit_alt IS NULL))
);

CREATE TABLE day_quests (
    id         BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    user_id    BIGINT NOT NULL REFERENCES users (id),
    local_date DATE NOT NULL,
    key        TEXT NOT NULL CHECK (key IN ('steps','pushups','reading','meals_logged','protein','yoga','exercise','sleep')),
    target     INTEGER NOT NULL CHECK (target > 0),
    unit       TEXT NOT NULL,
    target_alt INTEGER CHECK (target_alt > 0),
    unit_alt   TEXT,
    points     INTEGER NOT NULL CHECK (points > 0 AND points % 5 = 0),
    position   INTEGER NOT NULL,
    UNIQUE (user_id, local_date, key)
);

CREATE TABLE activity_logs (
    id           BIGINT PRIMARY KEY DEFAULT nextval('log_ids'),
    user_id      BIGINT NOT NULL REFERENCES users (id),
    local_date   DATE NOT NULL,
    type         TEXT NOT NULL CHECK (type IN ('pushups','reading','yoga')),
    quantity     INTEGER NOT NULL CHECK (quantity > 0),
    unit         TEXT NOT NULL CHECK (unit IN ('reps','minutes','pages')),
    client_op_id UUID NOT NULL,
    logged_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
    deleted_at   TIMESTAMPTZ,
    UNIQUE (user_id, client_op_id),
    CHECK ((type = 'pushups' AND unit = 'reps' AND quantity <= 500)
        OR (type = 'yoga' AND unit = 'minutes' AND quantity <= 1440)
        OR (type = 'reading' AND unit = 'minutes' AND quantity <= 1440)
        OR (type = 'reading' AND unit = 'pages' AND quantity <= 2000))
);
CREATE INDEX activity_logs_day ON activity_logs (user_id, local_date) WHERE deleted_at IS NULL;

CREATE TABLE meal_logs (
    id           BIGINT PRIMARY KEY DEFAULT nextval('log_ids'),
    user_id      BIGINT NOT NULL REFERENCES users (id),
    local_date   DATE NOT NULL,
    name         TEXT NOT NULL CHECK (char_length(name) BETWEEN 1 AND 80),
    kcal         INTEGER NOT NULL CHECK (kcal BETWEEN 0 AND 10000),
    protein_g    NUMERIC(6,1) NOT NULL CHECK (protein_g >= 0),
    carbs_g      NUMERIC(6,1) NOT NULL CHECK (carbs_g >= 0),
    fat_g        NUMERIC(6,1) NOT NULL CHECK (fat_g >= 0),
    fiber_g      NUMERIC(6,1) NOT NULL DEFAULT 0 CHECK (fiber_g >= 0),
    client_op_id UUID NOT NULL,
    logged_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
    deleted_at   TIMESTAMPTZ,
    UNIQUE (user_id, client_op_id)
);
CREATE INDEX meal_logs_day ON meal_logs (user_id, local_date) WHERE deleted_at IS NULL;
CREATE INDEX meal_logs_recent ON meal_logs (logged_at DESC) WHERE deleted_at IS NULL;

CREATE TABLE health_daily (
    user_id     BIGINT NOT NULL REFERENCES users (id),
    local_date  DATE NOT NULL,
    metric      TEXT NOT NULL CHECK (metric IN ('steps','active_energy','basal_energy','exercise_minutes',
                    'distance_m','flights','workouts','workout_minutes','sleep_minutes','mindful_minutes',
                    'water_ml','resting_hr','hrv_ms','vo2max','weight_kg','body_fat_pct','lean_mass_kg')),
    value       DOUBLE PRECISION NOT NULL,         -- per-metric bounds in a CHECK, see Metrics in v1
    source      TEXT NOT NULL CHECK (source IN ('healthkit','fake')),
    measured_at TIMESTAMPTZ NOT NULL,
    updated_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (user_id, local_date, metric)
);

CREATE TABLE day_scores (
    user_id      BIGINT NOT NULL REFERENCES users (id),
    local_date   DATE NOT NULL,
    points       INTEGER NOT NULL,
    base_points  INTEGER NOT NULL,
    bonus_points INTEGER NOT NULL,
    max_points   INTEGER NOT NULL,
    percent      INTEGER NOT NULL CHECK (percent BETWEEN 0 AND 100),
    counted      BOOLEAN NOT NULL,
    detail       JSONB NOT NULL,
    computed_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    finalized_at TIMESTAMPTZ,
    PRIMARY KEY (user_id, local_date)
);
CREATE INDEX day_scores_recent ON day_scores (user_id, local_date DESC);

-- migration 0005
CREATE TABLE audiobookshelf_accounts (
    user_id           BIGINT PRIMARY KEY REFERENCES users (id) ON DELETE CASCADE,
    abs_user_id       TEXT NOT NULL,
    username          TEXT NOT NULL,
    access_token      TEXT NOT NULL,
    refresh_token     TEXT NOT NULL,         -- rotated by Audiobookshelf on every refresh
    access_expires_at TIMESTAMPTZ NOT NULL,
    linked_at         TIMESTAMPTZ NOT NULL DEFAULT now(),
    synced_at         TIMESTAMPTZ,
    last_error        TEXT CHECK (last_error IN ('auth_failed', 'unreachable'))
);

CREATE TABLE listening_daily (
    user_id    BIGINT NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    local_date DATE NOT NULL,
    minutes    INTEGER NOT NULL CHECK (minutes BETWEEN 0 AND 1440),
    synced_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (user_id, local_date)
);
```

Notes:

- There is no stored streak.
- Join creates the user, the six templates (yoga disabled), the device, and snapshots every writable date, in one transaction.
- `first_local_date` is `localToday`, or `localToday - 1` when the join happens before 10:00 local.
- Template targets and `points` are copied into `day_quests`, so later template edits never change an existing day.

### Scheduler

One goroutine under `recover` and a per-run context timeout runs on boot and every 5 minutes.
For each live user, in the user's timezone, it finds every `local_date` from `first_local_date` with no `day_scores` row that has `finalized_at` set, and where `now >= time.Date(y, m, d+1, 10, 0, 0, 0, loc)`.
For each such date, in one transaction with the advisory lock, it runs `ensureSnapshot`, `scoreDay`, and upserts the row with `finalized_at = now()`.
Catch-up after restarts and deploys is therefore automatic, and no day is skipped.
It also applies pending timezone switches that have come due.

When `NEWME_ABS_URL` is set, a second loop under the same guards polls every 15 minutes (and on boot) for each linked account.
It refreshes the Audiobookshelf session when the access token is within 2 minutes of expiring, or once when Audiobookshelf answers 401, and stores the rotated refresh token before using the new access token.
It reads `GET /api/me/listening-stats`, and for the person's still-open local dates (today, and yesterday until its 10:00 grace ends, never before the join date) stores `floor(seconds / 60)` capped at 1440 in `listening_daily`.
Only a changed value writes and rescores the day, in one transaction under the day lock; finalized days are never touched.
A rejected sign-in records `last_error = auth_failed` and keeps the link, a network or server failure records `unreachable`, and the next good poll clears it.
Linking runs one poll straight away.
Audiobookshelf dates its days in its own server time zone, which is assumed to be the people's zone.

### Deployment (compose)

Project directory `~/docker-server/npc_projects/new-me`, files copied from the repository `deploy/` folder.

- `server`
  - image `ghcr.io/nc1107/new-me:${NEWME_TAG:-latest}`
  - label `com.centurylinklabs.watchtower.enable=true`
  - Traefik labels: Host `new-me.npc-server.top`, entrypoint `websecure`, `tls.certresolver=cloudflare`, `middlewares=secureHeaders@file`, service port 8080, `traefik.docker.network=traefik_proxy`
  - healthcheck `["CMD", "/app/server", "-healthcheck"]`, interval 30s, start period 20s
  - `mem_limit: 256M`
  - networks: internal and `traefik_proxy`
- `db`
  - `postgres:16-alpine`, pinned, no watchtower label
  - internal network only
  - `pg_isready` healthcheck, `db_data` volume
- `db-backup`
  - `prodrigestivill/postgres-backup-local:16`, daily
  - `BACKUP_KEEP_DAYS=7`, `BACKUP_KEEP_WEEKS=4`, `BACKUP_KEEP_MONTHS=6`
  - dumps to `./backups`
- `.env`: `POSTGRES_PASSWORD`, `NEWME_APP_KEY`, `NEWME_TAG`, `NEWME_TRUSTED_PROXY_HOPS`.

Operations:

- Run one restore drill (dump, restore into a scratch database, row-count check) before M3.
- Watchtower does not roll back.
  Rollback means setting `NEWME_TAG` to the previous `X.Y.Z` in `.env` and running `docker compose up -d`.
- Record the actual scw-watchtower poll interval in `deploy/README.md`.
- The Dockerfile sets `org.opencontainers.image.source`.
  After the first push, make the GHCR package public or give watchtower a `read:packages` token, and record which.
- The Docker build is `golang:1.26-alpine` to `distroless/static-debian12:nonroot`.

### Tests

Real Postgres through `TESTDB_URL`, truncate-all reset per test, httptest server over the production router, fluent `expect(status).decode()`.
`internal/score` is tested without a database: integer formulas, bonus, percent rounding at the 70% boundary, reading mix, protein tenths, and the streak table.
Handler tests cover: app key 403, 401 on bad token, 426, join flows (first, code, re-pair, full, name and color conflicts, lockout after 5 attempts), the day window at 09:59 and 10:00 with an injected clock, idempotent replay, delete without undelete, stale health write ignored, rate limits.
`scripts/test.sh` starts a throwaway Postgres in Docker.

## 5.
App

### Structure

```
app/lib/
  main.dart                 runZonedGuarded, portrait lock, root gate
  api/                      ApiClient (dio), models, error mapping
  state/                    session, api_client_provider, clock, today, board, me, health_sync, prefs
  health/                   HealthSource interface; health_source_factory.dart; healthkit_source.dart; fake_health_source.dart
  features/onboarding/      probe, invite code, join or re-pair, name and color, connect Health
  features/update_required/  blocking screen
  features/today/           score ring, quest cards, food card, day detail sheet
  features/board/           two columns, 7-day strips, waiting placeholder
  features/log/             bottom sheet
  features/me/              profile, targets, quests, Health card, create pairing code, about
  theme/                    tokens.dart, accent.dart (from check-in)
  widgets/                  AppTextField, PrimaryButton, PillBadge, ScoreRing, QuestCard, AccentPicker, OfflineBanner, Skeletons, EmptyState
```

Root gate: not restored shows a blank frame; no session shows onboarding; a 426 shows `update_required`; otherwise `HomeShell`.

### State

- `sessionProvider`: a Notifier holding one JSON blob `{baseUrl, userId, token}` under a single `flutter_secure_storage` key, read and written atomically.
  Keychain accessibility is `first_unlock_this_device` so the Swift shim can read it while the phone is locked.
  Non-secret prefs in `shared_preferences`: `healthPrompted`, `lastSyncedAt`, last-used log type, last count-up date, and the last `/today` and `/board` responses for the offline view.
- `apiClientProvider` watches the session and takes the app key as a constructor parameter.
  `const kAppKey = String.fromEnvironment('NEWME_APP_KEY')` is asserted non-empty in release builds.
  It is the fake seam in tests.
- `todayProvider`, `boardProvider` and `meProvider` are AsyncNotifiers refreshed with `ref.invalidate`.
- `clockProvider` and `healthSourceProvider` are overridable.
- `healthSyncProvider` is the single-flight sync controller (below).
- `accentProvider` derives from the session user's color.
- Riverpod's automatic retry is disabled (the `ProviderScope` retry returns null).
- The log sheet generates `clientOpId` when it opens, not on submit, and reuses it on retry.
- Status handling in the client: 401 with a token signs out; 403 `bad_app_key` shows a dedicated error and never signs out; 426 routes to the update screen; network errors and 5xx are treated as offline, never as sign-out.
- `X-Client-Version` carries `kClientVersion`, covered by the pubspec drift test.

### Theme and accent

Keep `tokens.dart`, `accent.dart` (presets green, sky, violet, amber, rose, teal) and the ThemeData block from check-in.
`AccentPicker` takes `selected` and `onChanged`, not a provider, and disables colors taken by the other user.
Each Board column is wrapped in `Theme(data: base.copyWith(extensions: [accentById(user.color)]))` so two accents show in one frame.
The SnackBar is themed once.
`MediaQuery.disableAnimations` is respected.
Animate on change only: ring sweep when points change, the check animation on quest completion, number count-up only on the first view of the day.

### Screens

Every network-backed screen follows one rule set.

- **Loading**: a skeleton shaped like the final layout.
- **Error**: centered text with "Try again"; cached data stays visible below it.
- **Offline**: network errors and 5xx show the last cached response under a slim banner "Offline - updated 14:02".
  With no cache the error state is shown.

Navigation: custom bottom bar from check-in, Today, Board, center accent FAB (Log), Me.
Plain `Navigator` for pushes, no router package.

**Onboarding**
- On launch the prefilled `new-me.npc-server.top` is probed silently.
- The server field appears only behind a "Change server" link or when the probe fails, with distinct copy for unreachable, wrong address, and "update required".
- If `initialized` is false: "What should we call you?" with name, then color.
- Otherwise: invite code entry, validated with `POST /invites/check`, then "I'm new" (name and color) or a row of existing-user chips for re-pair.
- A full server (`canJoinNew` false) shows only the chips.
- The last step is an optional, skippable "Connect Health".
- Timezone is sent from `flutter_timezone`.
- After a forced sign-out the screen reads "You were signed out.
  Enter a code to come back." with the server prefilled.
- Loading: the probe shows a skeleton line and disabled primary button.
  Error: inline field error under the code or server field.
  Offline: unreachable copy with "Try again".
  Empty: not applicable, nothing is persisted until join succeeds.
- Wrong code shows "That code did not work", and a dead code (locked or expired) says to ask for a new one.

**Update required**: a blocking full screen with the minimum version and a button that opens TestFlight.
No other navigation.

**Today**
- Large score ring with an animated sweep, a tick at 70%, points in the centre, and below it "Streak line: 70% - you are at 62%" (or "Streak day counted").
- Streak pill ("Day N") and rest chip beside it.
- Quest cards: title, progress bar, `actual / target` (reading reads "12 min + 5 pages"), a "+" for manual metrics that opens the Log sheet already on that metric, and a small "+20" chip when the bonus is earned.
- Completing a quest plays the 220ms check animation and `mediumImpact`.
- Food card under the quests: kcal eaten / target with a thin bar, then protein, carbs and fat as compact eaten/target rows and "burned N" from active energy.
  It is not scored.
- Tapping a quest card or the Food card opens a day detail sheet listing the day's entries (time, quantity) with swipe-to-delete and a "Deleted - Undo" snackbar.
- Footer: "Health synced Xh ago".
  Pull to refresh runs a Health sync and a reload.
- Empty (day with nothing logged): ring at 0, cards at zero, copy "Nothing yet today."
- Unset targets: the Food card hides those rows and shows "Set your targets" linking to Me.
- Health states:
  - If `health.stepsEverSynced` is false the steps card is a "Connect Health" card, excluded from the day max until the first sync.
  - After `healthPrompted` is set, a day with `stepsToday == null` shows "No steps yet.
    Open Health > Sharing > Apps > New Me and allow Steps."
  - There is no re-request button after the first prompt.
- Loading: ring skeleton plus three quest-card skeletons.
  Error and offline as above.

**Board**
- Two columns, one per user, each in that user's accent.
- Headline is today's points with day percent beneath, then streak with rest marks, week and season points, a 7-day strip (hollow dot for a rest day), and "synced Xh ago" under each column.
- With one user, the other column is a dashed placeholder "Waiting for Nadia" with a "How she joins" sheet (TestFlight invite, open the app, enter your code).
- Empty state on day one: both at zero with "Nobody has moved yet."
- Loading: two-column skeleton.
  Error and offline as above.

**Log (bottom sheet)**
- Opens on the last-used type.
  Segments: pushups, reading, meal, and yoga only when its template is enabled.
- Pushups: chips 10, 15, 20, 25 log immediately with an "Added 20 - Undo" snackbar, plus a number pad for custom values.
- Reading: minutes or pages toggle.
- Meal: name, kcal, protein, carbs, fat, with fiber behind "More".
  Recent-meal chips (from `/meals/recent`, both users) log in one tap and carry a portion stepper (0.5, 0.75, 1, 1.25, 1.5, 2) that multiplies stored macros; the form has the same stepper.
- Confirmation is asked above the sanity limits: pushups over 200, pages over 300, kcal over 3000.
- Save is disabled until the quantity is above 0 (kcal above 0 for meals), with inline errors via `AppTextField`.
- An "Add to yesterday" toggle appears only before 10:00.
- A failed save keeps the sheet open with a retry that reuses the same `clientOpId`.
- Empty (no recent meals): the chip row is hidden.
  Loading: chips show a skeleton row.
  Offline: save fails with "You are offline" and the sheet stays open.

**Me**
- Avatar and name, accent picker, timezone (device zone by default, PATCHed when the device zone changes).
- Targets: kcal, protein, carbs, fat.
- Quest editor: enabled toggle and target only, with the note "Takes effect tomorrow".
- Health connection card: connect, last sync, what is read.
- Admin only: "Create pairing code" showing the code, its expiry, and a copy button.
- About: version and server address.
- "Leave this server": calls `DELETE /devices/me`, then deletes the session blob.
- Loading: skeleton rows.
  Error and offline: edits are disabled offline and a save error keeps the edited value in place with "Try again".

### HealthKit

`package:health` 13.3.2.
It is behind a conditional import: `health_source_factory.dart` uses `if (dart.library.io) 'healthkit_source.dart'` and defaults to `FakeHealthSource`, and `Health()` is constructed lazily, so the web build does not crash.

Reads, for local midnight on the device through now:

- `STEPS` via `getTotalStepsInInterval(start, end, includeManualEntry: false)`.
- `ACTIVE_ENERGY_BURNED` for the same interval.
- Until 10:00 local (`backdateUntil`), yesterday's midnight-to-midnight values are also pushed.

Sync controller (single flight):

- Triggers: app start, resume, pull to refresh, first connect.
- Resume syncs at most every 5 minutes by the injected clock.
  Pull to refresh and first connect bypass the throttle.
- The `PUT /health/daily` is skipped when the value equals the last successfully pushed one.
- It is driven by an `AppLifecycleListener` created in the Notifier `build` and disposed with `ref.onDispose`.
- On success the returned `days` replace the cached day, so no second `GET /today` is needed.

Permission is requested only from a user tap (the Connect Health card or the onboarding step), and then `healthPrompted` is persisted.
iOS does not report read denial, so the no-data hint above is the denial path.

Native background delivery (`BackgroundHealth` in `app/ios/Runner/AppDelegate.swift`, method channel `newme/background`):

- Flutter calls `configure({baseUrl, token, appKey, clientVersion})` whenever a session exists or its token changes, `clear()` on sign-out, and `enable()` after Health access was asked for (also at start when Health was already prompted).
  `BackgroundHealthBridge` in `app/lib/health/` wraps the channel and is a no-op on web or when the plugin is missing.
- Swift keeps the config in its own Keychain item (generic password, service `top.npcserver.newme.background-health`, `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`), so a wake while the phone is locked can still read it.
- `application(_:didFinishLaunchingWithOptions:)` registers an `HKObserverQuery` and `enableBackgroundDelivery(for:frequency: .hourly)` for steps, active energy, basal energy, exercise time, walking and running distance and flights climbed, every launch, when configured and enabled.
- On wake it runs an `HKStatisticsQuery` (cumulative sum, which deduplicates sources, excluding samples with `HKMetadataKeyWasUserEntered` true) per type from local midnight to now, plus yesterday while the local hour is before 10.
- Values are rounded to whole numbers and sent as one `PUT /api/health/daily` with `X-App-Key`, `Authorization`, `X-Client-Version`, `source: healthkit` and `measuredAt: now`.
  A 422 with code `date_closed` retries with today's items only.
- It runs inside `beginBackgroundTask`, allows one push at a time (a wake during a push triggers one more pass), skips values equal to the last pushed ones (kept in `UserDefaults`), and always calls the observer's completion handler.
- Sleep, heart and body metrics stay foreground-only.
- `Runner.entitlements` carries `com.apple.developer.healthkit.background-delivery`.
  `Info.plist` has no `UIBackgroundModes` entry, because HealthKit launches the app for observer queries without one.
- The server needs no change.

### Platform files

- iOS deployment target 15.0 in the Podfile `platform` line, the `post_install` override, and every `IPHONEOS_DEPLOYMENT_TARGET` entry.
  `package:health` 13.3.2 requires 15.0 and Flutter 3.47's template default is already 15.0.
  Do not copy check-in's 13.0.
- `flutter config --no-enable-swift-package-manager` runs locally and in `ci.yml` and `release.yml`, because Swift Package Manager leaves a white launch screen.
- `Runner.entitlements`, written fresh: `com.apple.developer.healthkit = true`, `com.apple.developer.healthkit.access = []`, `keychain-access-groups = [$(AppIdentifierPrefix)top.npcserver.newme]`.
  No `aps-environment`.
- `Info.plist`: `NSHealthShareUsageDescription`, `NSHealthUpdateUsageDescription` ("New Me never writes to Health."), `ITSAppUsesNonExemptEncryption` false, portrait only, no `UIBackgroundModes`, no URL scheme, no Firebase keys. `CFBundleDisplayName` is "New Me".
- Manual signing in Release with Apple Distribution for team 76S78SUWVM, profile "New Me App Store Distribution", `ExportOptions.plist` adapted from check-in with the new bundle id.
- App icon: generated once from `assets/brand/icon.svg` with ImageMagick into `AppIcon.appiconset`.
  Dark canvas, accent glyph of two overlapping rounded rings forming a rising arc.
  It is also the in-app logo.

### Tests

`flutter_test` only, with hand-rolled fakes through provider overrides, `clientFactory` injection and a secure storage channel mock.
Widget tests: onboarding (first join, code join, re-pair, failures), Today scoring display and the 70% tick copy, health states, log sheet validation and portion stepper, Board placeholder, offline banner, 426 screen.
Unit tests: the sync controller (throttle, equality skip, single flight) with a fake clock, and the version drift guard.

## 6.
CI and release

### ci.yml

On pull requests and pushes to non-main branches.

- `server` job: gofmt, vet, build, `go test -race` with a Postgres service.
- `app` job: `flutter config --no-enable-swift-package-manager`, `flutter pub get --enforce-lockfile`, format, analyze, test, and `flutter build web` with a dev key.
- `ios-build` job on `macos-15`, path-filtered to `app/ios/**`, `app/pubspec.yaml` and `app/pubspec.lock`: `flutter build ios --no-codesign`.

### release.yml

Triggers: `push` to `main`, `schedule` with cron `17 6 1,15 * *`, and `workflow_dispatch`.
One workflow means one `run_number` counter and one concurrency group (`release`).
The twice-monthly run keeps the newest TestFlight build well under the 90-day expiry.

Jobs:

1. `tests`: server and app tests.
   Push only.
2. `version`: conventional-commit bump and tag on push.
   Build number is `run_number*100+run_attempt`.
   On schedule and dispatch it does not tag and outputs the latest existing tag.
3. `docker`: push only.
   Builds `ghcr.io/nc1107/new-me:latest` and `:X.Y.Z` with `-ldflags -X main.version`.
4. `app-store`: `macos-15`, checks out the version tag (the latest tag on schedule), Flutter 3.47.0, `flutter config --no-enable-swift-package-manager`, CocoaPods, "Select latest Xcode" copied from check-in plus `xcodebuild -version`, manual signing, `test -n "$NEWME_APP_KEY"`, `flutter build ipa --dart-define=NEWME_APP_KEY=...`, `altool` upload, then `scripts/asc-wait.sh`.
   - `scripts/asc-wait.sh` mints an App Store Connect JWT and polls the build until `processingState` is `VALID`.
     It fails on `INVALID` or after 30 minutes.
5. `release`: needs `[version, docker, app-store]`, push only, creates the GitHub Release after processing passes.
   The release-notes gate from check-in is dropped.
6. `deploy-verify`: push only, polls `https://new-me.npc-server.top/api/health` until `version` equals the new version, 15 minute timeout.

Other rules:

- Android and Play jobs are removed.
  There is no `has_appstore` gating: missing secrets fail the job via `test -n`.
- A `failure()` step opens a GitHub issue.
- A keepalive step re-enables the workflow so GitHub does not disable the schedule after 60 days of inactivity.
- Watchtower pulls `:latest` within its poll interval, so a merge to `main` is a deploy.
- The pre-push hook `.githooks/pre-push` mirrors the CI format checks.

### Secrets

Seven in total.

Shared with check-in (rotating the certificate means updating both repositories):

- `IOS_CERTIFICATE_BASE64`
- `IOS_CERTIFICATE_PASSWORD`
- `ASC_API_KEY_BASE64`
- `ASC_KEY_ID`
- `ASC_ISSUER_ID`

New for this app:

- `IOS_PROVISIONING_PROFILE_BASE64`
- `NEWME_APP_KEY`, generated with `openssl rand -hex 32`.
  The web review build uses a different key.

### Apple checklist

Browser steps, once:

1.
   Create the App Store Connect app record with a unique App Store name such as "New Me - Habits".
2.
   Accept pending agreements.
3.
   Invite Nadia under Users and Access and add her to an internal TestFlight group with automatic distribution.

Scripted through the App Store Connect API, in this order:

1.
   Register bundle id `top.npcserver.newme`.
2.
   Enable the HEALTHKIT capability.
3.
   Create the "New Me App Store Distribution" profile.

Enable automatic updates in TestFlight on both phones.

## 7.
Milestones

- **M0 skeleton**: repository and monorepo layout, `CLAUDE.md`, CI, lint, an empty Flutter app that builds for iOS and web, a Go server with the health endpoint, compose deployed behind Traefik.
  It also includes the Apple setup session and a first TestFlight upload of the empty skeleton with the HealthKit entitlement and usage strings, so signing problems surface in the cheapest milestone.
- **M1 server**: migration 0002, access model and pairing, logs, health upsert, quests and scoring, streak, board, scheduler, CLI invite, rate limits, tests.
- **M2 app**: theme, onboarding, Today, Board, Log, Me, offline handling, HealthKit foreground sync, tests, visual review on web at phone width.
  The backup restore drill completes before M3.
- **M3 release**: release workflow, Swift background-delivery shim, first TestFlight build on Nick's phone, Nick joins first, then Nadia is added as an internal tester.
- **Later**: workouts, meals from Mealie, notifications, bloodwork, screen time.

## 8.
Open items

Decided here, editable later:

- Day boundary is local midnight with a 10:00 grace for backdating.
  Timezone is per user and defaults to the device zone.
- Public repository.
  Switching to private costs macOS minutes.
- Version bumps come from conventional commits on `main`, as in check-in.
  If "release please" meant the release-please tool, swap the version job later.
- Quest defaults above; Nick and Nadia edit enabled and target in the app.
- Open to record after first deploy: whether the GHCR package is public or watchtower uses a token, and the actual watchtower poll interval.
- `.gitignore` covers `.env`, `backups/`, `*.p12`, `*.mobileprovision`, `AuthKey_*.p8`, `key.properties` and `docs/research/`.
