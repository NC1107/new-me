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
| pushups | manual log, sets of reps, or a Health workout (v6) | sum of `quantity` of `pushups` logs; a qualifying workout on the day makes the quest complete whatever the reps (actual = target), earning full base points and the completion bonus: `strength` of 20 minutes or more, or `hiit` of 15 minutes or more whose `avgHr` is at least 60% of the person's heart-rate reserve (resting HR plus 0.6 times (220 minus age minus resting HR)); when the birth year, a resting HR reading or the workout's `avgHr` is missing, `hiit` needs 20 minutes like strength |
| reading | manual log, minutes or pages, plus Audiobookshelf listening | minutes `m` (manual minutes plus that day's `listening_daily` minutes) and pages `g`, summed separately |
| meals_logged | derived from meal logs | count of meals with `kcal > 0` |
| protein | derived from meal logs | sum of `protein_g` in tenths of a gram |
| yoga | manual log, minutes, plus Health workouts (v6) | sum of `quantity` of `yoga` logs plus the whole minutes of that day's `yoga` workouts (pilates and flexibility arrive from Health as `yoga`) |
| exercise | HealthKit, `health_daily` metric `exercise_minutes`, plus manual `other` activity | `floor(value)` plus manual minutes (moderate and hard in full, easy half) |
| sleep | HealthKit, `health_daily` metric `sleep_minutes` | `floor(value)` |
| active_energy | HealthKit, `health_daily` metric `active_energy` | not scored; shown on Today as "burned N" |

`health_daily` holds 18 metrics, each with a per-day bound enforced by a CHECK and by `PUT /health/daily`.
Steps, active_energy, basal_energy, distance_m and water_ml are 0 to 200000, 20000, 20000, 200000 and 20000.
exercise_minutes, workout_minutes, sleep_minutes and mindful_minutes are 0 to 1440.
flights is 0 to 1000, workouts 0 to 50, hrv_ms 0 to 500 and vo2max 0 to 100.
resting_hr is 20 to 250, weight_kg 20 to 400, body_fat_pct 1 to 80 and lean_mass_kg 10 to 300.
v8 adds an 18th metric, `height_cm` (100 to 250), a point-in-time reading that is only used when the profile has no height.
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
| exercise | 30 min | 100 | enabled (v7; off for people who joined earlier) |
| sleep | 420 min | 50 | enabled (v7; off for people who joined earlier) |

Yoga is a template and an activity log type that ship disabled.
Exercise and sleep are Health-fed like steps and have positions 6 and 7; v7 turns them on for new people (exercise also counts manual activity logs).
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

`internal/score.ComputeStreak` is a pure function.
The streak is never stored; it is derived at read time from `day_scores` (counted, plus the recorded outcome of finalized days), the person's away spans and the partner covers.
Under the v7 rules (see `design-v7.md` and its Server decisions):

1. Walk every date from the first day through today.
2. Away day (inside an away span): changes nothing, even if the day counted.
3. Counted day: streak + 1, and one step toward the next freeze.
4. Today before it has counted is open; yesterday while its grace window is open and not counted is pending. Neither changes the streak.
5. A recorded outcome wins: a frozen day (reason `freeze`, `readiness`, `repair` or `cover`) keeps the streak and adds no day (a `freeze` also spends one); a settled miss with no reason breaks it.
6. Otherwise the day is decided now: covered by the partner (frozen, reason `cover`), then rest after an easy readiness morning (frozen, reason `readiness`, no freeze), then a freeze if one is held and the streak is above zero (frozen, reason `freeze`), else the streak resets.
7. Freezes: start with 2, earn 1 per 7 counted days, hold at most 2. At the maximum the progress waits at 6 of 7. A freeze spent covering the partner is a spend on the coverer's balance at the covered date.
8. Days before the person's `streak_rules_from` follow the old weekly rest rule (one miss a week forgiven while a streak runs, never right after another miss); that history stays as recorded.

Settling: the scheduler records the decisions (`day_scores.settled`, `frozen_reason`, `away`) for finalized days, oldest first, once; a settled day is never rewritten except by a repair.
Repair: until 22:00 the next local day, reaching 100% of today's base points (`percent == 100`) turns a missed, settled, unfrozen, non-away yesterday into a frozen day with reason `repair`; no freeze is spent.
Shared streak (`score.SharedStreak`): a date adds one when every person counted, was frozen or was away and at least one counted; any miss resets it; an undecided day (open, pending, no entry) or a day nobody counted changes nothing.

Table tests cover the freeze rules, away days, recorded versus decided days, the rule transition from the weekly rest rule, the repair window, covers and the shared streak.

Presentation: the streak pill reads "Day 1" when the streak is 0. The 7-day strip marks frozen (snowflake), away and repaired days.

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
| `NEWME_APNS_KEY` | empty | contents of the APNs `.p8` key, base64; with the three below, turns push on |
| `NEWME_APNS_KEY_ID` | empty | the key's 10-character id |
| `NEWME_APNS_TEAM_ID` | empty | Apple team id (`76S78SUWVM`) |
| `NEWME_APNS_TOPIC` | empty | app bundle id (`top.npcserver.newme`) |
| `NEWME_APNS_PRODUCTION` | `true` | `true` uses `api.push.apple.com` (TestFlight, App Store), `false` the sandbox host |
| `NEWME_ANTHROPIC_API_KEY` | empty | Claude API key (v6); empty turns meal estimates and the plan wording off |
| `NEWME_ANTHROPIC_BASE_URL` | empty (`https://api.anthropic.com`) | override for tests or a proxy; must be an http(s) URL |
| `NEWME_USDA_API_KEY` | empty (`DEMO_KEY`) | USDA FoodData Central key for meal lookups and the food search; empty uses the shared demo key, which allows only about 10 calls an hour per IP, so set a real key (free at fdc.nal.usda.gov) |
| `NEWME_DEV_CORS` | `false` | local web review only, never set in production |

The four `NEWME_APNS_*` credentials are all set or all unset; a partial set stops the server at boot.
Unset leaves push off and everything else works.
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
  - `PUT /health/daily`, `PUT /health/workouts` and `PUT /health/sleep`: an additional 30 per minute per device, one shared bucket.
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
| 413 | `payload_too_large` | body over 1 MB (8 MB on `POST /meals/estimate`), or a meal photo over 5 MB decoded |
| 422 | `date_closed` | date outside the day window |
| 422 | `invalid_timezone`, `invalid_request` | validation, with per-item errors where relevant |
| 422 | `abs_login_failed` | Audiobookshelf rejected the username or password |
| 404 | `abs_disabled` | `NEWME_ABS_URL` is not set |
| 502 | `abs_unavailable` | Audiobookshelf could not be reached while linking |
| 404 | `abs_not_linked` | `POST /me/audiobookshelf/sync` before the person linked |
| 404 | `estimate_disabled` | `NEWME_ANTHROPIC_API_KEY` is not set |
| 502 | `estimate_unavailable` | Claude could not split the text, or no item could be sized at all (a single item that fails is returned estimated, or at zero for the person to fill in) |
| 404 | `not_found` | `/api/foods/{id}` for a food that does not exist |
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
  201 {user: {id, name, color, timezone, isAdmin, birthYear, heightCm, sex, goal}, token}

DELETE /devices/me                                  204, revokes the calling device

POST   /invites                                     admin
  201 {code, expiresAt}

GET    /me
  200 {user: {id, name, color, timezone, isAdmin, birthYear, heightCm, sex, goal {kind, paceKgPerWeek}},
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
              birthYear: 1900..current year in the person's zone, or null to clear (absent leaves it alone),
              heightCm: 100..250 or null, sex: male|female|null, goal: {kind, paceKgPerWeek},
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
       listening: {minutes, syncedAt},                   Audiobookshelf minutes already counted in the reading quest, 0 when none; syncedAt is the last good read or null
       readiness, plan}                                  v6, see below
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
                workoutsThisWeek,
                syncedAt,
                highlights: {steps, exercise_minutes, sleep_minutes}}]}
                                                         the caller first, each person on their own local today
                                                         highlights are that person's local-today readings, each key omitted when there is no row
                                                         workoutsThisWeek counts workouts since Monday of that person's own local week (integer, 0 when none)

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
  req {items: [{date, metric: one of the 18 keys, value, source, measuredAt}]}
  200 {days: [DayDetail]}                                every affected date, oldest first, so the app skips GET /today
  422 {code, error, items: [{index, code, error}]}       code is date_closed when every bad item is, else invalid_request

