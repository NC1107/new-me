# New Me v6: autopilot, widgets and Watch

Earlier design documents still hold unless a section below changes them.

## Why

Nick, after using v0.3.0: "right now it's a lot of manual tasks and doesn't feel like the app is doing anything for me."
He also picked widgets and an Apple Watch app.
So this phase moves the app from a logbook to an assistant: it reads what already happened, credits it automatically, tells each person what matters today, and nudges at the right moment; manual entry becomes the exception.

## 1. Credit what already happened

- **Audiobooks feel live.** The listening poll runs every 5 minutes, and `POST /api/me/audiobookshelf/sync` (throttled to once a minute per person) runs it for the caller on app open, pull to refresh and Today resume, so listening shows up within seconds of opening the app.
  The reading card shows "Listening synced 3 min ago".
- **Workouts complete quests.** A strength or HIIT workout of 15 minutes or more from Apple Health completes the "Get stronger" quest for that day, whatever the push-up count; push-ups still count when logged.
  Yoga, pilates and flexibility workout minutes count toward the yoga quest.
  Quest cards say "Done by your Strength workout, 42 min".
- **Meals from a photo or a sentence.** The meal sheet gains "Snap it" (camera or photo library) and "Describe it" ("chicken burrito bowl, no rice").
  The server sends the image or text to Claude (`claude-sonnet-4-6`, vision for photos) with a strict JSON schema and returns `{name, kcal, protein, carbs, fat, fiber, confidence, notes}`, which pre-fills the form for one-tap confirmation; nothing is logged without the person confirming.
  Config `NEWME_ANTHROPIC_API_KEY`; unset hides both buttons.
  Images are not stored.

## 2. The app tells you what matters

- **Readiness.** Each morning the server computes a simple readiness from last night's sleep against the person's target, and HRV and resting heart rate against their own 30-day baselines: Ready, Normal or Take it easy, with the one or two reasons in plain words ("HRV 18% below your usual, slept 6 h 10").
  Shown as the first card on Today; tapping explains the numbers.
  Without enough history (fewer than 7 days of HRV or resting HR) it uses sleep only and says so.
- **Today's plan.** Under readiness, a short generated plan for the day built from data, not chores: which quests are already done by data, what is left and the easiest way to finish ("8,000 steps: you usually get 3,000 after 5 pm; a 20-minute walk at lunch covers the rest"), which habits are due when.
  Rule-based and deterministic; when the Claude key is set, the wording is polished by Claude from the same facts (never new facts), cached per day.
- **Weekly recap.** Every Sunday evening, a recap screen and push: points, counted days, steps, sleep, workouts and reading for the week against the previous week for both people, best day, the challenge result, and one suggestion for next week.
- **Adaptive goals.** Every Monday morning a "Goals for this week" card proposes updated targets from the data (the steps suggestion from v4, sleep target nudged toward what is realistic), each with a one-tap accept; accepting updates the quest template from that day.

## 3. Nudges at the right moment

Server-side, from the data the background Health sync keeps current, sent as push (respecting per-person notification preferences and quiet hours 21:30 to 07:30 except the sleep nudge):

- **Behind pace** (14:00 and 18:30): if steps are behind the person's usual curve for the time of day, "2,100 steps to go. A 20-minute walk does it."
  Only one per window, never after the steps quest is done.
- **Close to done** (any time): when the day is within one quest of counting, "One quest left: 10 push-ups finishes your day."
- **Wind down** (45 minutes before the bedtime needed to hit the sleep target, from the average wake time): "Bed by 22:40 for 7 h 30."
  Only when sleep is a quest or tracked, and only when last night was short.
- These replace the generic evening reminder when push is available; the local reminder stays as the fallback.
- Nudge preferences in Me > Notifications: Behind pace, Close to done, Wind down, Morning plan (each on by default).

## 4. Widgets

A WidgetKit extension (`top.npcserver.newme.widgets`, App Group `group.top.npcserver.newme`, both registered with profiles in CI):

- Home Screen small: today's percent ring, points and streak.
- Home Screen medium: ring plus today's due habits as interactive buttons (iOS 17 App Intents) that mark the habit without opening the app.
- Lock Screen: circular ring and a rectangular "2 quests left, 3 habits due".
- The app writes a compact snapshot (today's score, quests, due habits, session for the intent's API call) into the App Group whenever Today changes and asks WidgetKit to reload; the habit intent calls `PUT /api/habits/{id}/marks/{date}` with the stored session and updates the snapshot optimistically.

## 5. Apple Watch

A watchOS app (`top.npcserver.newme.watchkitapp`, HealthKit and App Group), SwiftUI, sharing the session through WatchConnectivity:

- Today: the ring, points, streak and quests.
- Habits: due slots, tap to mark.
- Quick log: push-ups with the Digital Crown, reading minutes.
- A complication showing the ring.

## Build and release

- The widget and Watch targets are added to the Xcode project; `release.yml` installs the three profiles (secrets `IOS_PROVISIONING_PROFILE_BASE64`, `IOS_WIDGET_PROFILE_BASE64`, `IOS_WATCH_PROFILE_BASE64`) and `ExportOptions.plist` maps each bundle id to its profile.
- Every native change is verified by the CI iOS build before it reaches `main`.
- A manual `release.yml` run with `dry_run` builds, signs, exports, checks and validates the IPA from a branch without tagging or uploading, so signing changes are proven before they merge.

## Decisions for widgets and Watch

The build is described in `docs/design.md` under "Widgets and Watch (v6)"; these are the choices behind it.

- **One snapshot, written by Dart.** Flutter already holds Today and the session, so it builds the JSON and the native side only stores and forwards it.
  Swift never fetches `/api/today`, which keeps the flattening of habits into slots in one tested place.
- **A file in the App Group, not shared defaults.** An atomic write with "complete until first user authentication" protection never leaves a half-written snapshot and stays readable when a widget refreshes on a locked phone.
- **The token travels in the snapshot.** The interactive widget and the Watch call the API themselves; the App Group is readable only by this team's signed bundles.
  Sign-out deletes the file and sends an empty context to the Watch.
- **Optimistic widget taps.** The intent writes the change and reloads before the request, then folds in the server's answer or undoes only its own change.
  A count habit goes up by one per tap.
- **Watch: network first, then the phone.** A Watch with its own connection talks to the API directly; with none (or a 5xx) it hands the same request to the phone over `sendMessage`, and the phone answers with the status and body.
  The phone activates WatchConnectivity at launch, before any Flutter engine, because that message can wake it in the background.
- **Midnight makes the snapshot stale.** Widgets and the Watch show "New day" instead of yesterday's numbers until the app runs again.
- **Reading minutes on the Watch** sit beside push-ups on the Log page, as section 5 lists, both on the Digital Crown.
- **The complication waits for a profile.** A watchOS complication must be its own widget extension with its own bundle id, and no App Store profile exists for `top.npcserver.newme.watchkitapp.complication` yet.
  The `NewMeComplication` target is built in every CI run (unsigned in Release) so its code stays honest, but the Watch app does not embed it.
  Once the bundle id and profile exist: add an "Embed Foundation Extensions" phase to `NewMeWatch` holding `NewMeComplication.appex`, switch its Release settings to manual signing with the new profile, map it in `ExportOptions.plist`, and install the profile in `release.yml`.
- **HealthKit on the Watch** is entitled and described because the profile carries it, but nothing reads Health on the Watch yet; the phone's background delivery already covers the data.
- **Icons.** The Watch icon is a single 1024 px opaque PNG generated from `assets/brand/icon-1024.png` with ImageMagick; widget extensions need none.
