# Feasibility research digest

Generated 2026-10-26 from a 25-agent research and verification sweep.
Each topic was researched by one agent with web access, then a second agent tried to refute its strongest claims against primary sources.
Confidence tags: [H] high, [M] medium, [L] low, as judged by the researcher.
Raw structured output with every source URL is in `feasibility-raw.json`.

## healthkit-flutter

### Recommended approach

Hybrid: Flutter app using pub.dev 'health' (v13.3.2) for onboarding permission request and foreground/on-launch reads of almost everything (steps, workouts, sleep stages, weight/body fat/lean mass/BMI, resting HR, HRV, active energy, exercise time, stand, mindful, water, dietary energy). Add a small native Swift shim (MethodChannel plus AppDelegate, roughly 100-200 lines, my estimate) that (a) reads the two missing types, vo2Max and toothbrushingEvent, and (b) registers HKObserverQuery plus enableBackgroundDelivery for a handful of types (workouts, sleep, body mass, steps) using HKAnchoredObjectQuery with persisted anchors and a background URLSession upload straight to the Go/Postgres server, with completionHandler on every path. Treat background delivery as best-effort: also sync on every app foreground, schedule a BGAppRefreshTask, and have the server flag gaps. Send raw samples with UUID, source bundle ID, start/end plus UTC offset; dedupe and apply source priority (Watch over iPhone, Renpho for body composition) server-side and use HKStatisticsCollectionQuery for daily steps/energy totals. Compute your own sleep score server-side from sleep stages. Make toothbrushing a manual in-app tap with HealthKit as optional bonus. Test everything on physical devices.

### After verification

The hybrid recommendation stands with three adjustments. (1) Use health 13.3.2 for permissions and foreground reads. It is current and maintained. (2) Do not wait on or depend on PR #521. It is open, unreviewed and only build-verified. If you want background delivery without writing native code, you could vendor that branch behind a flag, but the Swift shim with HKObserverQuery, HKAnchoredObjectQuery, a background URLSession and the completion handler on every path (with a timeout) is the lower-risk choice. The shim also covers the two missing types, vo2Max and toothbrushingEvent. Verify toothbrushingEvent against Apple's docs when writing it. (3) Treat background delivery as best effort. Reports of it silently stopping exist (watchOS 26, 2-3 days, FB20692241 unresolved), so keep the sync on foreground, BGAppRefreshTask, and server-side gap flags. Never advance the anchor when a query fails (for example when the device is locked). Keep the manual toothbrushing tap as the primary source. health_connector is not a better option: it has the same lack of iOS observer support, 143 types rather than 150+, and low adoption. Sleep score: compute your own server-side. Re-check Apple's iOS 26 release notes for a public score API before finalizing.

Claims that did not survive unchanged:

- UNCERTAIN: 6. Background delivery stops after a day or two on watchOS 26; DTS confirmed known issue; FB20344425 closed works as designed; FB20692241 refiled
  Correction: DTS did not clearly confirm a platform bug; the 'as designed' response was about the missing-handler case, and the corrected-code case is still tracked in FB20692241 with no stated root cause. It is watchOS-hosted, 2-3 days not 'a day or two', and iPhone-side behavior is untested. Treat as 'unresolved reports of unreliable delivery', not 'confirmed known issue'. Thread 814914 claim unverified.
- UNCERTAIN: 8. No public Sleep Score API in HealthKit; score computed in Health app (duration 50, bedtime consistency 30, interruptions 20)
  Correction: Keep as medium-confidence: no public sleep score type found as of this check; verify against Apple's iOS 26 HealthKit release notes before relying on the absence. Computing your own score server-side is a safe plan either way.

### Cannot do or could not verify

- Cannot read the native Apple Sleep Score from HealthKit - no public API found.
- Cannot detect whether the user denied read permission - HealthKit returns empty results by design.
- Cannot guarantee background sync with the app terminated or the phone locked - protected data is unavailable while locked, and background delivery is best-effort with known watchOS 26 reliability issues.
- Cannot read VO2max or toothbrushing events with the 'health' package as-is.
- Cannot verify iPhone-side HKObserverQuery stability on iOS 26 from sources - only watchOS-side reports were found; it needs a physical device test.
- Cannot test HealthKit in the iOS Simulator with real Watch/Renpho data - physical devices are needed.

### Claims

- [H] Main maintained package is pub.dev 'health' v13.3.2, now published by carp.dk (repo moved to carp-dk/carp-health-flutter). It exposes 111 HealthDataType values. Present: STEPS, ACTIVE_ENERGY_BURNED, BASAL_ENERGY_BURNED, WORKOUT (+WORKOUT_ROUTE), SLEEP_* stages (ASLEEP, AWAKE, AWAKE_IN_BED, IN_BED, OUT_OF_BED, DEEP, LIGHT, REM, UNKNOWN, SESSION), WEIGHT, BODY_FAT_PERCENTAGE, LEAN_BODY_MASS, BODY_MASS_INDEX, HEIGHT, RESTING_HEART_RATE, HEART_RATE, HRV SDNN and RMSSD, EXERCISE_TIME, APPLE_STAND_TIME, APPLE_STAND_HOUR, APPLE_MOVE_TIME, MINDFULNESS, WATER, DIETARY_ENERGY_CONSUMED (+ many dietary macros/micros, NUTRITION), DISTANCE_WALKING_RUNNING, FLIGHTS_CLIMBED.
  Design implication: Covers nearly all required metrics out of the box, with the two gaps below. Workouts carry type/duration/distance/energy; heart rate per workout must be fetched as a separate HEART_RATE query over the workout window (not verified that the package attaches it).
  Sources: https://pub.dev/packages/health, https://pub.dev/documentation/health/latest/health/HealthDataType.html
- [H] The 'health' package has NO VO2MAX and NO TOOTHBRUSHING enum value (verified against the 111-value enum list). Both exist in HealthKit itself (vo2Max quantity type; toothbrushingEvent category type).
  Design implication: Reading VO2max and toothbrushing events requires a small native Swift shim (MethodChannel) or a fork/PR of the plugin. Alternative for toothbrushing: just make it an in-app manual/Watch-complication check-in and treat HealthKit as optional bonus. Brushing events from Apple Watch only exist when the user brushes with a connected Bluetooth/Watch-detected brush flow, so manual tap is the realistic baseline.
  Sources: https://pub.dev/documentation/health/latest/health/HealthDataType.html
- [H] The released 'health' package does not support HKObserverQuery / enableBackgroundDelivery on iOS (README never mentions it; only Android Health Connect background-read permission). A PR #521 (carp-health-flutter) adds registerBackgroundDeliveryCallback + configureBackgroundDelivery using three native iOS files (HKObserverManager, HKBackgroundDeliveryWorker running a headless FlutterEngine, HKDeliveryUserDefaults). It is OPEN, unreviewed, not merged, no device validation reported, and the engine crashes if run in foreground.
  Design implication: Do not depend on an unmerged PR. Background delivery needs native code. Using the 'health' package for foreground reads plus your own small shim for background wake-ups is the lowest-risk split.
  Sources: https://github.com/carp-dk/carp-health-flutter/pull/521, https://pub.dev/packages/health
- [M] Alternative package health_connector v3.14.0 (verified publisher, MIT, iOS+Android, 150+ types claimed, aggregateSum/Avg/Min/Max, incremental synchronize() with sync tokens). Maintainer explicitly declined to add HKObserverQuery background delivery (Sep 2026) and suggests the workmanager plugin plus synchronize(). VO2max and toothbrushing support not confirmed on the package page (a type catalog exists but was not fetched). Low adoption (~1.9k downloads).
  Design implication: Worth a look for its aggregation and anchored-style sync, but workmanager on iOS maps to BGTaskScheduler, which is opportunistic and not data-triggered. It is a weaker background mechanism than HKObserverQuery for this use case.
  Sources: https://pub.dev/packages/health_connector, https://github.com/fam-tung-lam/health_connector/issues/227
- [H] Native background pattern (Swift): create HKObserverQuery per type, call healthStore.enableBackgroundDelivery(for:frequency:) (.immediate/.hourly/.daily), and on wake query samples since last sync, upload, then call completionHandler on EVERY code path including errors. If the handler is not called, the system stops delivering. Requires the HealthKit background-delivery entitlement and registering observers in application(_:didFinishLaunching) so a cold relaunch re-arms them. Use a background URLSession for the upload, and send sample UUIDs as idempotency keys.
  Design implication: The shim is small: roughly 100-200 lines of Swift in AppDelegate (observers for steps, workouts, sleep, body mass, etc.; an HKAnchoredObjectQuery with persisted anchor per type; background URLSession POST of JSON to the server). It can bypass Dart entirely, which avoids the headless-engine fragility. Estimate is my inference, not a sourced figure.
  Sources: https://developer.apple.com/forums/thread/801627, https://openwearables.io/blog/getting-apple-health-data-into-your-backend
- [M] Background delivery reliability caveat: Apple Developer Forums report HKObserverQuery with background delivery on watchOS 26 stops delivering after a day or two even with the handler fixed. Apple DTS confirmed it as a known issue; feedback FB20344425 was closed as 'works as designed' and FB20692241 refiled. This thread is about watchOS-side apps; iPhone-side behaviour was not tested in the source. Other forum threads report variable frequency across devices.
  Design implication: Never rely on background delivery alone. Always also sync on app foreground/launch, on a BGAppRefreshTask, and have the server detect gaps. Daily sync is easy to satisfy with open-app catch-up plus best-effort background pushes.
  Sources: https://developer.apple.com/forums/thread/801627, https://developer.apple.com/forums/thread/814914
- [H] HealthKit read permissions are privacy-opaque: requestAuthorization success means the sheet was processed, not that read was granted. Denied or revoked read types simply return empty results indistinguishable from no data. Only write (share) status is queryable via authorizationStatus. Also the device must be unlocked to request data (plugin README) and protected health data is not readable while the phone is locked, which affects background wake-ups.
  Design implication: Build an in-app 'data collection checklist' where the user confirms each source (Watch worn, Renpho synced to Health) and detect staleness server-side (no steps for 48h means prompt them to check Settings > Health > Data Access). Request all read types in a single sheet at onboarding. Note the Apple doc fetch returned only a title, so the doc wording is from general knowledge, though the behaviour is long-established.
  Sources: https://developer.apple.com/documentation/healthkit/hkhealthstore/requestauthorization(toshare:read:completion:), https://pub.dev/packages/health, https://openwearables.io/blog/getting-apple-health-data-into-your-backend
- [M] watchOS 26 / iOS 26 Sleep Score: no public HealthKit type or developer API for the score was found. A developer forum post says none exists. Apple's score (0-100: duration 50, bedtime consistency 30, interruptions 20; stages not used) is computed in the Health app from sleep analysis data and also works with third-party sleep data. I could not retrieve Apple's iOS 26 HealthKit release notes to be sure.
  Design implication: Compute your own sleep score server-side from raw sleep-stage samples, using the published weighting (duration, bedtime consistency, interruptions) as a template. This also keeps scoring consistent and fair across both users. Re-verify against Apple HealthKit docs before building.
  Sources: https://developer.apple.com/forums/tags/health-and-fitness?page=3, https://www.macworld.com/article/2947066/i-dont-trust-my-apple-watchs-sleep-score-and-neither-should-you.html, https://9to5mac.com/2025/09/10/psa-the-new-sleep-score-feature-works-with-third-party-devices/
- [M] Dedup and source pitfalls: HealthKit merges iPhone, Watch, and third-party samples; one type can have multiple sources. The 'health' package offers removeDuplicates and, on iOS, a recording-method filter that only distinguishes automatic vs manual. Sample UUIDs should be used as idempotency keys. Sleep stage SLEEP_ASLEEP maps to asleepUnspecified and SLEEP_LIGHT maps to asleepCore on iOS. Overlapping sleep from Watch and iPhone or other apps needs merging.
  Design implication: Store raw samples with source bundle ID/device name, sample UUID, start/end ISO timestamps with UTC offset. Do dedup/priority server-side (e.g. Watch over iPhone for steps/HR/sleep, Renpho source for body mass) or use HKStatisticsCollectionQuery for steps/energy, which applies HealthKit's own source-priority merging. Plain sample sums of steps can double count iPhone+Watch. Timezone handling is my inference: store the user's local-day boundary at sample time rather than deriving it from the server timezone.
  Sources: https://pub.dev/packages/health, https://openwearables.io/blog/getting-apple-health-data-into-your-backend
- [L] Renpho scale data reaches HealthKit only if the Renpho app has Apple Health sync enabled; the data then shows as body mass, body fat %, lean body mass, BMI samples with Renpho as source. This is inferred and not verified from a source in this research.
  Design implication: Add a checklist step to verify Renpho > Apple Health toggle, and consume weight, body fat, and lean mass via the health package (all available types).
  Sources: 

### Alternatives considered

- Wait for or contribute to carp-health-flutter PR #521 for background delivery - open, unreviewed, headless-engine design, so risky as a dependency; a vendored fork is possible.
- Use health_connector (v3.14.0) with its synchronize() incremental tokens and workmanager - cross-platform and typed, but background wakeups are opportunistic via BGTaskScheduler rather than data-driven, and VO2max/toothbrushing coverage is unverified.
- Fully native Swift sync helper (the shim grown to cover all types), with Flutter handling only the UI - most reliable on background delivery, more Swift to maintain.
- Apple Shortcuts/Health Auto Export-style automation pushing to the server - zero native code but depends on third-party apps and automation triggers; not verified in this research.
- Open Wearables iOS SDK (mentioned in the cited article, native Swift) - not evaluated.

## renpho-scale

### Recommended approach

Primary path: each partner has their own Renpho Health account and profile on their own iPhone, Renpho writes to Apple Health, and the Flutter app reads HealthKit (weight, body fat %, BMI, lean body mass) via a plugin such as health, then uploads to the Go/Postgres backend tagged with the device owner. This is zero reverse engineering, per-person identity comes free from the phone, and it survives Renpho API changes. Add manual weight entry plus a sanity filter and 'not me' discard for mis-assigned weigh-ins, and a 'last synced' staleness indicator. Score on trends (4 HealthKit fields), not on absolute body-comp numbers, since BIA values are noisy and consumer-grade. Optional enrichment later: a Go poller against cloud.renpho.com using the hass-renpho-health protocol for visceral fat, water and muscle mass, treated as best-effort. Keep BLE-direct as a last resort stretch goal, gated on confirming scale HVIN.

### After verification

The primary path stands: each partner uses their own Renpho Health account and profile on their own iPhone, Renpho writes to Apple Health, and the Flutter app reads HealthKit through the health plugin (13.3.2, maintained). The plugin supports WEIGHT, BODY_FAT_PERCENTAGE, BODY_MASS_INDEX and LEAN_BODY_MASS on iOS. Three adjustments. First, treat weight and body fat % as the only fields guaranteed to be in HealthKit. The App Store text is inconsistent about the rest, so verify on a real device before building scoring on BMI or lean mass. Second, base the staleness indicator on the sample timestamp, since the scale buffers up to 20 offline readings and the Renpho app backfills them with the original time. Both partners must also open the Renpho app now and then. Third, keep the 'not me' discard and sanity filter, because profile auto-assignment on a shared scale is unverified third-party lore. Keep the cloud poller (hass-renpho-health protocol) as an optional best-effort enrichment for visceral fat, water and muscle mass. It is a 5-commit, 1-star reverse-engineered project that needs each partner's Renpho credentials. Keep BLE-direct as a last resort, gated on the HVIN sticker. It is only validated on macOS, reading stored records erases them from the official app, and iOS behavior is untested."

Claims that did not survive unchanged:

- UNCERTAIN: 2. Muscle mass, bone mass, body water, visceral fat, BMR and body age stay inside the Renpho app
  Correction: Muscle mass, bone mass and body water stay in-app per a secondary source. Visceral fat is not documented as synced. BMR/resting calories may sync, since the App Store text names resting calorie consumption. Body age is unverified. Confirm per type on the actual device.
- UNCERTAIN: 5. Renpho supports multiple profiles; auto-assignment is weight-based per third-party sources; failure reports exist
  Correction: Multiple profiles are confirmed. Weight-based auto-assignment and the misassignment anecdotes are unverified third-party claims. The design still holds, since the recommended path avoids shared-scale assignment ambiguity only if each partner's weigh-in lands on their own profile and phone. With one shared scale, misassignment risk remains, so keep the 'not me' discard and a sanity filter.
- UNCERTAIN: 7. BLE specifics: profile write within about 2 seconds, approximate body comp, stored-record deletion, macOS-only testing, openScale is Android-only
  Correction: Confirmed: 2 s window, stored-record deletion, macOS-only testing. Unverified here: the 0x03/0x04 approximation detail, the 'weight only without profile' behavior, and openScale being Android-only. Also note iOS CoreBluetooth background limits were not researched, so BLE-direct on iOS is untested territory.

### Cannot do or could not verify

- Could not confirm the exact HKQuantityTypeIdentifier list Renpho writes; only Renpho's own text naming body fat %, BMI, lean body mass (plus weight).
- Could not verify an official CSV export in the Renpho Health app.
- Could not verify Renpho's own documentation on how auto user recognition works or its weight-gap threshold; only third-party descriptions.
- Could not identify Nick's scale model/HVIN, so BLE protocol support is unconfirmed.
- Found no renpho2mqtt project; did not check Home Assistant's core BLE integration for Renpho support.
- Did not verify Flutter BLE plugins or iOS background BLE behavior with sources.

### Claims

