# New Me v4: workouts and insights

This phase adds real workouts from Apple Health and turns steps and sleep from single numbers into insights.
Everything in the earlier design documents still holds unless a section below changes it.

## Why

Nick asked for "the workout portion", sleep insights, step insights, and how much he should actually walk, and whether that depends on who he is.

## What the evidence says about steps

- Large pooled studies (Paluch et al., The Lancet Public Health, 2022; Ding et al., The Lancet Public Health, 2025) find that the benefit of more daily steps levels off at roughly 6,000 to 8,000 for adults aged 60 and over and roughly 8,000 to 10,000 for younger adults, with most of the gain already reached around 7,000.
- Age is the factor that moves the target.
  Height and weight do not set the step goal; height changes stride length, so it matters for distance, not for count.
- The practical way to raise a goal is from a person's own recent baseline, about 1,000 steps a day higher at a time, until the age band is reached.

New Me therefore suggests a step goal from the person's last two weeks and their age, explains the reason in plain words, and never prescribes from body size.
The copy says this is general guidance, not medical advice.

## Data

### Workouts (from Apple Health)

The app reads `WORKOUT` samples (foreground sync, last 14 days on each sync, then incremental) and sends each one:

`PUT /api/health/workouts` with `{items: [{id, type, startedAt, endedAt, durationMin, kcal, distanceM, avgHr, source}]}`

- `id` is the HealthKit sample UUID; the server upserts by `(user, id)`, so re-sending is safe.
- `type` is one of `walking, running, cycling, strength, hiit, yoga, swimming, hiking, dance, climbing, other` (the app maps HealthKit activity types onto these).
- `kcal`, `distanceM` and `avgHr` are null when Health has none; `avgHr` is the mean heart rate during the workout.
- The server stores the local date of `startedAt` in the person's zone.
- At most 100 items per request; answers `{saved: n}`.

`GET /api/workouts?days=N` (1..365) answers `{workouts: [{id, type, date, startedAt, endedAt, durationMin, kcal, distanceM, avgHr}], week: {count, minutes}}`, newest first, for the caller.

Workouts do not change scoring; the exercise quest already counts Apple exercise minutes.

### Sleep nights (from Apple Health)

The app turns the sleep stage samples of each night (18:00 the day before to 12:00) into one record and sends the last 14 nights on each sync:

`PUT /api/health/sleep` with `{nights: [{date, bedAt, wakeAt, asleepMin, deepMin, remMin, coreMin, awakeMin, source}]}`

- `date` is the morning the night ends; the server upserts by `(user, date)`.
- `bedAt` is the first asleep or in-bed sample, `wakeAt` the end of the last asleep sample.
- Stage minutes are 0 when the watch reports only plain "asleep".

### Age

`PATCH /api/me` accepts `birthYear` (1900..current year, or null), and `GET /api/me` returns `user.birthYear`.
It is optional, asked once on the Steps insight screen and editable in Profile.

## Insights

`GET /api/insights` computes everything server-side as pure, unit-tested functions:

```
{
  steps: {
    avg7, avg30, median14, trend: "up" | "flat" | "down",
    best: {date, value} | null,
    daysAtGoal30, goal,
    suggestion: {target, median14, bandLow, bandHigh, ageKnown} | null
  },
  sleep: {
    avg7Min, avg30Min, targetMin,
    avgBedtime: "23:10" | null, avgWake: "06:50" | null,
    bedtimeSpreadMin,
    stages7: {deepMin, remMin, coreMin, awakeMin} | null,
    lastNight: {date, bedAt, wakeAt, asleepMin, deepMin, remMin, coreMin, awakeMin} | null,
    nights: [{date, asleepMin}] (last 14)
  },
  workouts: {
    week: {count, minutes},
    last30: {count, minutes, byType: [{type, count, minutes}]}
  }
}
```

Rules:

- `trend` compares the last 7 days' average with the 7 before; more than 5% either way is up or down.
- Step suggestion needs at least 5 days with steps in the last 14, else `suggestion` is null and the app says to wear the phone or Watch for a week.
  Band: under 60 is 8,000 to 10,000; 60 and over is 6,000 to 8,000; unknown age uses 7,000 to 10,000.
  Target: if the median is below the band, the median plus 1,000 rounded up to the next 500, never above the band's low end; inside the band, the median plus 1,000 rounded to 500, capped at the band's high end; at or above the band's high end, the median rounded down to 500 (keep what you do).
  Never below 3,000.