GET    /health/trends?metric=<key>&days=<1..365>
  200 {metric, points: [{date, value}]}                  the caller's own readings, ascending, the last N local days ending today; days with no reading are absent
  422 invalid_request                                    unknown metric, or days missing, not an integer or outside 1 to 365

PUT    /health/workouts
  req {items: [{id, type, startedAt, endedAt, durationMin, kcal, distanceM, avgHr, source}]}
  200 {saved: n}                                         1 to 100 items, upserted by (user, id) in one transaction
  422 {code: "invalid_request", error, items: [{index, code, error}]}   every bad item is listed and none is stored

GET    /workouts?days=<1..365>
  200 {workouts: [{id, type, date, startedAt, endedAt, durationMin, kcal, distanceM, avgHr}],
       week: {count, minutes}}                           the caller's own, newest first, local dates of the last N days ending today
                                                         week is the ISO week (Monday to today) of the caller's local today, whatever days is
  422 invalid_request                                    days missing, not an integer or outside 1 to 365

PUT    /health/sleep
  req {nights: [{date, bedAt, wakeAt, asleepMin, deepMin, remMin, coreMin, awakeMin, source}]}
  200 {saved: n}                                         1 to 31 nights, upserted by (user, date) in one transaction
  422 {code: "invalid_request", error, items: [{index, code, error}]}

GET    /insights
  200 {steps: {avg7, avg30, median14, trend, best, daysAtGoal30, goal, suggestion},
       sleep: {avg7Min, avg30Min, targetMin, avgBedtime, avgWake, bedtimeSpreadMin, stages7, lastNight, nights},
       workouts: {week: {count, minutes}, last30: {count, minutes, byType: [{type, count, minutes}]}}}
                                                         the caller's own, computed by the pure functions in internal/insights

-- v5 (docs/design-v5.md) --------------------------------------------------------------

GET    /habits
  200 {habits: [{id, name, icon, kind, weekdays, slots: [{label, time}], target, position, paused}]}
                                                         the caller's live habits in order, paused ones included
                                                         kind check|count; weekdays are ISO numbers 1 (Mon) to 7 (Sun); time is "HH:MM" or null
                                                         a count habit has slots [] and a target; a check habit has target null

POST   /habits
  req {name, icon, kind, weekdays?, slots?, target?}     weekdays defaults to every day; appended after the last habit
  201 {habit}
  422 invalid_request                                    name 1 to 40 chars without control characters; icon outside the list below;
                                                         check needs 1 to 8 slots (label 1 to 24 chars, optional time HH:MM) and no target;
                                                         count needs target 1 to 50 and no slots; weekdays empty or outside 1..7; more than 30 habits

PATCH  /habits/{id}
  req any of {name, icon, weekdays, slots, target, paused}   kind cannot change; the merged habit is validated as a whole
  200 {habit}                                            open days are rescored (today, and yesterday inside the grace)
  404 not_found                                          not the caller's, or deleted

DELETE /habits/{id}
  204                                                    soft delete; marks are kept; open days are rescored

PUT    /habits/order
  req {ids: [id, ...]}                                   every live habit of the caller exactly once
  200 {habits}

PUT    /habits/{id}/marks/{date}
  req {slot, done}                                       check habit: set one slot done or undone
  req {count}                                            count habit: set the day's count, 0 clears it (cap 1000)
  200 {date, habits: [<today habit state>], day: <day with quests>}   idempotent
  404 not_found                                          not the caller's habit
  422 date_closed                                        outside today / yesterday-before-10:00 / after joined_on, same as logs
  422 invalid_request                                    slot out of range, wrong field set for the kind, habit paused, habit not scheduled that weekday

POST   /cheers
  req {to: userId, kind: "clap" | "fire" | "flex" | "heart"}
  201 {cheer: {from, fromName, kind, at}, to}            first of that kind to that person on the sender's local day; pushes "<name> cheered your day"
  200 same body                                          a repeat: the stored cheer, nothing sent
  404 not_found                                          no such person
  422 invalid_request                                    unknown kind, or cheering yourself

GET    /rewards
  200 {reward: <reward> | null, history: [<reward>]}     reward is the one being earned; history is the reached ones, newest first

POST   /rewards
  req {name (1..40), target (1..100000)}
  201 {reward}                                           progress counts combined points earned from this moment
  409 reward_active                                      one is still being earned

POST   /rewards/{id}/claim
  200 {reward}                                           marks a reached reward as enjoyed; repeating keeps the first claimedAt
  404 not_found
  409 reward_not_reached

PUT    /devices/me/push
  req {token}                                            hex APNs device token, 32 to 200 characters
  204                                                    repeating is fine; a token seen on another install moves to this one
DELETE /devices/me/push
  204
```

v5 additions to existing responses:

- `GET /today` gains `habits: [{id, name, icon, kind, slots: [{index, label, time, done}], target, count}]` (the requested day's due, unpaused habits in the person's order) and `cheers: [{from, fromName, kind, at}]` (received on the caller's local today, newest first).
- `GET /board` gains `challenge: {kind, title, target, progress, done, endsOn}` and `reward: <reward> | null`.
  `<reward>` is `{id, name, target, progress, startedAt, reachedAt, claimedAt, createdBy}`.
  On the board it is the reward being earned, or else the newest reached one that nobody has claimed yet, or null.
- `GET /me` and `PATCH /me` gain `notifications: {partnerDone, cheers, challenge, reward}`, all default true; a PATCH may send any subset.
- `day.bonusPoints` and `day.points` include habit points and the challenge award; `maxBase` never does.

v6 additions (see `docs/design-v6.md`; every field and route is additive, and every feature is off or empty when its configuration is missing):

```
POST   /me/audiobookshelf/sync                          auth
  200 {linked: true, username, syncedAt, lastError, minutesToday}
  runs the caller's listening sync now; at most once per 60 seconds per person, a call within the minute answers with the stored state and does not call Audiobookshelf
  404 abs_disabled (NEWME_ABS_URL unset), 404 abs_not_linked

