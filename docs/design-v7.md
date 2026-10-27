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

## Server decisions

Implemented in `server/` (migration 0009); endpoint shapes, tables and the streak algorithm are in `docs/design.md` (Streak, Endpoints v7 additions, Migration 0009).
Where this document left a choice open, the server does the following.

### Research change: no training-load ratio

- Section 4's acute:chronic training-load ratio, its lighter-week proposal and the "3 or more easy mornings" proposal are not built: the ACWR is not valid for prescribing training (Impellizzeri et al. 2020) and the easy-mornings count is an invented heuristic.
- `GET /api/insights` instead reports `activity`: the last seven days of workouts against the WHO 2020 guideline (150 to 300 moderate-equivalent minutes with a vigorous minute counting as two, and 2 or more strength days).
  A session is vigorous at 60% of heart-rate reserve or more; without a heart rate or a resting rate and age, HIIT is vigorous and everything else moderate.
  It only reports; it never proposes training less.
- The readiness "easy" rest day is kept: it is a streak rule of this document, not a training prescription.

### Streaks

- Under the freeze rules a freeze is only spent while the streak is above zero. A miss at zero is simply a miss.
- Freeze progress waits at 6 of 7 while two freezes are held; the first counted day after one is spent earns it back.
- An away day neither breaks nor extends a streak even if it counted. For the shared streak a counted away day still counts as the "at least one counted" day.
- The shared streak adds a day when everyone counted, was frozen or was away and someone counted. A frozen day beside a counted one therefore adds a day for the couple; two frozen or away days add nothing and break nothing.
- Settling is done by the scheduler (right after finalizing) and records the decision the derivation would make; until then the same decision is shown. The readiness morning is evaluated from stored sleep, HRV and resting heart rate.
- History stays as recorded: at migration each person's `streak_rules_from` is set to the first unfinalized date, and every earlier day keeps the weekly rest rule. The 22:00 repair window and the 10:00 cover window use the covered person's own local time.
- A repair needs `percent == 100` on today, which counts only quests that are in the day (Health-fed quests stay out until their data arrives).
- A cover is refused while the partner holds a freeze of their own. It is stored as a spend on the coverer and refunded when the covered day ends up counted or away.
- Milestones: streak lengths use the current streak, are recorded once, and a batch recorded together (first run, or a late night) announces only the highest. `newMilestones` on Today lists those achieved yesterday or today. Milestone pushes sit outside the daily budget of 2 but obey the person's notification window; they have their own `milestones` switch. Streak and shared milestones are separate pushes.

### Schedule and notifications

- Quiet hours run from bedtime to wake plus the offset. A bedtime after midnight ends the window at midnight.
- The wind down runs for 45 minutes before bedtime; a bedtime that puts it before 18:00 (including after midnight) skips it.
- The monthly look-back is an automatic push (budget slot) at the first notification of the 1st, sent before the morning plan, which then steps aside. `lookback` and `milestones` are new notification switches.
- Habit reminders stay on the phone.

### Weekly challenge

- Each person's share is sized from their own two previous weeks (steps 110% of their weekly steps to the nearest 1,000, at least 10,000, 35,000 without history; workouts last week plus one, at least 2; reading 110% of their weekly minutes to the nearest 10, at least 30, 75 without history; counted days 5).
  The challenge target is the sum of the shares.
- It completes when every person has reached their own share, so neither carries the other. Combined progress adds each person's progress capped at their own share. The 50-point award is unchanged.
- A person who joins mid-week gets a share and the combined target grows by it. Challenges from before v7 keep their combined target and are measured on the pair's total.

### Health soundness

- Protein: new people have `protein_auto`; with no chosen target the snapshot takes 1.6 g/kg of the latest weight on or before the day, rounded to 5 g, else 100 g. A proposal appears when the current target is 20% or more away from that. Existing people keep their target.
- Existing people get `enable` proposals for sleep and exercise; a dismissed offer stays quiet for four weeks.
- Smoothed weight is an EWMA with alpha 0.1 per weigh-in; the weekly rate compares the latest trend with the newest weigh-in at least 28 days earlier, or the first one when the history is between 7 and 28 days.

### Look-backs

- Averages: reading and push-ups and habits kept count empty days as zero; steps, sleep, protein and the body measurements average the days that have a reading; workouts are events per seven days. Windows are clipped to the days since joining; the first window is shown once it is over.
- `better` is nil for a change under 1% and for weight, which has no good direction. The monthly look-back ranks improvements by relative change against the previous month (from zero ranks as 100%); the couple's metrics are the average of the two people.