- [H] Renpho Health app (blue icon) syncs to Apple Health: Body Fat Percentage, Body Mass Index and Lean Body Mass are explicitly named in the App Store text; weight is described as synced to HealthKit too. Likely HK types: bodyMass, bodyFatPercentage, bodyMassIndex, leanBodyMass (type names are inferred from Apple's standard identifiers, not stated by Renpho).
  Design implication: Treat HealthKit as guaranteeing only weight, BMI, body fat % and lean mass. Build trends and head-to-head body-comp scoring on those four and nothing else.
  Sources: https://apps.apple.com/us/app/renpho-health/id1543340610, https://sahha.ai/integrations/renpho/
- [M] Muscle mass, bone mass, body water %, visceral fat, BMR and metabolic/body age are reported to stay inside the Renpho app only (secondary source says Apple Health lacks matching fields; the App Store text also mentions resting-calorie data and height, unverified). Not independently confirmed per-type.
  Design implication: Do not depend on visceral fat, water or muscle mass from HealthKit. If wanted, they need the cloud API or BLE path. Verify empirically by querying HealthKit on a real device after one weigh-in.
  Sources: https://scorevitals.com/howtos/sync-smart-scale-to-apple-health, https://apps.apple.com/us/app/renpho-health/id1543340610
- [M] Apple Health sync from the Renpho app is phone-mediated: most Renpho models are Bluetooth, so data reaches HealthKit only when the Renpho app receives the reading (phone near scale, app able to connect). Some reviewers report flaky Apple Health sync. Each partner's HealthKit exists only on their own phone, which is correct for a two-user app.
  Design implication: The Flutter app should read HealthKit on each phone and upload to the Go backend, with a visible 'last weigh-in synced' timestamp and a manual weight entry fallback.
  Sources: https://gainframe.app/blog/renpho-scale-review/, https://apps.apple.com/us/app/renpho-health/id1543340610
- [L] No official public Renpho API. The App Store listing mentions shareable reports but I could not verify an official CSV export; one low-quality German how-to site claims a CSV export exists in the Health app.
  Design implication: Do not plan on a CSV import pipeline. Check the in-app settings once on a real device; if present it is only useful for a one-time historical backfill.
  Sources: https://apps.apple.com/us/app/renpho-health/id1543340610, https://www.antwort.net/a/technologie/wie-kann-man-daten-aus-der-renpho-health-app-exportieren.html
- [M] Unofficial cloud clients exist. Legacy Renpho-app API projects (antoinebou12/hass_renpho, neilzilla/hass-renpho) are reported broken or stale for newer accounts. StartupBros-com/hass-renpho-health targets the Renpho Health API at cloud.renpho.com, exposing weight, BMI, body fat, muscle mass, water, bone mass, visceral fat, BMR, body age, protein, subcutaneous fat, skeletal muscle; it uses reverse-engineered AES-128-ECB, polls 5 min minimum, and logs in with the user's app credentials. teknikqa/ha-renpho is similar and only tested on one live account. Wire protocol credited to forkerer/RenphoGarminSync-CLI and danvaneijck/renpho-api.
  Design implication: A Go backend poller using each partner's Renpho credentials is the only way to get the full panel (visceral fat, water, muscle etc.) without BLE. It is fragile: undocumented API, can break on any app update, and may log the partner out of the app. Use as optional enrichment, not as the primary path. I found no renpho2mqtt project in search.
  Sources: https://github.com/StartupBros-com/hass-renpho-health, https://github.com/teknikqa/ha-renpho, https://github.com/antoinebou12/hass_renpho, https://community.home-assistant.io/t/renpho-custom-integration/693771
- [M] Renpho multi-user: the app supports multiple profiles. Auto-assignment is weight-based (match weight to each profile's history), per third-party description only; no official doc found. Failure reports: a couple sharing one account saw duplicated stats, and a reviewer had a partner's weight land on their profile and the bad point lingered until superseded.
  Design implication: Give Nick and Nadia separate Renpho accounts/profiles on their own phones. If their weights are far apart, mis-assignment risk is low. Add backend sanity checks (reject a weigh-in more than a few percent or ~2 kg away from that person's recent value, prompt to confirm) and an 'it was not me' discard button.
  Sources: https://scienceinsights.org/how-does-a-renpho-scale-know-who-is-on-it/, https://www.techadvisor.com/article/722799/renpho-smart-body-fat-scale-3810502/, https://apps.apple.com/us/app/renpho-health/id1543340610
- [M] Direct BLE: most common Renpho family is the QN-Scale protocol (service 0xFFF0 style). Confirmed-working in the unofficial Python client: ES-CS20M (some revisions), ES-26M, ES-28ML, ES-30M, ES-32MD, R-MSB01. Experimental: ES-26BB-B, R-A012, R-A016, some ES-CS20M revisions on 0x55aa (GATT) or 0xaabb (broadcast, weight only). Newer ES-CS20M revisions (HVIN ESCS20MB2) use Renpho's own protocol on service 0x1A10. Marketed model name is unreliable; the HVIN sticker revision suffix determines protocol.
  Design implication: Before committing to BLE, read the HVIN on the underside of the Renpho scale and match it against these lists. The user said only 'Renpho smart scale' so the model is unknown.
  Sources: https://github.com/ronnnnnnnnnnnnn/renpho-escs20m, https://blescalesync.dev/guide/supported-scales, https://github.com/oliexdev/openScale/wiki/Supported-scales-in-openScale, https://github.com/oliexdev/openScale/issues/1509, https://github.com/oliexdev/openScale/pull/1523
- [M] BLE specifics: QN extended flavor will not start a measurement without a profile; the client must write a profile (height, age, sex) within about 2 seconds or the scale returns weight only. Body composition is derived from raw impedance using approximate algorithms (only 0x03 and 0x04 approximated in software), so values will not match the Renpho app exactly. Broadcast-only units give weight only (body comp estimated from BMI). Reading stored offline records can delete them from the scale and hide them from the official app. The Python client was only tested on macOS. openScale (Android) is the main open-source reference for QN handling but it is Android-only.
  Design implication: BLE-direct from Flutter (flutter_blue_plus / CoreBluetooth) is technically feasible but means owning the protocol, formulas and conflict with the Renpho app which also wants the scale. iOS cannot reliably scan in background for a passive weigh-in, so the app must be foregrounded. Worth it only as a stretch goal, with the Renpho app kept for everything else.
  Sources: https://github.com/ronnnnnnnnnnnnn/renpho-escs20m, https://blescalesync.dev/guide/supported-scales, https://github.com/oliexdev/openScale/wiki/Supported-scales-in-openScale
- [L] I did not verify Flutter-specific BLE libraries, iOS background BLE limits, or HealthKit write semantics from sources in this pass; those statements are from general knowledge.
  Design implication: Spike these on a physical iPhone before relying on them.
  Sources: 

### Alternatives considered

- Cloud API poller (hass-renpho-health style) in the Go backend: richest metrics, no phone involvement, but undocumented, reverse-engineered, breaks on app updates, uses stored credentials.
- Direct BLE from Flutter (QN protocol): independent of Renpho cloud and app, but model-dependent, must supply profile within about 2 s, approximate body-comp formulas, foreground only on iOS, and conflicts with the official app.
- Replace or supplement the scale with one that has a documented path (for example a Withings scale with an official API), only if Renpho proves unreliable.
- One-time historical backfill via in-app export, if it exists (unverified).

## ios-screen-time

### Recommended approach

Ranked by effort vs reliability:

1. Zero-entitlement baseline, build first (low effort, high reliability, honest data): a daily/weekly manual check-in. Preferably a screenshot of Settings > Screen Time (daily average or yesterday) shared into the app; on-device OCR (Apple Vision via a small Flutter plugin, or google_mlkit_text_recognition) extracts the total and the 'Pickups' count, with a confirm/edit step. Both users see each other's number, which keeps it honest (social accountability replaces enforcement). Score on weekly average vs the user's own baseline (relative improvement), which also helps fairness between Nick and Nadia. Cost: roughly 15 seconds per day or per week. Weekly screenshot is enough for a 'beat last week' game.

2. Submit the Family Controls (Distribution) entitlement request now, in parallel, for app + DeviceActivityMonitor extension (+ report extension if wanted), each bundle ID, with a plain self-monitoring description. Costs nothing and the wait is 2 days to 6+ weeks. Meanwhile develop with the development entitlement on your own devices (works via Xcode install; TestFlight will not work until approved).

3. Once approved: DeviceActivityMonitor extension with a repeating daily schedule and threshold events (e.g. 1h, 2h, 3h, 4h, 5h, 6h) on a FamilyActivitySelection of all categories, writing the highest hit and timestamp to App Group UserDefaults; the host app syncs to the Go/Postgres or Next backend. Add a DeviceActivityReport view embedded in the app for the user's own detailed dashboard (display only). Treat hits as coarse bands and cross-check with the manual/OCR number; allow correction. Validate first in a 1 to 2 day spike that the all-categories event matches Settings within tolerance on iOS 26.

4. Optional cheap signal: Shortcuts personal automations 'when [Instagram/YouTube/TikTok] opens' that call your server webhook, giving open counts for 'bad' apps.

Architecture: in Flutter, put screen time behind a ScreenTimeSource interface with implementations Manual, Ocr, DeviceActivityBuckets so the scoring engine does not care which is active.

### After verification

The recommendation largely stands. Key sandbox claim is confirmed by DTS. Keep the tiered plan: (1) build the manual/OCR screen-time baseline behind a ScreenTimeSource interface; (2) file Family Controls distribution requests now, one per bundle ID (app, DeviceActivityMonitor extension, and optional report extension), and expect the extension IDs to be the slow part, so budget weeks and file a DTS ticket with Team ID if stuck; (3) after approval, validate on an actual TestFlight build (not only Xcode dev builds) that threshold events and authorization status behave as in dev, since a forum report notes .approved vs approvedWithDataAccess differences; (4) write the monitor extension in native Swift with an App Group, bridged by MethodChannel, optionally starting from ioridev/flutter_screentime templates; use flutter_family_controls (0.0.5) only for authorization and the picker; (5) treat threshold hits as coarse bands and keep manual/OCR as the source of truth. Do not depend on the 5 MB limit or iOS 26 reliability claims until tested in the 1-2 day spike. The Shortcuts webhook idea is untouched by this pass (not checked).

Claims that did not survive unchanged:

- UNCERTAIN: 3. DeviceActivityMonitor can write to App Group; threshold events pattern; ~5 MB extension memory
  Correction: Keep the pattern as the standard workaround but mark the 5 MB limit as community-reported, not Apple-documented, and flag schedule-window sensitivity.
- UNCERTAIN: 4. Individual authorization supported (.individual, iOS 16); events need FamilyActivityPicker tokens; 'all apps' exactness unverified
  Correction: Keep as is, and add: validate on a TestFlight build, not only a dev build, because capability status may differ.
- UNCERTAIN: 5. Threshold callbacks unreliable (overcounting, 0-minute fires on iOS 26.2, silent failures)
  Correction: Keep the 'treat as coarse bands, cross-check with manual/OCR' stance.
- UNCERTAIN: 6. Family Controls is privileged; distribution entitlement needed for TestFlight
  Correction: State as 'strongly implied by practice and secondary sources, no Apple page stating TestFlight explicitly'. Plan as if required.
- REFUTED: 8. No Flutter plugin wraps DeviceActivity; flutter_family_controls 0.0.3; app_blocker 2.1.0; screen_time_api_ios minimal; screen_time Android-only; DEV article recommends MethodChannel
  Correction: flutter_family_controls is 0.0.5, not 0.0.3. No package gives a typed Dart API over DeviceActivity monitoring/reporting, but ioridev/flutter_screentime offers extension templates worth reviewing. Conclusion stands: write the monitor extension natively in Swift and bridge via MethodChannel plus App Group.

### Cannot do or could not verify

- Export exact minutes from DeviceActivityReport to the host app or server: Apple DTS says it is intentionally sandboxed.
- Read Settings > Screen Time numbers, the weekly report notification, or per-app durations as data via any public API without the Family Controls route.
- Get per-app minute breakdowns in your own code: apps are opaque tokens, only the Apple-rendered report shows names, and monitor events give only 'threshold reached' (inference from API shape).
- Use Family Controls on TestFlight without Apple approving the distribution entitlement for each bundle ID; the timeline is unpredictable.
- Detect 'ignore limit for today / one more minute' or password-entry events via Shortcuts; no such trigger found. A DeviceActivityMonitor intervalDidEnd / shield approach might approximate limit-bypass but would require shielding apps with ManagedSettings and was not verified.
- Guarantee threshold accuracy: documented overcounting and spurious firings exist on iOS 17 through 26.2.
- Verify the Family Controls flow in the iOS Simulator; a real device is required.

### Claims

- [H] A DeviceActivityReport extension is intentionally sandboxed so its usage data cannot be exported to the host app. An Apple DTS engineer answered 'Yes' to 'Is DeviceActivityReportExtension intentionally sandboxed so Screen Time data cannot be exported to the containing app?' and pointed to forum thread 817516 (not fetched by me).
  Design implication: Do not plan on App Group, UserDefaults, file, or network export from the report extension. Reports can only render usage inside Apple's own view hosted in your app. Secondary sources report writes silently no-op.
  Sources: https://developer.apple.com/forums/thread/818174, https://developer.apple.com/forums/thread/817516 (referenced only, unverified)
- [M] A DeviceActivityReport view can display accurate totals to the user inside the host app (via DeviceActivityReport SwiftUI view), but the host app never sees the numbers. Reports say the report extension also fails to launch on some builds (iOS 26.4 thread).
  Design implication: Report can serve as a read-only personal dashboard (Flutter UiKitView/platform view embedding a SwiftUI DeviceActivityReport), but it cannot feed points, streaks, or the server. The extension has reliability issues on recent iOS.
  Sources: https://developer.apple.com/forums/tags/device-activity?page=2, https://developer.apple.com/forums/thread/821625, https://popsm.medium.com/time-after-screen-time-part-2-the-device-activity-report-extension-10eeeb595fbd
- [M] DeviceActivityMonitor extension can write to an App Group and is the commonly used workaround. A repeating daily schedule (00:00-23:59:59) with DeviceActivityEvents at thresholds fires eventDidReachThreshold; the extension records the hit in App Group UserDefaults and the host app reads it. Crunchybagel describes this pattern used in Streaks (mark day missed). Extension memory limit about 5 MB.
  Design implication: Coarse buckets (e.g. events at 1h/2h/3h/4h/6h) written as 'highest threshold reached today' give a banded daily score. This is the only route to programmatic data. Inference: buckets, not minutes.
  Sources: https://crunchybagel.com/monitoring-app-usage-using-the-screen-time-api/, https://developer.apple.com/forums/thread/767136, https://developer.apple.com/forums/thread/746416
- [M] Individual authorization is supported: requestAuthorization(for: .individual) manages the current device (added iOS 16), no parent/child setup. Events must target apps/categories/web domains selected via FamilyActivityPicker (opaque tokens). I did not find a source stating that an 'all apps' event total is exact; selecting all categories is an inference.
  Design implication: Works for the two-person own-device case. User must pick apps/categories in the picker once; need to validate in a spike that selecting all categories yields a total close to Settings > Screen Time.
  Sources: https://crunchybagel.com/monitoring-app-usage-using-the-screen-time-api/, https://levelup.gitconnected.com/swiftui-monitor-restrict-device-activity-our-own-device-or-family-devices-a6d2f9fe254a
- [M] Threshold callbacks are unreliable: overcounting (300 min threshold fired at ~150 min on iOS 17.6.1, likely double-counting Safari and websites), callbacks firing with 0 minutes on iOS 26.2 (FB21450954), silent failures, repeat firing. Also the extension may not be woken exactly at crossing time.
  Design implication: Treat the data as untrusted-ish: use for coarse bands, show Apple's own report (or a manual confirm) as ground truth, don't award or deduct big points on a single threshold event. These are community reports, not Apple statements.
  Sources: https://developer.apple.com/forums/thread/763542, https://developer.apple.com/forums/thread/811305, https://www.weblineglobal.com/blog/fix-deviceactivitymonitorextension/, https://www.technetexperts.com/fix-eventdidreachthreshold-failure/
- [M] Family Controls is a privileged entitlement: you must request permission from Apple before distributing apps using it via TestFlight or App Store. Dev entitlement suffices only for Xcode-installed development builds (inference from Apple's model; no primary Apple page fetched confirming TestFlight specifically, but forum reporters had bundle IDs approved 'for an app I'm testing via TestFlight').
  Design implication: Plan for a distribution-entitlement request for the app AND each extension bundle ID (monitor, report, any shield) separately. Submit before building anything else on this path.
  Sources: https://crunchybagel.com/monitoring-app-usage-using-the-screen-time-api/, https://developer.apple.com/forums/thread/812332, https://newly.app/how-to/family-controls-entitlement
- [M] Approval timing is unpublished. Apple engineer said Apple provides no timelines. Reports: 2 days to a few days (best case), ~3 weeks typical, 31-33 days and 4.5 weeks, some stuck at 'Submitted' 4+ weeks with DTS tickets in early 2026. Each extension bundle ID needs its own request; multiple requests allowed.
  Design implication: Budget 1 to 6 weeks, with risk of indefinite wait. A personal two-user 'not for App Store' use case may be scrutinized; write a plain, genuine description (self-monitoring/digital wellbeing). Build the rest of the app so screen time is a pluggable module.
  Sources: https://developer.apple.com/forums/thread/725036, https://developer.apple.com/forums/thread/812332, https://developer.apple.com/forums/thread/820811, https://note.com/niki_ai/n/na8c9c4847174?hl=en, https://developer.apple.com/forums/thread/765098
- [M] No Flutter plugin wraps DeviceActivity (monitor/report). flutter_family_controls 0.0.3 covers authorization, FamilyActivityPicker, ManagedSettings; app_blocker 2.1.0 uses FamilyControls+ManagedSettings shields; screen_time_api_ios is minimal; screen_time is Android-only. A DEV article recommends a custom MethodChannel.
  Design implication: Write your own small Swift plugin (picker + schedule start + App Group read) plus native extension targets in Xcode. Extensions are always Swift regardless of Flutter. Flutter plugins are low-version, thin; don't depend on them.
  Sources: https://pub.dev/documentation/flutter_family_controls/latest/, https://pub.dev/packages/app_blocker, https://dev.to/eniolaajani/building-a-custom-screen-time-flutter-app-with-ios-native-apis-4k9f
- [M] Shortcuts has no trigger or action exposing Screen Time totals or 'app limit ignored / extend time' events. Available app automation is 'App is opened/closed', which can start a timer or redirect. I found only blogs, no Apple doc; absence of a trigger is inferred from the lack of any listed one.
  Design implication: Do not rely on Shortcuts for usage totals. A Shortcut 'when app X opens, POST to server' can count opens of specific apps (e.g. social/video) as a cheap proxy, but it is user-removable and lacks duration.
  Sources: https://dev.to/joshvickerson/setting-app-time-limits-on-ios-using-shortcuts-2dgl, https://www.macstories.net/news/the-full-list-of-automation-triggers-in-shortcuts-for-ios-13/
- [M] Apple's Screen Time weekly report notification and Settings screen are not exposed to apps. I did not find any API reading them; the only programmatic route is the Screen Time API family.
  Design implication: Manual entry or screenshot OCR are the non-entitlement fallbacks.
  Sources: https://developer.apple.com/videos/play/wwdc2021/10123/

### Alternatives considered

- Manual entry only: simplest, always works, relies on honesty; fine for two people who trust each other.
- Screenshot OCR of Settings > Screen Time (Vision framework or ML Kit, with confirmation): near-zero entitlement risk, automates entry; layout may change between iOS versions so keep the edit step.
- Weekly report screenshot instead of daily: lowest friction; pair with a Shortcut reminder.
- Shortcuts app-open webhooks to count opens of distracting apps.
- Skip screen time scoring and instead reward positive behaviors (audiobook minutes, reading) that are measurable elsewhere, with screen time as a self-reported stat.
- Fully native Swift for just a small screen-time companion target while the rest stays Flutter (this is required anyway, since extensions are Swift).

## nutrition-data

### Recommended approach

Layered lookup, all behind the Go API with a single local Postgres food table (source, source_id, gtin, name, brand, per-serving and per-100g nutrients, serving options, verified flag, created_by). 

PRELOAD at deploy time: USDA Foundation + SR Legacy (tiny, CC0) for generic foods and ingredients with Postgres full-text/trigram search. Optionally USDA Branded trimmed to GTIN, brand, name, serving size, and core nutrients (about 3 GB raw to import once, twice-yearly refresh) for offline US barcode hits.

QUERY LIVE and CACHE FOREVER: barcode scan goes local gtin match, then USDA Branded API search by GTIN if not preloaded, then Open Food Facts /product/{barcode} (User-Agent set, 15/min is plenty), writing every hit into the local table as source-tagged rows. Text search is always local (never OFF search, never search-as-you-type against remote APIs).

SCAN when nothing matches: photograph the Nutrition Facts panel (and optionally the barcode number), send to a vision LLM from the backend with a strict JSON schema, validate with calorie-from-macros arithmetic, show a confirm/edit screen, save as a user-verified record keyed to the barcode so the miss never happens twice. Optional: contribute back to OFF later.

FINAL FALLBACK: quick-add (name plus calories plus optional macros) and a manual custom-food form, plus an LLM 'describe your meal' estimate flagged as approximate. Copy-from-recent and favorites cut repeated entry for a two-person household.

RECIPES: run Mealie in the same Docker Compose (URL import, meal plan, shopping list, API) or store recipes in your own tables; compute recipe nutrition by mapping ingredients to the local food table, and use pantry/'cook at home' logic in your own service. Avoid Spoonacular/TheMealDB as the core.

BEFORE BUILDING: run a 30-50 barcode hit-rate test of your real pantry against USDA Branded and OFF, and spike mobile_scanner plus Vision OCR on Xcode 26 with real devices.

### After verification

The layered design stands. Make these changes. (1) Treat FatSecret as excluded, mainly because of its 24h cache rule and mandatory attribution, and stop asserting which tier has barcode. (2) Drop the mobile_scanner accelerometer concern: it was Android-only and is fixed in 7.4.2, so pin to 7.4.2 or later. Keep the real-device iOS 26 spike with the close-range lens API for Pro iPhones. (3) Nutritionix stays out, with a reported 2-MAU business trial noted but unverified. (4) USDA and OFF facts hold. Add: use OFF v3.6 and set a custom User-Agent. Store only text nutrient data from OFF, not the CC BY-SA images. Show the ODbL attribution line in the app's About screen. Keep the private-use ODbL reading marked as inference. (5) Keep the 30-50 barcode hit-rate test against USDA Branded and OFF before building.

Claims that did not survive unchanged:

- REFUTED: 7. FatSecret editions
  Correction: The claims that barcode is NOT in Basic and that Premier Free 'adds barcode scanning and autocomplete' are not supported by the pricing page, which does not assign them to a tier. Mark tier-to-feature mapping as unverified. Also Premier Free is unlimited calls. Nick would likely not qualify for Premier Free unless he counts as a startup. Regardless, FatSecret's 24h cache rule conflicts with the cache-forever design, so it remains out of the core.
- UNCERTAIN: 8. mobile_scanner 7.4.2 on iOS and open issues
  Correction: Remove #1801 from the list of open iOS issues: it is closed, fixed in 7.4.2, and Android-specific, so the iOS accelerometer concern is wrong. 'About 42 days old' is fine at the time of the original fetch. The language-change black preview and Pro iPhone close-focus items remain unverified. No iOS 26 confirmation exists, so the real-device spike stays necessary.

### Cannot do or could not verify

- Did not verify OFF's actual US barcode coverage or total product count; only unreliable mirror numbers were found.
- Did not research OFF Open Prices or the OFF image OCR features.
- Could not verify Edamam or CalorieNinjas free-tier limits from primary sources.
- Did not verify the Mealie meal-plan/URL-import endpoints or Tandoor's API from primary docs (only third-party aggregator and Mealie's API-usage page).
- Did not confirm whether google_mlkit_text_recognition works on Xcode 26 arm64 simulators, or mobile_scanner explicit iOS 26 support.
- Did not benchmark any LLM on nutrition-label extraction accuracy or get official per-image costs; prices are from third-party blogs.
- Did not verify USDA Branded data quality metrics or the ODbL private-use interpretation against the license text.

### Claims

- [H] USDA FoodData Central API: free, requires a data.gov API key; 1,000 requests/hour/IP default (429 and 1h block if exceeded); DEMO_KEY is 30/hr and 50/day. Endpoints: /food/{fdcId}, /foods, /foods/list, /foods/search. Data types: Foundation, SR Legacy, Survey (FNDDS), Experimental, Branded. Data is CC0 1.0 (public domain); credit is requested but not required. Keys must not be committed publicly.
  Design implication: The Go backend holds the key and proxies/caches; 1,000/hr is far beyond two users. Never ship the key in the Flutter app or a public repo. No license obligations, so USDA can be copied wholesale into Postgres.
  Sources: http://fdc.nal.usda.gov/api-guide/
- [H] USDA bulk downloads (release 04/2026 for Foundation and Branded): Foundation JSON 459K zipped/6.5M; Foundation CSV 3.7M/32M; SR Legacy (final, 04/2018, never updated) JSON 12.3M/205M, CSV 6.7M/54M; Branded JSON 195M zipped/3.1G unzipped, Branded CSV 428M/2.9G. The download page itself states no license, but the API guide states CC0.
  Design implication: Preload Foundation + SR Legacy (generic whole foods, small) fully into Postgres. Branded is optional: importing it (about 3 GB raw, a few hundred MB loaded after trimming to key nutrients plus GTIN/UPC, brand, serving size) gives offline US barcode lookup. Re-import is a twice-yearly cron job.
  Sources: http://fdc.nal.usda.gov/download-datasets/, http://fdc.nal.usda.gov/api-guide/
- [L] Branded Foods data quality: label-derived values supplied by manufacturers/Label Insight; includes gtin_upc, serving size, household serving text. I did not verify error rates or staleness in a source. Generally known to contain stale or reformulated products, which is inference, not verified here.
  Design implication: Treat branded matches as 'probably right', allow user edits, and let a scanned label override a stored branded record (user-corrected records win).
  Sources: http://fdc.nal.usda.gov/download-datasets/
- [H] Open Food Facts API limits: product read 15 req/min per IP, search 10 req/min per IP (not for search-as-you-type, ban risk), global 503 limits; custom User-Agent 'AppName/Version (email)' required; reads need no auth. Product endpoint e.g. /api/v3.6/product/{barcode}.json. Full-text search is not in API v2 (use Search-a-licious). Requests made directly by users from a mobile app are limited per user.
  Design implication: Barcode lookup through the Go backend with a proper User-Agent is fine at 15/min for two users. Do not use OFF for text search; use local Postgres search instead. Cache every hit.
  Sources: https://openfoodfacts.github.io/openfoodfacts-server/api/
- [H] Open Food Facts dumps: MongoDB dump, JSONL (openfoodfacts-products.jsonl.gz), Parquet (food.parquet on Hugging Face, simplified), CSV (en.openfoodfacts.org.products.csv.gz, tab-separated, about 0.9 GB gz / 9 GB unzipped), RDF (experimental). Daily deltas cover the previous 14 days. Total product count not stated on the page.
  Design implication: Do not preload the whole OFF dump; it is global and large. If wanted, filter the Parquet/JSONL to countries_tags contains en:united-states with nutriments present and load only that subset. Otherwise live lookup by barcode plus caching is enough.
  Sources: https://world.openfoodfacts.org/data
- [M] OFF licensing: database under ODbL, contents under DbCL, images CC BY-SA. Requested attribution: 'Contains data from Open Food Facts, available under the Open Database License'. ODbL share-alike applies to public use/distribution of derived databases; a private two-person app is not a public use. My reading of ODbL as not triggering obligations for private use is inference, not stated on the page.
  Design implication: Store OFF-sourced rows with a source='off' tag and put an attribution line in an About screen. Keep OFF records distinguishable so any later public release could comply or purge them.
  Sources: https://world.openfoodfacts.org/data, https://openfoodfacts.github.io/openfoodfacts-server/api/
- [L] OFF US coverage: no authoritative US count found. Mirror snapshots of country tag pages show only about 1.7k-1.9k products tagged United States, but these are from community mirrors with inconsistent tagging and cannot be trusted as a total. Actual US barcode coverage was not verified.
  Design implication: Do not assume OFF covers US products well. Measure it: before building, test 30 to 50 barcodes from your actual pantry against OFF and USDA Branded and pick the order by hit rate. Plan for a frequent miss and a label-scan fallback.
  Sources: https://ssl-api.openproductsfacts.org/countries, https://us.openfoodfacts.org/origins
- [L] I did not find OFF 'Open Prices' or image-OCR feature details in this research pass (not fetched). Not a dependency for this design.
  Design implication: Ignore for v1. Revisit only if you want price tracking for grocery cost; contribute-back to OFF is optional.
  Sources: 
- [M] Nutritionix: sources conflict. A June 2026 competitor blog says the free developer tier is gone, with paid plans from about $499/month; older sources claim 50-200 calls/day free. Treat as not available.
  Design implication: Do not depend on Nutritionix.
  Sources: https://calorieapi.com/blog/nutritionix-api-pricing, https://selfhostednutrition.org/api/nutritionix-api-when-to-use/
- [H] FatSecret Platform API Basic edition: free self-serve, 5,000 calls/day per key, US dataset, community support; mandatory attribution; cached content not marked storable-indefinitely must be removed or re-requested within 24h. Premier Free (startups/non-profits/students, verification) adds barcode scanning and autocomplete, still with attribution. Barcode is not in Basic.
  Design implication: Usable as an optional live text-search supplement for restaurant/chain items but the 24h cache rule means you cannot build your own database from it. Low priority; USDA branded plus OFF covers most needs.
  Sources: https://platform.fatsecret.com/api-editions, https://platform.fatsecret.com/terms
- [L] Edamam and CalorieNinjas free-tier numbers could not be verified from primary sources. Edamam secondary sources say a free tier exists scaling to about $49/month; CalorieNinjas has a keyed free plan with a monthly quota (numbers unverified).
  Design implication: Skip both. They add terms/quotas risk without covering anything USDA + OFF + LLM parsing do not. CalorieNinjas-style natural-language parsing ('2 eggs and toast') can be replaced by your own LLM call.
  Sources: https://blog.suggestic.com/food-api-ultimate-list
- [M] Barcode scanning: mobile_scanner 7.4.2 (about 42 days old at fetch) uses AVFoundation/Apple Vision on iOS, not ML Kit, so no ML Kit pod weight on iOS. Open issues exist: black preview up to about 1 min after a system language change (Oct 2026), accelerometer read on launch since 7.4.1 (#1801), close-range focus problems on Pro iPhones (workaround: getBestCloseRangeScanningLens()). No confirmed iOS 26 breakage found, but also no explicit iOS 26 confirmation.
  Design implication: Use mobile_scanner for UPC/EAN; enable close-range lens selection; test on both real iPhones early. Keep a manual barcode-number entry field as a fallback.
  Sources: https://pub.dev/packages/mobile_scanner, https://github.com/juliansteenbakker/mobile_scanner/issues/1801, https://github.com/juliansteenbakker/mobile_scanner/issues
- [M] google_mlkit_text_recognition 0.17.1 (published about 2 months before fetch): iOS min deployment target 15.5, Xcode 15.3+, 64-bit only (exclude armv7), Latin script by default. A search result noted ML Kit historically lacks arm64 iOS simulator slices and Xcode 26 dropped Rosetta simulators; the Flutter plugin status for this was NOT confirmed.
  Design implication: Prefer a thin Apple Vision (VNRecognizeTextRequest) platform channel or the community Vision-based plugin for OCR so simulator dev works and no Google pod is needed; or skip on-device OCR entirely and send the photo to a vision LLM (below). Verify the simulator question by building a spike on Xcode 26 before committing.
  Sources: https://pub.dev/packages/google_mlkit_text_recognition, https://github.com/d-date/google-mlkit-swiftpm/pull/115
- [M] LLM-based label parsing: no authoritative per-image cost figure found; third-party sources list Claude Sonnet 4.6 at $3/$15 per M tokens and Gemini 2.5 Flash at $0.30/$2.50. Both support image input and structured JSON output. I did not verify accuracy on nutrition labels. Cost for a few labels per week is negligible either way.
  Design implication: Send the label photo directly to a vision model with a strict JSON schema (serving size, servings per container, calories, macros, sodium, fiber, sugars, added sugars) from the Go backend. Validate with arithmetic checks (4/4/9 kcal rule within tolerance, %DV sanity) and show a confirm screen with the photo beside parsed values. Use regex over OCR only as an offline fallback.
  Sources: https://reintech.io/blog/openai-api-vs-claude-api-vs-gemini-api-comparison-2026
- [M] Recipes: Spoonacular official free plan is 50 points/day, 1 req/s, 402 after quota (third-party sites claim 150, official page takes priority); points not equal to requests. TheMealDB: free V1 with test key '1', free for dev/education, publicly released apps require supporter upgrade, free list results limited to 100, multi-ingredient filter is premium; small catalog, not US-centric nutrition. Mealie: self-hosted, long-lived API tokens, interactive API docs at /docs, shopping lists with API-only extras; Tandoor: OpenAPI 3 spec at /openapi/ on each instance, covers recipes, meal plans, shopping lists, URL scraping (third-party aggregator claim).
  Design implication: Do not build on Spoonacular's 50 points/day or TheMealDB's small catalog. Either run Mealie in the same Docker Compose (URL scraping, meal plan, shopping list with an API) and have the app consume its API, or keep recipes in your own Postgres tables with an LLM-based 'paste URL or photo to import' step. Mealie meal-plan and URL-import endpoint details were not verified here.
  Sources: https://spoonacular.com/food-api/pricing, https://www.themealdb.com/api.php, https://mealie.io/documentation/getting-started/api-usage/, https://apis.io/providers/tandoor/

### Alternatives considered

- Skip Branded preload; live-query only USDA Branded search + OFF with caching. Simpler, slightly slower first scan, works fine at 2 users.
- Fully LLM-driven logging (photo of meal/label and natural language) with the nutrient DB only as grounding. Faster input, less accurate; pair with confirm screens.
- Use FatSecret Basic as an extra live text-search source for restaurant/chain items, accepting attribution and the 24h cache-expiry rule.
- Use Tandoor instead of Mealie for the recipe manager (OpenAPI at /openapi/), or build recipes natively in Postgres to avoid a second service.
- Import the filtered US subset of the OFF Parquet dump instead of live OFF calls, for fully offline lookups.

## workout-generation

### Recommended approach

Architecture: deterministic rules engine owns the plan, with an LLM used only for choice and explanation within a closed candidate set.

1. Data source. Vendor free-exercise-db (Unlicense, 876 exercises, static JPGs) into Postgres. Add a curated overlay table of roughly 40-80 rows: tags for pull_up_bar, treadmill, mat, climbing-gym; extensor/antagonist and shoulder-health exercises; yoga session templates; fix null equipment rows. Keep a normalized muscle map and movement-pattern tags (horizontal push, vertical pull, squat, hinge, carry, trunk). Optionally enrich with wger names/translations later (CC per-entry license, so skip for now). Per-user equipment profile: Nadia = living room (yoga mat, dumbbells, pull-up bar, treadmill); Nick = those plus apartment gym plus climbing.

2. Rules engine (code, unit-tested, no LLM). Inputs: user profile (level, goals, available equipment, injury flags), weekly availability grid, fixed commitments, recent logs, and recovery signals (Apple Health sleep/HRV/resting HR where available). Responsibilities:
 - Choose split by days available: 2-3 days full body, 4-5 days upper/lower or push/pull/legs plus run/yoga days; 2 exposures per muscle per week.
 - Compute weekly hard-set targets per muscle (beginner low end about 6-10, cap about 20), allocate across sessions.
 - Progression: double progression within rep ranges, with RIR 1-3 targets; load increments from the actual dumbbell set; fallback to rep/tempo/variation progression when loads are fixed.
 - Deload every 4-6 weeks or on trigger (two consecutive regressions, low readiness, missed sessions): cut sets 30-50%.
 - Running: template progression (run/walk to continuous), mostly easy (80/20), weekly volume soft cap about 10-20% over trailing average, step-back every 3rd-4th week, longest run cap, plus miss handling (repeat/regress).
 - Climbing: log as external load; apply grip/pull interference rules and force antagonist/extensor work.
 - Scheduling: constraint solver (simple greedy or CP-SAT/OR-Tools-lite) over a week grid. Hard constraints: work hours, horse days, rest day count, no hard pull after hard climb, no two hard leg/long run days adjacent. Soft: preferred times, session duration fit, spread muscle groups. Re-plan only the remaining days of the week when a session is missed or moved.
 - Fairness: normalize challenge points and targets to each person's own baseline and available time (relative-to-plan completion, effort-adjusted points, time-budget-scaled goals) rather than raw volume, so Nadia's work and horse days don't penalize her. Head-to-head can use percent-of-personal-target.
 - Validators: every plan (human, rules, or LLM) passes the same checks (volume delta, load jump, equipment, rest, running delta).

3. LLM responsibilities (narrow). Given the rules engine's skeleton (session slots, target muscle sets, constraints) and a pre-filtered candidate list of catalog IDs per slot, the LLM picks exercise variety, orders them, writes a short coaching note and rationale, and suggests swaps when a user reports soreness or a skipped exercise. Output is strict JSON with catalog IDs only; server rejects unknown IDs or validator failures and retries with the error message (max 2-3 retries), falling back to a deterministic default pick. Generate once per week, persist, never regenerate on view. Run the LLM from a server job (Claude API or local model is optional; quality not critical because of the validator). Use it also for the periodic 'review' narrative (monthly progress summary).

4. Scheduling around fixed commitments. Store recurring blocks per person (work hours, horse days/times, commute, climbing gym nights) as calendar rules, plus one-off overrides from the app and optionally read Apple Calendar via EventKit on the phone (sync events to server). The scheduler fills remaining free windows, prefers short sessions on work days (20-40 min home/yoga/treadmill, evening), longer sessions on off days. Horse days count as external load (leg/core fatigue, treat as moderate lower-body stress) so the engine avoids heavy leg days adjacent to long horse days. Push the scheduled session to the Watch via WorkoutKit if desired (not verified here).

5. Build phasing. MVP: catalog import, equipment profiles, rules engine with 3-day full body and run/walk progression, logging, no LLM. Phase 2: scheduling constraints and calendar, climbing/horse load, deload logic. Phase 3: LLM for variety/explanations with validators. Phase 4: Health data (HRV/sleep) readiness adjustments.

### After verification

No refutation changes the architecture. The rules engine owns the plan, the LLM only picks and explains within a validated closed set, and free-exercise-db goes into Postgres with a curated overlay for pull-up bar, treadmill, mat, climbing-gym, antagonist and yoga rows. Three small amendments. (1) The overlay needs about 10 extra rows for pull-up bar tags (Pullups, Band Assisted Pull-Up, Scapular Pull-Up, V-Bar Pullup, Hanging Leg Raise, Hanging Pike and similar), and Finger Curls and the wrist curls can seed forearm and antagonist work. (2) Use the category value 'olympic weightlifting' in the import mapping. (3) wger is a maintained, self-hostable option with 932 exercises and a 2.7 release in 2026-09, but its per-entry CC licensing still makes it a later enrichment. Do not rely on ExerciseDB: its repo has been quiet since 2025-11, its hosted API is rate-limited, and the media and data terms are unread. The volume and running-progression numbers are heuristics from unverified secondary sources. Ship them as configurable defaults, not hard thresholds. This session was in plan mode, so I only ran read-only commands.

Claims that did not survive unchanged:

- UNCERTAIN: 6. No open structured yoga sequencing dataset found
  Correction: Keep it as 'none found'. The curated yoga session templates in the recommendation are the right fallback.
- UNCERTAIN: 7. Hypertrophy volume evidence (Schoenfeld 2017 dose-response, Baz-Valle, 4-10 sets/week, frequency matters little)
  Correction: Keep as medium confidence. The planned engine range of about 6-10 sets per muscle per week for beginners, capped at about 20, is conservative and consistent with this evidence. The recommendation does not depend on any single study.
- UNCERTAIN: 8. 10% rule is weak evidence (Groningen 20.8% vs 20.3%, Aarhus 22.1%, 2018 review 10% vs 24%)
  Correction: Keep the engine's soft cap of 10-20% over the trailing average, but treat it as a heuristic, not an evidence-backed threshold. Note that Buist's comparison group used a roughly 50% week-to-week increase for the first 8 weeks.

### Cannot do or could not verify

- Could not verify wger exercise count, exact exercise/exerciseinfo field names, or exact per-entry license version (wger.de was blocked by a bot check; docs page lacked these).
- Open Workout database was not researched.
- Did not verify double progression, RPE/RIR, and deload specifics against primary sources; stated as background knowledge.
- Did not verify couch-to-5K, Garmin Coach or Apple Fitness adaptive plan mechanics.
- Did not retrieve Daniels' VDOT equations or verified pace tables; secondhand tables conflict.
- Did not find concrete evidence-based numbers for climbing/pull-up interference (hours of rest, set caps); recommendations there are heuristics.
- Apple WorkoutKit (pushing custom workouts to the Watch) documentation fetch returned 404; availability and capabilities are unverified.
- Did not read ExerciseDB terms of use or the licenses on yoga datasets.
- Search tool results were partly low-quality secondary sources (blogs, aggregators, repeated forum copies).

### Claims

- [H] free-exercise-db (yuhonas) is Unlicense (public domain), 876 exercises in dist/exercises.json (README says 800+), one JSON per exercise with id, name, force, level, mechanic, equipment, primaryMuscles, secondaryMuscles, instructions, category, images (static JPGs, no GIFs).
  Design implication: Use as the primary seed catalog, vendored into the repo and imported into Postgres. No license friction, no network dependency, images can be self-hosted.
  Sources: https://github.com/yuhonas/free-exercise-db, https://raw.githubusercontent.com/yuhonas/free-exercise-db/main/dist/exercises.json
- [H] free-exercise-db distribution (I computed this from the JSON): category strength 584, stretching 123, plyometrics 61, powerlifting 38, olympic 35, strongman 21, cardio 14. Equipment: barbell 170, dumbbell 123, other 122, body only 111, cable 81, null 77, machine 67, kettlebells 56, bands 20. Level: beginner 525, intermediate 294, expert 57. 17 muscle groups (abdominals, abductors, adductors, biceps, calves, chest, forearms, glutes, hamstrings, lats, lower back, middle back, neck, quadriceps, shoulders, traps, triceps). force/mechanic can be null (30/87), equipment null for 77.
  Design implication: Equipment filter must map 'body only'+'dumbbell' (+ pull-up bar items) per person. Null equipment/force/mechanic rows need a cleaning pass or exclusion. Muscle taxonomy is coarse (no rear delt/front delt split, no hip flexor), so own a normalized muscle map for volume counting.
  Sources: https://raw.githubusercontent.com/yuhonas/free-exercise-db/main/dist/exercises.json
- [H] Coverage gaps in free-exercise-db for this household: it has pull-ups (Pullups, Band Assisted Pull-Up, Scapular Pull-Up, Weighted Pull Ups, Hanging Leg Raise), treadmill entries (Running/Jogging/Walking, Treadmill) in cardio, and 123 stretching items including Child's Pose and Cat Stretch, but there is no yoga category/flow, no climbing-specific training (hangboard, antiforearm extensor, campus), and only 'One Handed Hang' and 'Rope Climb' as nearby items. Pull-up bar is not an equipment value (likely 'other' or 'body only'), so exercises needing it must be tagged manually.
  Design implication: Add a small hand-curated overlay table (extra exercises + equipment tags: pull_up_bar, treadmill, living_room_mat, climbing_gym) layered on top of the imported catalog. Treat running and yoga as separate modules, not rows in the strength catalog.
  Sources: https://raw.githubusercontent.com/yuhonas/free-exercise-db/main/dist/exercises.json
- [M] ExerciseDB (exercisedb-api repo) is AGPL-3.0 code; README claims 11,000+ exercises, 15,000+ videos, 20,000+ images, 5,000+ GIFs. Fields in V2 sample: exerciseId, name, imageUrl, equipments, bodyParts, gender, exerciseType, targetMuscles, secondaryMuscles, videoUrl, keywords, overview, instructions, exerciseTips, variations, relatedExerciseIds. The API itself is a hosted service with pricing/RapidAPI; playground is rate limited and 'not for production'. Terms of use for the media were not read.
  Design implication: Do not depend on it. Media licensing and hosted-API terms are unclear; AGPL code and unknown asset rights are a poor fit for a clean self-hosted stack. Optional later: look at its schema (variations, relatedExerciseIds) as inspiration for substitution graphs.
  Sources: https://github.com/ExerciseDB/exercisedb-api
- [M] wger: application code AGPL-3.0-or-later; exercise/ingredient data is Creative Commons with the license listed per entry (older docs say CC-BY-SA 3.0; version may vary). REST API at /api/v2/ with OpenAPI schema at /api/v2/schema, public endpoints readable without auth, 20 results per page default, exercise endpoints not throttled. Self-hostable via docker compose. I could not verify exercise count (a third-party scraper listing says 800+) or the exact exercise/exerciseinfo field list; the wger.de site blocks bots with Anubis.
  Design implication: Good secondary source for translations, categories, and equipment/muscle metadata, and as a reference for a workout-log data model. Pulling it requires per-entry attribution and share-alike awareness; for a private two-user app that is low risk, but it is extra ingestion work. Verify exact fields from /api/v2/schema/ before committing.
  Sources: https://github.com/wger-project/wger, https://wger.readthedocs.io/en/latest/api/api.html, https://cdn.jsdelivr.net/gh/wger-project/wger@master/README.md
- [L] Open Workout was not researched (no source gathered).
  Design implication: Skip; free-exercise-db plus a small overlay already covers the equipment set.
  Sources: 
- [M] No open, structured yoga sequencing dataset was found. Search results were only computer-vision pose image datasets (Roboflow CC BY 4.0 for several, a Zenodo 'Yoga for all' set of 10 postures, a GitHub MediaPipe joint-angle set with unverified license). None provides pose-to-pose sequencing or API.
  Design implication: Do not generate yoga from a database. Treat Nadia's yoga as a user-chosen session type (duration, focus tags like hips/shoulders/recovery) with templated sequences authored by hand or by the LLM with human review, and log it as a mindful/flexibility workout. Optionally link to her preferred external yoga videos or app.
  Sources: https://zenodo.org/records/7818789, https://github.com/Manoj-2702/Yoga_Poses-Dataset, https://universe.roboflow.com/kesh/yoga-pose-0brcl/dataset/
- [M] Hypertrophy volume: Schoenfeld 2017 meta-regression found graded dose-response, growth increasing from 1-4 to 5-9 to 10+ weekly sets per muscle; later work (Baz-Valle) compared 12-20 vs more than 20 with diminishing but gradual returns; a secondary summary gives roughly 4-10 sets per muscle per week as an effective range and a recent meta-regression found frequency matters little once volume is matched. These came through aggregator/blog snippets, not the primary papers.
  Design implication: Encode per-muscle weekly set targets as config: roughly MEV about 4-6, working range about 8-16, hard cap about 20 hard sets per muscle per week, starting beginners at the low end. Frequency can be 2x per muscle per week for either a 3-day or 5-day layout. Verify against the primary papers before finalizing numbers.
  Sources: https://www.strongerbyscience.com/?p=56687, https://builtwithscience.com/fitness-tips/how-many-sets-per-muscle-group-per-week/, https://sportrxiv.org/index.php/server/preprint/download/460/967/908
- [L] Double progression, RIR/RPE autoregulation, and deload scheduling were NOT verified from a source in this research pass. They are standard practice and I am stating them from background knowledge: pick a rep range (e.g. 8-12), add reps at a fixed load until the top of the range at target RIR on all sets, then add the smallest load jump and reset to the bottom; deload about every 4-8 weeks or on performance regression, cutting volume about 30-50% at similar or slightly lower load.
  Design implication: Implement as deterministic functions in the rules engine with unit tests, and tag these parameters as tunable defaults. Dumbbell availability limits load jumps (unknown dumbbell weights), so ask the user for the actual dumbbell set; with fixed pairs, progress through reps, tempo, unilateral variants, or harder exercise variations instead of load.
  Sources: 
- [M] Running progression: the '10% weekly mileage increase' rule is weak evidence. A 2008 Groningen study found 20.8% injury in the 10% group vs 20.3% in a 50%-increase group; a 2012 Aarhus novice study found non-injured runners averaged a 22.1% weekly volume increase; a 2018 systematic review (as cited) found no difference between 10% and 24% average increases. Vendor blogs describe adaptive plans that recalibrate from logged runs but those are marketing sources.
  Design implication: Use a soft cap on weekly running-volume increases (about 10-20%, with every 3rd or 4th week reduced about 20-30%) plus a single-session cap (e.g. longest run not above about 40-50% of the week). Add guards on spikes relative to the trailing 4-week average rather than treating 10% as law.
  Sources: https://run.outsideonline.com/training/getting-started/myth-of-the-10-percent-rule/?scope=anon, https://www.trainingplan.dev/blog/posts/dynamic-mileage-progression, https://www.trainingplan.dev/blog/posts/why-static-plans-fail
- [M] Running templates: Hal Higdon 5K Novice is 8 weeks, about 3 runs, 2 strength, 1 cross-train, 3 rest per week (per a TrainingPeaks listing). Higdon Half Novice 1 is 12 weeks, weekday runs 3 to 5 mi, long run 4 to 10 mi. 80/20 (Fitzgerald): about 80% of training at low intensity, 20% moderate-to-hard. Jack Daniels VDOT: a race-performance-derived score mapped to E/M/T/I/R paces; secondhand pace tables vary by source and must be checked against the book or the official VDOT O2 calculator. Couch-to-5K was not researched.
  Design implication: Model running as templates (run/walk intervals to continuous 5K to 10K) parameterized by current fitness; use the 80/20 rule to assign intensities (mostly easy). Use Apple Watch workout data (distance, pace, HR) to compute week-over-week adaptation: advance if all key sessions completed at easy effort, repeat the week if one is missed, regress if two are missed or HR drift is high. Do not reimplement VDOT tables from secondhand numbers; compute paces from the published Daniels equations, or use only effort-based (HR/RPE) easy running initially.
  Sources: https://trainingpeaks.com/training-plans/running/5km/tp-15910/hal-higdon-5k-novice, https://trainingpeaks.com/training-plans/running/half-marathon/tp-139213/hal-higdon-half-marathon-novice-1, https://penguinrandomhouse.ca/books/316683/8020-running-by-matt-fitzgerald, https://www.endurancesportswire.com/80-20-endurance-announces-new-partnership-with-v-o2-and-legendary-coach-dr-jack-daniels/, https://www.athletedata.health/guides/vdot-running-paces
- [L] Climbing accounting: sources agree climbers overtrain pulling/finger flexors and under-train extensors and antagonists; recommendations include extensor (reverse wrist curl/finger extension) work, daily flexor stretches and tendon mobility, and phasing board/hangboard volume in slowly with off-board rest weeks. No source gave concrete pull-up programming, weekly splits, or hours-between-sessions numbers; the forum source is repeated copies of a single Mountain Project thread.
  Design implication: Make climbing a first-class 'external load' session type in the plan: Nick logs climbing sessions (day, duration, intensity) and the engine counts them as high pull/forearm/grip volume. Then (a) remove or cap vertical pulling (pull-ups, rows) and grip-heavy lifts within ~24-48 h of hard climbing days, (b) bias remaining volume toward push, legs, trunk, and shoulder/scapular health, (c) always add small doses of extensor and antagonist work, (d) count climbing finger stress separately and never schedule heavy grip work (deadlift heavy holds, hangs) the day before. Treat the specific hour/volume thresholds as tunable defaults and flag as unvalidated.
  Sources: https://www.kletterretter.com/en/hand-training-and-recovery/, https://www.outsideonline.com/health/training-performance/climbing-injury-prevention-exercises/?scope=anon, https://www.mountainproject.com/forum/message/126851011
- [M] LLM-generated programs: the searched literature shows a recurring pattern of LLM generation plus a parsing and validation stage against a schema, retrieval from a curated exercise DB to avoid invented exercises, and sports-science knowledge graphs as grounding. A 2026 repeated-generation study found the same profile can yield structurally different prescriptions across runs, and prior work shows low inter-rater agreement on quality. I found no source evaluating progressive overload logic enforced by a rules engine over LLM output. The commercial WPL 'hallucination-free' claim is unverified.
  Design implication: Do not let the LLM own numbers that matter for safety. Failure modes to design against: hallucinated exercises (mitigate by ID-only output constrained to catalog IDs via JSON schema/tool use plus server-side lookup), non-determinism (persist the generated plan, do not regenerate on each view, set temperature low, seed variants), unsafe volume jumps (post-validate weekly-set deltas, load jumps, and running mileage deltas, reject and re-ask with the validator error), equipment mismatch (hard filter candidates before the LLM sees them).
  Sources: https://www.nature.com/articles/s41598-026-37075-z, https://medium.com/@createdbysamp/how-i-built-a-mini-rag-workout-generator-with-supabase-c-and-ai-dadb21cd93ea, https://arxiv.org/pdf/2604.11287, https://wpl.dev/

### Alternatives considered

- Pure LLM generation per week with schema validation only: simplest to build and flexible but non-deterministic, hard to guarantee progression and recovery; rejected as the core, acceptable as the exercise-choice layer.
- Use ExerciseDB hosted API for GIFs and 11k exercises: richer media, but hosted terms, AGPL, and unknown media license plus external dependency; not recommended.
- wger as the full workout backend (self-hosted Docker): ready-made logging, routines, and API, but AGPL, Django/Python stack separate from your Go/Next.js choices, and per-entry CC licenses; could serve as reference or data source only.
- Adopt existing program templates (e.g. a published 3-day full body or upper/lower beginner programs) as static JSON and only run the progression/scheduling logic; very robust and much simpler, with the LLM limited to swaps. Strong fallback if the generator proves overkill.
- Use Apple Fitness+/Strava/Garmin-like adaptive running as the source and only ingest results: removes running logic, but you cannot use their plan APIs (not verified) and it weakens the shared gamification.

## gamification-fairness

### Recommended approach

Proposed scoring model (my design built from the sources; formulas are my inference, not published anywhere):

1. Personal goals by rule. Target T(p,h) = clamp(median of p's last 4 weeks of actuals x 1.05, floor, ceiling); floor and ceiling agreed once by both; recomputed monthly only. Availability scaling: each week each person marks work hours, horse days and travel. Capacity c = free_minutes_this_week / personal_median_free_minutes, clamped to [0.6, 1.2]. Effective target T_eff = T x c. Schedule load lives in the denominator, so neither person has an edge from free time and nobody can lower a goal by editing it. Show both people's targets and capacity inputs to each other.

2. Daily habit score s(p,h,d). Continuous habits (steps, run km, active minutes, audiobook minutes, home-cooked meals): s = min(1.25, actual / T_eff). Binary habits (teeth AM/PM, creatine, Huel, sleep window): s = 1 if done. Workout actual = effort units from heart-rate zone minutes weighted by zone, using that person's own max HR (Strava-style). Beyond 1.25, nothing further (cap as in Apple).

3. Daily points = 100 x sum over h of w_h x s. Starting weights: movement 0.25, workout or run 0.20, nutrition (home-cooked, no delivery order) 0.20, sleep 0.10, basics 0.10, reading or audiobook 0.10, screen time 0.05. Screen time is scored as a ratio to own 4-week baseline.

4. Weekly duel. WeekScore(p) = sum of the 7 daily points, with each day capped. Winner = higher WeekScore. Tie-break and a secondary badge go to the bigger improvement: z = (WeekScore - mean4) / max(sd4, 0.1 x mean4). A separate non-scoring Hall of Fame tab shows raw totals (most pushups, most miles) for bragging.

5. Cooperative layer (primary). Household streak: a day counts if both reach at least 70% of their own daily target. Weekly shared quests (cook at home 5 dinners, both run 3 times) with team progress = min of the two. Joint bonus +10 each for logged-together workouts or meals. Points above 70% of target feed a shared date-night fund. Weekly winner picks the weekend meal or movie, so a lopsided duel never costs the loser anything real.

6. Streaks. Per-habit and household; a day counts at s >= 0.7. Up to 2 pre-declared rest days per person per week never break a streak (weekend-amulet analog). Earn 1 freeze per perfect week, bank up to 2, applied automatically. Repair within 24 hours by earning 1.5x the daily goal, once per month. Milestone feedback at 3, 7, 14, 30, 60 days with the largest reward early. Streak bonus capped at about +10%. Loss aversion through a weekly point bank that erodes slightly on missed days (BE FIT style), no deposits or penalties.

7. Anti-gaming. Prefer HealthKit sensor data and treat user-entered records as low trust. Per-habit caps with diminishing returns, and a combined weight cap for self-report-only habits. Food logging rewards logging and cooking at home, never low calorie totals (my inference, to avoid pushing disordered eating). Partner can flag a suspicious entry, and an edit-with-reason correction path exists (spirit of Habitica's accepted Fix Values).

8. Rewards. Badges, a year-long start-vs-now metrics page, date-night fund, winner picks weekend meal, loser picks the next activity, quarterly bigger reward agreed together. These are unsourced choices for low cost and low friction.

### After verification

The scoring design survives intact. Changes: (a) Keep the cooperative-primary, light-competition layer, but justify it from the iDiabetes result (competition and support both worked; collaboration among strangers did not, which does not apply to a couple) and from enjoyment/stress data, and drop the claim that research shows competitiveness moderates experience. (b) The no-deposit, no-penalty choice is well supported: deposit uptake was only 61.7% and deposits were no more effective than rewards, and loss-framed feedback did worse than gain-framed feedback in healthy adults, so favor gain-framed feedback and treat the BE FIT-style eroding point bank as optional and mild (BE FIT's lost points applied to the family, was a different population, and the claim is not a general result about loss framing). (c) Rely on rule-derived personal targets rather than user-set goals, since Apple's percent-of-goal model rewards low goals (confirmed by third-party sources, no Apple statement). (d) Streak design (freezes, early milestones, diminishing returns) is supported by the Duolingo blog numbers, but those are Duolingo's own A/B results on language learners, so treat repair and the 70% threshold as untested design choices. (e) Cite journal DOIs rather than Penn press URLs, which now 404."

Claims that did not survive unchanged:

- UNCERTAIN: 6. Cooperation vs competition evidence: 2012 game experiment, 2024 physiological stress study, basketball no difference, 2026 VR exergaming study; evidence not on couples
  Correction: The 2024 study is about a Stroop task with a virtual agent, not a performance-and-wellbeing study of exercise, and the 2026 VR claim that 'some users have a worse experience depending on competitiveness' is not supported: the paper did not measure competitiveness; it only reports a few participants finding the pace target pressuring. Reword to: competitive framing raised intensity in a small 30-person confounded study, cooperative framing had the highest enjoyment.

### Cannot do or could not verify

- Verify Duolingo Streak Society, streak repair rules or Weekend Amulet figures from a primary Duolingo source; only fan wiki and third-party summaries were found.
- Find any study of competition between romantic partners; the evidence is on strangers, students and games, so all couples conclusions are inference.
- Retrieve Habitica's official anti-cheat policy, party and challenge rules or reward formulas; nothing on Finch, Streaks or Way of Life point economies was found.
- Verify Strava's Relative Effort coefficients or Garmin's auto-goal rule from official docs.
- Read the full text of BE FIT or iDiabetes; those facts come from news summaries.
- Research Stridekick or Fitbit challenge rules; not covered.
- Confirm the weights, caps and 0.7 threshold; they are untested starting values.

### Claims

- [H] Apple Watch competitions score 1 point per percentage point added to the rings each day, capped at 600 per day and 4,200 per 7-day competition. Most points wins.
  Design implication: Use percent-of-personal-goal scoring with a daily cap. The cap stops one huge day from deciding the week, and a 7-day duel is a clean unit.
  Sources: https://support.apple.com/guide/watch/compete-with-friends-apd68a69f5c7/watchos
- [M] The known weakness of Apple's percent-of-goal model is that the Move goal is user-set. Users report a lower goal earns more points for the same work, and that lowering your goal is the winning strategy. No primary Apple statement found (user reports and third-party blogs only).
  Design implication: Do not let goals be freely self-edited. Derive each goal by formula from the person's own rolling baseline, change it only at a fixed cadence (monthly), and show both people's goals to each other.
  Sources: https://discussions.apple.com/thread/252617680, https://www.podfeet.com/blog/2018/10/apple-watch-activity-competition/
- [H] Duolingo's own blog says streak milestone animations raised 7-day retention for new learners by 1.7%, and allowing up to 2 equipped Streak Freezes raised daily active learners by 0.38% relative. 7-day-streak users are 3.6x more likely to finish a course (not claimed causal). It credits habit formation, loss aversion, and diminishing marginal gain (day 2 to 3 is +50%, day 200 to 201 is +0.5%), and cites research that slack can motivate better than rigid rules. The blog did not cover repair or Streak Society.
  Design implication: Make streaks forgiving through banked freezes, not hard-fail. Spend reward effort on early-streak and milestone feedback, and cap the marginal points of long streaks.
  Sources: https://blog.duolingo.com/how-duolingo-streak-builds-habit/
- [L] The Weekend Amulet was a freeze covering weekend days and was later discontinued (fan wiki). Secondary reports say a 2017 test gave about +4% return after a week and -5% streak loss. A freeze must be equipped before the missed day. Prices and limits vary by source. Perfect Streak Week, special app icons and goal-commitment copy appear in a third-party write-up of Duolingo retention experiments. No primary source found for Streak Society or repair rules.
  Design implication: Copy the principle, not the numbers: scheduled rest days (a per-person version of the weekend amulet), pre-banked freezes, and a time-limited repair that costs extra effort.
  Sources: https://duolingo.fandom.com/wiki/Shop/Streak_freeze, https://econsultancy.com/six-a-b-tests-used-by-duolingo-to-tap-into-habit-forming-behaviour/, https://lazyweb.com/research/duolingo-retention-experiments, https://www.contentgrip.com/duolingo-streak-revival-campaign/
- [L] Strava Relative Effort weights time in heart-rate zones by intensity (TRIMP-like) using the athlete's own max heart rate, so effort is relative to the person; exact coefficients unverified. Garmin Connect weekly challenges rank on raw steps with no handicap (users ask for percent-of-goal). Garmin Auto Goal adapts step goal to history (exact rule unofficial).
  Design implication: Score workouts by effort relative to each person's own heart-rate zones, not raw distance or reps. Adapt goals from history. Keep raw leaderboards as non-scoring trivia.
  Sources: https://gearjunkie.com/health-fitness/strava-relative-effort, https://www.quadlockcase.com.au/blogs/news/what-is-stravas-new-relative-effort-all-about, https://forums.garmin.com/apps-software/mobile-apps-web/f/garmin-connect-web/322596/weekly-steps-challenge, https://www8.garmin.com/manuals/webhelp/approachx40/EN-US/GUID-1B4740C8-7DAB-46D4-9D19-EF66B4F5E988.html
- [L] Habitica's rewards depend on task value, difficulty and stats, and its community treats the 'Fix Character Values' escape hatch as legitimate play. Official anti-cheat policy, party/challenge rules and the Finch/Streaks/Way of Life economies were not retrieved (wiki returned HTTP 402).
  Design implication: For a two-person honor-system app, make cheating pointless rather than impossible: caps, low weight on unverifiable items, and a visible correction path. The point-economy comparison with Finch, Streaks and Way of Life still needs a follow-up pass.
  Sources: https://habitica.fandom.com/wiki/GP, https://en.wikipedia.org/wiki/Habitica
- [M] BE FIT (JAMA Internal Medicine 2017) gave families 70 points per week, losing 10 on days the step goal was missed, and reached goals on 0.53 of days vs 0.32 for controls. In iDiabetes (JAMA Network Open 2021), gamification with support and gamification with competition both increased steps vs control, while a collaboration arm with strangers did not. Read from news summaries, not full text.
  Design implication: A weekly point bank that erodes on missed days is a validated, cheap commitment device. Use it for the shared household pool, alongside both competition and partner support.
  Sources: https://pennmedicine.org/news/news-releases/2017/october/to-increase-exercise-study-shows-gaming-strategies-and-a-buddy-are-key, https://www.healio.com/news/primary-care/20171002/gamification-increases-physical-activity-among-families, https://pennmedicine.org/news/news-releases/2021/may/game-based-program-boosts-physical-activity-among-diabetes-patients
- [M] A 2022 JMIR randomized trial of 20-day step incentives found financial incentives beat control, but deposit contracts (loss framing) were no better than plain rewards, had lower uptake (about 62% vs 100%), and loss framing reduced effectiveness in healthy adults. The authors flag limited power.
  Design implication: Do not rely on punitive loss mechanics. Use loss aversion only through streak and banked-point erosion, with mild penalties and rewards as the main driver.
  Sources: https://jmir.org/2022/10/e38339/PDF
- [M] Cooperative goals produced more reported effort than competitive ones in a game experiment. A 2024 study found competition raised performance but also lasting physiological stress, so cooperation may be better when wellbeing matters. A basketball study found no difference. A 2026 VR study says competitive exergaming raises intensity but some users have a worse experience depending on competitiveness. Evidence is on strangers, students or games, not couples.
  Design implication: Make cooperative goals the spine and the duel a light weekly layer. Let either person dial the head-to-head down.
  Sources: https://faculty.washington.edu/garyhs/docs/wei-CHB2012-multiplayergames.pdf, https://pmc.ncbi.nlm.nih.gov/articles/PMC11263633/, https://www.researchgate.net/publication/8557467_The_Effects_of_Cooperation_and_Competition_on_Intrinsic_Motivation_and_Performance, https://www.frontiersin.org/journals/virtual-reality/articles/10.3389/frvir.2026.1897543/full
- [L] Kohler motivation gain: a preregistered meta-analysis of 19 articles found a significant motivation gain for partnered exercise vs alone. Plank studies with virtual partners show gains, and a summary of a bike study says the weaker member gains most from a moderately stronger partner. No study of romantic couples or of competition inside couples was found. A 95-person daily-diary study found exercising with a partner raised positive affect and relationship satisfaction that day (correlational), and a 2026 review calls the evidence mixed.
  Design implication: Reward doing things together (a joint workout or cooked meal earns a shared bonus), and show a reachable gap to your partner. The evidence supports partner presence more than scoreboard rivalry.
  Sources: https://scholarship.miami.edu/esploro/outputs/journalArticle/The-Köhler-Motivation-Gain-Effect-With/991031800615402976, https://kar.kent.ac.uk/41384, https://theconversation.com/second-best-is-best-train-with-a-stronger-partner-to-stay-motivated-11148, https://journals.sagepub.com/doi/full/10.1177/02654075211012086

### Alternatives considered

- Pure Apple-style percent-of-ring scoring with fixed agreed goals: simplest, but invites the lower-your-goal exploit.
- Fully cooperative mode with no duel: best wellbeing evidence, but drops the pushups-and-miles rivalry Nick wants.
- Handicap or Elo-style duel against expected score from own history: statistically fairest, harder to explain and tune for two users.
- Time-budget normalization only (points per available hour): directly addresses job and horse schedule, but needs reliable schedule input and could reward under-using free time.
- Heart-rate effort scoring only (Strava or TRIMP style): fair across fitness levels, but ignores non-workout habits like teeth, creatine and reading.

## books-audiobooks

### Recommended approach

Layered approach, ranked by automation level per source. (1) Core, fully manual-reliable: an in-app Start/Stop timer plus quick 'I read/listened N min' log (tagged audiobook/ebook/paper, optional book title) that posts to the Go backend. This works for Apple Books, Kindle, Libby, Audible, paper books and is the guaranteed fallback; award points for minutes with a daily cap. (2) Highest automation for audiobooks: self-host Audiobookshelf in the same Docker Compose stack, use one ABS user per person, and have the backend poll each user's listening sessions/stats/media progress with their token. Pair with a vetted third-party iOS client (ShelfPlayer or Still; test offline sync). This gives hands-off, per-user, minute-accurate data and finished events, but only for audiobooks you can put in ABS (DRM-free files or ripped Audible via Libation/audible-cli). (3) Book-level metadata: Hardcover GraphQL for currently-reading, finished, ratings and the yearly reading goal, polled hourly, optional per person. (4) Optional best-effort: Audible via the unofficial mkb79/audible library sidecar polling library percent_complete and stats/aggregates, marked experimental and nonessential. (5) Optional low-effort automation: Shortcuts personal automations (App Is Opened/Closed, Run Immediately, Get Contents of URL) for apps with no data source (Libby, Kindle, Apple Books), with server-side session pairing and caps; treat as unverified until tested on both phones. Anti-cheat is light: caps per day and require both open and close events. Automation levels: ABS high, Hardcover medium (events, not minutes), Audible medium-low (brittle), Shortcuts medium (approximate), Libby/Kindle/Apple Books none beyond the manual timer or Shortcut.

### After verification

Keep the layered structure, with these changes. (1) The manual timer and quick log stays as the guaranteed fallback. (2) Audiobookshelf stays the highest-automation audiobook path, but verify the session schema and the finished threshold on a live instance, and choose a client by testing offline sync and session reporting, since the third-party roster is larger and changing (ShelfPlayer, AudioBooth, SoundLeaf, Prologue, Audiary). The official iOS app is still a full early beta, so do not plan on it. (3) Hardcover is optional metadata only; verify the endpoint, mutations and limits yourself, since the docs were not reachable here. (4) Demote Audible and the audible-cli sidecar to a spike to validate against a real account, since the endpoint fields and aggregate windows are unverified and the project is mid-rewrite. Drop the 'low risk' wording on DRM removal. (5) Shortcuts automations stay unverified until tested on both phones. Screen Time ingestion should not be assumed possible: plan on threshold events or an on-device report only, and confirm the Family Controls entitlement path for TestFlight before committing to it. Overall confidence is lower than the researcher stated, because most claims could not be checked against primary sources in this pass.

Claims that did not survive unchanged:

- UNCERTAIN: 2. ABS sessions have no finished flag; finished lives on media progress (markAsFinishedTimeRemaining default 10s); ebook reading creates no sessions.
  Correction: Treat as plausible but unverified. Before relying on it, check the session schema at https://api.audiobookshelf.org/ and the finished threshold in a live instance.
- UNCERTAIN: 4. ABS only helps for DRM-free files; it cannot play Audible/Libby DRM; Libation or audible-cli can strip Audible DRM (gray area).
  Correction: Keep as 'audible-cli can download and decrypt Audible books for personal backup; legality varies by jurisdiction and Audible terms'. Drop 'low risk' as an unsupported claim.
- UNCERTAIN: 5. Audible has no official API; mkb79/audible and audible-cli call private endpoints; /1.0/library gives percent_complete/is_finished; /1.0/stats/aggregates gives 30 days daily and 12 months monthly.
  Correction: Treat the field names and windows as unverified. Probe a real account with `audible api` before designing around them. Note that the audible-cli project is mid-rewrite, so it carries churn risk.
- UNCERTAIN: 6. Libby/OverDrive has no public per-user API or progress export; Activity Timeline is exportable only as local troubleshooting data.
  Correction: Keep as 'no known public API or progress export' (negative claim, low-to-medium confidence). Libby's data is not usable for automation either way, so the recommendation does not change.
- UNCERTAIN: 7. Hardcover has a GraphQL API at api.hardcover.app/v1/graphql, Bearer token from settings, limits (60/min, 30s timeout, depth 3, 1000-row cap), user_book_reads fields and mutations.
  Correction: Treat limits as approximate and read the live rate-limit headers in the first call. Verify the endpoint, token page and mutation names via the GraphQL schema introspection or docs in a browser before building. The design needs only low polling volume (hourly, 2 users), so rate limits are not a risk.
- UNCERTAIN: 8. Apple Books exposes no progress/session data to Shortcuts or third parties; Screen Time per-app usage is not readable by a normal app; DeviceActivity/FamilyControls entitlement needs Apple approval.
  Correction: Keep the conclusion (Screen Time totals cannot be ingested into a backend; threshold events and an on-device report view are the only options) but mark it as unverified against Apple docs and re-check for iOS 26 changes. Note that the Family Controls distribution entitlement is requested through Apple, which may apply to TestFlight builds too; confirm before planning on it.

### Cannot do or could not verify

- Read Apple Books reading progress or time automatically through any public API or Shortcuts action.
- Get Libby/OverDrive listening progress or minutes programmatically; no public or documented user API found.
- Read Kindle/Whispersync progress without scraping or unofficial endpoints; no export exists.
- Read per-app Screen Time minutes (e.g. Books or Audible) from your own app; DeviceActivity is privacy-restricted and gated by a FamilyControls entitlement (from background knowledge, unverified here).
- Ship Shortcuts automations inside the app; each user must create them on their own phone.
- Guarantee that an 'app closed' Shortcut fires when an audio app keeps playing in the background; not verified.
- Rely on the Audible unofficial API long term; it is undocumented and can change or break auth at any time.
- Verify StoryGraph and Goodreads options in this session; no sources were fetched, so those are unverified background claims.

### Claims

- [H] Audiobookshelf (ABS) is the only source with a documented, official, per-user API for progress, sessions and stats. Auth is a per-user API token sent as Authorization: Bearer (query ?token= also works on GET). The API reference lists: Get Your Listening Sessions, Get Your Listening Stats, Get a Media Progress, Create/Update Media Progress, Get Library Items In Progress. Media progress fields: currentTime, progress, duration, isFinished, lastUpdate (ms epoch), startedAt, finishedAt, hideFromContinueListening.
  Design implication: Run ABS in the same Docker stack. The Go backend polls each user's /api/me endpoints (sessions, stats) every few minutes with each user's token and converts new listening time into points. Exact response schemas for sessions/stats were not read (the fetched docs page was truncated); confirm against a live instance.
  Sources: https://api.audiobookshelf.org/, https://deepwiki.com/audiobookshelf/audiobookshelf-api-docs/3.6-playback-and-progress-tracking
- [M] ABS listening sessions carry duration, time listened and current position but no finished flag. Finished state lives on the media progress record (auto-set when remaining time is under the markAsFinishedTimeRemaining setting, default 10s). Ebook reading in ABS creates no sessions.
  Design implication: Use sessions (timeListening deltas) for minutes-listened scoring and media progress for book-finished bonuses. Do not try to score ebooks via ABS. Source is a single user's issue report, so verify on a live instance.
  Sources: https://github.com/ryansull/syncshelf/issues/9
- [M] The official ABS iOS app is still an early beta distributed only via TestFlight (limited slots, reported full). Third-party iOS clients exist: ShelfPlayer, Plappa, Still, Prologue, SoundLeaf. ABS docs warn that some third-party apps use endpoints no longer recommended, which can produce incorrect sessions and stats.
  Design implication: Pick one third-party client (ShelfPlayer or Still were the ones stating session/progress sync) and test that it creates proper sessions, including offline playback that syncs later. Reliability as a progress source depends on the client choice, so test before committing. I did not verify offline-sync behavior of any specific client.
  Sources: https://docs.audiobookshelf.org/docs/documentation/community/community-apps, https://apps.apple.com/app/still-for-audiobookshelf/id6754208326, https://terminalbytes.com/soundleaf-ios-client-audiobookshelf-launch
- [M] ABS only helps for audiobooks you own as files. It cannot play Audible or Libby DRM content directly. Audible books can be brought into ABS via Libation or audible-cli (download and strip DRM), which is a legal gray area but low risk for personal use.
  Design implication: Decide whether you will move listening into ABS (high automation, extra effort of ripping/buying DRM-free) or stay on Audible (lower automation). Libation and OpenAudible were not fetched; their purpose (library download/export) is from background knowledge, and neither is known to expose listening progress.
  Sources: https://github.com/mkb79/audible-cli, https://github.com/rmcrackan/AudiobookHub
- [M] Audible has no official public API. The unofficial Python library mkb79/audible (and audible-cli, a CLI on top of it) authenticates as a device and calls private endpoints. GET /1.0/library with response_groups can return listening_status, percent_complete and is_finished. GET /1.0/stats/aggregates returns daily listening for up to 30 days and monthly for up to 12 months. A per-book last position exists but not a history.
  Design implication: A Python or Go sidecar (cron) could poll each person's Audible account every 15-60 min and derive listening minutes from percent_complete or position deltas times duration, or from stats/aggregates. This is brittle (private API, auth can break, ToS gray area, field name last_position_heard is unverified). Treat as an optional bonus source, never the only one. Needs a one-time device-registration login per person.
  Sources: https://github.com/mkb79/audible-cli, https://github.com/testiestshark/personal-observability/issues/112, https://pypi.org/project/audible/0.1.1/, https://moifort.github.io/audible-api-ts/
- [M] Libby/OverDrive has no public API for individual users and no listening-progress export. Libby has an Activity Timeline (checkouts history) that can be exported only as part of locally stored data for troubleshooting. Progress sync is not documented in any source found.
  Design implication: Do not build automation for Libby. Libby listening is manual or Shortcut-timer only. Nothing about an unofficial Libby API was verified, only that none was found.
  Sources: https://midhudson.org/member-resources/knowledge-base/eresources/overdrive/reading-history-for-overdrive-libby/, https://company.overdrive.com/2017/10/11/reading-history/
- [M] Hardcover.app has a public GraphQL API at https://api.hardcover.app/v1/graphql. Token comes from hardcover.app/settings and is sent as a Bearer header. Reported limits: 60 requests/min (burst 10, ~5000/day per one developer's header measurements), 30s timeout, max query depth 3, each top-level field costs a request, user_book_reads row cap 1000. user_book_reads has progress, progress_pages, started_at. Mutations exist: upsert_user_book_reads, insert/update_user_book_reads, plus user_book status changes.
  Design implication: Hardcover is a good book-level source (currently reading, finished, ratings, shelves, yearly goal) that both users could keep in sync with ABS (ABS community integrations exist) or manual updates. Poll hourly or less, which is far below limits. It records page/percent and finish dates, not minutes read, so score on finished-book events and progress deltas. docs.hardcover.app returned 403 to WebFetch, so exact auth header and current limits should be re-verified in a browser. From memory (low confidence), tokens may expire and need periodic re-issue.
  Sources: https://docs.hardcover.app/, https://github.com/ryansull/syncshelf/issues/6, https://github.com/ryansull/syncshelf/issues/7, https://github.com/hardcoverapp/hardcover-docs/issues/231, https://github.com/readest/readest/pull/6617
- [L] StoryGraph has no public API and Goodreads closed its API to new developers in 2020. Both offer CSV export (StoryGraph from account settings; Goodreads from My Books > Import/Export) and Goodreads RSS feeds of shelves, though these are less reliable now.
  Design implication: Not researched this session (no source fetched), so this is from background knowledge. Skip both and use Hardcover, which has a real API. Only revisit if one of you already tracks books in StoryGraph.
  Sources: 
- [M] Apple Books exposes no reading progress or session data to Shortcuts or to third-party apps. Apple documents only Reading Goals and iCloud progress sync for users. The .books App Intents schema is for third-party ebook readers to expose their own actions. Screen Time per-app or per-category usage is not readable by a normal app: DeviceActivity/FamilyControls is privacy-restricted (the app can only react to thresholds and render a report extension, not receive raw numbers), and the FamilyControls entitlement needs Apple approval.
  Design implication: No automation for Apple Books. The Screen Time statements are from background knowledge, since the search returned nothing on DeviceActivity; verify in Apple docs before designing screen-time-based scoring. A Shortcuts timer or manual log is the Apple Books path.
  Sources: https://developer.apple.com/documentation/appintents/app-schema-domain-books.md, https://www.apple.com/au/books
- [M] Kindle has no public API or export for reading progress. Whispersync data only reaches Amazon servers. Scraping read.amazon.com (cloud reader) was tried by others and described as hacky, and likely violates Amazon ToS. The 2026 Kindle iOS app reportedly has Goodreads integration and real page numbers.
  Design implication: Do not scrape Kindle. If either of you reads on Kindle, use manual minutes or Shortcut timers. Goodreads sync is not a useful ingestion path since the API is closed.
  Sources: https://gist.github.com/gnur, https://www.iclarified.com/46015/kindle-app-gets-book-browser-goodreads-integration-audible-progressive-play-more/comments
- [M] iOS Shortcuts Personal Automation supports an App trigger with Is Opened and Is Closed, and the Run Immediately option skips the confirmation prompt. An automation can then run Get Contents of URL (HTTP POST) to the server. Apple's user guide confirms app-opened triggers and run-immediately in general. An explicit statement of Is Closed plus Get Contents of URL working unattended was not found in the sources fetched.
  Design implication: Create two automations per audiobook/reading app (Opened posts start timestamp, Closed posts end). The server pairs them into a session and caps/validates it (e.g. ignore sessions over 3h, since app-open does not mean actively listening, and audio apps keep playing after being closed from the switcher). Needs a one-time on-device test per phone. Risks: backgrounded audio apps may not trigger Closed; the user has to set up the automations themselves (cannot be shipped in the app). Shortcuts can only be installed per phone by the user or via an iCloud shortcut link.
  Sources: https://support.apple.com/en-ca/guide/shortcuts/apd690170742/9.0/ios/26, https://www.switchingtomac.com/iphone-shortcuts-for-beginners/
- [M] A native in-app timer or manual log can write to Apple Health as Mindful Minutes (HKCategoryTypeIdentifierMindfulSession), and the Apple Watch Mindfulness app also writes that type, but Health data has no concept of reading vs meditation. Using Mindful as a reading signal conflates the two.
  Design implication: Prefer an in-app Reading/Listening timer (Start/Stop, optional Watch complication) that posts directly to your backend and tags the source (book, audiobook). Skip HealthKit Mindful for reading. Based on background knowledge, not fetched this session.
  Sources: 

### Alternatives considered

- Skip Audible/Libby/Kindle entirely and go all-in on ABS plus Hardcover: simplest and most robust, but forces DRM-free audiobook sourcing.
- Manual timer plus Shortcuts only: zero third-party dependencies, least accurate, relies on discipline.
- Use Hardcover alone (finished books and pages) and score per book/page rather than minutes: very low maintenance, coarse granularity.
- Run Libation to auto-rip Audible to files and sync into ABS so Audible stays the purchase source and ABS the listening source.

## ios-notifications-alarms

### Recommended approach

Hybrid, three tiers. (1) Local repeating notifications via flutter_local_notifications for the fixed daily habits (creatine/Huel, teeth AM/PM, bedtime wind-down), with interruptionLevel timeSensitive, an actions category (Done/Snooze) whose background handler POSTs to the backend. Keep well under 64 pending; use repeating calendar triggers, not unrolled schedules. (2) Server-driven visible APNs pushes (Go + sideshow/apns2, one .p8 key, device token from the 'push' package registered per user at /devices) for state-dependent nudges: streak-at-risk, partner overtakes, no dinner logged by 5pm, weekly recap; set aps.category for actions and interruption-level appropriately (active for most, timeSensitive sparingly, passive for recaps); the server cancels or skips the nag when completion is already recorded. Use content-available pushes only as best-effort hints to resync state. (3) AlarmKit for the morning wake-up alarm only (flutter_alarmkit), with a custom secondary button that opens a math/wake-check screen; scoring and a server-side check reward solving it, because a hard 'cannot dismiss until solved' is not possible. Home screen streak widget through home_widget + one SwiftUI WidgetKit extension in a shared App Group; Live Activities optional later via live_activities package using the same extension.\n\nNative pieces that cannot be pure Dart: (a) Xcode capabilities: Push Notifications, Background Modes -> Remote notifications, Time Sensitive Notifications, App Groups; Info.plist NSAlarmKitUsageDescription (and NSSupportsLiveActivities if used); (b) WidgetKit extension target in SwiftUI (home screen streak widget, AlarmKit alarm/countdown Live Activity UI, optional workout Live Activity), generated mainly by 'dart run flutter_alarmkit:setup'; (c) a Swift LiveActivityIntent for the AlarmKit secondary button (openAppWhenRun, alarm ID passed, deep link to the math screen) and likely a stop call from the intent; (d) AppDelegate wiring for flutter_local_notifications background actions (setPluginRegistrantCallback, different under UIScene lifecycle); (e) possibly a tiny APNs token shim if the stale 'push' package misbehaves on iOS 26; (f) the Apple Developer portal APNs key (.p8) and TestFlight build with aps-environment entitlement. Everything else (scheduling logic, API calls, UI, math puzzle, token registration) is Dart.

### After verification

The three-tier structure stands, with these changes. (1) Re-baseline the platform. The search results say the iOS 27 SDK exists and requires UIScene (apps built with it won't launch otherwise), and Flutter 3.41+ makes UIScene the default and auto-migrates only an unmodified AppDelegate. The brief says iOS 26 / Xcode 26 is current, which looks outdated, so confirm that and plan on UIScene from the start. Put the flutter_local_notifications registrant callback in didInitializeImplicitFlutterEngine and keep the UNUserNotificationCenter delegate in didFinishLaunchingWithOptions. (2) Treat the 'push' package (3.3.3, last released about 21 months ago) as a risk. Prototype token registration on a real device early, and keep a small native AppDelegate shim ready that forwards the device token over a MethodChannel. (3) On the server, node-apn is verifiably active (8.1.0, April 2026), but apns2 has had little activity since July 2025. If staying in Go, consider a thin HTTP/2 + JWT client of your own so alert, background, liveactivity and alarm push types are fully controlled. (4) AlarmKit: flutter_alarmkit 0.5.0 covers scheduling, but not a custom secondary-button intent or open-app. Expect to write that part in Swift or fork the plugin. Use supportedModes (openAppWhenRun is reportedly deprecated), add an explicit stop intent, call stop in the intent, and test on iOS 26.1+. App Groups are no longer required by flutter_alarmkit 0.5.0. Home widget and Live Activities still need one. Verify against Apple's own docs for the unverified items: interruption levels, AlarmKit, and background push limits.

Claims that did not survive unchanged:

- UNCERTAIN: 1. APNs .p8 server-side works in Go (sideshow/apns2) and Node (@parse/node-apn); both maintained
  Correction: node-apn is actively maintained (8.1.0, Apr 2026). apns2 works but has been quiet since mid-2025. Check that its PushType field accepts 'liveactivity' and 'alarm' before relying on it for Live Activity pushes. Otherwise a raw HTTP/2 + JWT client in Go is about 100 lines and removes the dependency risk.
- UNCERTAIN: 2. Flutter can receive APNs without Firebase via the 'push' package 3.3.3; no iOS AppDelegate code needed
  Correction: The package exists and its docs say no iOS AppDelegate change is needed. It is stale, though, and not tested against UIScene. Keep the 'tiny native shim' fallback in the plan. The shim is a few lines in AppDelegate that calls registerForRemoteNotifications and forwards the token over a MethodChannel. Test on a real device early.
- UNCERTAIN: 3. Interruption levels (passive, active, timeSensitive needs capability, critical needs Apple entitlement); flutter_local_notifications has interruptionLevel
  Correction: Treat as likely true, unverified against Apple. A correction: iOS 26 did not change these rules as far as I found. Two users makes critical alerts moot, since Apple approval is not realistic for a TestFlight app.
- UNCERTAIN: 5. AlarmKit (iOS 26) behavior: breaks silent/Focus, NSAlarmKitUsageDescription, authorization, schedules, stop plus secondary button (.countdown/.custom with LiveActivityIntent, openAppWhenRun), countdown needs Live Activity extension
  Correction: Core claims are plausible. Revise: use supportedModes instead of openAppWhenRun (the older property may be deprecated). Add a stop intent, which the iOS 27 SDK makes first-class. Whether a custom secondary intent leaves the alarm ringing is still unresolved; call stop explicitly in the intent's perform and test on a device on 26.1+.
- UNCERTAIN: 7. Live Activities need native code; live_activities 2.6.0 (660 likes, ~70k downloads, push-to-start iOS 17.2+); home_widget 0.10.0
  Correction: Confirmed for live_activities. Add that the extension needs the exact struct name LiveActivitiesAppAttributes. home_widget and live_activity_kit claims remain unverified. A shared widget extension for the alarm, home widget and Live Activity will conflict with the names and App Group the plugins each generate. Expect manual merging.
- UNCERTAIN: 8. Scheduling reliability: 64 pending local notifications; background pushes unreliable, throttled, not delivered when force-quit, about 30 s
  Correction: Keep the 64 claim. Treat the background-push claims as likely true and unverified against Apple. Design so correctness never depends on background pushes: always sync on app open.

### Cannot do or could not verify

- Force an AlarmKit alarm to remain ringing until a math problem is solved: the stop button always works, and no documented hook lets the app block dismissal (the Apple doc body did not load, so this rests on the absence of any such API plus general knowledge; verify).
- Run Dart or app code at the moment an AlarmKit alarm fires; the only documented hook is the secondary-button intent triggered by the user.
- Use Critical Alerts without Apple's approved entitlement; not realistic for this app.
- Guarantee delivery of silent/background pushes or background fetch for reminders, especially when the app was force-quit or Low Power Mode is on.
- Schedule more than 64 pending local notifications (iOS silently keeps only 64).
- Use AlarmKit on devices below iOS 26 (plugins throw UNSUPPORTED_VERSION); fine here since both phones can run iOS 26, but Apple Watch alarm behavior is unverified.
- Write the widget or Live Activity UI in Dart; it must be SwiftUI in a WidgetKit extension.

### Claims

- [M] Server-side APNs with a .p8 key works in Go and Node. sideshow/apns2 README: token (JWT) auth via NewTokenClient with key, KeyID, TeamID; the key does not expire; supports interruptionLevel and relevanceScore; no mention of Live Activity push type. @parse/node-apn README: token auth with .p8 path, keyId, teamId; repo looks active (1,246 commits, CI badge). Neither README showed a last-release date.
  Design implication: Use Go sideshow/apns2 (or raw HTTP/2 + JWT) in the backend. One .p8 key serves dev and prod for both phones. If Live Activity pushes are wanted, check the lib sends apns-push-type liveactivity, else hand-roll that single call. Not verified: library release dates.
  Sources: https://github.com/sideshow/apns2, https://github.com/parse-community/node-apn
- [M] Flutter can receive APNs without Firebase via the 'push' package (v3.3.3, page says published ~21 months ago). Token via Push.instance.addOnNewToken; foreground via addOnMessage; background via addOnBackgroundMessage (top-level fn, separate isolate); launch tap via notificationTapWhichLaunchedAppFromTerminated and addOnNotificationTap. The page shows AppDelegate code only for macOS, none for iOS (so likely none needed on iOS - inferred). Force-quit apps get no background pushes. Page contradicts itself on simulator support. flutter_apns is discontinued and depends on firebase_messaging; flutter_apns_x is unmaintained.
  Design implication: Use 'push' just to obtain/refresh the device token and handle taps. Send visible aps.alert pushes so iOS renders them without Dart running. Package is stale; budget for a small native shim (about 30 lines in AppDelegate: registerForRemoteNotifications, forward didRegister token over a MethodChannel) as fallback.
  Sources: https://pub.dev/documentation/push/latest/, https://pub.dev/packages/push, https://pub.dev/packages/flutter_apns
- [M] Interruption levels (Apple page body did not load; table is from general knowledge, so verify): passive, active (default), timeSensitive (needs Time Sensitive Notifications capability/entitlement, user can disable per app, breaks Focus), critical (needs Apple-approved Critical Alerts entitlement, bypasses mute and Focus). flutter_local_notifications DarwinNotificationDetails verified to have an interruptionLevel field (iOS 15+), plus categoryIdentifier, threadIdentifier, criticalSoundVolume; enum values not seen.
  Design implication: Use timeSensitive for creatine/Huel/teeth reminders (just add the capability in Xcode, no Apple approval). Do not plan on critical; Apple approval is intended for health/safety and a personal TestFlight app is unlikely to qualify. For anything that must wake someone, use AlarmKit instead.
  Sources: https://developer.apple.com/documentation/usernotifications/unnotificationinterruptionlevel, https://github.com/MaikuB/flutter_local_notifications/blob/master/flutter_local_notifications/lib/src/platform_specifics/darwin/notification_details.dart
- [H] Notification actions: flutter_local_notifications (latest stable 22.3.3, needs Flutter 3.38.1+) supports iOS actions via DarwinNotificationCategory declared in initialize. The foreground option runs onDidReceiveNotificationResponse on the main isolate; without it the action runs in a background engine via onDidReceiveBackgroundNotificationResponse (top-level, @pragma vm:entry-point), with a documented warning that it may not wake the UI part of the app. Needs AppDelegate setPluginRegistrantCallback wiring, which differs under the UIScene lifecycle. Remote (server) pushes need a matching category registered at app start and aps.category in the payload; the category must be registered by flutter_local_notifications or native code.
  Design implication: Register categories like TAKE_SUPPLEMENT (Done/Snooze) and MEAL_LOG at startup. Make 'Done' background actions that POST to the backend directly (idempotent API), and have the server cancel the follow-up nag push. Test the background-action path on a real device, particularly with the app terminated.
  Sources: https://pub.dev/packages/flutter_local_notifications
- [H] AlarmKit (iOS 26): per WWDC25 session 230 text, alarms break through silent mode and Focus, show on Lock Screen, Dynamic Island, StandBy and paired Apple Watch. Requires NSAlarmKitUsageDescription and authorization (authorizationState notDetermined/authorized/denied; per-app opt-in). Schedules: fixed date, Relative(time, weekly repeats, tracks time zone changes), countdowns with preAlert/postAlert. Alert has a stop button and an optional secondary button whose behavior is .countdown (snooze) or .custom (runs a LiveActivityIntent passed as secondaryIntent, which can set openAppWhenRun = true to open the app with the alarm ID). Countdown alarms require a Live Activity widget extension. Custom sound must be in bundle or Library/Sounds. The page does not document any app callback at fire time. A GitHub PR report says a custom secondary intent leaves the alarm ringing until the app calls stop; unverified.
  Design implication: AlarmKit gives true wake-up alarms, but the system stop button can always dismiss it (Apple page text did not load; 'cannot prevent dismissal' is from general knowledge and the absence of any documented hook). A math-to-dismiss alarm is therefore NOT enforceable. Practical pattern: AlarmKit alarm with a custom secondary button 'Solve to earn points' that opens the app to a math screen; scoring rewards completion and the server checks whether the task was solved within N minutes, otherwise re-rings via a second alarm or a time-sensitive nag. Make it points-based, not blocking.
  Sources: https://developer.apple.com/videos/play/wwdc2025/230/, https://developer.apple.com/documentation/alarmkit/scheduling-an-alarm-with-alarmkit, https://github.com/ImHangLi/maru/pull/88
- [M] Flutter AlarmKit plugins exist. flutter_alarmkit 0.5.0 (publisher gdelataillade.me, ~10 days old on the fetch, 27 likes, 2.6k downloads, early/small): auth, one-shot/countdown/recurring alarms, getAlarms, alarmUpdates stream, pause/resume/restart/cancel/stop, custom sound (.caf/.aiff/.wav under 30 s), customizable Live Activity buttons/icons/colors, AlarmMetadata. Needs Flutter 3.38+, Xcode 26+, iOS 26 device; 'dart run flutter_alarmkit:setup' patches the iOS project and adds a WidgetKit extension in ios/AlarmkitWidget; calls on iOS below 26 throw UNSUPPORTED_VERSION. Its page does not mention custom button intents or open-app-on-tap. Also hinata-platform/alarm_kit exists (maximumLimitReached error; Apple does not publish the alarm limit). The widely used 'alarm' package does NOT use AlarmKit: it uses a silent AVAudioPlayer to keep the app awake, and when the app is killed only a warning notification is guaranteed on iOS.
  Design implication: Do not use the 'alarm' package on iOS. Start with flutter_alarmkit for schedule/cancel/stop, and expect to write a small custom Swift piece for the secondary-button LiveActivityIntent that deep-links to the math screen (verify the plugin's widget template exposes this; otherwise fork/edit the generated AlarmkitWidget and the intent). Since the alarm schedule is local, resync on every app open and via a silent push.
  Sources: https://pub.dev/packages/flutter_alarmkit, https://github.com/hinata-platform/alarm_kit, https://github.com/gdelataillade/alarm
- [M] Live Activities need native code in any Flutter package. live_activities 2.6.0 (MIT, 660 likes, ~70k downloads, push-to-start iOS 17.2+, activityUpdateStream push tokens for server APNs updates) requires a Widget Extension in Xcode, App Groups, Push Notifications, NSSupportsLiveActivities, and SwiftUI written by hand. home_widget 0.10.0 handles home-screen widgets via shared storage: saveWidgetData then updateWidget(name:), with interactive widgets that call Dart; the widget UI must be native SwiftUI and its docs are at docs.page/abausg/home_widget (not fetched). live_activity_kit claims no-Swift Dart-defined UI, but it is unverified and obscure.
  Design implication: Streak/leaderboard widget: one WidgetKit extension in SwiftUI plus home_widget on the Dart side and a shared App Group. Live Activity (for example a workout timer or run) is optional and uses the same extension target. Put AlarmKit's widget, the home screen widget and any Live Activity in a single widget extension bundle to avoid maintaining several targets.
  Sources: https://pub.dev/packages/live_activities, https://pub.dev/packages/home_widget, https://pub.dev/documentation/live_activities_flutter/latest/
- [M] Scheduling reliability: iOS keeps only 64 pending local notifications (flutter_local_notifications docs: on iOS 10+ the 64 most recently set are kept). Background pushes (content-available, apns-push-type background, priority 5) are not guaranteed, are throttled, are not delivered to force-quit apps, may be deferred in Low Power Mode, and give about 30 s (the Apple doc body did not load; from general knowledge, verify). Apple guidance as recalled: use alert pushes for anything the user must see.
  Design implication: For fixed daily reminders (creatine, Huel, teeth AM/PM), local repeating notifications are the most reliable (work offline, use 1 pending slot each with a repeating calendar trigger). Use server visible pushes for dynamic, state-dependent messages (streak about to break, partner overtook you, no dinner logged, adaptive nag-until-done) because the server knows completion state and can skip or cancel. Do not rely on background fetch or silent pushes to reschedule things.
  Sources: https://pub.dev/packages/flutter_local_notifications, https://developer.apple.com/documentation/usernotifications/pushing-background-updates-to-your-app

### Alternatives considered

- Skip 'push' and use a tiny native Swift shim plus MethodChannel for APNs token and tap handling: less dependence on a 21-month-old package, about 30-50 lines of Swift.
- All reminders via server pushes only: simpler single source of truth, but they fail when the phone is offline or the home server is down; fixed daily habits are better done locally.
- Skip AlarmKit and use time-sensitive notification chains (for example repeated notifications every minute) as a wake-up: works on all iOS versions but cannot ring through the mute switch and is poor UX; the 'alarm' package keeps a silent audio session alive and is unreliable once the app is killed.
- Use Shortcuts/Clock alarm: the user sets a normal Clock alarm and the app only handles the post-wake check-in (open app, solve math, log weight); no native alarm code at all.
- Use live_activity_kit (claims no Swift) to avoid writing SwiftUI, but unverified and obscure; not recommended for a long-lived app.

## ios-private-distribution

### Recommended approach

PRIMARY: TestFlight internal testing only (no Beta App Review, no device UDIDs, no profile registration quota). Steps: (1) Add Nadia as an App Store Connect user with a role allowed for internal testing and create one internal group. (2) CI without a Mac: Codemagic personal free tier (500 macOS M2 min/month) with an App Store Connect API key, automatic signing and publishing to TestFlight; trigger on a git tag and on a monthly scheduled build so a build is never older than ~60 days. Backup CI if Nick prefers a self-contained repo: GitHub Actions macOS runner with fastlane match + pilot (200 macOS minutes on a private Free plan, unlimited on a public repo), or Xcode Cloud (25 free hours/month, no secrets, but first workflow setup needs Xcode on a Mac once). If Nick has a Mac: do local Xcode install for fast iteration on his phone via a development profile, use flutter build ipa + fastlane upload_to_testflight, or Xcode Cloud. (3) Keep Dart-only fixes cheap with either (a) server-driven content/config from the self-hosted backend, plus (b) optional Shorebird free tier patches on the TestFlight release (note it cannot target a TestFlight group and the base build still expires in 90 days). (4) Set capabilities (HealthKit, Background Modes, App Groups, Push) once before the first upload since they live in the App ID and provisioning profile. FALLBACK: ad hoc with both iPhones' UDIDs (valid for the profile lifetime, up to 1 year) if TestFlight misbehaves. MAINTENANCE CALENDAR: weekly/automatic none; every ~30 days: scheduled CI build uploaded (keeps newest build <60 days; the hard limit is 90 days); each TestFlight build: accept/update in the TestFlight app and check that the app launches; every spring (Apple raises the minimum SDK, e.g. the 2026-04-28 Xcode 26 rule): bump Xcode/Flutter version in CI; every September to October after new iOS ships: update Xcode, Flutter and plugins and retest HealthKit; every year at membership renewal: renew the $99 Apple Developer Program (lapse stops uploads and eventually removes TestFlight), renew/reissue the distribution certificate (valid 1 year) and refresh provisioning profiles (1 year) via match nuke or Codemagic regen, accept updated Apple agreements in App Store Connect, review/rotate the App Store Connect API key (no expiry, but revocable) and the APNs key (no expiry); if using ad hoc, re-register devices and reset device list at renewal; on any capability change: rebuild and re-sign.

### After verification

The recommendation stands. TestFlight internal testing is still the primary path, with the same Codemagic personal free tier, Xcode Cloud and GitHub Actions backups, and an ad hoc fallback. Four edits are needed. (1) Mark the internal-testing exemption from Beta App Review as likely but unverified, and check it on the first upload. (2) Drop the specific '200 macOS minutes' and '$0 default limit' figures for GitHub Actions. Say instead that the Free plan has 2,000 minutes and macOS bills at about 10x. (3) Note that a Codemagic personal plan cannot have collaborators. (4) In the ad hoc fallback and maintenance calendar, say that device slots are freed by removing devices at renewal, not by an automatic reset. I did not verify the 90-day schedule advice, Shorebird behavior, certificate and profile lifetimes, or APNs key expiry, so keep them marked as unverified. The monthly rebuild cadence is sound because the 90-day expiry is confirmed.

Claims that did not survive unchanged:

- UNCERTAIN: 2. Internal testing skips Beta App Review; internal testers must be App Store Connect users, so Nadia needs an invite
  Correction: Internal exemption is implied by Apple's page, not stated, and the 'available within minutes' timing is from secondary sources only. Treat it as likely true. Verify on the first upload.
- UNCERTAIN: 7. GitHub Actions macOS is 10x Linux; public repos free; Free plan 2,000 min (~200 macOS min); default $0 spending limit blocks overage
  Correction: Rate ratio is about 10x and the 2,000 figure is confirmed, but the 200 macOS minutes figure is an inference from the 10x ratio. The $0 default limit is not confirmed on this page. Note that a payment method on file means spending is governed by budgets.

### Cannot do or could not verify

- Could not verify from Apple's own pages that internal TestFlight skips Beta App Review (Apple's overview only mentions review for external testers); the claim rests on secondary sources.
- Apple's internal-tester help URL returned 404, so exact roles for internal testers are unconfirmed.
- Could not confirm the GitHub Free plan's 2,000-minute private-repo allowance from an official page.
- Did not verify the dev-profile 1-year validity, certificate lifetimes, 7-day free-profile limit, Shorebird's current paid price, or Shorebird behavior inside TestFlight on an official source.
- Did not verify HealthKit/Background Modes/App Groups/Push Xcode setup details or the `health` package's background-delivery support from primary documentation.
- Did not research watchOS companion app packaging in Flutter.

### Claims

- [H] TestFlight builds expire 90 days after upload and become unavailable to testers. Limits: 100 internal testers (App Store Connect users with access), 10,000 external.
  Design implication: Upload a fresh build at least every 60 days (ideally on a schedule). An expiry disables the app on both phones at once. Add an in-app build-age warning.
  Sources: https://developer.apple.com/help/app-store-connect/test-a-beta-version/testflight-overview
- [M] External testing sends the first build of a group to Beta App Review. Apple's overview page does not say internal testing needs review; secondary sources say internal builds skip Beta App Review and are available within minutes of processing. Internal testers must be members of the App Store Connect team, so Nadia needs an App Store Connect user invite with her Apple ID.
  Design implication: Use an internal group only and never create an external group. The Apple internal-tester help page returned 404, so the exact role names are from general knowledge; verify in the App Store Connect UI. Set ITSAppUsesNonExemptEncryption=false in Info.plist to skip the export-compliance prompt on each upload (inferred, standard practice).
  Sources: https://developer.apple.com/help/app-store-connect/test-a-beta-version/testflight-overview, https://instabug.com/blog/testflight-guide, https://docs.expo.dev/submit/testflight.md
- [H] Since 2026-04-28 all App Store Connect uploads (TestFlight included) must be built with Xcode 26+ against the iOS 26 SDK. The deployment target is independent of the SDK.
  Design implication: CI images must have Xcode 26. Pin the Xcode version in CI and expect a similar yearly SDK bump each spring, which is a recurring maintenance item.
  Sources: https://www.developer.apple.com/news/upcoming-requirements/, https://expo.dev/blog/app-store-connect-minimum-sdk-26
- [M] Ad hoc and development profiles allow up to 100 registered devices per product family per membership year. Disabling a device does not free a slot; the list can be reset only at the membership renewal. Ad hoc builds expire with their provisioning profile (at most 1 year, third-party sources). TestFlight does not use this device quota.
  Design implication: Ad hoc is a workable fallback with 2 iPhones (2 Watches count as a separate family) but it needs UDID registration and a re-sign at least yearly, and it does not give push-friendly update tooling. Keep it as a backup, not the primary path.
  Sources: https://developer-mdn.apple.com/help/account/devices/devices-overview, https://docs.applivery.com/en/app-distribution/platforms/apple/app-signing-types.md, https://help.apple.com/xcode/mac/9.0/en.lproj/dev7ccaf4d3c.html
- [L] Xcode direct install with a paid account uses a development profile, believed to last about 1 year (not verified on an Apple page). A free Apple ID gets 7-day profiles (general knowledge, not verified here). Nadia's phone would need to be connected to Nick's Mac for each reinstall.
  Design implication: Good for dev iteration on Nick's own phone, bad for Nadia's. Do not rely on it for her. Also, HealthKit background delivery and some capabilities work the same under dev signing, so it is a useful debugging path.
  Sources: https://docs.applivery.com/en/app-distribution/platforms/apple/app-signing-types.md
- [L] Apple Developer Enterprise Program is not applicable (requires 100+ employees, org eligibility). AltStore and other sideloading are not needed. These are general knowledge claims, not verified from a fetched source in this run. In the EU, alternative marketplaces exist but the user is presumably US-based (not asked).
  Design implication: Rule these out; TestFlight internal covers the need with less operational risk.
  Sources: 
- [H] Xcode Cloud: every Apple Developer Program membership includes 25 compute hours per month at no extra cost (since Jan 2024). Flutter's official docs give an ios/ci_scripts/ci_post_clone.sh that clones Flutter stable, runs flutter precache --ios, flutter pub get, installs CocoaPods and pod install. The script must be committed executable, and must live under ios/ci_scripts. Xcode Cloud needs the workflow created from Xcode on a Mac once.
  Design implication: Xcode Cloud is the zero-cost, zero-secret route (signing and TestFlight upload are managed by Apple), but the first-time workflow creation requires Xcode on a Mac (a borrowed Mac or a cloud Mac rental for one session). A Linux-only dev cannot create the workflow. Pin the Flutter version in the script rather than tracking stable HEAD (inference) for reproducibility.
  Sources: https://developer.apple.com/news?id=ik9z4ll6, https://docs.flutter.dev/deployment/cd, https://developer.apple.com/forums/thread/807674
- [M] Codemagic: personal accounts get 500 free macOS M2 build minutes per month, 1 concurrent build, no free minutes on Linux or for teams; overage about $0.095/min. Codemagic can sign automatically via an App Store Connect API key and publish to TestFlight with no Mac on the developer side.
  Design implication: Best no-Mac option: one Flutter iOS build takes roughly 10-20 min (inference), so 500 min/month covers about 25-50 builds, far more than needed. Verify the live pricing page before committing.
  Sources: https://docs.codemagic.io/billing/pricing.md, https://codemagic.io/pricing, https://agentdeals.dev/vendor/codemagic
- [M] GitHub Actions macOS runners bill at 10x the Linux minute rate; public repos with standard runners are free; private repos on the Free plan have a monthly quota (commonly 2,000 minutes, about 200 macOS minutes; figure from a secondary source, not confirmed in GitHub text). Default spending limit of $0 blocks overage.
  Design implication: A public repo gives free macOS builds, but this repo holds personal health logic and secrets handling so private is likelier; then 200 macOS minutes is about 10-15 builds/month, still enough for a release cadence of a few per month. Keep secrets only in GitHub Secrets if public (inference).
  Sources: https://docs.github.com/en/enterprise-cloud@latest/billing/concepts/product-billing/github-actions, https://bitrise.io/blog/post/best-github-actions-runners-in-2026-and-hidden-pricing-traps-to-avoid
- [M] fastlane flow (Flutter docs): flutter build ipa, then build_app(skip_build_archive: true, archive_path: ...) and upload_to_testflight; use fastlane match to sync distribution certs on ephemeral CI, pin fastlane via Gemfile, run flutter build ios --release --no-codesign --config-only first. App Store Connect API key (Key ID, Issuer ID, .p8 shown once) replaces password/2FA; this part is general knowledge, not from the fetched page.
  Design implication: Use an ASC API key (never an Apple ID password) in CI. match needs a private git repo (can be Nick's own self-hosted Gitea or a private GitHub repo) to store the encrypted certs and requires the Admin role for the key to create certs. Alternative: Codemagic or Xcode managed signing avoids match.
  Sources: https://docs.flutter.dev/deployment/cd
- [M] Flutter 3.35 raised the minimum iOS deployment target from 12 to 13 (auto-migrated). The `health` package (13.3.0 seen) wraps HealthKit on iOS; setup needs the HealthKit capability in Xcode and NSHealthShareUsageDescription (and NSHealthUpdateUsageDescription if writing) in Info.plist. Enabling HealthKit adds it to required device capabilities (UIRequiredDeviceCapabilities), which is fine for iPhones.
  Design implication: Target iOS 17 or 18 minimum in practice (both phones are current; inference) to use modern Swift/SwiftUI-bridge APIs, and set it explicitly in Xcode and the Podfile. The pub.dev health 13.3.0 page was only seen via search snippets; confirm the package's own iOS minimum and its background-delivery support when picking it.
  Sources: https://lists.proxmox.com/pipermail/pve-devel/2025-October/075650.html, https://pub.dev/packages/health/install, https://developer.apple.com/documentation/healthkit/setting-up-healthkit.md
- [L] Background Modes, App Groups and push capability setup in Xcode: not verified from a source in this run. From general knowledge: add capabilities under Signing & Capabilities (HealthKit incl. 'Background Delivery', Background Modes: background fetch/remote notifications, App Groups for Watch app or widget sharing, Push Notifications), these update the explicit App ID in the developer portal and are baked into the provisioning profile, so any capability change requires a re-signed build. Push requires an APNs auth key (.p8) via developer portal. HealthKit background delivery requires the HKObserverQuery plus enableBackgroundDelivery, which the Flutter `health` package may not expose, so a small native Swift plugin is likely needed.
  Design implication: Decide capabilities up front before the first TestFlight upload. Plan a small Swift method-channel plugin for HealthKit observer queries and watchOS companion pieces. Do the capability setup once on a Mac (or in Codemagic with automatic signing, which creates the App ID capabilities via the API). Verify each against Apple docs when implementing.
  Sources: 
- [M] Shorebird code push: usable on iOS (custom Dart interpreter for patched code) and vendor says it complies with App Store rules if the patch does not change the app's primary purpose. Only Dart changes can be patched (native or new native plugins require a new release), patches only run in Release builds on physical arm64 devices, and only Flutter's stable channel is supported. The FAQ says it cannot gate patches to TestFlight groups, so patches reach any install of that release; workaround is flavors/separate bundle IDs. Free tier: sources say about 5,000 patch installs/month, which is ample for 2 users; paid price figures conflict ($20/month vs $240/year) so check the live page. TestFlight compatibility is not explicitly documented.
  Design implication: Shorebird is optional. It saves rebuild minutes and the 90-day treadmill only partly, since the base binary still expires at 90 days in TestFlight, so a re-upload is mandatory regardless. Since the only users are two people in internal testing and Apple's TestFlight is a beta channel, ship patches there at low policy risk (inference, not Apple-confirmed). A cheaper alternative is to make most behavior server-driven (workout plans, scoring rules, copy) from the Go/Next backend so fewer client changes are needed.
  Sources: https://docs.shorebird.dev/code-push/faq/, https://shorebird.dev/product/code-push/, https://patchrelease.com/ota-update-tools-compared

### Alternatives considered

- Ad hoc distribution via Codemagic/fastlane or Diawi-style install page: 100-device/year quota, profile up to 1 year, no 90-day cliff but needs UDID registration and a yearly re-sign. Good backup.
- Xcode direct install from a Mac with a paid account: about 1-year dev profile (unverified), requires physical connection for Nadia's phone, so only Nick's phone is practical.
- Xcode Cloud only: zero secrets and 25 free hours/month, but requires a Mac once to create the workflow.
- GitHub Actions + fastlane match: most controllable and keeps everything in the repo; macOS minutes are 10x and limited on private Free plans.
- Self-hosted Mac mini runner or a rented Mac (MacStadium, AWS EC2 Mac has a 24h minimum): overkill for a 2-user app.
- AltStore/SideStore: free-account style 7-day re-signing, unnecessary with a paid account.
- Apple Developer Enterprise Program: not eligible for a 2-person private use.

## bloodwork-supplements-health

### Recommended approach

Treat labs as a private reference table plus informational nudges, not medical advice. Ingestion: (1) primary is PDF upload from Files or Share Sheet into the Go backend, where a vision LLM (Claude with PDF input) extracts rows into a strict schema (analyte, LOINC, value, unit, ref range, flag, collection date, lab). A mandatory review screen then lets the user confirm each row against the PDF page. (2) Secondary, behind a spike, is a small Swift plugin in the Flutter app that reads HKClinicalType.labResultsRecord and posts FHIR JSON; parse every coding and take effectiveDateTime as the date. Nudges: a hand-written rules table of at most around 8 markers (vitamin D, B12, ferritin, magnesium, plus a few lipids and glucose flags) that each produce a suggestion card with the reasoning, max dose, retest interval and 'talk to your doctor' flag. Adherence: own table; Huel and creatine are daily check-ins with a lock-screen/Watch one-tap, optional NFC tag firing a Shortcut POST, streak and points computed server-side with a grace rule. Brushing: manual morning/evening tap as the baseline, plus HealthKit ingestion of toothbrushingEvent when a smart brush app syncs, deduped by time window. Guardrails: persistent 'not medical advice' on every nudge screen; no dose recommendation above the ODS upper intake; always show the reference range from the PDF; out-of-range critical values (very high or low) display 'see a clinician' and never a supplement; no iron suggestion without ferritin and a doctor prompt; pregnancy, kidney disease, medications and existing supplements are collected in the profile checklist and suppress relevant cards; never let the LLM author the recommendation text or doses, and log the source row for every nudge.

### After verification

Keep the overall design: PDF upload with a Claude vision extraction and mandatory review screen as the primary path, a hand-written rules table of at most about 8 markers, and the guardrails (no LLM-authored advice or doses, not-medical-advice banner, critical values go to 'see a clinician'). Changes: (1) The HKClinicalRecord plugin stays behind a spike. Add TestFlight-on-paid-team behavior as an explicit spike question, because no source covers it. Also check whether Nick's and Nadia's providers appear in Health's Health Records provider list at all, since that decides whether the plugin has any value. Note the privacy policy URL requirement for the entitlement. (2) For supplement adherence, keep app-owned tables and streaks as the source of truth. Add a spike item on iOS 26 HKMedicationDoseEvent as an optional read-only signal, with write access unconfirmed and a reported crash on the authorization request. (3) Do not hardcode the vitamin D 4000 IU figure on trust. Have a human verify each dose and upper limit in the rules table against the ODS fact sheets once, and store the source URL with each rule. Magnesium 350 mg applies to supplemental magnesium only. (4) Add a creatine and creatinine rule: a high creatinine in a creatine user produces an informational note plus 'see a clinician'. (5) Treat smart-toothbrush HealthKit ingestion as optional, pending the brush they own. Items 5 and 7 were not independently verified here."

Claims that did not survive unchanged:

- UNCERTAIN: 5. PDF extraction: LLM vision or deterministic parsers; vendors do LOINC and UCUM normalization; one hand-audit found 4 of 88 rows wrong; no peer-reviewed benchmark.
  Correction: Keep as anecdotal. The mandatory per-row review screen in the recommendation is the right mitigation regardless.
- UNCERTAIN: 6. Supplement mappings and limits: vitamin D UL 4000 IU/day; magnesium supplement UL 350 mg/day; B12, iron guidance.
  Correction: Magnesium 350 mg is confirmed as supplement-only. Vitamin D 4000 IU stays background-knowledge. Rather than hardcode doses, have the rules table cite the ODS URL per marker, and have a human (Nick) verify each number once against the fact sheets in a browser.
- UNCERTAIN: 7. Creatine: ISSN 2017 position finds no compelling evidence of renal harm in healthy people; serum creatinine rises predictably; evidence in kidney disease is limited.
  Correction: Treat as plausible. The creatinine-rise point matters operationally. If bloodwork ingestion flags high creatinine or low eGFR for a creatine user, show an informational note ('creatine can raise creatinine') plus 'see a clinician', not a supplement suggestion.
- REFUTED: 8. HealthKit has no dietary supplement type for creatine or Huel; nutrition types exist; supplement adherence is app-owned data.
  Correction: There is still no dedicated creatine or Huel supplement type, and app-owned adherence data remains the right primary design. But iOS 26 gives a read path: the app may read HKMedicationDoseEvent for user-tracked vitamins or supplements (if the user adds creatine in Health's Medications), as an optional dedupe source. Add that to the spike list. Huel can still be logged as nutrition quantity samples.
- UNCERTAIN: Recommendation item: HealthKit toothbrushingEvent ingestion when a smart brush app syncs.
  Correction: Keep the manual tap as the baseline. Ingestion is a bonus and depends on Nick and Nadia owning a brush whose app writes to Health. Ask them which brush they have.

### Cannot do or could not verify

- Third-party apps cannot write Clinical Health Records; they are read-only.
- Shortcuts cannot read clinical records.
- HealthKit has no supplement or creatine type, and most lab analytes have no standard HealthKit quantity type.
- Silent NFC tap-to-log from inside a custom app is not possible; it must go through a Shortcut, and lock-state behavior was not verified.
- I could not verify NIH ODS dosing figures directly (403), the Apple toothbrushingEvent page, Quest brush support, or whether the clinical-records entitlement works through TestFlight.
- The app cannot diagnose or prescribe; it can only give informational, low-risk suggestions.

### Claims

- [H] Lab results from Apple Health Records are stored as read-only HKClinicalRecord samples (type HKClinicalType.labResultsRecord) whose fhirResource property holds the raw FHIR Observation JSON, normally with LOINC codes. Third-party apps can read them with per-type user permission.
  Design implication: A native Swift HealthKit bridge can pull labs as FHIR JSON and upload it to the Go backend. The backend maps by LOINC, not by printed test name.
  Sources: https://developer.apple.com/videos/play/wwdc2020/10669/, https://github.com/speckofthecosmos/clinical-vitals-sync, https://www.health3.app/features/apple-health-clinical-import/
- [M] Reading clinical records needs the HealthKit capability with Clinical Health Records enabled, plus the Info.plist keys NSHealthShareUsageDescription and NSHealthClinicalHealthRecordsShareUsageDescription. A paid team can use it in development builds. One personal project reports Apple reviews the entitlement only at App Review and that a free team cannot use it. I did not verify whether it works through TestFlight, which has a lighter beta review. Verify this early with a spike.
  Design implication: Do a day-one spike on a real TestFlight build before relying on the HealthKit clinical path. Keep PDF upload as the guaranteed fallback.
  Sources: https://newly.app/articles/health-records-entitlement, https://github.com/speckofthecosmos/clinical-vitals-sync
- [M] Apple Health Records only has data if a provider is connected in Health. Labcorp (account-based, 2018) and Quest (MyQuest account) joined the program, and many Epic-based health systems also feed it. I found no current Apple page listing supported institutions, so current status is unverified. One Epic (Kaiser) export came as multi-coded Observations (several LOINC codings per record), and effective dates had to be taken from FHIR effectiveDateTime because the HealthKit start date is the ingestion time.
  Design implication: Ask Nick and Nadia which lab or health system they use. Parse every coding on each Observation and use effectiveDateTime as the test date.
  Sources: https://www.hcinnovationgroup.com/clinical-it/news/13030858/labcorp-joins-apple-health-records-project, https://fiercehealthcare.com/tech/quest-diagnostics-becomes-second-national-lab-to-join-apple-health-records, https://github.com/speckofthecosmos/clinical-vitals-sync
- [M] Shortcuts cannot read clinical records, and most lab analytes (A1c, lipids, ferritin etc.) have no standard HealthKit quantity type. Only a few such as glucose map. The manual alternative is the Health app's Export All Health Data zip, which includes the FHIR JSON.
  Design implication: Do not rely on Shortcuts for labs. Store labs in your own Postgres table (loinc, value, unit, ref_low, ref_high, flag, date) rather than writing them back to HealthKit.
  Sources: https://github.com/speckofthecosmos/clinical-vitals-sync
- [M] For PDFs, existing projects use LLM vision/OCR or deterministic parsers. Vendors (Volo Health, Sensible) pipeline extraction, LOINC mapping and UCUM unit normalization. Quest and Labcorp layouts differ, and some panel rows have no clean LOINC match. In one hand-audit (LabLedger, 88 rows from 5 reports), 4 rows were wrong, including a misread positive result taken from the reference column. No peer-reviewed accuracy benchmark was found.
  Design implication: Use a vision LLM to extract rows into a strict JSON schema, with the reference range and flag read from the same row. Then show a mandatory human review table (value, unit, range, date) beside the PDF page before saving. Validate with plausibility bounds and a unit check, and send unmatched LOINC rows to manual selection.
  Sources: https://www.sensible.so/doc-types/lab-reports, https://developers.volohealth.com/docs/lab-pdf-extraction, https://github.com/CjOaOyL/family-health, https://github.com/MaXiMo000/LabLedger/pull/4, https://www.jonda.health/articles/extract-lab-results-from-pdf-llm-build-or-buy
- [M] Safe supplement mappings (from my background knowledge, not verified this session because NIH ODS pages returned 403): low 25(OH)D -> vitamin D3 at moderate dose with retest in about 8-12 weeks and an upper intake of 4000 IU/day for adults; low B12 -> oral B12 with a note to see a clinician about cause (pernicious anemia, metformin, etc.); low ferritin -> diet first and discuss with a clinician before iron; magnesium supplements are capped at 350 mg/day from supplements (UL) and serum magnesium is a poor marker of body stores. Iron is the riskiest because men and non-deficient people can overload (hemochromatosis).
  Design implication: Ship a small hand-curated rules table (marker, condition, suggestion, max dose, retest interval, doctor-flag). Verify each row against NIH ODS in a browser before coding. Never auto-recommend iron or high-dose anything, and never let an LLM generate dosages.
  Sources: https://ods.od.nih.gov/factsheets/VitaminD-HealthProfessional/, https://ods.od.nih.gov/factsheets/Iron-HealthProfessional/, https://ods.od.nih.gov/factsheets/Magnesium-HealthProfessional/, https://ods.od.nih.gov/factsheets/VitaminB12-HealthProfessional/
- [M] Creatine: the ISSN 2017 position reports no compelling evidence of renal harm in healthy people, and serum creatinine rises as a predictable effect of larger creatine pools rather than nephrotoxicity. Evidence for people with existing kidney disease is limited. Secondary sources only; the primary paper was not retrieved.
  Design implication: When creatinine or eGFR is outside range for a user taking creatine, show an informational note that creatine can raise creatinine, so ask the clinician. Do not label it kidney damage. Include a creatine tag on the lab-review screen.
  Sources: https://www.nutraingredients.com/Article/2017/06/14/Experts-confirm-safety-and-efficacy-of-creatine-supplements, https://www.frontiersin.org/journals/nutrition/articles/10.3389/fnut.2025.1682746/full
- [M] HealthKit has no dietary supplement type for creatine or Huel. Nutrition types (dietary energy, protein etc.) exist, and Huel could be logged as nutrition. Creatine has no calories to speak of. Supplement adherence is therefore app-owned data.
  Design implication: Store adherence in your own Postgres table (user, item, taken_at, source). Optionally write Huel as dietary energy and protein to HealthKit through the food-log path.
  Sources: https://developer.apple.com/documentation/healthkit/hkcategorytypeidentifier.md
- [M] NFC tag Shortcuts personal automations can run with 'Ask Before Running' off, triggering a Shortcut in the background. Sources disagree about whether the phone must be unlocked. Some actions still prompt. Apps cannot read an NFC tag and act silently on their own, so the workaround is the tag firing a Shortcut that calls the app or an HTTP endpoint.
  Design implication: Offer a tag on the creatine tub that fires a Shortcut doing a POST to the Go backend's /intake endpoint (works without any Swift code). Keep an in-app one-tap and a Watch complication as the primary path.
  Sources: https://www.matthewcassinelli.com/nfc-tags-siri-shortcuts/, https://community.home-assistant.io/t/nfc-tags-without-clicks/236284
- [M] HealthKit has toothbrushingEvent as a category type (HKCategoryTypeIdentifier.toothbrushingEvent), logged as start and end times of brushing sessions. I could not retrieve the Apple page, so details of metadata and write rules are unverified. Oral-B, Oclean Care and Philips Sonicare (app version 10.5.0 and newer; newer Philips Dental+ app) all advertise Apple Health sync. Which data types each writes was not stated in the sources. Sonicare sync needs a connected brush and the app in use. One user reported bulk backfills carry old timestamps with recent write times, which breaks incremental sync keyed on creation date. Quip was not checked.
  Design implication: Query HealthKit by sample start/end date, not by the anchored creation order, so back-filled sessions are not missed. Treat brushing from the toothbrush as the primary source if they own a smart brush, and keep a manual tap as the default so it works with a plain brush.
  Sources: https://www.kodeco.com/books/watchos-with-swiftui-by-tutorials/v1.0/chapters/15-healthkit, https://apps.apple.com/us/app/oclean-care/id1253819110, https://www.philips.co.uk/c-f/XC000020815/can-i-sync-the-sonicare-app-with-the-apple-health-app, https://apps.apple.com/dk/app/philips-sonicare/id1047099766, https://github.com/Lybron/health-auto-export/issues/56

### Alternatives considered

- Manual entry only: type the 6-10 key values per test; zero extraction risk, but friction means it may not get used.
- Apple Health 'Export All Health Data' zip: parse the FHIR JSON on the backend; no entitlement needed, but manual and heavy each time.
- Deterministic per-lab PDF parsers (as in the family-health or LabKit projects): no LLM cost or hallucination, but brittle across layouts.
- Skip lab nudges and use generic vitamin reminders only: lowest risk, much less personal.
- Writing labs back into HealthKit: not viable since most analytes have no HK type.

## sleep-wake

### Recommended approach

RECOMMENDED SLEEP SCORING MODEL (computed from HealthKit sleepAnalysis; Apple's Sleep Score is not needed and not available)

Definitions per person, per night (sleep day runs noon to noon, local time):
- A = union of all asleep samples (allAsleepValues) across sources at 1-minute epochs. In-bed-only and awake gaps are not asleep.
- Main session = longest cluster of A, merging gaps under 60 min.
- onset = start of session; wake = end of session (end of last asleep sample).
- TST = minutes asleep inside the session. TIB = wake - first inBed start if present, else wake - onset.
- Per-person targets (editable): need N (default 450 min), target wake W* with flex band, target bedtime B*. Workday and free-day targets can differ.

NIGHTLY SCORE, 0-100:
1. Duration (30): 30 * clamp(TST / N, 0, 1). If TST > N + 90 min, subtract 30 * (TST - (N + 90)) / 120, floor 15 (no reward for oversleeping).
2. Wake-time consistency (25): dev_w = circular minutes between wake and the trailing 7-night median wake. 25 * (1 - clamp((dev_w - 30) / 90, 0, 1)). Full within 30 min, zero at 120+.
3. Bedtime consistency (15): same with onset; full within 45 min, zero at 150+ (dev_b - 45) / 105.
4. Interruptions (15): n = awake gaps over 5 min inside the session (the only awake data Apple writes). 15 - min(15, 3n). Optional efficiency = TST/TIB term: 0 below 80%, full above 90%.
5. Morning (15): Up-on-time U = 10 * (1 - clamp((|wake - W*| - 15) / 75, 0, 1)). Get-moving M = 5 if first 20+ step burst occurs within 30 min of wake (unvalidated proxy), else 0. If step data is missing, give those 5 points to U (no penalty).
A night is 'slept well' (streak-eligible) at score >= 70. A night with no data (Watch not worn) is a neutral skip: no points, and the streak is not broken for up to 1 night per week.

WEEKLY SCORE:
- SRI_7 = 100 * fraction of minutes where state(t) == state(t - 24h) over the trailing 7 days (14 days once available). R = 40 * clamp((SRI_7 - 41) / (75 - 41), 0, 1).
- SJL_h = |median free-day midpoint - median work-day midpoint| (hours, trailing 28 days, needs 4+ free nights). Penalty P = 10 * clamp(SJL_h - 1, 0, 1), i.e. full penalty at 2 h or more.
- Weekly sleep points = R + 0.4 * mean(nightly score) + 20 - P, where the flat 20 is a base for participation (tune as needed), floored at zero.

Fairness: all targets are per person; consistency is relative to own median; oversleeping earns nothing extra; head-to-head compares percent of own max or streak length; separate workday and free-day templates for Nadia.

DATA REQUIRED (HealthKit read): sleepAnalysis (required); stepCount (optional, get-moving bonus); heartRate, restingHeartRate, heartRateVariabilitySDNN, respiratoryRate, appleSleepingWristTemperature, appleSleepingBreathingDisturbances (optional, informational chips only). Also per-person targets, work/free-day schedule, and the timezone offset stored with each night. Enable background delivery on sleepAnalysis and finalize a night 15-30 min after the last sample arrives or on next app open.

OPTIONAL: AlarmKit alarm to help hit W*. Record the stop-intent time only as a soft signal; never score on it.

Note: the point weights, thresholds (30/90 min bands, 70 cutoff) are my design choices, not research-derived; only the SRI anchors (41/75) and the 1-hour consistency and 1-2 hour SJL guidance come from sources.

### After verification

The scoring model largely stands. Revisions: (1) Do not rely on sleep latency or true out-of-bed time. Apple says latency can be derived from inBed vs detailed samples, but Watch samples may lack leading and trailing detail, so treat these as optional soft signals. Wake = end of last asleep sample stays. (2) Union asleep samples across sources at 1-minute epochs. The no-overlap guarantee only holds within one source's detailed samples. (3) Finalize each night only after the batch write, e.g. via background delivery on sleepAnalysis plus a 15-30 min quiet period or on next app open. DTS confirms there is no incremental or real-time stage data, so no live smart-alarm logic. (4) Sleep Score is not exposed via HealthKit (listings show no such identifier). Computing your own score is correct. If you want to mirror Apple's output bands in the UI, use the shipped 26.2 bands: Very Low 0-40, Low 41-60, OK 61-80, High 81-95, Very High 96-100. (5) SRI anchors 41 and 75 are fine (eLife P5 and P95). Cite the adjusted P5 HR as about 1.20-1.22 and note the P95 benefit is null after full adjustment. (6) Social jetlag: use MSFsc (sleep-corrected free-day midpoint) or at least do not penalize free-day oversleep recovery. The plain midpoint difference as written can penalize catching up on sleep. The 1 h and 2 h penalty thresholds are design choices. (7) Wrist temperature and breathing disturbances stay informational. Wrist temperature needs Series 8+/Ultra/SE3 plus Sleep Focus 4+ h for about 5 nights. HRV RMSSD now also exists as an identifier. (8) Unverified: Phillips 2017 numbers (2.5 h, r = 0.37, n = 61), the vendor 1-3 h and 3 h thresholds, the Apple PDF, and the Sleep Cycle thresholds. None are load-bearing for the model. Sources: Apple HealthKit .md pages, forums thread 849362, eLife 88359, OUP Sleep zsad253, GSMArena and 9to5Mac for Sleep Score bands, Apple support HT213275."

Claims that did not survive unchanged:

- UNCERTAIN: 3. Binary asleep/awake for 1-3 h sessions and full stages only above 3 h (single vendor source); Watch stage samples are written as a batch after the session ends (DTS); accelerometer plus heart rate; Apple validation PDF Oct 2025 unread.
  Correction: Keep: 'batch-written after session end, no incremental or real-time access (DTS)'. Mark the 1-3 h and 3 h thresholds as single-vendor, unverified. Do not hard-code them. The design already handles missing stages by using allAsleepValues, which is fine.
- UNCERTAIN: 6. SRI definition (Phillips 2017): same-state probability 24 h apart, rescaled 200(x-1/2) to -100..100; no main sleep episode needed; Regular vs Irregular quintile melatonin onset about 2.5 h earlier; SRI vs GPA r = 0.37; 61 students, diaries.
  Correction: Keep the definition (high prior), but flag 2.5 h, r = 0.37 and n = 61 as carried over from the earlier researcher and not re-verified. These are context numbers only and do not affect the scoring model.
- UNCERTAIN: 8. Social jetlag = difference between free-day and work-day sleep midpoints (Wittmann/Roenneberg 2006; MCTQ relative SJL = MSF - MSW); MSFsc formula not retrieved; Sleep Cycle uses weekday-weekend wake gap, under 1 h target and over 2 h flagged.
  Correction: Keep the definition. Note the standard SJL is absolute |MSF - MSW| and, in the standard form, uses the sleep-corrected MSFsc to remove oversleep debt on free days. The researcher's plain-midpoint version over-penalizes people who sleep in to catch up. Label the 1 h and 2 h thresholds as design choices unless Sleep Cycle's page is confirmed.

### Cannot do or could not verify

- Cannot read the watchOS 26 Sleep Score from HealthKit: no such type exists in the HKQuantity or HKCategory identifier lists.
- Cannot get real-time sleep stages or detect sleep onset or wake live: Apple Watch writes sleep samples in a batch after the session, possibly many minutes after waking.
- Cannot get a true 'out of bed' time: HealthKit exposes none, Watch samples omit the trailing awake period, and I found no documented iOS first-unlock API. Wake time is the end of the last asleep sample and the step-latency proxy is unvalidated.
- Cannot reliably detect AlarmKit alarm dismissal: swipe and banner dismissals don't fire the stop intent and no 'dismissed' state is exposed (iOS 26.2.1 reports).
- Cannot compute sleep latency from Watch data alone, because leading awake time is not written.
- Cannot vouch for deep/REM accuracy: Apple's validation PDF could not be read (fetch exceeded size limit), so stage minutes are treated as estimates.
- Cannot confirm WHOOP, Oura, AutoSleep, RISE or Sleep Cycle internal formulas and weights: none are published in the sources found.

### Claims

- [H] HealthKit exposes sleep as one category type, sleepAnalysis. Values: inBed, awake, asleepCore (light/intermediate), asleepDeep, asleepREM, asleepUnspecified (stage unknown), deprecated asleep. A static set allAsleepValues exists for predicates. Each sample has one value. inBed samples overlap the detailed stage samples, and the stage samples do not overlap each other.
  Design implication: Build the asleep timeline as the union of allAsleepValues samples. Never sum raw sample durations because overlapping sources cause double counting. Merge samples from multiple sources by taking the union, or pick one source per user.
  Sources: https://developer.apple.com/documentation/healthkit/hkcategoryvaluesleepanalysis.md
- [H] Apple's docs say samples recorded by Apple Watch only include 'awake' samples that occur BETWEEN two sleep samples. There may be no detailed samples at the start or end of an inBed sample. So the final awake period before getting up is NOT represented as awake, and the last asleep sample's endDate is the wake time. Sleep latency and the real out-of-bed time cannot be derived from Watch samples alone.
  Design implication: Define sleep_onset = start of first asleep sample and wake_time = end of last asleep sample in the main session. Do not compute sleep latency or time awake in bed after waking from Watch data. Use inBed only as a weak hint, because it may come from the phone's Bedtime schedule.
  Sources: https://developer.apple.com/documentation/healthkit/hkcategoryvaluesleepanalysis.md
- [M] Stage and quality caveats. An integration vendor's doc reports binary asleep/awake is written for sessions of 1-3 h, and full stages only above 3 h (single secondary source). Apple Watch sleep-stage samples are written as a batch after the session ends and post-processing completes (Apple DTS answer), not incrementally, and can show up in HealthKit many minutes after waking. Stage estimation uses accelerometer plus heart rate; Apple publishes a validation PDF (Oct 2025) that I could not read because the fetch exceeded the size limit.
  Design implication: Compute the nightly score lazily. Use an HKObserverQuery with enableBackgroundDelivery and an anchored query, and finalize the night's score only once the session samples settle (for example 15-30 min after the last sample arrives, or on next app open). Do not promise real-time wake detection. Use only timing and total sleep for the core score and keep deep/REM out of points.
  Sources: https://developer.apple.com/forums/thread/849362, https://developer.apple.com/forums/thread/780009, https://support.mydatahelps.org/apple-sleep-device-data-types, https://www.apple.com/health/pdf/Estimating_Sleep_Stages_from_Apple_Watch_Oct_2025.pdf
- [M] Other overnight HealthKit types that exist (verified in the identifier listings): respiratoryRate, heartRate, restingHeartRate, heartRateVariabilitySDNN, walkingHeartRateAverage, appleSleepingWristTemperature, appleSleepingBreathingDisturbances, stepCount, oxygenSaturation, timeInDaylight. Wrist temperature needs Series 8+/Ultra/SE3 and about 5 nights of Sleep Focus-based baseline setup (Apple support). A dev-forum report says the HealthKit sample carries only the absolute value, with no baseline or deflection metadata (unverified). I found no documentation that respiratoryRate or heartRate are tagged as sleeping values; they are ordinary samples you window by the sleep session times.
  Design implication: For recovery context, compute overnight means of HR, HRV and respiratory rate inside [sleep_onset, wake_time] and compare with each person's own 14-28 day baseline. Show these as informational chips, not in the points formula. Wrist temp and breathing disturbances are optional and device-dependent.
  Sources: https://developer.apple.com/documentation/healthkit/hkquantitytypeidentifier.md, https://support.apple.com/en-us/HT213275, https://developer.apple.com/forums/thread/725445
- [H] The watchOS 26 Sleep Score does not appear in HealthKit: the full HKQuantityTypeIdentifier and HKCategoryTypeIdentifier listings on developer.apple.com contain no sleep-score type. The Health app computes it (retroactively, from existing sleep data including third-party sources). Components: duration 50, bedtime 30, interruptions 20 points. Bands changed in watchOS 26.2 beta to Very Low 0-40, Low 41-60, OK 61-80, High 81-95, Very High 96-100 (26.0 had Excellent 90-100). I could not confirm the final shipped bands.
  Design implication: The app must compute its own sleep score from sleepAnalysis. Mirror Apple's public 50/30/20 split idea (duration, bedtime, interruptions) so the number feels familiar. Do not promise to display Apple's own score. The 'no HealthKit type' finding is high confidence; the band numbers are medium (press sources only).
  Sources: https://developer.apple.com/documentation/healthkit/hkquantitytypeidentifier.md, https://developer.apple.com/documentation/healthkit/hkcategorytypeidentifier.md, https://www.macrumors.com/2025/09/10/watchos-26-sleep-score/, https://9to5mac.com/2025/11/04/watchos-26-2-sleep-score-changes-apple-watch/
- [H] Sleep Regularity Index (SRI), verified from the Phillips 2017 paper: the probability that a person is in the same asleep/awake state at two time points 24 h apart, evaluated minute by minute and averaged over all days, rescaled with y = 200(x - 1/2) to run -100 to 100 (100 periodic, 0 random). It does not require designating a main sleep episode, so naps and all-nighters are handled. In the study the Regular versus Irregular quintile had melatonin onset about 2.5 h earlier, and SRI correlated with GPA (r = 0.37). Observational, 61 students, sleep diaries.
  Design implication: SRI is directly computable from the asleep-union timeline at 1-minute resolution. Use a trailing window of 7 days for display and 14 days for stability. Use the 0-100 form, SRI = 100 * P(same state), matching Sleep Cycle's and the UK Biobank paper's scale.
  Sources: https://dash.harvard.edu/server/api/core/bitstreams/7312037e-385a-6bd4-e053-0100007fdf3b/content, https://www.nature.com/articles/s41598-017-03171-4
- [H] UK Biobank evidence (n=88,975, 7-day wrist accelerometry). SRI has a non-linear relation to mortality. Median SRI is 60 (SD 10), 5th percentile 41, 95th percentile 75. All-cause HR is 1.53 at the 5th percentile and 0.90 at the 95th, relative to the median. After adjusting for BMI, BP and activity the 5th-percentile HR is 1.22. A separate analysis (Windred 2024, n=60,977) reports regularity as a stronger predictor than duration. Limits: observational, single week of exposure, inferred sleep, mostly older White cohort, reverse causation possible.
  Design implication: Map SRI to points using empirical anchors: 0 pts at SRI <= 41, full points at SRI >= 75, linear between. These are accelerometer-based population percentiles, so label them targets, not clinical thresholds. Make no health claims in the UI. Numbers are high confidence; causal interpretation is medium.
  Sources: https://elifesciences.org/articles/88359, https://academic.oup.com/sleep/article/47/1/zsad253/7280269
- [M] Social jetlag (SJL) is the difference between the midpoint of sleep on free days and on work days (Wittmann/Roenneberg 2006; the MCTQ docs define relative SJL as MSF - MSW). The sleep-corrected MSFsc is part of the MCTQ literature but I could not retrieve its formula. Sleep Cycle uses a practical version: weekday-to-weekend wake-time gap, under 1 h as target and over 2 h flagged as social jetlag.
  Design implication: Compute SJL = |median free-day midpoint - median work-day midpoint| over a trailing 28 days with at least 4 free-day nights (skip otherwise). The work/free split should come from each person's own configured schedule (Nadia works weekdays, Nick works from home). Use it as a weekly modifier only. Flag that MSFsc's formula was not verified.
  Sources: https://en.wikipedia.org/wiki/Social_jetlag, https://docs.ropensci.org/mctq/reference/sjl_sc.html, https://ftp.fau.de/cran/web/packages/mctq/vignettes/sjl-computation.html, https://sleepcycle.com/sleep-talk/understanding-your-sleep-score
- [L] There is no public iOS 'got out of bed' signal. HealthKit has none, and Apple Watch samples omit the trailing awake time. I found nothing documenting first-unlock as a readable event, and iOS has no public first-unlock callback (my inference; not found documented). Plausible proxies, all inference and unverified: (a) end of last asleep sample, (b) first stepCount sample after wake_time, (c) first HR above the person's resting baseline. RISE reportedly uses first phone pickup in the morning and last at night (Built In article; mechanism unverified).
  Design implication: Treat wake_time (end of last asleep sample) as the objective wake signal. Add a get-moving latency = time from wake_time to first 20+ step burst, as an optional low-weight bonus with a sanity cap. Latency will often be near 0 because Apple's session usually ends once the wearer is moving, and steps from a phone in another room add noise. Never penalize a missing or late signal.
  Sources: https://developer.apple.com/documentation/healthkit/hkcategoryvaluesleepanalysis.md, https://www.builtinchicago.org/articles/rise-science-app-launch-15m-funding, https://developer.apple.com/forums/thread/763329
- [M] AlarmKit (iOS 26+, iPhone/iPad) lets an app schedule prominent alarms and timers that can break through Silent/Focus, with snooze and countdown. But the app cannot reliably tell if or when the user dismissed an alarm: swiping away doesn't call the stop intent; the stopIntent LiveActivityIntent fires for the on-screen Stop button but not when the user dismisses by interacting with the unlocked screen or the Live Activity banner (reproduced on iOS 26.2.1 per forum); AlarmManager alarm updates don't expose a 'dismissed' state. An Apple DTS engineer asked for a repro and said they hadn't seen the issue. Mostly single-developer reports.
  Design implication: AlarmKit is useful for delivering a wake alarm and for a self-declared 'alarm set' habit, but not as a measurement tool. Score off HealthKit wake time. The stop intent may be recorded as a bonus signal, but missing events must never reduce a score.
  Sources: https://developer.apple.com/documentation/alarmkit.md, https://developer.apple.com/forums/thread/815064, https://x.com/simonbs/status/1933874805067108653, https://mjtsai.com/blog/2025/06/20/ios-26-alarmkit/
- [M] Third-party consistency approaches. Sleep Cycle's newer score has three pillars (Duration, Quality, Routine) with Routine the biggest weight (no numeric weights published); Routine uses SRI plus weekday/weekend wake gap and advises wake variation under 1 h. WHOOP's sleep consistency is a 0-100% measure of bed/wake time similarity over roughly the last 4-5 nights (community report, not official). SleepScore (sleep.ai) uses deviation from average bed/wake time. COROS includes bedtime consistency as one of six factors. Oura's Sleep Score contributors include total sleep, efficiency, latency, restfulness and timing (personalized ideal bedtime); no consistency formula or weights found. RISE uses sleep debt plus a circadian-based energy schedule. I found no usable AutoSleep documentation.
  Design implication: Copy the pattern: weight consistency at least as much as duration, measure it as deviation from the person's own recent norm, and judge over 7-14 days rather than a single night. Do not copy any vendor's undocumented weights.
  Sources: https://sleepcycle.com/sleep-talk/understanding-your-sleep-score, https://www.community.whoop.com/t/whoop-sleep-consistency/800.md, https://support.ouraring.com/hc/en-us/articles/360057792293, https://resources.sahha.ai/product/sleep-score-explained, https://www.risescience.com/blog/app-sleep-science-become-morning-person
- [M] Fairness reasoning (not researched, no study on couple-based comparative sleep scoring found). Consistency metrics (SRI, deviation from own median) are relative to each person's own routine, so they do not reward free time. Duration needs a personal target and an upper cap because sleeping long is not a habit to reward.
  Design implication: Each person sets target wake window and sleep need (default 7.5 h, range 7-9 h). Points come from adherence to their own targets, never raw hours. For head-to-head, compare percent-of-max or streak length, not minutes of sleep.
  Sources: https://elifesciences.org/articles/88359, https://sleepcycle.com/sleep-talk/understanding-your-sleep-score

### Alternatives considered

- Self-report one-tap morning check-in ('up by target?') instead of or alongside the step proxy: simple and unambiguous, but honor-system, which is reasonable between a couple.
- Use only a weekly SRI-style number (as Sleep Cycle weights Routine highest) with no per-night score: simplest and best evidenced, but gives less daily feedback for streaks.
- Compute MSFsc-corrected social jetlag instead of the simple midpoint gap: more precise, but its formula was not verified here.
- Use Screen Time / DeviceActivity for first-pickup wake detection (as RISE reportedly does): not researched here and likely needs the Family Controls entitlement; verify before committing.
- Ask users to screenshot Apple's Sleep Score: rejected, since it is not in HealthKit and cannot be automated.

## architecture-sync

### Recommended approach

Flutter client with drift as a read cache plus a small hand-rolled idempotent outbox. The server is authoritative for scores, streaks and head-to-head. Backend is TypeScript (Hono + Drizzle + Postgres) with an in-process pg-boss/cron scheduler. It runs daily scoring, pushes, and nightly claude-sonnet-4-6 calls, and also serves a static web dashboard, all in one app container. Compose = caddy + app + postgres, with nightly pg_dump. HealthKit ingestion is the one native piece: a thin Swift channel doing observer + anchored queries and background delivery, sending upserts keyed by (user, hk_uuid) plus tombstones from HKDeletedObject, advancing the anchor only after a server ack. Treat background delivery as best effort and sync on every foreground. Store raw samples with UTC instants and device tz, derive daily_metric by local date (sleep by end date), and make scoring a recomputable pure function.

Schema sketch:
user(id, name, tz_default)
device(id, user_id, token_hash, name, last_seen, revoked_at)
health_sample(user_id, hk_uuid PK, type, value, unit, start_at, end_at, tz, source, deleted_at)
hk_anchor(user_id, device_id, type, anchor_blob)
workout(user_id, hk_uuid PK, kind, start_at, end_at, distance_m, energy_kcal, avg_hr, tz)
daily_metric(user_id, local_date, metric, value, PK(user_id, local_date, metric))
habit_def(id, user_id, key, target_per_day, weight)
habit_log(id, client_op_id UNIQUE, user_id, habit_id, local_date, count, logged_at)
meal_log(id, client_op_id UNIQUE, user_id, local_date, name, kcal, protein_g, carbs_g, fat_g, source, cooked_at_home bool)
food_item(id, barcode, name, per_100g jsonb, source)
score_event(id, user_id, local_date, rule_key, points, detail jsonb) with UNIQUE(user_id, local_date, rule_key), rebuilt idempotently
streak(user_id, habit_key, current, best, last_date)
challenge(id, kind, period, metric, handicap jsonb) and challenge_result(challenge_id, user_id, value, rank)
goal(id, user_id, year, metric, start_value, target_value)
generated_plan(id, user_id, week_start, model, prompt_hash, plan jsonb)
push_token(device_id, apns_token)
sync_op_seen(client_op_id PK, device_id, applied_at) for dedupe

### After verification

The recommendation largely stands: Flutter client with Drift read cache and a hand-rolled idempotent outbox, server-authoritative scoring, thin Swift HealthKit channel with observer plus anchored queries and tombstones, foreground sync as the reliable path. Changes: (1) Keep the Dart `health` package only for convenience reads; it has no anchors or deletions on iOS, so the native Swift module owns ingestion. (2) Do not rely on the forum threads for background cadence or locked-phone behavior; they are watchOS-extension reports and do not mention locking. Handle databaseInaccessible by deferring until protected data is available, and add a periodic reconcile on foreground in case deletion records have expired. (3) For cumulative metrics (steps, active energy), use HKStatisticsCollectionQuery (or equivalent source-deduplicated aggregation) rather than summing raw samples, to avoid iPhone/Watch double counting. (4) Go is a viable alternative: the official anthropic-sdk-go v2 is maintained (Go 1.25+), so the TS choice should rest on Nick's preference and scheduler ergonomics, not SDK availability. (5) Verify pg-boss version and the pinned Claude model ID before implementation. Correct the flutter_offline_first_sync version to 0.1.1."

Claims that did not survive unchanged:

- UNCERTAIN: 3. Background delivery is advisory; hourly cap for some types; forum shows 8-16 min vs ~1 hr; protected data unreadable while locked
  Correction: The variance numbers come from Apple Watch extension reports on watchOS, not iPhone apps, so they are weak evidence for an iPhone-app design. The locked-phone claim is likely true (HealthKit data protection, HKError.databaseInaccessible) but the cited threads do not support it; cite Apple's HealthKit data protection docs or drop the forum attribution. Treat background delivery as best-effort either way.
- UNCERTAIN: 5. Inference: real offline need is write-capture plus cached reads; single-owner records; shared things server-authoritative LWW
  Correction: None needed. One caveat: head-to-head views and streaks are derived from the other person's data, so those are cached-read-only and may be stale offline; the UI should show last-synced time.
- UNCERTAIN: 7. Inference: Postgres over SQLite for jsonb, timestamptz, generate_series, pg-boss
  Correction: Reasonable. Verify pg-boss current major version and Postgres requirement before committing; node-cron or a simple in-process scheduler is an alternative for this scale.
- UNCERTAIN: 8. Inference: day must be user-local; cumulative types summed per local day; sleep belongs to the day it ends on; fixed server tz wrong
  Correction: Add: store the tz per sample (already in schema) and, for cumulative types, prefer HKStatisticsCollectionQuery on-device to avoid double-counting overlapping sources (iPhone + Watch steps); summing raw samples server-side will over-count unless de-duplicated by source priority. This is inference, not verified.

### Cannot do or could not verify

- Could not verify wger, Gadgetbridge, Home Assistant or Fitbit-like schemas; the time-series modeling claim is inference from common practice (low confidence).
- Could not verify the current Anthropic Go SDK status or the TS SDK version; the claude-api skill should be consulted before implementation.
- Could not confirm that the `health` package lacks iOS background delivery beyond its pub.dev page, which does not document it. A pub.dev README check of its source or issue tracker is advisable.
- Could not verify whether Renpho syncs to Apple Health in a way that preserves per-sample UUIDs and body composition fields. This is on the critical path for scale data.
- Did not benchmark background delivery behavior on iOS 26 devices; evidence is forum reports only.
- Plan mode was active, so no files were written or prototypes built.

### Claims

- [H] HealthKit gives every sample a UUID and the Flutter `health` package (v13.3.2 on pub.dev, iOS 15+, SwiftPM/CocoaPods) exposes it as HealthDataPoint.uuid, so idempotent upserts keyed on (user, uuid) are feasible. It reads workouts, sleep stages and routes.
  Design implication: Server table health_sample has a primary key of (user_id, hk_uuid) and ingest uses INSERT ... ON CONFLICT DO UPDATE. Re-sending the same batch is harmless, so the client can retry freely.
  Sources: https://pub.dev/packages/health
- [H] The `health` package page documents no iOS background delivery, no anchored queries and no deleted-object tracking. Apple's HKAnchoredObjectQuery returns new samples plus HKDeletedObject (UUID only) against a persisted anchor, and Apple says the deletion records are temporary. Observer queries do not list deletions; pair them with an anchored query.
  Design implication: Plan a small custom Swift platform channel (or Flutter plugin) of roughly 200 lines. It runs HKObserverQuery with enableBackgroundDelivery and HKAnchoredObjectQuery, and stores the anchor per type. It posts upserts and tombstones to the server and advances the anchor only after the server acks. Keep the Flutter `health` package for permissions and foreground reads. This is the one place Swift is unavoidable, and it stays tiny.
  Sources: https://developer.apple.com/documentation/healthkit/hkdeletedobject.md, https://developer.apple.com/documentation/healthkit/hkanchoredobjectquery.md, https://pub.dev/packages/health
- [M] HealthKit background delivery is advisory. Hourly is the documented cap for some types such as steps. Forum reports show wide variation, from 8-16 minutes on some devices to about 1 hour on others, and no guarantee. Health data is also unreadable while the phone is locked ('Protected health data is inaccessible').
  Design implication: Never depend on background push for correctness. Sync on every app foreground and on background delivery as a bonus. The server should score a day from whatever has arrived and re-score idempotently when late data lands, so scoring is a recomputable pure function of the stored data. Show the user a 'last synced' stamp.
  Sources: https://developer.apple.com/forums/thread/814914, https://developer.apple.com/forums/thread/790004, https://pub.dev/packages/health
- [M] Offline-first Flutter sync packages exist (syncdrift_flutter 0.1.1, sync_queue_drift 0.1.x, flutter_offline_first_sync 0.1.0) but they are all young and 0.x. Drift is the established SQLite layer.
  Design implication: Do not adopt a 0.x sync framework. Hand-roll a small outbox, about 150 lines, on drift: a pending_ops table of {client_op_id uuid, kind, payload, created_at}. Retry in order with exponential backoff. Every write endpoint is idempotent on client_op_id. Reads are cached in drift so screens render instantly and offline.
  Sources: https://pub.dev/packages/syncdrift_flutter, https://pub.dev/packages/sync_queue_drift, https://pub.dev/packages/flutter_offline_first_sync
- [M] Inference: with two users and a home server that is sometimes down, the real offline need is write-capture (log a meal, tick a habit, brush teeth) and a cached read of the last-known state. Full multi-master sync is not needed, because each record has a single owner. Conflicts only arise on shared things (shared goals, challenges), which can be server-authoritative and last-write-wins.
  Design implication: Use a hybrid: drift cache plus an outbox, with the server as the single source of truth for scores, streaks, and head-to-head. Do NOT compute streaks and points on the client. The client shows optimistic provisional values and replaces them with server values after sync.
  Sources: reasoning from project context; no external source
- [M] Inference: Go+Postgres+Caddy and TypeScript (Hono/Next + Drizzle + Postgres) are both fine at this scale. The main differentiators are scheduled jobs and the Claude API. Both have official or supported Claude SDKs; I did not verify the current Go SDK status in this pass. Nick has shipped both stacks.
  Design implication: Recommend TypeScript (Hono API + Drizzle + Postgres) with an in-process scheduler (pg-boss or node-cron) and one shared codebase with the web dashboard. The Anthropic TS SDK is the first-party default and Zod types can be shared. Choose Go if he wants a single static binary and minimal memory; this is a taste call, not a technical constraint. Before building, check the Anthropic Go SDK status via the claude-api skill.
  Sources: reasoning from project context; Go SDK status not verified
- [M] Inference: SQLite would technically suffice for two users, but Postgres is already in Nick's toolbox and gives timestamptz, jsonb, generate_series for day-bucket reports, and pg-boss. The extra container is cheap on a home server.
  Design implication: Use Postgres. Compose with 3 services: caddy (TLS for *.npc-server.top), app (API + scheduler + web dashboard in one container), postgres with a volume plus a nightly pg_dump to another disk. Keep the scheduler in-process in the app container instead of a separate worker; split it out only if jobs block requests. Use Claude calls with claude-sonnet-4-6 per Nick's rules, in a nightly job that writes a workout plan or insight into a table, never in the request path.
  Sources: reasoning; no external source
- [L] Inference from common practice: health apps store raw per-sample rows (immutable, keyed by source UUID) and derive daily aggregates in a separate table. I did not fetch the wger, Gadgetbridge or Home Assistant schemas in this pass, so no claim is made about their internals.
  Design implication: Two layers. health_sample is the raw layer: type, value, unit, start_at and end_at as timestamptz, source, hk_uuid, tz, deleted_at. daily_metric is derived: (user_id, local_date, metric) with value, rebuilt idempotently from raw rows. Charts and scoring read daily_metric. Raw rows are kept so any metric can be recomputed when the scoring rules change.
  Sources: no verified source; wger/Gadgetbridge/HA schemas not fetched
- [M] Inference: 'day' must be defined in the user's local time, not UTC. Cumulative types (steps, active energy) are summed per day, while sleep belongs to the day it ends on. Travel and DST make a single fixed server timezone wrong.
  Design implication: Store each sample's UTC instants plus the device IANA tz at ingest time (health_sample.tz). Compute local_date = (start_at AT TIME ZONE tz)::date. Sleep: assign by end_at local date. Keep a user_tz_history table so recomputes are deterministic. Define an app-wide 'day rolls over at 04:00 local' setting for habit and meal logs, so late-night logging counts toward the same day.
  Sources: reasoning; no external source
- [M] Inference: with no real auth, pairing = enter server URL, GET /users to list the two profiles, tap your name, and POST /pair to get a random device token that is stored in the iOS Keychain. The main risks are two devices claiming one user (for example a new phone), and a stranger on the internet claiming a profile, since the domain is public.
  Design implication: Add a minimal gate, since the cost is small: a shared household passphrase (or a one-time 6-digit pairing code that Nick generates on the web dashboard) required at /pair. Tokens are per device (device table: id, user_id, token_hash, name, last_seen), and multiple active devices per user are allowed (new phone, iPad). Revoke is a button on the dashboard. Never rely on device HealthKit identity; it is not exposed. Alternatively keep the server on a Tailscale/LAN-only hostname and skip the passphrase.
  Sources: reasoning; no external source
- [M] Inference: a web dashboard is cheap if the API is TypeScript. Big before/after charts, year-in-review, and admin tasks (pairing codes, scoring-rule tuning, data backfill) fit better on a laptop screen than a phone.
  Design implication: Serve a small server-rendered or Vite/React SPA from the same container under the same domain, using Recharts or uPlot against the same JSON API. Use a Next.js app only if he wants SSR or he prefers its ergonomics; a plain Hono + static SPA is lighter. Gate by the same device-token cookie.
  Sources: reasoning; no external source

### Alternatives considered

- Online-only REST with optimistic UI and no local DB: simplest, but writes made while the home server is down are lost and the first screen waits on the network. Acceptable only if downtime is rare and logging is tolerant of retry.
- Full local-first sync engine (PowerSync, ElectricSQL, Replicache-style): robust multi-master sync, but heavy for two users with single-owner data and adds a service to run. Not verified in this pass.
- Go + Postgres + Caddy (Nick's existing pattern): equally valid, single static binary, lower memory. Cost is no shared types with a web dashboard and a separate frontend stack.
- SQLite instead of Postgres in a single container with litestream backup: fewest moving parts and fine for two users; loses jsonb and generate_series conveniences.
- Next.js + Drizzle full-stack (Nick's other pattern) giving API and dashboard in one framework: fine, but heavier runtime than Hono + static SPA for a mostly-JSON API.
- Third-party aggregators (Vital/Junction, Spike) for HealthKit ingestion: they appeared in search results as SDKs but are cloud services, so they conflict with self-hosting; not recommended.

## Completeness critic

### Features or flows no topic covered

- First-run onboarding and pairing flow: server address entry, who-am-I selection, the per-person data checklist (equipment, schedule, targets, injuries, meds), HealthKit permission walkthrough. Only fragments exist (architecture device/token_hash, passphrase question); no topic owns the screen flow, re-pairing after reinstall, or a lost phone.
- To-do list with task-completion rewards is not covered by any topic. No schema table (architecture has habit_log but no todo/task), no scoring weight in gamification, no notifications design for it.
- Reward for not ordering food out / DoorDash is only a nutrition weight line. Nothing says how it is detected (self-report? bank/email receipts? 'cooked at home' toggle), how the honor system is verified, or what counts on days with no dinner logged.
- Year-long goal and start-vs-now metrics: architecture has a goal table, but no topic defines which metrics, baseline capture at day 1 (weight, 1-mile time, pushups max, resting HR, VO2max), how Jan-to-Dec progress is displayed, or what the year-end reward is.
- Math problems as a standalone feature: only appears as the alarm dismissal check. No design for daily math practice, difficulty, scoring, or whether it is a habit at all.
- Pushups / pull-ups / miles head-to-head: HealthKit gives workouts and distance but not rep counts. No topic defines manual rep logging, a strength-test or max-reps challenge flow, or how Hall of Fame raw totals are captured.
- Workout logging UX during a session: sets, reps, weights, rest timer, Watch companion or not. The generator is covered but the in-session logger, exercise swap UI and history/progression view are not.
- Meal planning loop that actually drives 'cook more at home': recipe selection, weekly meal plan, shopping list, pantry, and the daily 'what's for dinner' nudge. Nutrition covers Mealie as an option but no topic ties it to scoring (cooked_at_home flag) or to the 5pm nag.
- Calorie and macro targets: no topic computes TDEE/goal calories or protein targets from weight and body goals, and gamification deliberately avoids calorie scoring, so the purpose of calorie tracking is undefined.
- Running-specific flow: run tracking source (Watch workout import only vs in-app), plan display, treadmill runs (no GPS, distance from Watch), and Watch-side delivery of the plan. WorkoutKit was unverified.
- Weekly and monthly recap / review screen and the LLM narrative. Mentioned as a notification and a job but with no screen or data design.
- Settings and admin: editing targets, availability weekly check-in, rest days, scoring weights, partner-flag/dispute resolution UI, data correction. Gamification assumes these exist; architecture only offers a maybe-admin web dashboard.
- Failure and offline modes beyond sync: home server down, domain/cert expiry, how a TestFlight build behaves with no backend, and backup restore for Postgres.
- Home server exposure and reachability: *.npc-server.top domain, Caddy TLS, LAN-only vs public vs Tailscale. Notifications topic needs APNs outbound from the server, and phones need to reach it away from home.
- Watch app: nobody decided if there is a watchOS app. Several features (one-tap creatine, workout start, quick teeth tap, plan on wrist) imply one, and it changes signing and build.
- Screen-time 'not typing password / ignoring limit' incentive from the original note has no workable source (explicitly cannot detect). No replacement mechanic is proposed.
- Sleep and wake: wake-up improvement beyond alarm - e.g. wind-down routine, caffeine cutoff, light exposure - and the 'Huel in the morning' sequence tied to wake time are not connected.
- Data export, year-end archive, and what happens to data if the relationship or the app stops (low priority but missing). Also onboarding of a future third person is explicitly out of scope; confirm.
- Tracking of reading as 'instead of videos': no mechanism to measure video time (YouTube etc.), only screen-time buckets or Shortcuts open counts.

### Risky assumptions

- Background HealthKit sync via a custom Swift shim is treated as a core design element in healthkit and architecture topics, yet delivery is best-effort, evidence is only watchOS reports, and iPhone iOS 26 behavior is untested. Daily scoring, streaks and the head-to-head depend on data arriving; the partner's view will often be stale or missing mid-day.
- Apple Watch worn to bed by both, every night, is assumed by the sleep model (and HRV, workout, HR-zone effort points). If Nadia charges overnight or Nick forgets, sleep scoring, effort-based workout points and readiness all degrade. Neutral-skip rules cover only 1 night per week.
- Renpho writes body fat, lean mass and BMI to Apple Health and weigh-ins land on the right profile for a single shared scale. Unverified. Architecture flags per-sample UUID preservation as critical path. Misassignment between two people with a shared scale is plausible and silently corrupts the year-long before/after metrics.
- Family Controls distribution entitlement is not guaranteed for a private TestFlight app, may take weeks, and dev entitlement does not work on TestFlight. Screen time is weighted 0.05 and is manual/OCR first, so the risk is low in score but the original 'passwords/limit bypass' idea is dead.
- Monthly CI re-upload to beat the 90-day TestFlight expiry is a recurring failure mode: a lapsed CI key, Xcode requirement bump (April 2026 style), or expired certificate silently leaves both phones with an expired app. Single point of failure with no alerting is proposed.
- Internal TestFlight needs Nadia as an App Store Connect user; unverified role and no-review claim. Also internal testers are capped and Nadia gains a (limited) role in Nick's developer account.
- Native Swift surface is larger than any one topic admits: HealthKit shim, optional clinical records plugin, DeviceActivityMonitor extension, WidgetKit extension merged with AlarmKit and Live Activity templates, AppDelegate wiring for notification actions, possible APNs token shim, possible Watch app. Plugin-generated extensions are noted to conflict, and the combined maintenance load on a Flutter project may erase the benefit of not being Swift-only.
- AlarmKit math-to-dismiss cannot block dismissal and cannot run code on fire; the original idea may not be deliverable. Also AlarmKit requires iOS 26 on both phones and the dismiss/stop signal is unreliable on 26.2.
- Scoring model has many untested numbers (weights 0.25/0.20/..., 0.7 streak cutoff, capacity clamp 0.6-1.2, sleep bands) and is a multiplicative stack of personal baselines (median of last 4 weeks x1.05, capacity scaling, effort units). Complexity makes it opaque, and baselines recomputed from your own history can punish improvement or let someone sandbag early weeks to set a low target. No cold-start rule for the first 4 weeks.
- Self-reported items (teeth, creatine, Huel, home-cooked, reading minutes via timer) dominate points while HealthKit data is trusted; a couple who are honest may be fine, but the design adds partner-flag machinery that could feel adversarial. Combined cap on self-report weight is mentioned but not specified.
- LLM dependencies: label OCR, meal estimate, lab PDF extraction, weekly workout choice, monthly narrative all assume an Anthropic API key and sending lab PDFs and photos to a cloud service. Cost, privacy of bloodwork and server outbound reliability are accepted without sign-off.
- Fairness is built on 'work hours, horse days and travel' being declared weekly by each person; this assumes a weekly manual check-in habit that itself is another chore, and that the horse schedule is stable enough to model.
- Exercise catalog assumes free-exercise-db covers pull-up bar, treadmill, yoga and climbing adequately; 40-80 curated overlay rows plus yoga templates is a content-authoring effort treated as small. Yoga has no dataset at all, and yoga is Nadia's main workout, so her experience is hand-built.
- Mealie in the same compose stack plus Audiobookshelf plus Postgres plus app adds multiple self-hosted services to maintain, each with separate auth models, for two users. Ripping Audible books via Libation is a ToS gray area, and ABS requires switching players.
- Bloodwork nudges, even with guardrails, are health advice; the rules table needs human verification of every dose and the HealthKit clinical records route has unknown entitlement behavior on TestFlight.

### Contradictions between topics to resolve in the design

- Backend language: nutrition (Go API), healthkit-flutter and notifications (Go + sideshow/apns2, Go server), vs architecture-sync (TypeScript Hono + Drizzle, pg-boss). Workout generation and bloodwork assume 'Go backend' or 'server job' loosely. Pick one; Nick has shipped both.
- Where raw HealthKit data goes: healthkit-flutter has the Swift shim upload via background URLSession straight to the server with source-priority dedupe server-side, while architecture says use HKStatisticsCollectionQuery on-device for cumulative types to avoid double counting and sum raw samples only with dedupe. Both claim a different owner of the step/energy total.
- healthkit-flutter says send raw samples and dedupe by source priority server-side while also recommending HKStatisticsCollectionQuery daily totals. Architecture schema stores only raw health_sample and derives daily_metric, with no column for client-computed statistics. Needs one rule.
- Screen time: ios-screen-time says use the Family Controls entitlement approach later and OCR first; books-audiobooks suggests Screen Time per-app minutes are unavailable and treats it as a dead end; gamification scores screen time as ratio to 4-week baseline from data nobody can get automatically. The scoring weight assumes a numeric daily input that only manual or OCR supplies, with accuracy and effort burdens that do not fit a 0.05 weight.
- Alarm and sleep: notifications topic builds AlarmKit around a math dismiss screen; sleep-wake says never score on stop-intent time and dismissal cannot be reliably detected. The 'math problems' reward then has no trustworthy trigger, and 'get moving within 30 min' proxy is unvalidated.
- Sleep scoring weights differ between topics: healthkit-flutter notes Apple's score (duration 50, bedtime consistency 30, interruptions 20) but sleep-wake builds a different 0-100 model plus weekly SRI. Gamification gives sleep weight 0.10 in daily points, but sleep-wake has both a nightly score and a weekly score with its own points; unclear how they feed daily points or streaks.
- Streak thresholds: gamification uses s >= 0.7 for daily streaks, sleep-wake uses nightly score >= 70 with a neutral-skip of 1 night per week, gamification allows 2 declared rest days per person. Three different forgiveness mechanisms (rest days, freezes, neutral skip) overlap with no precedence.
- Toothbrushing and creatine: gamification lumps them as binary 'basics' at 0.10 weight, bloodwork topic wants grace until noon for Huel/creatine and notifications want local repeating reminders with a Done action; no single source of truth defines when a day's habit window closes (architecture proposes a 04:00 rollover question, others assume midnight).
- Fairness approach: workout-generation says normalize to time budget and relative-to-plan completion; gamification uses capacity c from free minutes with a clamp and median-based targets and also adds a Hall of Fame of raw totals. Two parallel fairness mechanisms (plan completion vs capacity-scaled target) must be unified or workout points are double-adjusted.
- Cooperative-first vs head-to-head: user wanted PvP comparisons (pushups, miles); gamification recommends cooperative as primary and demotes raw comparisons to a non-scoring tab. Needs the user's decision, not just the researcher's inference.
- Nutrition scoring: gamification rewards logging and home cooking but never calories, nutrition-data builds a full barcode/label/LLM calorie-tracking system, user also asked for a calorie tracker. Heavy investment in detail that scoring deliberately ignores; what the logged numbers are used for is unspecified.
- Workout push to Watch and Watch app: workout-generation floats WorkoutKit, notifications and bloodwork imply one-tap Watch actions, ios-private-distribution says to ask whether a watchOS companion is needed and notes it changes signing. No topic assumes the same answer.
- Local notifications must work if the server is down (notifications), while gamification, scoring and streaks are server-authoritative (architecture) and the Done action POSTs to the backend. Offline taps need the outbox, but the notification action background handler is a separate code path from the drift outbox.
- Muscle of the HealthKit surface: bloodwork recommends reading HealthKit clinical records and HKMedicationDoseEvent as spikes, healthkit-flutter lists a defined set of types to request in onboarding; permission list and the number of HealthKit prompts vary, and the entitlement/TestFlight risk is unresolved.
- Distribution: ios-private-distribution recommends Codemagic/GitHub with scheduled builds plus optional Shorebird; the Family Controls dev entitlement 'does not work on TestFlight' and the HealthKit plus App Group plus Push capabilities are baked into the App ID. Combined with Shorebird 'cannot target a TestFlight group', patch strategy is inconsistent with the rest.
- Server exposure: architecture asks LAN/Tailscale vs public; user said no auth needed and cached identity, notifications requires APNs from server (outbound only, fine), but phones away from home need reachability, and the pairing passphrase (needed if public) contradicts the 'no auth' ask.

### Questions raised

- Do you have a Mac, even occasionally? If not, will you accept Codemagic/GitHub Actions CI as the only build path? And is your developer account individual or organization, and are you the Account Holder (to add Nadia as an App Store Connect user)?
- Which backend language: Go (single binary, like your Flutter+Go+Postgres+Caddy app) or TypeScript (Hono/Next + Drizzle, shared with a web dashboard)? Do you want the web dashboard at all?
- Is the server reachable from the public internet at npc-server.top, or only via LAN/Tailscale? What should happen when you two are away from home and the server is down?
- Are you okay with a Swift layer of several targets (HealthKit shim, widget extension, AlarmKit intent, possibly a Watch app) inside the Flutter project, or should we cut anything that forces more than the HealthKit shim?
- Do you want an Apple Watch app (start a workout, one-tap creatine/Huel/teeth, see today's plan) or is the iPhone app plus normal Watch workouts into Health enough?
- Is 'by next morning plus whenever the app opens' enough for syncing health data, or do you need near-real-time partner comparisons during the day?
- Check on both phones: does the Renpho app write weight, body fat and lean mass to Apple Health (Health > Sources), do you each have your own Renpho account/profile, and what is the scale's model number and are your weights far enough apart for auto-recognition?
- Do both of you wear the Apple Watch to sleep every night? When does each of you charge it?
- Nadia: how competitive is she, honestly? Does she want a head-to-head at all, or cooperative-first with a light weekly duel? What does 'fair' mean to her, and would she tolerate a capacity-scaling system that shows her schedule inputs to you?
- What exactly are Nadia's weekly fixed commitments: work hours, commute, which days and hours are horse days, and how physical are they (riding only or mucking and lifting)? Does the horse schedule change week to week, and would she do a short weekly availability check-in?
- What dumbbells do you have (adjustable or fixed pairs, which weights)? Is the apartment gym equipment list known (machines, barbell, rack, cable)? Does Nadia want strength training or just yoga plus running, and how should yoga be generated (own routines, videos, studio)?
- Training level and limits per person: lifting history, current running ability (can each of you run 20 minutes continuously?), injuries, and how many days a week and how long per session on workdays versus off days? How often and how hard do you climb (bouldering vs lead, hangboard)?
- Which calorie tracking depth do you want: just calories and protein, or full macros and micronutrients? Do you have calorie or weight goals (cut, maintain, build), and are you okay that scoring never rewards lower calories? Do you actually want a calorie tracker to be used daily, or only for cooked-at-home logging?
- What is your typical pantry and where do you shop? (Drives a 30-50 barcode test.) Do you want recipes in Mealie, in your own tables, or not at all in v1? Do you eat out often enough that restaurant and chain meals matter?
- How do you want 'no eating out / no DoorDash' verified: honor-system tap, partner check, or receipt/email detection? What counts as eating out (coffee, lunch at work)?
- Which LLM provider for label OCR, meal estimates, lab PDFs and workout choice: Anthropic API key on the server, or a local model? Are you comfortable sending bloodwork PDFs to a cloud API?
- Where do you each read or listen today: Audible, Libby, Apple Books, Kindle, paper? Would you move audiobooks into Audiobookshelf (DRM-free or ripped Audible) or must listening stay in current apps? Is a start/stop timer or Shortcut automation acceptable?
- Is a daily or weekly screenshot of Screen Time acceptable, and are you willing to request the Family Controls entitlement and accept possible rejection? Do you want to reward only lower total time or specific apps (social, video)?
- Is a math-to-dismiss alarm a hard requirement, given Apple lets the user always stop an AlarmKit alarm? Are both phones on iOS 26.x? Would an app-prompted math check-in after the alarm be acceptable?
- What does your bloodwork source look like (Quest, Labcorp, Kaiser/Epic)? Is it in Health Records? Any medications, supplements, kidney/thyroid/iron conditions, or pregnancy plans that should suppress nudges? Which toothbrushes do you own (Oral-B, Sonicare, plain)?
- What time should a 'day' end (midnight or 04:00), what is the grace window for creatine and Huel (noon?), and should AM/PM teeth have fixed windows?
- What rewards would you two actually care about (date night fund, winner picks the meal, bigger quarterly reward), and who controls payout? Do you want raw leaderboards (most pushups, most miles) visible, and how do you want pushup and pull-up counts captured?
- What should the year goal be, and which start-vs-now metrics do you each want on day one (weight, body fat, 1-mile time, max pushups, resting HR, VO2max, screen time average)? Should the year start now (Oct 2026) or Jan 1, 2027?
- Should the to-do list be shared, personal, or both, and how should rewards for tasks work (points per task, partner-assigned tasks)? Should math problems be a standalone daily habit?
- How long to retain raw data and where do nightly Postgres backups go? Is the 90-day TestFlight cliff acceptable with a monthly CI rebuild, or would you prefer ad hoc as primary?

### Suggested MVP cut

- Week-one foundation: Flutter app, Go (or TS, pick one) + Postgres + Caddy in Docker Compose behind a *.npc-server.top host, pick-your-name pairing with a device token, onboarding checklist that captures targets, schedule and equipment, TestFlight internal build via CI with the 90-day rebuild scheduled and alerted.
- Habit core with immediate reward: daily check-ins for teeth AM/PM, creatine, Huel, no-eating-out and home-cooked dinner, using local repeating notifications with Done actions and a home-screen streak widget (or in-app only if the widget extension is too costly). Duolingo-style streaks with rest days and freezes, one simple forgiveness rule.
- HealthKit read on app open only (no background delivery in v1): steps, workouts, distance, weight/body fat from Renpho, resting HR, sleep duration. Use the `health` package, no Swift shim yet, plus a 'last synced' indicator. Capture day-1 baseline metrics for the year start-vs-now page.
- Simple, transparent scoring: personal targets set by hand at onboarding (no median/capacity engine yet), daily points over 5 to 6 habits with one cap, weekly shared quest plus a light weekly duel as percent of own target, and a household streak. Hall of Fame tab with manual pushup and mile totals.
- Fairness in v1 is a manual weekly availability toggle (normal, busy, horse day) that scales that person's targets, shown to both. Defer calendar integration and capacity math.
- Cooking at home loop: manual meal log with 'cooked at home' flag, quick-add calories and protein, favorites and recents, and a single USDA/OFF barcode lookup with a manual-entry fallback. Defer LLM label scanning, Mealie and the preloaded Branded import.
- Workouts: manual logging plus a rules-only 3-day full-body and run/walk generator from the free-exercise-db catalog and equipment profiles, no LLM, no scheduling solver; yoga as a few hand-written sessions for Nadia.
- Sleep: show last-night duration and wake-time consistency from HealthKit, with the simple nightly score and sleep streak only; defer SRI, social jetlag, and AlarmKit.
- Reading: in-app start/stop timer and quick log with a daily cap; defer Audiobookshelf, Hardcover, Audible, and Shortcuts automation.
- Screen time: weekly screenshot or typed number, relative to own baseline, 0.05 weight; submit the Family Controls entitlement request in parallel and do nothing else until it is approved.
- Defer to later phases: bloodwork ingestion and supplement nudges, background HealthKit delivery shim, VO2max, toothbrush HealthKit events, AlarmKit math alarm, Live Activities, Watch app, Renpho cloud poller, LLM workout choice and monthly narrative, climbing/horse load scheduling, to-do list with rewards (consider a very small version as it is cheap), web dashboard.
