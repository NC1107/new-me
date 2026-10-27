# New Me v7: kind, general and looking back

Earlier design documents still hold unless a section below changes them.
This batch follows the beta review (`beta-review-2026-10.md`) with Nick's decisions of 2026-10-27.

## Nick's decisions

- Streak forgiveness: two freezes, repair, away mode and a shared streak, yes.
- Keep settings general; no horse or job-specific features.
- Notification budget, except reminders that are genuinely time-dependent (medicine at 08:00).
- The first notification of the day comes 10 minutes after wake-up, configurable.
- It is a two-person app for Nick and his fiancee: no judgement-softening, hiding or consent screens; no meal photos (text "describe it" stays).
- Health soundness changes from the coach review, yes.
- The goal is a year with the app: show look-backs that prove improvement over time.

## 1. Streak forgiveness and the shared streak

- **Freezes.** Each person starts with 2 freezes and earns 1 more per 7 counted days, holding at most 2.
  A missed day with a freeze available is covered automatically at finalize time and shown as a frozen day (a snowflake) in the week strip and history; it keeps the streak but adds no day to it.
  This replaces the weekly rest-day rule; days already finalized keep their recorded result.
- **Repair.** Until 22:00 the next day, a missed (unfrozen) yesterday can be repaired by reaching 100% of today's base points; repaired days count as frozen days.
  Today shows a "Repair yesterday" card with progress while the window is open.
- **Away mode.** Either person can mark a span of days as away (sick, travel), today or up to 14 days ahead, from Me or from a "Can't today?" link on Today.
  Away days neither break nor extend any streak, do not use freezes, are skipped by nudges, and show as away on Us.
- **Shared streak.** The couple streak counts days on which both people counted, froze or were away, with at least one of them counted.
  It is the first element on Us.
  When one person misses and has no freeze, the partner can spend one of their own freezes to cover them (a one-tap "Cover Nadia" until 10:00 the next day), which keeps both the shared streak and the partner's personal streak.
- Server: pure, unit-tested streak functions over day flags (counted, frozen, repaired, away) for personal and shared streaks; finalize decides freezes; the API exposes freezes held, repair window, away spans, and the shared streak.

## 2. General schedule

- Me > Schedule: wake time and bedtime, separately for workdays and days off, and which weekdays are workdays.
  Defaults 07:00 and 23:00, Monday to Friday.
  Asked once in onboarding as one screen ("When do you usually wake up?").
- Everything time-based follows the schedule: the first notification (wake + 10 minutes, the offset configurable from 0 to 120 minutes), habit time defaults in templates, quiet hours (bedtime to wake), the wind-down nudge, and the "yesterday is still open" note.
- Today shows "Yesterday is open until 10:00" with what is still missing while the grace window is open.
- The weekly challenge gives each person their own share of the target, sized from their own history, so neither carries the other.
- Generic manual activity: a "Log activity" entry with a free name, minutes and an intensity (easy, moderate, hard) that counts toward exercise minutes for the day; covers anything Health does not see.

## 3. Notifications

- Automatic nudges stay within the budget of 2 per day (v6), all after the first notification of the day and before bedtime.
- The morning plan is the first notification, at wake + offset.
- Habit reminders are sent only for habits with a time set, and are outside the budget because they are time-dependent by design.
  Habits without a time never notify.

## 4. Health soundness (coach review)

- Sleep and exercise quests are on by default for new people, and offered to existing people as a one-tap goal proposal.
- A readiness "take it easy" morning makes that day a rest day automatically if it would otherwise be missed (it uses no freeze).
- Protein target per kilogram: default 1.6 g/kg from the latest weight (rounded to 5 g), shown with the 7-day hit rate; a proposal when the current target is far off.
- Weight shown as a smoothed trend (exponential moving average, alpha 0.1) with the weekly rate; the raw reading is secondary.
- Training load: session load from duration and average heart rate, acute (7 days) versus chronic (28 days) ratio, and a lighter-week proposal when the ratio is above 1.5 or after three "take it easy" mornings in a week.

## 5. Look-backs: a year of improvement

- A "Progress" screen (from Insights and from Us) built for the long run:
  - Rolling 30-day averages compared with the previous 30 days and with the first 30 days: reading minutes per day, steps, sleep, workouts per week, push-ups per day, protein, habits kept per day.
  - Smoothed weight, body fat and lean mass trends, VO2 max and resting heart rate trends, each with "since you started" change.
  - Each metric as a small sparkline card with an up or down arrow in the good direction and plain text ("Reading: 24 min a day, up from 11 in your first month").
- Monthly look-back: on the 1st of each month, a card and a push summarising the previous month against the one before and against the first month, for each person and the couple, with the three biggest improvements.
- Milestones: 7, 14, 30, 50, 100, 200 and 365 days for each person and the shared streak, plus firsts (first 10k-step day, first week of every quest), each with a one-off celebration and kept in a milestones list.
- Server: one `GET /api/progress?window=30` computing all comparisons in pure, tested functions; `GET /api/lookback?month=YYYY-MM`; milestones recorded once.
