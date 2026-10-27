# Design review: accepted changes

Source: four-lens adversarial review on 2026-10-26, synthesized, then adjusted by the orchestrator.
The overrides section wins over the accepted list where they conflict.

## Overrides (orchestrator decisions)

- Keep the app key (403 on missing or wrong key) and invite codes for every join after the first, but drop NEWME_BOOTSTRAP_CODE: the first POST /join while initialized is false needs no code. The operational rule stands: Nick joins before the TestFlight link is shared.
- Keep a CLI `server invite` subcommand (run via docker exec) that prints a fresh single-use code, as the recovery path if Nick reinstalls.
- Keep yoga as an activity log type and a quest template that is disabled by default (the user listed yoga). The Log sheet shows it only when the template is enabled.
- Keep NEWME_APP_KEY as a single value, not a comma-separated list; rotation is an .env change plus a rebuild and both users reinstall rarely.
- Keep minClientVersion in /server-info and the 426 handling, since it is cheap.
- Season 0 row starts on the date migration 0001 runs (current_date), not on a configurable env var; drop NEWME_SEASON_START.
- docs/research is not committed to the repo (it names personal schedules and health details). design.md must not contain work hours.
- Everything else in the accepted list applies as written.

## Accepted changes

### 1. 3 Day and backdating (replace the Day bullet)

Day = local calendar day in users.timezone. Logs and health upserts are accepted only for local_today, or for local_today-1 while local_now < 10:00 (constant GRACE_HOURS=10 in internal/score). Otherwise 422 {code:'date_closed'}. The app defaults every entry to today and shows a quiet 'Add to yesterday' toggle only before 10:00, using backdateUntil from /me and /today. Deletes obey the same window. A timezone change never rewrites existing local_date values and applies from the next day boundary. PATCH /me validates timezone with time.LoadLocation. The app sets the timezone from the device (flutter_timezone) on join and PATCHes it if the device zone changes.

Why: The server must decide the date, not the client. 04:00 is useless for Nadia, who is up around 03:00 and works 04:00-15:00; 10:00 covers both of them and still finalizes a day early the next morning.

### 2. 3 Recompute rule (replace section)

Every write path (POST/DELETE /logs, PUT /health/daily, PATCH /me quest edits) runs in one transaction: pg_advisory_xact_lock(user_id, date as int), ensureSnapshot(tx,user,date), the write, scoreDay(user,date), upsert into day_scores. Finalized days may be recomputed inside the window. Streak is NOT stored: drop day_scores.streak and derive it at read time from the user's counted flags with a pure internal/score.Streak function. day_scores gets finalized_at TIMESTAMPTZ NULL. Every log read filters deleted_at IS NULL through shared query helpers backed by partial indexes.

Why: Prevents the stale-last-writer race between a health PUT and a log POST on foreground sync, and removes the stored-streak cascade problem when a day is edited.

### 3. 3 Points (replace the first two bullets)

All point math is integer. Quest points = (points * min(actual,target) + target/2) / target. A completed quest adds a bonus of points/5, so templates require points % 5 = 0 (CHECK). Day percent is computed on BASE points only: sum(quest base points) * 100 / sum(template points), capped at 100, compared as base*100 >= 70*max (no floats). Bonus points count toward displayed day, week and season points on the Board but not toward percent or the streak. The server sends points and percent; the app never recomputes. Today shows 'Streak line: 70% - you are at 62%' and the ring draws a tick at 70%. A quest card shows a small '+20' chip when its bonus is earned.

Why: Resolves the contradiction where 100% needed 480 points and the 70% line was a number nobody could see. Percent on base points makes the threshold explainable in one sentence.

### 4. 3 Streak (replace the Streak bullet)