POST   /meals/estimate                                  auth
  req {text} | {image: <base64 JPEG or PNG>, mediaType: "image/jpeg" | "image/png", text?: <hint>}
  text 200 {items: [{text, name, brand, quantity, unit, grams, kcal, protein, carbs, fat, fiber,
                     source: "library"|"usda"|"openfoodfacts"|"estimated", sourceId, matchedName,
                     confidence: "low"|"medium"|"high", origin}],
            total: {kcal, protein, carbs, fat, fiber}, databaseShare: 0..100,
            name, kcal, protein, carbs, fat, fiber, confidence, notes}
  image 200 {name, kcal, protein, carbs, fat, fiber, confidence, notes}   a single Claude estimate, no items
  the top-level fields are the total with the item names joined, kept so older app builds keep working;
  databaseShare is the percent of total kcal whose numbers came from USDA, Open Food Facts or a saved food that began as one
  nothing is stored and nothing is logged: the app shows the items and the person logs them
  404 estimate_disabled, 413 image over 5 MB decoded, 422 neither text nor image, text over 500 characters, image that is not the declared JPEG or PNG,
  429 rate_limited (20 per person per hour, with Retry-After), 502 estimate_unavailable

GET    /foods?q=&remote=1                               auth
  200 {foods: [Food], candidates: [Food]}
  Food {id | null, saved, name, brand, servingText, servingGrams, kcal, protein, carbs, fat, fiber,
        source: "usda"|"openfoodfacts"|"manual"|"estimated", sourceId, servings: [{text, grams}], useCount, lastUsedAt}
  foods are the household's saved foods matching every word of q (prefix match), exact names first, then most used; an empty q lists the most used
  candidates are unsaved USDA and Open Food Facts results with id null, only when remote=1 and q is not empty
  a bare food name puts the FNDDS not-further-specified food first, named "<Food>, any kind" (design-v14)
  candidates draw on Foundation, SR Legacy and FNDDS foods whose leading name segment the query names (design-v16)
POST   /foods                                           auth
  req {name, servingText, kcal, brand?, servingGrams?, protein?, carbs?, fat?, fiber?, source?: default "manual", sourceId?, servings?: [{text, grams}]}
  201 Food; 200 with the saved copy when that source and sourceId are already saved
PATCH  /foods/{id}                                      auth
  req any of name, brand, servingText, servingGrams, kcal, protein, carbs, fat, fiber, servings; source and sourceId cannot change
  200 Food
DELETE /foods/{id}                                      auth
  204
POST   /foods/{id}/use                                  auth
  200 Food with useCount incremented
  404 not_found, 422 invalid_request

GET    /recap?week=YYYY-Www                             auth
  200 {week, from, to, complete,
       people: [{userId, name, color, this: Stats, previous: Stats, bestDay: {date, points} | null, suggestion}],
       pair: {this: Stats, previous: Stats, bestDay},
       challenge: {kind, title, target, progress, completed} | null}
  Stats = {points, countedDays, steps, sleepAvgMin, sleepNights, workouts, readingMinutes}
  week defaults to the last completed ISO week, or to the week ending today from Sunday 19:00 local on; a person who joined this week gets this week
  422 for a malformed week, a week after this one or before the one the caller joined

GET    /goals/proposals                                 auth
  200 {week, weekStart, proposals: [{key: "steps"|"sleep", title, unit, current, proposed, reason}]}
POST   /goals/proposals/{key}/accept
  200 same body as GET /me; the target applies like a PATCH /me template edit (from tomorrow, today on the join day)
POST   /goals/proposals/{key}/dismiss
  204
  404 not_found for an unknown key or a proposal that is not pending this week
