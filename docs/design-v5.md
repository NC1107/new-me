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

## Server decisions

These are the choices made while building the server side.
`docs/design.md` has the endpoint list, schema and configuration.

### Habits

- Icons are a fixed list of 26 Material rounded names, validated on write (list in `docs/design.md`).
- Weekdays go over the wire as ISO numbers 1 to 7 and are stored as a bitmask (bit 0 = Monday).
- Slots are a JSON array on the habit.
  A slot's index is its position, so reordering or deleting slots in an edit changes which marks line up with which slot.
  Marks on an index past the end are ignored.
- A count habit has no slots; sending slots for one is a 422.
  Count marking sets the day's total (`{count}`), not an increment, which keeps retries idempotent and lets the long-press sheet set a number.
- Paused habits and deleted habits stop paying immediately on open days; a finalized day keeps the bonus it was finalized with (the engine reads it back instead of recomputing it).
- Marking a paused habit, or on a weekday it is not scheduled, is a 422.
- Habit and challenge points are added to `day_scores.bonus_points` only, so `maxBase`, `percent` and `counted` never move.

### Cheers

- A repeat of the same kind, to the same person, on the sender's local day answers 200 with the stored cheer and sends nothing (idempotent), rather than a 409, so a retried tap is harmless.
- "Received today" is the recipient's own local day, using the instant the cheer was stored.
- `from` is the sender's user id; `fromName` is added so the chip needs no lookup.

### Weekly challenge

- Kinds rotate by ISO week number modulo 4: steps, workouts, counted days, reading (week 45 is workouts).
- Created lazily on the first settle of the week (any board read, write that settles, or scheduler pass) and then frozen.
  Sizing only reads the two weeks before the week, so when it is created does not change the target.
- Steps: sum over people of their average daily steps (days with a reading) over the previous 14 days, times 7, times 1.1, rounded to the nearest 5,000, at least 5,000; 70,000 with no history.
- Workouts: last week's combined count plus 1, at least 3.
- Counted days: both people counted on 5 of the 7 days.
  Progress is the number of days on which every live user's day counted.
- Reading: the spec gave no rule, so it is the previous two weeks' combined reading minutes (logged minutes plus listening) halved, times 1.1, rounded to 10, at least 60; 150 with no history.
- Progress is computed from stored data on every read.
  Completion is final: it is stamped once and a later deletion does not reopen it.
- The 50-point award is a `challenge_awards` row per person on that person's local date at the moment of completion, folded into scoring as a per-day bonus input.
  It is not a rewrite of any finalized day.

### Rewards

- Progress is combined all-time points now minus the combined total when the reward started (`baseline`), so it is exact to the instant even though points are stored per day.
  It is clamped to 0..target.
- Reaching moves the reward to history at once.
  `claim` marks it enjoyed and can only be done on a reached reward; repeating it keeps the first time.
- The board shows the reward being earned, or else the newest reached one that is unclaimed, so the app has something to celebrate; after the claim it is null until the next one starts.
- Creating a reward first settles, so one that has just been earned never blocks the next with a 409.

### Push

- `NEWME_APNS_PRODUCTION` defaults to true when unset, since the only build that receives push is TestFlight.
- A bad `.p8` is logged at boot and leaves push off; a half-set credential group is a boot error.
- Messages: "<name> finished the day", "<name> cheered your day", "Challenge complete" (title of the challenge), "Reward reached" (name of the reward).
  Each carries `kind` (`partner_done`, `cheer`, `challenge`, `reward`) in the payload for the app to route a tap.
- The per-person switches are checked when a message is queued, so a muted event is never sent.
  The points and awards happen whether or not a notification is wanted.

### Left for Apple setup

- Create an APNs auth key (.p8) in the developer portal, set the four `NEWME_APNS_*` variables on the server.
- Enable Push Notifications on the App ID, regenerate the App Store provisioning profile, and update the `IOS_PROVISIONING_PROFILE_BASE64` secret.
- The app needs the `aps-environment` entitlement and must call `PUT /api/devices/me/push` with the hex token.