internal/score.Streak(days, today): iterate the user's finalized days ascending from their first local date (days before join are skipped; a missing date is a miss). n=0. Counted day: n++. Missed day: if n>0 AND no rest used in that day's ISO week (key = Monday date) AND the previous day was not itself a miss or rest, mark the rest as used for that week and keep n unchanged (the day is flagged 'rest'); otherwise n=0. A miss at n==0 consumes nothing. Two consecutive misses always break, including across the Sunday/Monday boundary. The allowance is per ISO week, unused rest does not carry over. Today is excluded until finalized: displayed = n through yesterday plus 1 if today is already counted. The streak is continuous across seasons; only points reset on Jan 1. Table-test: first week, three-day gap, Sun+Mon misses, backdated fill rescuing a gap, DST day. Today shows a rest chip ('Rest day ready' / 'Rest day used Tue'), the 7-day strip shows a hollow dot on a rest day, and the streak pill reads 'Day 1' instead of 0.

Why: The old rule gave different numbers depending on how each ambiguity was read. This makes the number reproducible from day_scores and visible to the users.

### 5. 3 Seasons

Seed both rows in migration 0001: Season 0 (starts_on = migration date, ends_on 2026-12-31) and Season 1 (starts_on 2027-01-01, ends_on NULL). Add btree_gist EXCLUDE USING gist (daterange(starts_on, COALESCE(ends_on,'infinity'),'[]') WITH &&) and CHECK (ends_on >= starts_on). Season lookup is by local_date. Week = Monday-start week clipped to the current season, so the week of Jan 1 shows only 2027 days. Remove POST /seasons from v1 (insert a row by SQL if ever needed). Streak is continuous across seasons.

Why: Without seeded rows the Board has no season on Jan 1, and ISO week 53 straddles the reset and contradicts 'everyone starts at zero'.

### 6. 3 Quest snapshot and templates

Replace 'generated when a day is first viewed' with ensureSnapshot(tx,user,date): INSERT ... SELECT FROM quest_templates WHERE enabled ON CONFLICT (user_id,local_date,key) DO NOTHING, called from every path that reads or writes a day and from the sweeper. Template edits (enabled, target) take effect from the next local day and the editor says 'Takes effect tomorrow'. Points values are fixed and not editable in v1. Admin cannot edit another user's templates. A protein template with no profile target snapshots a default of 100 g until the user sets one. Backfill for a date before a user's first snapshot uses current templates once at join time.

Why: Removes the write-on-GET race and the gameable lower-the-target-at-22:00 hole, and keeps the Board number meaningful without head-to-head.

### 7. 3 Metrics and quest list

Reading progress p = min(1, minutes/20 + pages/15), stored as target (minutes, 20) plus target_alt (pages, 15) on quest_templates and day_quests, shown as one bar labelled like '12 min + 5 pages'. Add metric active_energy (kcal burned from Health ACTIVE_ENERGY_BURNED) to the HealthKit sync and health_daily. It is shown on Today as 'burned 540 / eaten 1,850' and is not scored in v1. The meals_logged quest counts only meals with kcal > 0. Remove yoga as a log type, quest and metric from v1 (the generic activity_logs schema leaves room). Remove the Board 'Numbers' list.

Why: The user asked for steps and calories pulled from Health during the day; calories burned is the only reading of that from HealthKit, with eaten calories coming from meal entries. Yoga and the raw-numbers brag list were not asked for and the latter is the head-to-head the user declined.

### 8. 4 Access control and pairing (replace)

