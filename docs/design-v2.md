# New Me v2: playful redesign, real onboarding, full Health

This document supersedes the visual and onboarding sections of `design.md`.
Scoring, seasons, streak rules, access control and the existing wire contract stay as `design.md` describes them unless a section below changes them.

## Why

Nick's feedback on v0.1: the app copied check-in's dark, neon, utilitarian UI.
New Me should feel like Duolingo: light, friendly, tactile, encouraging, one clear thing per screen.
Onboarding must be a real guided flow, never a server address form.
Health must read everything useful from Apple Health, not only steps.

## Principles

1. One question per screen in onboarding, with a progress bar and one big Continue button.
2. Every tap answers: a press animation, a haptic, and a visible state change.
3. Celebrate progress: a quest completing, the day counting, a streak growing.
4. Warm and calm: soft colours on a warm paper canvas, no neon, no pure black.
5. Plain words: "Walk 8,000 steps", never "steps quest target".
6. The server is invisible to people. It is baked into the build.

## Visual language

### Colour tokens (light only for v2)

| Token | Value | Use |
| --- | --- | --- |
| canvas | `#FBF8F3` | page background, warm paper |
| surface | `#FFFFFF` | cards, sheets, bottom bar |
| sunken | `#F3EFE8` | progress tracks, input fills, pressed rows |
| border | `#E8E2D8` | 2px card and input borders |
| lip | `#D9D2C5` | bottom edge of white chunky buttons |
| ink | `#25283D` | primary text |
| inkSecondary | `#4B4F63` | secondary text |
| inkMuted | `#6E7283` | captions, hints (must stay at or above 4.5:1 on canvas) |
| flame | `#F08A24` | streak flame and counts |
| danger | `#D9534F` | destructive actions and errors |

Person colours replace the old neon accents.
Each has a fill, a lip (about 18% darker, the 3D button edge) and a tint (a very light wash for selected states and icon circles).

| Stored key | Name | Fill | Lip | Tint |
| --- | --- | --- | --- | --- |
| `green` | Fern | `#3FA66B` | `#2F8553` | `#E6F4EC` |
| `sky` | Sky | `#3D8FD6` | `#2C70AD` | `#E5F0FA` |
| `violet` | Iris | `#7B6CD9` | `#5F51B5` | `#EEEBFA` |
| `amber` | Honey | `#E89A2C` | `#BF7A17` | `#FCF1E1` |
| `rose` | Coral | `#E5675A` | `#BF4C40` | `#FCE9E7` |
| `teal` | Lagoon | `#2A9D8F` | `#1F7A6F` | `#E3F3F1` |

The stored colour keys stay the same strings the server already accepts; only the names and rendered values change.
Quests get fixed category colours so they read the same for both people: steps Sky, exercise Coral, pushups Honey, reading Iris, meals Fern, protein Lagoon, sleep Iris, yoga Lagoon.
Category colour appears only in the icon circle tint and the progress fill, never as large flat areas.

### Type

Nunito, bundled as static TTF assets (Regular 400, SemiBold 600, Bold 700, ExtraBold 800, Black 900), never fetched at runtime.

| Role | Size / weight |
| --- | --- |
| display | 32 / 900 |
| title | 24 / 800 |
| headline | 20 / 800 |
| body | 16 / 600 |
| label | 14 / 700 |
| caption | 13 / 600 |
| button | 15 / 800, uppercase, 0.8 letter spacing |

Numbers that change use tabular figures.

### Shape and depth

- Cards: white, 2px border, radius 16, no drop shadow.
- Chunky button: 52 tall, radius 14, fill colour with a 4px lip below; pressed, the face moves down 4px onto the lip.
- Secondary chunky button: white face, 2px border, `lip` coloured lip.
- Progress bar: 16 tall, fully rounded, sunken track, fill with a lighter highlight stripe along the top third.
- Gutters 20, card gap 12, content max width 480 centred (for the web test build).
- Icons: Material rounded variants only (`Icons.*_rounded`).

### Motion and haptics