```

v6 additions to existing responses:

- `GET /today` gains `listening.syncedAt`, `readiness` and `plan`.
  `readiness` is `{level: "ready"|"normal"|"easy", reasons: [{kind, text}], basis: "full"|"sleep_only"}`, or null when there is neither last night's sleep nor a comparable heart reading.
  `plan` is `{items: [{kind: "done"|"todo"|"habit", key, text}], summary}`.
  Readiness `easy` is exposed for the app to show; scoring does not change on an easy day.
Both are null on any day but the caller's local today.
  `listening.syncedAt` is the last good Audiobookshelf read, null while not linked.
- `GET /me` and `PATCH /me` `notifications` gain `behindPace`, `closeToDone`, `windDown`, `morningPlan` and `weeklyRecap`; `closeToDone`, `morningPlan` and `weeklyRecap` default true, `behindPace` and `windDown` default false.
- `GET /me` gains `features: {mealEstimate, planPolish}`, true when `NEWME_ANTHROPIC_API_KEY` is set.
- Push kinds added: `nudge_behind_14`, `nudge_behind_1830`, `nudge_close_to_done`, `nudge_wind_down`, `nudge_morning_plan`, `weekly_recap`.

Readiness rules (`internal/readiness`).
Each signal votes: HRV at least 15% below the person's mean of the 30 days before today is -1, at least 5% above is +1; resting heart rate at least 5 bpm above its 30-day mean is -1; last night's sleep at least 60 minutes under the target is -1, within 15 minutes of it or more is +1.
A baseline needs today's reading and at least 7 readings in the 30 days; with neither HRV nor resting HR comparable the basis is `sleep_only`.
Full basis: the sum decides, Ready at +2 or more, Easy at -1 or less, otherwise Normal.
Sleep only: Easy when 60 minutes or more short, Ready when the target was met, otherwise Normal.
Last night is the `sleep_nights` row dated today (asleep minutes), else today's `sleep_minutes` metric; the target is the sleep quest target (7 h while the quest is off).

Plan rules (`internal/plan`).
Items are done quests (naming the workout when `doneBy` is set), then open quests with the easiest way to close them, then due habits sorted by their next open slot time.
Steps: remaining steps and minutes at 100 steps a minute rounded to the nearest 5 (at least 5), with a generic moment from the time of day (before 11:30 "around midday", before 17:00 "this afternoon", then "this evening"; over 60 minutes it suggests two walks).
There is no hourly step history, so "when you usually walk" is not used.
Push-ups: remaining reps; reading: remaining minutes (pages count proportionally) and "An audiobook counts."; meals, protein, yoga, exercise: what is left.
Sleep has no suggestion.
Health-fed quests whose metric never synced are left out.
The summary is "N of M quests done." plus the open quest closest to done plus the habit count.
With the Claude key set, the summary is reworded once per person and day (`plan_polish` claims the day's single call, so a failure is never retried that day), shown only while the set of done and open quests is the same as when it was written, and rejected when it contains a number the facts do not.

Recap rules (`internal/recap`).
Per ISO week and person: points (base plus bonus of the stored day scores), counted days, steps (sum), average asleep minutes over recorded nights, workouts, reading plus listening minutes; the pair adds them (sleep weighted by nights).
Best day is the most points, earliest on a tie.
The suggestion is the first match of: fewer than 4 counted days in a completed week, steps down more than 10% on the week before, average sleep under 7 h over at least 3 nights, no workouts, points down on the week before, otherwise "beat N points".
The scheduler pushes each person's summary line once on Sunday from 19:00 in their zone (`notice_log` kind `weekly_recap`).

Goal proposals (`internal/goals`).
Steps: the `GET /insights` suggestion when it differs from the goal by 500 or more.
A steps raise also needs the goal met on at least 10 of the 14 days before today; lowering is always allowed.
Nothing about calories is ever proposed.
Sleep: when at least 5 of the last 14 nights are recorded and their average is 45 minutes or more under the target, the target moves halfway toward the average, rounded to 15 minutes, never under 5 h and never under the average.
Only enabled quests get proposals.
A proposal is stored per ISO week when first shown and frozen; one that no longer matches the template target is recomputed; accepted and dismissed ones do not return until next Monday.

Nudges (`internal/nudge`, run by the scheduler on every pass, so every 5 minutes).
All times are the person's local time, each kind is sent at most once per local day (claimed in `notice_log` before sending) and only when push is on and the person's preference allows it.
Budget: at most 2 automatic pushes per person per local day across behind pace, close to done, wind down, morning plan and the Sunday recap (counted from `notice_log`); cheers, challenge, reward and partner-done do not count.
When the budget is tight the order is close to done, behind pace, wind down; the morning plan goes only as the first push of the day, and the recap is skipped when the budget is spent.
Behind pace and close to done are never sent when today's readiness is `easy`.
No wording says "behind"; the behind-pace push reads "2,100 steps to go. A 20-minute walk does it." under the title "Steps to go".
Nothing but the wind down is sent from 21:30 to 07:30.
Behind pace: in the two-hour windows from 14:00 (`nudge_behind_14`) and from 18:30 (`nudge_behind_1830`), when today's steps reading exists, the steps quest is on and not done, and steps are under 85% of the expected steps so far.
Expected is the usual daily steps (14-day median, capped at the goal; the goal itself without 5 days of history) times a curve of the share of a day normally walked: 0% at 07:00, 25% at 10:00, 50% at 14:00, 80% at 18:30, 100% at 22:00, linear between.
Close to done: the day has not counted and finishing one open quest would reach 70% of the day's base points; "One quest left: 10 push-ups finishes your day." when it is the only open quest, otherwise "10 push-ups would make today count."
Morning plan: at 08:00 or 30 minutes after the average wake time of the last 14 nights (at least 4 recorded), whichever is later, for three hours; title from the readiness level, body the first readiness reason and the plan summary.
Wind down: 45 minutes before the bedtime that meets the sleep target from the average wake time (rounded to 5 minutes), for 90 minutes, only when last night was at least 30 minutes short, sleep is a quest or at least 4 nights are recorded, and the nudge time is 18:00 or later (a bedtime after midnight is skipped): "Bed by 22:40 for 7 h 30."

Habit icon keys (Material rounded names): `check_circle`, `brush`, `clean_hands`, `bathtub`, `medication`, `vaccines`, `water_drop`, `local_cafe`, `restaurant`, `lunch_dining`, `fitness_center`, `directions_walk`, `directions_run`, `directions_bike`, `sports_gymnastics`, `self_improvement`, `spa`, `bedtime`, `wb_sunny`, `menu_book`, `edit_note`, `favorite`, `bolt`, `eco`, `star`, `pets`.

Wire types:

- `Log` is a tagged union.
  Activity: `{id, kind: "activity", type, quantity, unit, localDate, loggedAt}`.
  Meal: `{id, kind: "meal", name, kcal, protein, carbs, fat, fiber, localDate, loggedAt}`.
- `DayDetail`: `{date, basePoints, bonusPoints, points, maxBase, percent, counted, streakLine, quests: [QuestScore]}`.
  `points` is base plus bonus, `percent` is on base points, and `streakLine` is the percent a day needs to count.
- `QuestScore`: `{key, title, target, unit, targetAlt, unitAlt, actual, actualAlt, points, basePoints, bonusPoints, done, doneBy}`.
  `doneBy` (v6) is `{kind: "workout", type, minutes}` when a Health workout is what completed the quest (push-ups by a qualifying strength or hiit workout, yoga when workout minutes were needed to reach the target), otherwise null.
  `actual` stays the logged amount except for yoga, where it includes workout minutes.
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
- `PUT /health/workouts` and `PUT /health/sleep` are history, not day entries: the day window does not apply.
  Sleep nights do not change scoring.
  Workouts do since v6 (a qualifying strength or HIIT workout completes push-ups, yoga workouts add to yoga), so the PUT rescores every still-open day the batch touches, including the day an edited workout moved away from, in the same transaction and under the day locks.
  Workouts on a day past its grace window are stored but never rescore it.
- Workout item rules: `id` 1 to 100 characters, `type` one of `walking, running, cycling, strength, hiit, yoga, swimming, hiking, dance, climbing, other`, `source` 1 to 32 characters, none with control characters.
  `startedAt` is within the last 400 days and not more than 5 minutes ahead of the server, `endedAt` is after `startedAt` and not in the future.
  `durationMin` is above 0 (after rounding to a tenth) and at most 1440, `kcal` 0 to 20000, `distanceM` 0 to 1000000, `avgHr` 20 to 250; the last three may be null or absent.
  Stored values keep one decimal.
  `date` is the local date of `startedAt` in the caller's zone.
  The upsert replaces every field, so a re-sent or edited sample never duplicates.
- Sleep night rules: `date` is today or a past day within the last 400 days in the caller's zone; `bedAt` and `wakeAt` are instants with `wakeAt` after `bedAt`, at most 24 hours later and not in the future; the five minute fields are numbers from 0 to 1440, rounded to whole minutes; `source` as above.
  The upsert replaces the whole night.
  The server does not check that `date` matches the local date of `wakeAt`, or that the stage minutes add up.
- `GET /insights` rules are in `docs/design-v4.md` and are implemented in `server/internal/insights`.
- API changes inside a release are additive.
  Removals wait one release.
- `/api/health` returns `{status, version}`.
  The binary supports `-healthcheck`, which calls `127.0.0.1:8080/api/health` and exits 0 or 1; the compose healthcheck uses it.
- Version is built in with `-ldflags -X main.version=$VERSION`.

### Endpoints, v7 additions

All additive.

- `GET /today` gains `freezes {held, earnedTowardNext}`, `repair {date, until, progressPercent}` or null (only on the caller's local today, while yesterday is a missed unfrozen day and before 22:00), `away {today, current, upcoming}` and `newMilestones` (milestones reached yesterday or today). `streak.restAvailable` now means a freeze is held and `restUsedOn` the last frozen day of the week.
- `GET /board` gains `sharedStreak {current, best}` and, per person, `freezes`, `away` and `last7[].frozen|away|repaired`.
- `POST /away {from, to, note}`: from today to 14 days ahead, 1 to 14 days long, no overlap with an existing span (409 `away_overlap`); `DELETE /away/{id}` (204). Days already settled as away keep that outcome.
- `POST /streak/cover {date}`: spends one of the caller's freezes on the partner's missed yesterday until 10:00 their next day, when the partner holds no freeze and the day has not counted (422 `cover_closed`, `no_freeze`; 409 when already covered). A cover on a day that ends up counted is deleted at settle time, which refunds the freeze.
- `GET /me` and `PATCH /me` gain `schedule {workdays: [1..7], workday {wake, bed}, dayOff {wake, bed}, firstNotificationOffsetMin 0..120}` (defaults 07:00, 23:00, Monday to Friday, 10), `protein {perKg, auto, weightKg, suggested, effective}` and the notification switches `milestones` and `lookback`.
- `POST /logs` accepts `kind activity, type other` with `name` (1 to 60), `minutes` (or `quantity`, 1 to 1440) and `intensity easy|moderate|hard`. Moderate and hard minutes count fully and easy half toward the exercise quest, together with Health's exercise minutes; a logged activity also connects the exercise quest before Health reports anything.
- `GET /goals/proposals` gains `kind` (`target` or `enable`) and the keys `exercise` (enable only), `sleep` (enable while off, target while on) and `protein` (target, when the current target is 20% or more away from 1.6 g/kg of the latest weight).
- `GET /insights` gains `weight {latestKg, smoothedKg, weeklyRateKg, points}` (EWMA, alpha 0.1), `activity` (last 7 days against the WHO 2020 guideline: moderate, vigorous and moderate-equivalent minutes, strength days, targets 150 to 300 and 2) and `protein {targetG, perKg, weightKg, suggestedG, daysHit7, days7, hitRate7}`.
- `GET /progress?window=30` (7 to 365): per person, for 12 metrics, `current`, `previous`, `first`, `changeFromPrevious`, `changeFromFirst` (`abs`, `pct`, `better`), `goodDirection`, a weekly `series` and a plain `summary`.
- `GET /lookback?month=YYYY-MM` (default the last completed month): per person and for the couple, month value, previous month, first 30 days, changes and `improvements` (the three biggest).
- `GET /milestones`: the caller's and the couple's milestones, newest first.
- `challenge` on `/board` gains `people [{userId, name, color, target, progress, done}]`; `target` is the sum of the shares and `progress` adds each person's progress capped at their own share. It completes when every person reached their own share.

### Endpoints, v8 additions

All additive; the formulas, labels and citations are in `docs/design-v8.md`.

- `GET /me`, `PATCH /me` and the `user` object of `POST /join` gain `heightCm` (100 to 250, one decimal, or null), `sex` (`male`, `female` or null) and `goal {kind: lose|maintain|gain, paceKgPerWeek}`. A patch sends `heightCm` and `sex` (null clears) and `goal: {kind, paceKgPerWeek}`. Lose is 0.25 or 0.5, gain a multiple of 0.05 up to 1 (limited to 0.5% of body weight when the target is computed), maintain 0; anything else is 422.
- `PUT /health/daily` accepts the metric `height_cm` (100 to 250).
- `GET /targets`: `{asOf, disclaimer, inputs, targets, sources}`.
  - `inputs[] {key: weightKg|heightCm|age|sex|goal|steps14, value, unit, source: profile|health|missing, note}`; weight is the v7 smoothed trend, height is the profile value or else Health's, steps14 is the average of the days with steps in the 14 complete days before today (at least 5 days).
  - `targets[] {key, value, unit, current, formula, sources, label: guideline|convention|derivation, missing, applicable, details}` for `restingEnergy`, `maintenance`, `estimatedFromLogs`, `calories`, `protein`, `fat`, `saturatedFatMax`, `carbs`, `fiber`, `sleep`, `activity`, `steps` and `pushups`. `value` is null when an input is missing and `missing` says which; `formula` is one plain sentence with the numbers plugged in; `current` is the setting in force; `details` carries the extras (pace options, bedtime, 7-night shortfall, Sleep Regularity Index, WHO week, push-up sets).
  - `sources` maps every source key a target cites to its citation.
- `POST /targets/apply {keys}`: sets `calories`, `protein`, `fat` and `carbs` on the profile targets and `steps`, `sleep`, `pushups` and `water` (v16, `docs/design-v16-water.md`) on the quest templates, through the same path as `PATCH /me` (open days are scored first, so a change starts tomorrow, except on the join day). All or nothing: an unknown or non-applicable key, or one with no value yet, is 422. 200 is the `GET /me` body plus `applied`.
- `POST /pushups/max {reps: 1..1000, date?}`: records a max test (one a day, a second replaces it) and answers 201 `{date, reps}`. The date follows the log rules (today, or yesterday inside the grace window).
- `GET /goals/proposals` gains the key `calories` (profile target, offered only when the person has one), and the `protein` proposal now follows the v8 goal-aware formula. Either is also offered when the formula value moved by more than 5% (100 kcal for calories) since its baseline because an input changed.

### Endpoints, v11 to v14 additions

All additive; the reasons are in `docs/design-v11.md` to `docs/design-v14.md`.

- Days carry `goalPercent` (base points against 70% of the possible points, so 100 is a counted day) beside `percent`.
- Habits carry `minutes`, `proposedPoints` and `proposedMinutes`; `GET /habits/proposals`, `POST /habits/{id}/approve` and `/decline` answer a partner's proposal.
- `POST /training/today/full` takes the full session on an eased day; sessions carry `eased` and `easedReason`.
- `POST /training/today/pull {"dayIndex": n}` starts a plan day as today's session on a rest day (v14); a rest day's `GET /training/today` returns that session with `restDay` true.
- `GET /exercises/{key}/images/{n}` serves how-to photos; exercises carry `steps`, `cues`, `imageUrls`, `kind` and `perSide`.
- `GET /training/history?month=YYYY-MM` and `GET /exercises/{key}/history?days=N` back the calendar and the strength chart.
- `GET /foods/barcode/{code}` looks a product up; food candidates carry `imageUrl` and `sourceUrl`.
- `GET /rewards` returns `reward` (the focus), `rewards`, `history`, `bank` and `priceHelp`; `PATCH` and `DELETE /rewards/{id}` and `/approve`, `/decline`, `/cancel`, `/focus` and `/claim` manage the wishlist. A create with the old `target` field and no `price` is approved at once for builds without approvals.
- `GET /me` and `PATCH /me` carry the partner-nudge, cover and approvals switches; challenges carry `reason` and `missed`, and `/board` a nullable `lastChallenge`.

### Endpoints, v10 additions

All additive; the reasons are in `docs/design-v10.md`.

- Habits carry `points` (0, 10, 25 or 50, default 25) on `GET/POST/PATCH /habits` and in Today's habit states; a due habit adds its points to the day's `maxBase` and its completed share to `basePoints`, replacing the flat habit bonus.
- `GET /me` and `PATCH /me` carry `units` (`metric`, `imperial`, or null before it was chosen); goal paces accept 0.2 to 0.5 kg a week to lose and 0.05 to 1 to gain.
- `schedule.firstNotificationOffsetMin` accepts 0 to 360.
- `PUT /health/history {items}`: up to 200 readings for closed days up to ten years back, stored only where none exists and never rescored; answers `{stored, received}`.
- Server-written text (target formulas, the protein goal reason, training reasons, the look-back push) follows the person's units.

### Endpoints, v9 additions

All additive; the rules and citations are in `docs/design-v9.md`.

- `GET /exercises`: `{exercises, muscles, equipment}`; each exercise has `key, name, primaryMuscles, secondaryMuscles, measure, load, equipment, easierKey, harderKey, custom, best, maxTest`, where `best` is the strongest set (with `e1rmKg` for loaded work) and `maxTest` the latest max test.
- `POST /exercises`, `PATCH /exercises/{key}` and `DELETE /exercises/{key}` manage the caller's custom exercises; deleting keeps the sets.
- `POST /exercises/{key}/max {reps|seconds, date?}` records a max test; a push-up max also writes the v8 push-up max.
- `POST /sets {clientOpId, exercise, reps|seconds, loadKg?, rir?, sessionId?, date?}` logs a set once per op id (201, or 200 on replay) and answers with the rescored day; push-up sets count toward the push-ups quest. `DELETE /sets/{id}` soft deletes and rescores. `GET /sets?exercise=&days=` lists live sets.
- `GET /training/profile` and `PUT /training/profile {equipment, dumbbellMaxKg, daysPerWeek 2..6, sessionMinutes 20..90, experience new|some|experienced, focus}`.
- `POST /training/plan {weeks?}` designs a plan with Claude and validates it (201, 404 `training_disabled` without a key, 422 `no_training_profile`, 422 `plan_invalid` with `violations`, 502 `planner_unavailable`, 429 after 10 a day). `GET /training/plan`, `POST /training/plan/change {kind: swap|bodyweight|shorter|pain|new_block, detail}` and `DELETE /training/plan`.
- `GET /training/today`: `{date, plan, session, restDay, blockEnded}`; the session lists each exercise with its plan prescription, the progression `target {exercise, sets, amount, loadKg}`, the `reason` and the sets logged today.
- `POST /training/sessions/{id}/complete` completes the session and answers with the rescored day; the push-ups quest then has `doneBy {kind: session, type: <plan-day label>}`.
- `GET /training/progress`: hard sets per muscle for the last four ISO weeks against the evidence `range`.
- `GET /lookback` gains `people[].lifts[] {key, name, measure: reps|seconds|e1rm, value, best, first, firstMonth}`.


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

-- migration 0006
CREATE TABLE workouts (
    id           BIGSERIAL PRIMARY KEY,
    user_id      BIGINT NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    health_id    TEXT NOT NULL CHECK (char_length(health_id) BETWEEN 1 AND 100),
    type         TEXT NOT NULL CHECK (type IN ('walking', 'running', 'cycling', 'strength', 'hiit',
                     'yoga', 'swimming', 'hiking', 'dance', 'climbing', 'other')),
    local_date   DATE NOT NULL,
    started_at   TIMESTAMPTZ NOT NULL,
    ended_at     TIMESTAMPTZ NOT NULL,
    duration_min NUMERIC(6,1) NOT NULL CHECK (duration_min > 0 AND duration_min <= 1440),
    kcal         NUMERIC(7,1) CHECK (kcal BETWEEN 0 AND 20000),
    distance_m   NUMERIC(9,1) CHECK (distance_m BETWEEN 0 AND 1000000),
    avg_hr       NUMERIC(4,1) CHECK (avg_hr BETWEEN 20 AND 250),
    source       TEXT NOT NULL CHECK (char_length(source) BETWEEN 1 AND 32),
    updated_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (user_id, health_id),
    CHECK (ended_at > started_at)
);
CREATE INDEX workouts_user_day ON workouts (user_id, local_date DESC);

CREATE TABLE sleep_nights (
    user_id    BIGINT NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    local_date DATE NOT NULL,
    bed_at     TIMESTAMPTZ NOT NULL,
    wake_at    TIMESTAMPTZ NOT NULL,
    asleep_min INTEGER NOT NULL CHECK (asleep_min BETWEEN 0 AND 1440),
    deep_min   INTEGER NOT NULL CHECK (deep_min BETWEEN 0 AND 1440),
    rem_min    INTEGER NOT NULL CHECK (rem_min BETWEEN 0 AND 1440),
    core_min   INTEGER NOT NULL CHECK (core_min BETWEEN 0 AND 1440),
    awake_min  INTEGER NOT NULL CHECK (awake_min BETWEEN 0 AND 1440),
    source     TEXT NOT NULL CHECK (char_length(source) BETWEEN 1 AND 32),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (user_id, local_date),
    CHECK (wake_at > bed_at AND wake_at - bed_at <= interval '24 hours')
);

ALTER TABLE users ADD COLUMN birth_year INTEGER CHECK (birth_year BETWEEN 1900 AND 2100);
-- the API narrows the upper bound to the current year
```

