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