The app key is an abuse filter, not authentication; the device token is the real auth. Middleware order: recoverer, request id, Timeout(30s), 1 MB MaxBytesReader, app key, rate limit, token auth. A missing or wrong app key returns 403 {error,code:'bad_app_key'}, never 401, so the app does not sign the user out. 401 is reserved for bad or revoked tokens. NEWME_APP_KEYS is a comma-separated list for overlapping rotation, compared with subtle.ConstantTimeCompare. GET /api/health is exempt from the key. Pairing: GET /server-info returns only {name, initialized, joinOpen, minClientVersion}; no user list. The first POST /join (initialized=false) creates the admin and requires NEWME_BOOTSTRAP_CODE from the server env. Every later join and every re-pair requires a single-use invite code (>=64 bits, SHA-256 hash stored, 15 min TTL, locked after 5 wrong tries) created by the admin in Me or with `docker exec new-me /app/server invite`. NEWME_MAX_USERS=2 is enforced in the join transaction under the advisory lock. After a valid code, POST /join {code, name, color, timezone} creates a member, or {code, userId} re-pairs. Name uniqueness: UNIQUE(lower(name)) WHERE deleted_at IS NULL; colors must differ (409). Add DELETE /devices/me and call it from 'Leave this server'. Use check-in's ratelimit.go and trusted-proxy client IP (not RealIP): /join 5/min per IP, authenticated 120/min per device, PUT /health/daily 30/min; 429 with Retry-After. X-Client-Version below minClientVersion returns 426 and the app shows a blocking 'Update required' screen. Throttle devices.last_seen_at writes to once per 5 min.

Why: A key extractable from the IPA plus tap-a-name re-pair on a public host lets a stranger become Nick or claim admin first. This is the smallest scheme that closes it without passwords, and it recovers from a lost phone via docker exec. 403 for the key avoids the check-in 401-signs-out behavior on key rotation. Replaces the admin who edits users, removes DELETE /users and GET /users.

### 9. 4 Endpoints and wire format

