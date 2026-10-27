# New Me v5: daily habits and together

Earlier design documents still hold unless a section below changes them.

## Daily habits

Nick's direction: habits are created on the schedule they are needed, and marking one off must be instant, because any inconvenience means it will not get done.

### Model

- A habit belongs to one person and has a name, an icon (from a curated set of rounded Material icons), and a schedule.
- Schedule: the days it applies (every day, or a chosen set of weekdays) and one or more slots per day.
  - A check slot has a label ("Morning", "Evening" or free text) and an optional time ("07:30").
    Brushing teeth is one habit with two slots, morning 07:30 and evening 22:00.
  - A count habit has one daily target (water, 8 glasses) and is marked with repeated taps.
- Habits have a position for ordering and can be paused (kept, but not shown or reminded).
- Starter templates in the app: Brush teeth (07:30 and 22:00), Creatine (daily, 08:00), Huel (weekdays, 12:00), Water (8 glasses), Vitamins (daily, 08:00), Floss (daily, 22:00), Stretch (daily), Custom.

### Scoring

- Each completed slot, and a count habit reaching its target, earns 5 bonus points that day.
- Habit points add to the day's total and to week and season points, but never to `maxBase`, so habits can only help and can never break a streak.
- Finalized days never change, as everywhere else.

### Marking off

- Today shows a Habits strip near the top with only today's due slots, ordered by time; slots whose time has passed and are not done are highlighted, done ones show a check.
- One tap marks a slot done, with a check animation and a light haptic; tapping a done slot undoes it.
  A count habit's tap adds one; long-press opens a tiny sheet to set the number.
- Marking is optimistic: the strip updates instantly and the request follows; a failure reverts with a short message.
- Yesterday's slots can be marked until the 10:00 grace like logs.
- Each timed slot can remind with a local notification at its time (on by default per slot, off per slot in the habit editor) that carries two actions: Done (marks it without opening the app, from the lock screen) and Snooze 30 min.
  A slot already done before its time is not reminded.

### API

- `GET /api/habits` lists the caller's habits with schedule.
- `POST /api/habits`, `PATCH /api/habits/{id}`, `DELETE /api/habits/{id}` (soft), `PUT /api/habits/order`.
- `PUT /api/habits/{id}/marks/{date}` with `{slot, done}` for check habits or `{count}` for count habits; idempotent; answers the day's habit state and the rescored day.
- `GET /api/today` gains `habits: [{id, name, icon, kind, slots: [{index, label, time, done}], target, count}]` for the due habits of the day.

## Together

### Cheers

- On Us, tapping the partner's card opens four reactions (clap, fire, flex, heart, as icons, not emoji); one cheer per kind per day.
- The partner sees "Nadia cheered your day" on Today (a dismissible chip with the icon) and gets a push notification.
- `POST /api/cheers {to, kind}`; `GET /api/today` gains `cheers: [{from, kind, at}]` received today.

### Weekly couple challenge

- Every Monday the server picks one shared challenge for the week, rotating through kinds, sized from the last two weeks so it is reachable but a stretch:
  combined steps (110 percent of the pair's combined 7-day average times 7, rounded to 5,000), combined workouts (sum of last week's counts plus 1, at least 3), both count 5 of 7 days, combined reading minutes.
- Progress shows on Us and as a small card on Today; finishing it gives both people 50 bonus points on the day it completes and a celebration.
- `GET /api/board` gains `challenge: {kind, title, target, progress, done, endsOn}`.

### Shared reward

- One active reward at a time, set by either person: a name ("Date night") and a target in combined points earned since it started.
- Progress on Us; when reached, both get a celebration and it moves to a history list; anyone can start the next one.
- `GET /api/rewards`, `POST /api/rewards {name, target}`, `POST /api/rewards/{id}/claim` (marks it enjoyed); board gains `reward: {id, name, target, progress, reachedAt}`.

### Push notifications

- Apple Push Notification service with token-based auth from the server, so the partner hears about things as they happen.
- Events: partner finished their day (counted), cheer received, challenge completed, reward reached.
- Server config: `NEWME_APNS_KEY` (the .p8 contents, base64), `NEWME_APNS_KEY_ID`, `NEWME_APNS_TEAM_ID` (76S78SUWVM), `NEWME_APNS_TOPIC` (top.npcserver.newme), `NEWME_APNS_PRODUCTION` (true for TestFlight); unset disables push and everything else still works.
- `PUT /api/devices/me/push {token}` registers the device token; `DELETE` removes it; a 410 from Apple removes it too.
- Each person can turn each event kind off in Me > Notifications.
- iOS needs the `aps-environment` entitlement and a provisioning profile with Push Notifications, which means regenerating the App Store profile and updating the `IOS_PROVISIONING_PROFILE_BASE64` secret.