Notes:

- There is no stored streak.
- Join creates the user, the six templates (yoga disabled), the device, and snapshots every writable date, in one transaction.
- `first_local_date` is `localToday`, or `localToday - 1` when the join happens before 10:00 local.
- Template targets and `points` are copied into `day_quests`, so later template edits never change an existing day.

Migration 0007 `v5_habits_together_push.sql` adds the v5 tables (see `docs/design-v5.md`):

- `habits` (user, name, icon, kind check|count, `weekdays` bitmask with bit 0 = Monday, `slots` JSONB array of `{label, time}`, `target`, `position`, `paused`, `deleted_at`) with CHECKs tying slots and target to the kind.
- `habit_marks` (habit, local_date, slot, count; primary key on the first three): one row per done check slot, or one row at slot 0 holding a count habit's total.
- `cheers` (from, to, kind, sender-local `local_date`, `created_at`; unique per sender, recipient, kind and day).
- `challenges` (one per `week_start`, kind, title, frozen target, `completed_at`) and `challenge_awards` (primary key challenge + user, `local_date`, points): scoring reads the awards as a per-day bonus input.
- `rewards` (name, target, `baseline` combined points at the start, `reached_at`, `claimed_at`); a partial unique index allows one row with `reached_at IS NULL`.
- `push_tokens` (one per device, token unique), `notice_log` (event dedupe, primary key kind + user + date), and four `users.notify_*` booleans defaulting to true.

