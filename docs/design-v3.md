# New Me v3: always on

This phase finishes milestone M3 and takes the first items from the "Later" list in `design.md`.
Everything in `design.md` and `design-v2.md` still holds unless a section below changes it.

## Goals

1. The Us tab is current without anyone opening the app: Health reaches the server in the background.
2. Audiobooks count toward the reading quest automatically.
3. A gentle evening reminder protects the streak.
4. The backup is proven restorable.

## 1. Background Health delivery

Native Swift in `app/ios/Runner/`, verified by the CI iOS build.

- The provisioning profile already carries `com.apple.developer.healthkit.background-delivery`.
  `Runner.entitlements` gains that key, and `Info.plist` gains `UIBackgroundModes` with `processing` only if HealthKit delivery needs it (it does not need `fetch`).
- Flutter hands the native side what it needs through a `newme/background` method channel whenever the session or Health permission changes: `configure({baseUrl, token, appKey, clientVersion})` and `clear()` on sign-out.
  Swift stores this in its own Keychain item with `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`, so it is readable when the phone wakes the app in the background while locked.
- At launch, when configured and Health was connected, Swift registers an `HKObserverQuery` and `enableBackgroundDelivery(frequency: .hourly)` for steps, active energy, basal energy, exercise time, walking and running distance and flights climbed.
- On wake it computes each type's cumulative sum with `HKStatisticsQuery` (`.cumulativeSum`, which de-duplicates sources, user-entered samples excluded) for local midnight to now, plus yesterday when the local hour is before 10, and sends one `PUT /api/health/daily` with the same item shape the Dart sync sends (`date`, `metric`, `value`, `source: healthkit`, `measuredAt`).
  A 422 `date_closed` retries with today's items only, like the Dart sync.
- It wraps the work in `beginBackgroundTask`, never runs two pushes at once, skips values equal to the last pushed ones (kept in `UserDefaults`), and always calls the observer completion handler.
- Sleep, heart and body metrics stay foreground-only.
- The server needs no change.

## 2. Audiobookshelf listening

Both people use Audiobookshelf at `books.npc-server.top` (version 2.37.1).

- Server config: `NEWME_ABS_URL` (empty disables the feature).
- `PUT /api/me/audiobookshelf` with `{username, password}`: the server logs in to Audiobookshelf once, keeps only the tokens it needs to stay signed in (refreshing them as Audiobookshelf requires), never the password, and answers with the linked account name.
  `DELETE /api/me/audiobookshelf` unlinks.
  `GET /api/me` gains `audiobookshelf: {linked, username, syncedAt}` (null when the feature is off).
- The scheduler polls each linked account every 15 minutes, reads listening time per day for the last 2 days from the listening stats, and stores it in a new `listening_daily (user_id, local_date, minutes, synced_at)` table.
  Audiobookshelf buckets days in its own server time zone; this is accepted because everyone lives in one zone, and the doc says so.
- The reading quest's minutes become manual reading minutes plus listening minutes for the day.
  Pages still count on their own as before.
  Finalized days never change.
- `GET /api/today` gains `listening: {minutes}` for the day, and the reading quest card shows "18 min listened" under its progress.
- App: Me gains an Audiobookshelf row and page (link with username and password, linked state with last sync, unlink).
  The onboarding Read more goal screen mentions that audiobooks count once linked in Me.

## 3. Evening reminder

Local notifications only (no push server), via `flutter_local_notifications`.

- One reminder per day at a time the person picks (default 20:00), on by default once they allow notifications.
- Copy depends on the day, computed when the app last had fresh Today data: "2 quests left to save your streak" or "You are at 54%, a short walk gets you there"; no reminder at all once the day has counted.
  The app reschedules tonight's reminder every time Today changes and cancels it when the day counts.
- Onboarding gains one step after Apple Health: the mascot asks "Want a nudge in the evening?" with ALLOW and NOT NOW; ALLOW requests notification permission.
- Me gains a Reminders row: on/off and the time.
- Tapping the notification opens Today.

## 4. Operations

- Restore drill: dump the production database through the backup sidecar, restore it into a scratch Postgres container, compare row counts per table, and record the result and the commands in `deploy/README.md`.
- Record that the GHCR package is public and the watchtower poll interval (300 s) in `deploy/README.md`.
