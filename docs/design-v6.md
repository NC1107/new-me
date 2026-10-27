# New Me v6: autopilot, widgets and Watch

Earlier design documents still hold unless a section below changes them.

## Why

Nick, after using v0.3.0: "right now it's a lot of manual tasks and doesn't feel like the app is doing anything for me."
He also picked widgets and an Apple Watch app.
So this phase moves the app from a logbook to an assistant: it reads what already happened, credits it automatically, tells each person what matters today, and nudges at the right moment; manual entry becomes the exception.

## 1. Credit what already happened

- **Audiobooks feel live.** The listening poll runs every 5 minutes, and `POST /api/me/audiobookshelf/sync` (throttled to once a minute per person) runs it for the caller on app open, pull to refresh and Today resume, so listening shows up within seconds of opening the app.
  The reading card shows "Listening synced 3 min ago".
- **Workouts complete quests.** A qualifying strength or HIIT workout (see Server decisions) from Apple Health completes the "Get stronger" quest for that day, whatever the push-up count; push-ups still count when logged.
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

## Server decisions

Sections 1 to 3 are implemented in `server/`; the endpoint shapes, tables and rules are in `docs/design.md` (Endpoints, v6 additions; Schema, migration 0008).
Where this document left a choice open, the server does the following.

### Credit

- The listening poll runs every 5 minutes.
  `POST /api/me/audiobookshelf/sync` is throttled to once a minute per person in memory, so a restart forgets the throttle, which is harmless.
  A throttled call answers with the stored state and does not call Audiobookshelf.
- Pilates and flexibility sessions already reach the server as the `yoga` workout type, so the server only knows `yoga`.
- Beta review rules: a strength workout of 20 minutes or more, or a HIIT workout of 15 minutes or more at an average heart rate of at least 60% of heart-rate reserve, sets the push-ups actual to the target, so the quest earns its full base points and the completion bonus.
  Logged reps still count and win when they reach the target alone; then `doneBy` is null.
  `actual` for push-ups stays the logged reps, so a card can read 0 of 30 with `done: true` and `doneBy`.
  Yoga workout minutes are added to logged yoga minutes in `actual`; `doneBy` is set on yoga only when the quest is complete and logged minutes alone would not have reached the target.
- `PUT /api/health/workouts` rescores open days only, including the day an edited workout moved away from.
  A finalized day keeps its score.

### Meal estimate

- The model is `claude-sonnet-4-6`, `anthropic-version: 2023-06-01`, one user message, the tool `report_meal_estimate` forced with `tool_choice`, so the answer is always arguments of that tool.
- A photo is sent as a base64 `image` block; the optional `text` next to an image is passed on as the person's own words about it.
- The server validates the declared type against the file's magic bytes, caps the decoded image at 5 MB, and drops it after the call; nothing about the image or the text is stored or logged.
- Every number is clamped to the meal log bounds (kcal 1 to 10000, grams 0 to 5000, name 80 characters, notes 200), a missing kcal is an upstream failure, an unknown confidence becomes `low`.
- The 20 per hour limit is a sliding window per person in memory and counts requests that passed validation, since each costs a Claude call.
- `GET /api/me` `features.mealEstimate` tells the app whether to show "Snap it" and "Describe it"; `estimate_disabled` is the fallback.

### Readiness, plan, recap, goals

- Thresholds are in `docs/design.md` and in the package comments, and every one is covered by a table test.
- Readiness is null, not an empty card, when there is neither last night's sleep nor a comparable HRV or resting heart rate.
- The plan has no "when you usually walk" part because the server stores daily steps only; the walk suggestion uses the time of day.
- The Claude wording of the plan summary is generated at most once per person and day, on the first Today load or morning push of the day.
  It is shown only while the same quests are done and open, so a morning text is never shown against an evening state.
  A failed or rejected call is not retried that day, and the deterministic summary is used.
- The recap defaults to the last completed week, except from Sunday 19:00 local, when it defaults to the week that is ending, so the push opens on the week it describes.
  The Sunday push is gated by the new `weeklyRecap` preference.
- A goal proposal is frozen when first shown for the week.
  Dismissing or accepting it ends it for that ISO week.
  Accepting uses the same snapshot-first path as `PATCH /api/me`, including the join-day exception.

### Nudges

- Preferences: `behindPace`, `closeToDone`, `windDown`, `morningPlan` as asked, plus `weeklyRecap` for the Sunday push; `behindPace` and `windDown` default off, the others on.
- At most 2 automatic pushes a person a day (recap included), priority close to done, behind pace, wind down, morning plan only first; none of the first two on an easy readiness day.
- Wording is forward ("2,100 steps to go"), never "behind".
- Goal raises need the goal met on 10 of the last 14 days; nothing about calories is proposed.
- Easy readiness is shown on Today only; scoring is unchanged.
- "Each kind at most once a day" is applied per window for behind pace: `nudge_behind_14` and `nudge_behind_1830` are separate kinds, so there are at most two a day, one per window.
- Behind pace needs a steps reading for today, so a Health sync that has not run yet never produces a "you are behind" push.
- The expected-steps curve and the other numbers are in `docs/design.md`; there is no hourly history to learn them from.
- The decision function is pure (`internal/nudge/decide.go`) and takes the clock in its input; the scheduler loads the facts, claims the kind in `notice_log`, then sends.
  With push off the nudge pass does nothing and claims nothing.
- A wind down whose nudge time would fall before 18:00 (a bedtime after midnight) is skipped rather than moved to another day.

### Configuration

| variable | effect |
|---|---|
| `NEWME_ANTHROPIC_API_KEY` | turns on meal estimates and the Claude plan wording; unset keeps both off |
| `NEWME_ANTHROPIC_BASE_URL` | optional override of `https://api.anthropic.com` |

The listening and nudge features need no new configuration: listening follows `NEWME_ABS_URL` and nudges follow the APNs variables.