Migration 0008 `v6_autopilot.sql` adds (see `docs/design-v6.md`):

- five more `users.notify_*` booleans (`behind_pace` and `wind_down` default false, the rest true): `behind_pace`, `close_to_done`, `wind_down`, `morning_plan`, `weekly_recap`.
- `plan_polish` (primary key user + `local_date`, `facts_key`, `text` nullable, `attempted_at`): the row is the claim on the day's single Claude call and `text` the cached wording.
- `goal_proposals` (primary key user + `week_start` + `key` steps|sleep, `current`, `proposed`, `reason`, `state` pending|accepted|dismissed, `decided_at`).
- The nudge and recap pushes reuse `notice_log` with the new kinds; no other table changed.

#### Migrations 0017 to 0024 (v11 to v13)

- 0017 habit minutes and proposals; 0018 eased sessions; 0019 exercise how-to; 0020 shared rewards; 0021 challenge kinds, missed state and notification switches; 0022 stretches (`exercises.kind`, `per_side`); 0023 held pushes; 0024 the approved price kept during a price change.

#### Migrations 0015 and 0016 (v10)

- `users.units` (null until chosen) and `habits.points` (0, 10, 25 or 50, default 25).
- `first_notification_offset_min` may be up to 360.

#### Migrations 0013 and 0014 (v9)