- Sleep averages count only nights with data; `bedtimeSpreadMin` is the standard deviation of bedtimes over the last 14 nights (handled across midnight).
- `targetMin` is the sleep quest target, or 420 when the quest is off.

`GET /api/board` members gain `workoutsThisWeek` (count).

## App

- Today: the Body card gains a Workouts tile (this week's count and minutes) and the Sleep tile shows last night's stage bar; both open their insight screens.
- Insights live behind a new "Insights" entry on Today (below Body) and on Me: three screens.
  - Steps: 30-day bar chart with the goal line, 7 and 30 day averages, trend, best day, and the suggestion card ("Try 8,500 a day. You have averaged 7,400 over two weeks, and most of the benefit for your age comes by 8,000 to 10,000.") with USE THIS GOAL (updates the steps quest from tomorrow) and the optional birth year prompt; a short "Why not based on height or weight?" explainer.
  - Sleep: last night card (bed and wake time, asleep, stage bar), 14-night bars against the target, averages, average bed and wake times, a consistency line ("Your bedtime varies by about 40 minutes"), and up to two gentle tips derived from the numbers (late average bedtime, short average sleep, high spread).
  - Workouts: this week summary, list of recent workouts with type icon, duration, kcal, distance and average heart rate, and a by-type breakdown for 30 days; a workout detail sheet.
- Us: each person's card shows workouts this week.
- All charts are `CustomPainter`, follow the v2 visual language, have accessible summaries, and survive text scale 2.0.

## Implementation decisions (server)

Where this document left room, the server does the following.
`docs/design.md` has the exact endpoint, schema and error text.

- Averages, the median, the trend and the suggestion use the complete days before today (yesterday back), so a morning with few steps never drags them down.
  `best` and `daysAtGoal30` include today.
  `avg7`, `avg30` and `median14` count only days with steps above 0; the "5 days of the last 14" test uses the same days.
  `trend` is flat unless both weeks have data.
- `avg30`, `avg7`, `median14` are whole numbers; the median of an even count is the mean of the middle two, rounded.
  `best` is the most recent day among ties.
- `goal` is the steps quest target whether or not the quest is enabled.
  `targetMin` is the sleep quest target only while that quest is enabled, else 420.
- Suggestion target: below the band it is the median plus 1,000 rounded up to 500 and capped at the band's low end; inside the band (low end included, high end excluded) it is the median plus 1,000 rounded to the nearest 500 (halves up) and capped at the high end; at or above the high end it is the median rounded down to 500.
  The 3,000 floor applies last.
  Age is the local today's year minus `birthYear`; a birth year in the future counts as unknown.
- Sleep: only nights with `asleepMin` above 0 count.
  `avg7Min` and `avg30Min` cover the morning dates of the last 7 and 30 days ending today.
  `nights`, `avgBedtime`, `avgWake`, `bedtimeSpreadMin` and `lastNight` use the last 14 days of nights, `nights` oldest first, `lastNight` the newest of them, so a night older than two weeks is never shown as last night.
  Times of day are read in the person's current zone and averaged as angles on a 24 hour circle, so 23:00 and 01:00 average to 00:00.
  The spread is the population standard deviation of bedtimes around that circular mean, each distance taken the short way round the clock, rounded to minutes; one night gives 0.
  `stages7` is the per-night average of each stage over the nights with data in the last 7 days, and null with none.
  A night that straddles a daylight saving change keeps its wall-clock times, so its minutes can differ from the elapsed time.
- Workouts: `week` runs from Monday of the person's local week through today; `last30` is the 30 local dates ending today; `byType` is sorted by minutes, then count, then type.
  `GET /workouts` fills `week` from the same ISO week whatever `days` is.
  Minutes are rounded to whole numbers in summaries; `durationMin` in lists keeps one decimal.
- Request limits the document left open: workouts 1 to 100 per request, sleep 1 to 31 nights per request, history no older than 400 days, `source` 1 to 32 characters, workout `id` 1 to 100 characters.
  Bad items return 422 `invalid_request` with the per-item list used by `PUT /health/daily`, and nothing from that request is stored.
- Sleep minutes are accepted as any JSON number (a client may send `420.0`) and rounded to whole minutes before the 0 to 1440 check.
  Timestamps must be RFC 3339 with an offset or `Z`.
- Both PUT endpoints are outside the day window and never rescore a day, and they share the `PUT /health/daily` rate limit bucket.
- `birthYear` allows 1900 up to the current year in the person's zone; the table check is 1900 to 2100 because a CHECK cannot read the clock.