JSON is camelCase everywhere (clientOpId, localDate, isAdmin) to match check-in; dates are 'YYYY-MM-DD', instants RFC 3339 UTC. Route groups: public (health, server-info), authLimited (join), requireAuth, requireAdmin. Remove GET /users, PATCH/DELETE /users/{id}, POST /seasons, GET /history (and the Me progress chart). Add GET /meals/recent?limit=20 (DISTINCT ON lower(name),kcal,protein,carbs,fat over BOTH users' meals, newest first, so Nadia can repeat what Nick entered). POST /logs returns the log plus the updated day score and is 201 first time and 200 with the same body on replay of the same (user_id, clientOpId); a replay of a deleted row does not undelete. GET /today and /me return localToday, backdateUntil, serverNow. GET /board returns per user {id,name,color,today:{points,percent,counted},week,season,streak,last7:[{date,percent,rest}],syncedAt} plus season. Logs are a tagged union {id,kind:'activity'|'meal',...}. Per-set caps at 422: reps <= 500, pages <= 2000, minutes <= 1440, kcal <= 10000.

Why: Aligns with the reference project, gives the screens the calls they need without fan-out, and removes endpoints for cut features.

### 10. 4 PUT /health/daily

Items {date, metric, value, source, measuredAt}. Whitelist metrics steps and active_energy. Batch max 50, one transaction, 422 with per-item errors. Upsert with ON CONFLICT (user_id,local_date,metric) DO UPDATE ... WHERE health_daily.measured_at <= EXCLUDED.measured_at so a stale retry or second device cannot lower a count. Date window as for logs. Recompute each affected date in the same transaction and return the affected day scores so the app skips a second GET /today.

Why: Steps are the biggest quest; a stale lower write must not reopen a completed quest.

### 11. 4 Schema (migration 0001)

steps, reps, minutes, pages, kcal, quest targets: INTEGER with CHECK (> 0 and the caps above). protein_g, carbs_g, fat_g, fiber_g: NUMERIC(6,1) CHECK >= 0, selected ::float8. health_daily.value: DOUBLE PRECISION, server rejects non-finite or out-of-range per metric. Activity type, quest key and health metric are CHECK-constrained text. client_op_id UUID NOT NULL with UNIQUE(user_id, client_op_id) on activity_logs and meal_logs; add updated_at. Add target_alt/unit_alt to quest_templates and day_quests. Add UNIQUE(user_id,key) on quest_templates; indexes on logs (user_id,local_date) WHERE deleted_at IS NULL, devices(user_id), day_scores(user_id,local_date DESC); add an invites table (hash, expires_at, used_at, attempts). Enforce a single live admin inside the join transaction.

Why: pgx cannot scan fractional NUMERIC into int64, nullable UNIQUE leaves retries unprotected, and unchecked values can wreck points.

### 12. 4 Jobs (replace)

One scheduler goroutine under recover and a context timeout runs on boot and every 5 minutes. For each user it finalizes every local_date with no finalized day_scores row where now in users.timezone >= date + 1 day + GRACE_HOURS (10 h), ensuring the snapshot and scoring each missing date since the user's first date (catch-up after restarts and deploys). Use time.In(loc) with date arithmetic for DST. Import _ "time/tzdata" so LoadLocation works in the distroless image.

Why: The single 00:10 server-time run was ill-defined across timezones and silently skipped days when watchtower restarted the container, which breaks streaks.

### 13. 4 Server health, version, dev CORS

/api/health returns {status, version} with a cached DB ping. The binary supports a -healthcheck flag (calls 127.0.0.1:8080/api/health) used by the compose healthcheck (30s interval, 20s start period). Build the version in with -ldflags -X main.version. Document that watchtower does not roll back; rollback means pinning NEWME_TAG to the previous :X.Y.Z in .env. Add dev-only CORS middleware behind NEWME_DEV_CORS=true allowing localhost origins and the X-App-Key, Authorization and X-Client-Version headers; never set in production compose. API changes within a release are additive only; removals wait one release.

Why: The key rule would otherwise make the container permanently unhealthy, and web visual review fails at CORS preflight.

### 14. 5 App structure and state

Replace the state/ line: sessionProvider (Notifier, one JSON blob {baseUrl,userId,token} under a single flutter_secure_storage key, read and written atomically; only non-secret prefs like healthPrompted and lastSyncedAt in shared_preferences; 'Leave this server' deletes the blob and calls DELETE /devices/me). apiClientProvider watches the session and takes the app key as a constructor parameter (const kAppKey = String.fromEnvironment('NEWME_APP_KEY'), asserted non-empty in release builds), and is the fake seam for tests. todayProvider and boardProvider are AsyncNotifiers refreshed with ref.invalidate. clockProvider and healthSourceProvider are overridable. Disable Riverpod's automatic retry (ProviderScope retry returns null). accentProvider derives from the session user's color. The log sheet generates clientOpId when it opens, not on submit.

Why: Seeded Notifiers do not express loading and error for server data, Keychain survives reinstall while prefs do not, and time logic is untestable without an injected clock.

### 15. 5 Theme and accent

Keep tokens.dart, accent.dart and the ThemeData block from check-in. accent_picker takes selected and onChanged instead of reading a provider; taken colors are disabled in the picker. Each Board column is wrapped in Theme(data: base.copyWith(extensions:[accentById(user.color)])). Theme the SnackBar once. Respect MediaQuery.disableAnimations. Animate on change only: ring sweep when points change, check animation on quest completion, count-up only on the first view of the day.

Why: A global accent cannot show two people in one frame, and animation on every open reads as decoration.

### 16. 5 Onboarding (replace)

On launch, probe the prefilled new-me.npc-server.top silently. Show the server field only behind a 'Change server' link or when the probe fails, with distinct copy for unreachable, wrong address and 'update required'. If initialized is false: 'What should we call you?' with the bootstrap code field, then color. Otherwise: invite code entry, then either 'I'm new' (name and color) or a re-pair user chip row (returned only after a valid code). Final optional, skippable step: connect Health. After a forced sign-out show 'You were signed out. Enter a code to come back.' with the server prefilled. Operational rule: complete the first join on Nick's phone before the TestFlight link is shared.

Why: Fewer steps for two people on one fixed server, and every pairing dead end now has copy and a recovery path.

### 17. 5 Today

Add a Food card under the quests: kcal eaten / target with a thin bar, then protein, carbs and fat as compact eaten/target rows plus 'burned N' from active_energy. It is not a quest and not scored. Unset targets are hidden and replaced by 'Set your targets' linking to Me. Tapping a quest card or the Food card opens a day detail sheet listing that day's entries (time, quantity) with swipe-to-delete and a 'Deleted - Undo' snackbar. Health states: if no steps row has ever arrived, the steps card is a 'Connect Health' card excluded from day max until the first sync; after healthPrompted is set, a zero with no row shows 'No steps yet. Open Health > Sharing > Apps > New Me and allow Steps.' There is no re-request button after the first prompt. Show the partner's 'synced Xh ago' under each Board column. Quest '+' opens the log sheet already on that metric.

Why: Without totals the macro entry has no payoff, typos have no fix, and iOS hides read denial so a denied user would otherwise sit at 0/8000 with a broken streak.

### 18. 5 Log sheet

Open on the last-used type. Pushup chips log immediately with an 'Added 20 - Undo' snackbar and keep a number pad for custom values; values above sanity limits (pushups > 200, pages > 300, kcal > 3000) ask for confirmation. Meal form: name, kcal, protein, carbs, fat; fiber behind 'More'. Save is disabled until quantity > 0 (or kcal > 0 for meals) with inline errors via AppTextField. Recent-meal chips come from /meals/recent (both users), log in one tap, and have a portion stepper (0.5, 0.75, 1, 1.25, 1.5, 2) that multiplies the stored macros; the form has the same stepper. Remove the yoga segment. A failed save keeps the sheet open with a retry, using the same clientOpId.

Why: Dinner is shared; repeating a partner's meal at a different portion in one tap keeps full-macro logging alive for both.

### 19. 5 Offline and errors

No local write queue in v1. Treat network errors and 5xx as offline, never as sign-out (only 401 signs out). Cache the last /today and /board response and show it under a slim 'Offline - updated 14:02' banner. Loading is a skeleton shaped like the ring plus three quest cards and a two-column Board skeleton. Error is centered text with 'Try again' that keeps cached data below it.

Why: The server will be down during redeploys; a cached screen and retryable sheet cover this without a sync engine.

### 20. 5 Board

If only one user exists, render the other column as a dashed placeholder 'Waiting for Nadia' with a short 'How she joins' sheet (TestFlight invite, open app, enter your code). Show one 7-day strip per user. Remove the Numbers list. Headline is today's points with day percent underneath and the streak with rest marks.

Why: Nick is alone for the first days, and a missing column looks broken.

### 21. 5 Me

Remove the progress chart and the admin user management. Admin section only has 'Create pairing code'. Quest editor allows enabled and target only, with the note 'Takes effect tomorrow'. Timezone defaults to the device zone.

Why: Matches the cuts above and the 'basic app' brief.

### 22. 5 HealthKit in v1 (replace)

Read STEPS via getTotalStepsInInterval(start, end, includeManualEntry: false) with start = local midnight on the device and end = now, plus ACTIVE_ENERGY_BURNED for the same interval. Also push yesterday's midnight-to-midnight values until 10:00. Sync on start, resume and pull to refresh through a single-flight controller; resume syncs at most every 5 minutes (injected clock), pull-to-refresh and first connect bypass the throttle, and the PUT is skipped when the value equals the last successfully pushed one. Drive it with AppLifecycleListener in the Notifier build, disposed with ref.onDispose. Permission is requested only from a user tap (Connect Health card or onboarding step), then healthPrompted is persisted. The Swift background-delivery shim moves into v1: it ships in M3 together with the first TestFlight build and before Season 0 scores count, since the user wants data pulled during the day. package:health is behind a conditional import (health_source_factory.dart with if (dart.library.io) 'healthkit_source.dart' defaulting to FakeHealthSource) and Health() is constructed lazily; add a flutter build web step to ci.yml.

Why: Foreground-only sync finalizes days short and breaks streaks, which contradicts the user's request. Manual Health entries would let anyone cheat the one competition. The conditional import keeps the web review build from crashing.

### 23. 5 Platform files (replace)

iOS deployment target 15.0 in the Podfile platform line, the post_install override, and all IPHONEOS_DEPLOYMENT_TARGET entries (package:health 13.3.2 requires 15.0; Flutter 3.47's template default is already 15.0, so correct the old 'template is 13, health needs 14' text and do not copy check-in's 13.0). Run flutter config --no-enable-swift-package-manager locally and in ci.yml and release.yml, as check-in found SPM leaves a white launch screen. Write Runner.entitlements fresh: com.apple.developer.healthkit = true, com.apple.developer.healthkit.access = [], keychain-access-groups = [$(AppIdentifierPrefix)top.npcserver.newme]; no aps-environment. Info.plist: NSHealthShareUsageDescription, NSHealthUpdateUsageDescription ('New Me never writes to Health.'), ITSAppUsesNonExemptEncryption=false, portrait only, no UIBackgroundModes in the first build (the shim adds it), no URL scheme, no Firebase keys. Copy the 'Select latest Xcode' step from check-in's release.yml and print xcodebuild -version.

Why: Copying check-in verbatim would fail the build, the signing profile, or App Store processing.

### 24. 6 CI and release (replace release bullets)

Put the schedule (cron '17 6 1,15 * *' plus workflow_dispatch) in release.yml so there is one run_number counter and one concurrency group. On schedule events the version job skips tagging and uses the latest tag, the app-store job checks out that tag, and docker and GitHub Release jobs run only on push. Delete the has_appstore gating; missing secrets fail the job (test -n). Add a failure() step that opens a GitHub issue and a keepalive step that re-enables the workflow. After altool upload, run scripts/asc-wait.sh which mints an ASC JWT and polls the build until processingState is VALID (fails on INVALID or 30 min timeout). Add a pre-build test -n on NEWME_APP_KEY. The release job needs [version, docker, app-store] and is created only after the processing check passes. Add a final deploy-verify job that polls https://new-me.npc-server.top/api/health until version equals the new version (15 min timeout). ci.yml gets a path-filtered macos-15 'flutter build ios --no-codesign' job for app/ios/**, pubspec.yaml and pubspec.lock. Dockerfile sets org.opencontainers.image.source; after the first push set the GHCR package public (or give watchtower a read:packages token) and record which.

Why: A separate rebuild workflow would collide on build numbers and could ship an untagged commit. A green upload does not mean a usable build, and Nick has no Mac to debug on.

### 25. 6 Secrets and Apple checklist (replace)

Five secrets are shared with check-in (IOS_CERTIFICATE_BASE64, IOS_CERTIFICATE_PASSWORD, ASC_API_KEY_BASE64, ASC_KEY_ID, ASC_ISSUER_ID; rotating the cert means updating both repos). New per app: IOS_PROVISIONING_PROFILE_BASE64 and NEWME_APP_KEY (openssl rand -hex 32; the web review build uses a different key). Replace 'same six iOS secrets' in section 2. Browser steps: create the App Store Connect app record with a unique App Store name such as 'New Me - Habits' (CFBundleDisplayName stays 'New Me'), accept pending agreements, invite Nadia under Users and Access, add her to an internal TestFlight group with automatic distribution. Scripted via the ASC API in this order: register bundle id top.npcserver.newme, enable HEALTHKIT, then create the 'New Me App Store Distribution' profile. Enable automatic updates in TestFlight on both phones.

Why: The old text contradicted itself, and app-record creation cannot be scripted. The profile must be created after the capability.

### 26. 6 Deployment (add compose spec)

compose at ~/docker-server/npc_projects/new-me. server: image ghcr.io/nc1107/new-me:${NEWME_TAG:-latest}, label com.centurylinklabs.watchtower.enable=true, Traefik labels (Host new-me.npc-server.top, websecure, tls.certresolver=cloudflare, middlewares=secureHeaders@file, port 8080, traefik.docker.network), healthcheck, mem_limit 256M. db: postgres:16-alpine pinned, no watchtower label, internal network only, pg_isready healthcheck. db-backup: prodrigestivill/postgres-backup-local:16 daily with KEEP_DAYS 7, WEEKS 4, MONTHS 6. .env: POSTGRES_PASSWORD, NEWME_APP_KEYS, NEWME_BOOTSTRAP_CODE, NEWME_TAG, NEWME_TRUSTED_PROXY_HOPS. Run one restore drill before M3. Record the actual scw-watchtower poll interval in docs.

Why: These are the usual first-deploy failures, and the data is health and food history with no backup stated.

### 27. 7 Milestones and 8 repo hygiene

M0 additionally includes the Apple setup session and a first TestFlight upload of the empty skeleton with the HealthKit entitlement and usage strings. M3 includes the Swift background-delivery shim; remove M4. Keep docs/research out of the public repo (move it to a private notes dir or .gitignore it) because it holds schedules and health details; design.md must contain no schedules. .gitignore: .env, backups/, *.p12, *.mobileprovision, AuthKey_*.p8, key.properties. Copy check-in's .githooks pre-push.

Why: Surfaces iOS signing problems in the cheapest milestone, and avoids publishing a person's work hours next to the server address.

## Rejected findings

- Product: 'Also log for Nadia' toggle creating a second meal_log with logged_by
  Rejected: Cross-user writes add a consent and schema surface. Recent-meal chips drawn from both users plus a portion stepper give the same one-tap repeat without it.
- Product: show the partner's targets via tap-through on Board and partner arc on the Today ring, per-user non-green accents, restyle of the visual language
  Rejected: Adds screens and diverges from the Onyx conventions the design must follow. Per-user accent from the saved color already differentiates people. Plain-copy and animate-on-change advice was taken in a smaller form.
- Product: local offline write queue for logs
  Rejected: A sync engine is not a basic v1. Cached screens, an offline banner, a retryable sheet and idempotent clientOpId cover the realistic failure.
- Product: 'Suggest my targets' calculator in Me (Mifflin-St Jeor)
  Rejected: Not requested and adds a form and formula to maintain. A default protein target at snapshot and the 'Set your targets' prompt are enough.
- Product: season recap card; show 'rest' marks beyond the strip; 'Nadia joined' animation
  Rejected: Decoration beyond a basic app. The streak-across-seasons statement was kept.
- Server: PATCH /logs/{id} edit endpoint, POST /admin/rescore, version column on templates
  Rejected: Delete plus re-add with undo covers editing. Rescoring is a one-off SQL or code change if rules change.
- Server: reading progress as max(minutes/20, pages/15)
  Rejected: Conflicts with the sum rule; the sum gives correct partial credit for mixed entries like 10 min plus 8 pages, so the sum was chosen.
- Server: 10 hour vs 04:00 server-enforced window as separate rules
  Rejected: Merged: the server enforces the window (server reviewer) but at 10:00 (product reviewer) because of Nadia's early schedule.
- Server: day_scores 'metric' and 'source' columns on quests, covering index details
  Rejected: The quest key already names the metric. Speculative columns not needed for v1.
- Ops: dead-man heartbeat to Uptime Kuma or healthchecks.io, gitleaks in CI, cert/profile expiry-check step, reusable ios-build workflow
  Rejected: More infrastructure than a two-person app needs. A twice-monthly cron with a failure issue and keepalive covers the 90-day risk; revisit if a rebuild is ever missed.
- Ops: Traefik rateLimit middleware and WATCHTOWER interval tuning
  Rejected: In-app limiter copied from check-in is enough. Only the poll interval is recorded, not changed.
- Flutter: lint-set note and kClientVersion drift test restated
  Rejected: Already covered by copying analysis_options and the existing drift test in the design; no change needed.
- Flutter: hasPermissions and explicit denied-state detection
  Rejected: iOS cannot report read denial, so the design uses healthPrompted plus a no-data hint instead.
- Product: drop day percent from the Board
  Rejected: Percent on base points is now the explainable streak metric and sits under points on the Board.