- `exercises`: the seeded catalog (key, name, primary and secondary muscles, `measure` reps|seconds, `load` bodyweight|external, equipment, easier and harder keys, position) plus custom rows with a `user_id`.
- `exercise_sets` (reps or seconds, optional `load_kg` and `rir`, optional `session_id`, soft delete, unique on user + `client_op_id`) and `exercise_max_tests`.
- `training_profiles` (one row per person), `training_plans` (weekly template as JSONB, one active plan per person) and `training_sessions` (one per person and date, `completed_at`).

#### Migrations 0011 and 0012 (v8)

- `users`: `height_cm`, `sex`, `goal_kind` (default maintain) and `goal_pace_kg`; `health_daily` accepts the metric `height_cm`.
- `pushup_max_tests` (primary key user + `local_date`, `reps`).
- `target_baselines` (primary key user + `key` calories|protein, `value`, `inputs` JSONB, `set_on`): the formula value and inputs when a target was last applied, accepted, dismissed or first seen.
- `goal_proposals` accepts the key `calories` and reasons up to 600 characters.

#### Migration 0009 (v7)

- `day_scores`: `frozen_reason`, `away`, `settled` (all finalized days at migration time are settled).
- `users`: `streak_rules_from`, `protein_auto`, `workdays`, `workday_wake_min`, `workday_bed_min`, `dayoff_wake_min`, `dayoff_bed_min`, `first_notification_offset_min`, `notify_milestones`, `notify_lookback`.
- New tables `away_spans`, `streak_covers`, `challenge_shares`, `milestones`.
- `activity_logs`: type `other_minutes`, columns `name` and `intensity`; `goal_proposals`: `kind` and the keys `exercise` and `protein`.

### Scheduler

One goroutine under `recover` and a per-run context timeout runs on boot and every 5 minutes.
For each live user, in the user's timezone, it finds every `local_date` from `first_local_date` with no `day_scores` row that has `finalized_at` set, and where `now >= time.Date(y, m, d+1, 10, 0, 0, 0, loc)`.
For each such date, in one transaction with the advisory lock, it runs `ensureSnapshot`, `scoreDay`, and upserts the row with `finalized_at = now()`.
Catch-up after restarts and deploys is therefore automatic, and no day is skipped.
It also applies pending timezone switches that have come due.
Each pass also settles the streak outcomes of finalized days, applies repairs, sends the monthly look-back push (on the 1st, first), the v6 nudges and the Sunday recap push, and records milestones with their pushes; these only send while push is on.
Nudges follow each person's schedule: nothing before wake plus the offset or from bedtime on, the morning plan at the first notification, the wind down 45 minutes before bedtime, and nothing on an away day.

When `NEWME_ABS_URL` is set, a second loop under the same guards polls every 5 minutes (and on boot) for each linked account; `POST /me/audiobookshelf/sync` runs the same sync for one person on demand.
It refreshes the Audiobookshelf session when the access token is within 2 minutes of expiring, or once when Audiobookshelf answers 401, and stores the rotated refresh token before using the new access token.
It reads `GET /api/me/listening-sessions` (50 per page, newest update first) until a session predates the earliest open day, sums `timeListening` per local date of each session's `startedAt` in the person's zone, and for the still-open local dates (today, and yesterday until its 10:00 grace ends, never before the join date) stores `floor(seconds / 60)` capped at 1440 in `listening_daily`.
Only a changed value writes and rescores the day, in one transaction under the day lock; finalized days are never touched.
A rejected sign-in records `last_error = auth_failed` and keeps the link, a network or server failure records `unreachable`, and the next good poll clears it.
Linking runs one poll straight away.
A session spanning midnight counts wholly toward the day it started; Audiobookshelf's own `TZ` is irrelevant.

Each scheduler pass then calls the shared settle step (`internal/together`): it makes sure the week's challenge exists, completes a challenge or reward that has been earned (writes the awards in one transaction and rescoring both people's day), and announces a partner whose day just counted.
The same step runs after every write that can change progress (`POST /logs`, `DELETE /logs/{id}`, the Health `PUT`s, habit marks) and on board and reward reads, so the scheduler only catches what no request saw, such as a listening poll.
Every effect happens once: the challenge completes through `UPDATE ... WHERE completed_at IS NULL`, awards are keyed by challenge and user, a reward through `reached_at IS NULL`, and the partner push through `notice_log`.
Push messages go through a bounded queue (64) with two workers, so APNs being slow, down or misconfigured never delays or fails a request; failures are logged, and a 410 or `BadDeviceToken` removes the token.

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
- `Runner.entitlements`: `com.apple.developer.healthkit = true`, `com.apple.developer.healthkit.access = []`, HealthKit background delivery, `aps-environment` and time-sensitive notifications for partner pushes, the App Group `group.top.npcserver.newme` shared with the widgets and the Watch, and `keychain-access-groups = [$(AppIdentifierPrefix)top.npcserver.newme]`.
- `Info.plist`: `NSHealthShareUsageDescription`, `NSHealthUpdateUsageDescription` ("New Me never writes to Health."), `ITSAppUsesNonExemptEncryption` false, portrait only, no `UIBackgroundModes`, no URL scheme, no Firebase keys. `CFBundleDisplayName` is "New Me".
- Manual signing in Release with Apple Distribution for team 76S78SUWVM, profile "New Me App Store Distribution", `ExportOptions.plist` adapted from check-in with the new bundle id.
- App icon: generated once from `assets/brand/icon.svg` with ImageMagick into `AppIcon.appiconset`.
  Dark canvas, accent glyph of two overlapping rounded rings forming a rising arc.
  It is also the in-app logo.