- Taps: scale to 0.96 over 90ms, light haptic.
- Pops: 250ms `easeOutBack` for badges and checks appearing.
- Quest done: check badge pops, small confetti burst from the card, medium haptic.
- Day counted: full-screen celebration sheet once per day with the mascot cheering, the streak number counting up, success haptic.
- Onboarding pages slide and fade (300ms).
- When `MediaQuery.disableAnimations` is true, every animation jumps to its end state.

### Mascot

A small round character drawn with `CustomPainter`, built from the app icon's ring: a ring body in the person's colour, two eyes with highlights, a mouth.
States: idle (blinks every few seconds), happy, cheer (hops), sleepy, sad, thinking.
It appears in onboarding, empty states, the day-counted celebration and the server-unreachable screen.
It never covers content and it is decorative for screen readers.

## Navigation

Three tabs in a white bottom bar with a 2px top border: Today, Us, Me.
Icons with short labels; the selected tab sits in a tinted rounded square with a 2px border in the person's colour.
The old centred FAB goes away; logging starts from a quest card or the food card.

## Onboarding

The app probes the baked-in server silently on launch.
The server address is never shown in the normal flow.
For the web test build the address comes from `--dart-define=NEWME_SERVER`; a hidden override (long-press the mascot on the welcome screen for 3 seconds) opens a small sheet to change it.
If the server cannot be reached, the mascot looks sad, the copy says New Me cannot be reached right now, and one Try again button retries.

Every step below is one screen with a top progress bar, a back arrow, the mascot with a short speech bubble, and a bottom Continue button that stays disabled until the step is answered.

### New person (first ever, or invited and new)

1. Welcome: mascot waves; "New Me"; "A daily game for two. Small habits, big year."; primary GET STARTED, secondary I HAVE AN INVITE CODE (only when the server is already initialised; if it is not, only GET STARTED).
2. Invite code (invite path only): four boxes of four characters, auto-advancing, paste-friendly; a wrong code shakes the boxes and says so.
3. New or returning (invite path only, when the code allows both): two big choice cards.
4. Name: "What should we call you?"
5. Colour: "Pick your colour"; six large swatches; the mascot recolours live; colours already taken are shown as taken.
6. Focus: "What do you want to work on?"; multi-select cards with icon, title and one-line description: Move more (steps), Work out (exercise minutes), Get stronger (pushups), Read more (reading), Eat well (meals and protein), Sleep better (sleep), Stretch (yoga). At least one is required.
7. Daily goals: one screen per chosen focus, Duolingo daily-goal style, a vertical list of four presets with names: steps Casual 5,000 / Regular 8,000 / Serious 10,000 / Intense 12,000; exercise 15 / 30 / 45 / 60 min; pushups 10 / 20 / 30 / 50; reading 10 / 20 / 30 / 45 min; meals 2 / 3 logged; protein asks for a gram target with presets 80 / 100 / 130 / 160; sleep 6h30 / 7h / 7h30 / 8h; yoga 10 / 15 / 20 / 30 min. A default preset is preselected.
8. Food (only when Eat well was picked): optional calorie target with presets and Skip.
9. Apple Health: a card listing what New Me reads, grouped (Activity, Workouts, Sleep, Heart, Body, Mindfulness and water), the line "New Me never writes to Health", and CONNECT APPLE HEALTH, which shows the system sheet for every type at once; secondary NOT NOW.
10. Done: confetti, the mascot cheers, "You're in, Nick!", "Day 1 starts now", LET'S GO.

The profile is created with `POST /api/join` after step 5 (it needs name, colour and time zone), then steps 6 to 8 are saved with one `PATCH /api/me` (quest templates enabled, targets, calorie target).
Leaving the app mid-flow resumes at the first unanswered step.

### Returning person (re-pair)

Welcome, invite code, "Who are you?" with the existing people as avatar cards, then Apple Health, then Done.

## Today

Top to bottom:

1. Top bar: the person's avatar (opens Me), flame with streak count, gem with today's points, and the partner's small avatar with their day percent as a ring (opens Us).
2. Greeting and mascot with a contextual line: "2 quests to go", "Streak saved for today!", "Rest day available".
3. Day card: a large progress bar towards the streak line with a flag marker at 70%, "54 of 400 points", and a plain sentence about what keeps the streak.
4. Quest cards: category icon circle, plain title ("Walk 8,000 steps"), progress text, the thick progress bar, and on the right either a small chunky + button (manual quests) or an "Apple Health" chip (automatic quests); done cards get a check badge and their bar turns to the person's colour.
5. Food card: kcal eaten against target as a progress bar, three macro mini bars, tap to log a meal.
6. Body card: two-column tiles for sleep, resting heart rate, exercise, weight (with a 7-day trend arrow), HRV and VO2 max; only metrics that have data appear; tap opens the Health detail screen.
7. This week: seven day circles with flames on counted days and a moon on the rest day.

## Logging

Bottom sheets with big targets, opened from a quest card's + or the food card.
Pushups: a big number with − and + buttons and quick chips +5, +10, +20.
Reading: minutes or pages toggle, the same big number stepper.
Yoga: minutes stepper.
Meal: name, kcal, protein, carbs and fat, a More link for fiber, portion chips, and recent meals as tappable chips at the top.
Saving closes the sheet and plays the card's progress animation; a quest that becomes done plays the done animation.

## Us (replaces Board)

Two person cards side by side: avatar, today's percent ring, today's points, streak flame, week and season points.
"This week": grouped bars per day in each person's colour.
"Today's highlights": steps, exercise and sleep for both people from Health.
No winner wording; it is a shared scoreboard.

## Me

Header with avatar in the person's colour, name, streak, season points.
Rows that open full pages: Daily goals (the same preset pickers as onboarding, plus a custom number), Food targets, Time zone, Apple Health (status, last sync, Sync now), Pairing code (admin), Leave this phone.

## Health detail

One screen listing every metric with today's value; tapping a metric shows a 30 or 90 day line chart drawn with `CustomPainter` from `GET /api/health/trends`.

## Apple Health scope

The app requests read access to all of these at once and never writes.

| Metric key | HealthKit source | Unit | Per day |
| --- | --- | --- | --- |
| `steps` | step count | count | sum, de-duplicated across sources |
| `active_energy` | active energy | kcal | sum |
| `basal_energy` | basal energy | kcal | sum |
| `exercise_minutes` | Apple exercise time | min | sum |
| `distance_m` | walking and running distance | m | sum |
| `flights` | flights climbed | count | sum |
| `workouts` | workouts | count | count started that day |
| `workout_minutes` | workouts | min | total duration |
| `sleep_minutes` | sleep analysis, asleep stages | min | the night that ends on that morning |
| `mindful_minutes` | mindful sessions | min | sum |
| `water_ml` | dietary water | ml | sum |
| `resting_hr` | resting heart rate | bpm | latest that day |
| `hrv_ms` | heart rate variability (SDNN) | ms | average that day |
| `vo2max` | VO2 max | ml/kg/min | latest that day |
| `weight_kg` | body mass | kg | latest that day |
| `body_fat_pct` | body fat percentage | % | latest that day |
| `lean_mass_kg` | lean body mass | kg | latest that day |

The app pushes today and yesterday on each sync, as today.
A type the person declined, or one with no data, is simply not sent.

## Server changes

- Migration 0004 widens `health_daily.metric` to the keys above with per-metric bounds.
- New quest keys `exercise` (minutes, from `exercise_minutes`, default 30, 100 points) and `sleep` (minutes, from `sleep_minutes`, default 420, 50 points); both are automatic like steps and only appear on days once that metric has ever been synced, the same rule as steps.
- Existing users get the two new templates added disabled.
- `PUT /api/health/daily` accepts the new metrics.
- `GET /api/today` `health` gains `metrics` (the day's values by key) and `latest` (for weight, body fat, lean mass and VO2 max: the newest value on or before the day, with its date).
- `GET /api/health/trends?metric=<key>&days=<1..365>` returns `{metric, points: [{date, value}]}` for the caller.
- `GET /api/board` members gain `highlights` with today's `steps`, `exercise_minutes` and `sleep_minutes` when present.