### Widgets and Watch (v6)

Targets in `Runner.xcodeproj`, added by hand and kept on CocoaPods (the Podfile only names Runner):

| Target | Bundle id | Platform | Profile |
| --- | --- | --- | --- |
| `NewMeWidgets` (app extension, embedded by Runner's "Embed Foundation Extensions") | `top.npcserver.newme.widgets` | iOS 17 | "New Me Widgets App Store" |
| `NewMeWatch` (single-target SwiftUI app, embedded by Runner's "Embed Watch Content") | `top.npcserver.newme.watchkitapp` | watchOS 10 | "New Me Watch App Store" |
| `NewMeComplication` (watchOS widget extension, embedded by `NewMeWatch`'s "Embed Foundation Extensions") | `top.npcserver.newme.watchkitapp.widgets` | watchOS 10 | "New Me Watch Widgets App Store" |

- All three take `Flutter/Companion.xcconfig`, which includes `Generated.xcconfig` and sets `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` from `FLUTTER_BUILD_NAME` and `FLUTTER_BUILD_NUMBER`, so every embedded bundle carries the app's version and build number.
- Release signs manually with Apple Distribution for team 76S78SUWVM; Debug and Profile use automatic signing, and CI's `--no-codesign` build signs nothing.
- The embed phases sit before "Thin Binary", which avoids the Xcode build cycle Flutter projects hit with extensions.
- `NewMeWatch/Info.plist` names `WKCompanionAppBundleIdentifier` literally, which is how `flutter build` detects the Watch app and stops passing `-sdk iphoneos`.
- `app/ios/Shared/` holds the Swift every target compiles: `CompanionSnapshot.swift` (model, App Group store, applying a server answer), `CompanionAPI.swift` (habit marks and activity logs with `X-App-Key`, Bearer token and `X-Client-Version`) and `CompanionStyle.swift` (warm palette, rounded system font, ring, Material to SF Symbol map).

The snapshot:

- Dart builds it in `lib/companion/companion_snapshot.dart` from the session and Today: version, date, name, accent fill and tint, points, percent, streak line, counted, streak, quests (key, title, done), one habit entry per check slot or count habit (habit id, slot or null, name, label, icon, done, count, target, time), and the session (base URL, token, app key, client version).
- `CompanionController` (`lib/state/companion.dart`, started by `HomeShell`) sends it over the `newme/widgets` channel whenever Today or the session changes and the JSON differs from the last one sent; sign-out sends `clear` from `SessionController.signOut` as well.
- `CompanionBridge` in `Runner/CompanionBridge.swift` writes it atomically to `companion-snapshot.json` in the App Group container (readable after first unlock), calls `WidgetCenter.shared.reloadAllTimelines()`, and passes it to the Watch with `updateApplicationContext`.
  An empty snapshot signs the widgets and the Watch out.
- The bridge is a no-op on web and when the plugin is missing.

Widgets (`NewMeWidgets/NewMeWidgets.swift`), one `NewMeToday` widget:

- Small: ring with points, "Day N" streak and percent.
- Medium: the same plus up to four habit buttons, undone first.
  A button runs `ToggleHabitIntent`: it flips the slot (or adds one to a count habit) in the snapshot, reloads, sends `PUT /api/habits/{id}/marks/{date}`, folds the answered score, quests and habit states back in, and undoes its own change if the server refuses.
- Lock Screen circular: capacity gauge with the percent.
  Rectangular: "62% · 180 pts", quests left, habits due.
- The timeline holds the current entry and a midnight entry that marks the snapshot stale, so yesterday's numbers are never shown as today's.

Watch (`NewMeWatch/`):

- Vertical pages: Today (ring, points, streak, percent, quests), Habits (tap to mark, with haptics) and Log (push-ups or reading minutes on the Digital Crown, then Save).
- Actions go straight to the API with the snapshot's session; with no network (or a 5xx) they go to the phone with `sendMessage`, and `WatchRelay` on the phone runs the same request, answers with the status and body, updates the phone's snapshot and asks Flutter to refetch Today.
- `WatchRelay` activates `WCSession` in `didFinishLaunchingWithOptions`, because a Watch message can wake the phone before any Flutter engine exists.
- The Watch saves each snapshot to its own App Group container for the complication.
- HealthKit is entitled and described in `Info.plist` (the profile carries it) but not read yet.

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
  It compiles the widget extension, the Watch app and the complication too.

### release.yml

Triggers: `push` to `main`, `schedule` with cron `17 6 1,15 * *`, and `workflow_dispatch`.
`workflow_dispatch` takes a boolean `dry_run`: `gh workflow run release.yml --ref <branch> -f dry_run=true` skips the tests, the tag, the image, the upload and the GitHub Release, and only builds, signs, exports, checks and validates the IPA from that branch, in its own concurrency group.
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
4. `app-store`: `macos-15`, checks out the version tag (the latest tag on schedule, the dispatched ref on a dry run), Flutter 3.47.0, `flutter config --no-enable-swift-package-manager`, CocoaPods, "Select latest Xcode" copied from check-in plus `xcodebuild -version`, manual signing with the four profiles (app, widgets, Watch, Watch complication), `test -n` on every secret, `flutter build ipa --dart-define=NEWME_APP_KEY=...`, `scripts/check-ipa.sh` (widgets, Watch app and complication embedded, every bundle on the app's version and build number, every signature valid), then `altool` upload and `scripts/asc-wait.sh`, or `altool --validate-app` on a dry run.
   - `ExportOptions.plist` maps `top.npcserver.newme`, `top.npcserver.newme.widgets`, `top.npcserver.newme.watchkitapp` and `top.npcserver.newme.watchkitapp.widgets` to their profile names.
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

Ten in total.

Shared with check-in (rotating the certificate means updating both repositories):

- `IOS_CERTIFICATE_BASE64`
- `IOS_CERTIFICATE_PASSWORD`
- `ASC_API_KEY_BASE64`
- `ASC_KEY_ID`
- `ASC_ISSUER_ID`

New for this app:

- `IOS_PROVISIONING_PROFILE_BASE64` ("New Me App Store Distribution")
- `IOS_WIDGET_PROFILE_BASE64` ("New Me Widgets App Store")
- `IOS_WATCH_PROFILE_BASE64` ("New Me Watch App Store")
- `IOS_WATCH_WIDGETS_PROFILE_BASE64` ("New Me Watch Widgets App Store")
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
4.
   For v6: register the App Group `group.top.npcserver.newme`, the bundle ids `top.npcserver.newme.widgets` (App Groups) and `top.npcserver.newme.watchkitapp` (HealthKit, App Groups), assign the group to all three ids, and create the "New Me Widgets App Store" and "New Me Watch App Store" profiles; regenerate the app profile so it carries the group.
5.
   For the complication: register `top.npcserver.newme.watchkitapp.widgets` with App Groups and the same group, and create the "New Me Watch Widgets App Store" profile.
   Apple refused `.complication` as unavailable, hence `.widgets`.

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
