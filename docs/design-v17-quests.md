# New Me v17: three opt-in quests

Earlier design documents still hold unless a section below changes them.
The water quest in `design-v16-water.md` is the pattern these follow.

## Why, and the opt-in decision

- Three habits with published evidence behind them are added as daily quests: a steady bedtime, fruit and vegetables, and breathing.
- All three ship disabled, for existing people and for new ones.
- Migration `0026_v17_quests.sql` adds each template switched off, last in the person's order, so nobody's day gets harder without choosing it.
- New people get the same three templates off from `db.DefaultTemplates`.
- They are turned on from Me > Daily goals, from the Targets page where a target exists, or as onboarding focuses ("Keep a steady bedtime", "Eat your five a day", "Breathe for 5 minutes").
- Onboarding switches off every quest nobody picked, so a new person who skips these focuses never sees them.
- Each quest is worth 50 points, like protein and water.
- Days already in progress keep the quests they started with, like any other template change.
- Every number below is either from the cited research or marked as a product choice.

## Keep a steady bedtime (`sleep_regularity`)

### Research

- Phillips et al., Sci Rep 2017;7:3216, defined the Sleep Regularity Index (SRI): the probability that a person is in the same state, asleep or awake, at two time points 24 hours apart, averaged over the days.
  A perfectly regular schedule scores 100 and the original scale runs down to -100.
- Windred et al., Sleep 2024;47(1):zsad253, used the SRI on seven days of wrist accelerometry from about 60,000 UK Biobank participants.
  Compared with the least regular quintile, the four more regular quintiles had 20% to 48% lower all-cause mortality, and regularity predicted mortality more strongly than sleep duration.
- Neither paper gives a per-night target, a window in minutes that a person can aim for on one night.
  Cribb et al., eLife 2023;12:RP88359, in the same cohort, report sleep onset standard deviations of 1.41, 0.96 and 0.72 hours across tertiles of regularity.
  Those are descriptive group averages and not a recommendation.

### What is research and what is a product choice

- Research: regular sleep and wake timing is worth having, and the SRI is how it is measured over days.
- Product choice: the daily quest.
  The night counts two points, one for the bed time and one for the wake time, each inside a window of the person's own usual time.
- Product choice: the usual time is the median of the person's last 7 nights before this one, read on their own clock, and it needs at least 3 of them.
  The median ignores a single odd night, and the 7 nights match the 7 days of the Windred analysis.
- Product choice: the window is 45 minutes either side by default, a number near the 0.72 hour (43 minute) onset spread of the most regular tertile.
  It can be set from 15 to 120 minutes in Daily goals, with 30, 45, 60 and 90 offered, and the page says plainly that the research names no window.
- Times are compared round the clock, so 23:50 and 00:10 are 20 minutes apart, and the usual time of a routine that crosses midnight is a time near midnight and not noon.

### How a day scores

- The quest is Health-fed: it joins the day only when there is a sleep night for that day and at least 3 earlier nights to form the routine.
  Until then it is not part of the day's maximum, so nobody is scored on a number they cannot produce yet.
- Both times inside the window completes the quest, one inside earns half the points, none earns nothing.
- Health sleep minutes alone do not join it, because minutes slept say nothing about when the person slept.
- The quest's `target` on the wire is the window in minutes, and its `actual` is the number of times inside it (0, 1 or 2).
- The quest also carries `detail` with the usual bed and wake times, the night's offsets from them in minutes, and whether each fell inside, so the card can show "Bed 11:00 PM, 30 min later than usual (10:30 PM)".
- The pure rule is `regularity.Evaluate` in `server/internal/regularity`, and the engine reads it through `engine.RegularityCheck`.

### The rolling index

- The Sleep insights screen shows the Sleep Regularity Index over the last 14 days, from `targets.SleepRegularity` (v8): "Sleep regularity 78 of 100".
- It needs 5 nights with sleep, two of them back to back, and says so when it has fewer.
- `sleep_nights` holds one sleep period a night, from `bed_at` to `wake_at`, so the index compares the 18:00 to 12:00 span of consecutive nights and leaves the afternoon out instead of assuming it awake.
  That is an approximation of the accelerometer index in the papers, which sees naps and wake periods in the night.
- The answer is `sleep.regularity` in `GET /api/insights`.

## Eat 5 a day (`produce`)

### Research

- WHO and FAO advise at least 400 g of fruit and vegetables a day (WHO Technical Report Series 916, 2003), not counting potatoes and other starchy roots.
- One portion for an adult is 80 g (NHS 5 A Day portion sizes, also the basis of the "5 a day" message).
  400 g at 80 g is five servings.
- Aune et al., Int J Epidemiol 2017;46:1029, a dose-response meta-analysis of 95 cohort studies, found the risk of cardiovascular disease and all-cause mortality still falling up to about 800 g a day, which is 10 servings.
  The benefit for total cancer levelled off at about 600 g.

### The quest

- Default target 5 servings, unit `servings`, allowed from 1 to 30.
- Five is the WHO minimum, so it is the default and the Targets page says it is a floor and that risk kept falling up to about 10.
- The Targets page lists it (source keys `who2003`, `nhs5aday`, `aune2017`), and "Use" sets the template target from the next day.
- It is logged by tap and is never inferred from meals.
- The activity type is `produce_servings` on the server and `produce` with unit `servings` on the wire, 1 to 30 per entry.
- The log form has "Add 1 serving", chips for 2, 3 and 4, and the list of what one serving is, taken from the NHS guide:
  - 1 medium fruit such as an apple, banana, pear or orange.
  - 2 small fruit such as plums, satsumas or kiwi fruit.
  - 7 strawberries or 14 cherries.
  - 3 heaped tablespoons of cooked vegetables such as carrots, peas or sweetcorn.
  - 3 celery sticks, a 5 cm piece of cucumber or 1 medium tomato.
  - 1 heaped tablespoon of dried fruit, about 30 g.
  - Anything else: about 80 g.
- The form also says that beans and pulses count once a day, that juice and smoothies count once however much is drunk, and that potatoes do not count, all as in the NHS guide.
- It is a hand-logged quest, so it is part of the day from the start, like push-ups.

## Breathe 5 min (`breathing`)

### Research

- Balban et al., Cell Rep Med 2023;4:100895, a randomised trial, compared five minutes a day of three breathing practices with mindfulness meditation for a month.
  Breathwork improved mood more than meditation, and cyclic sighing, which stresses a long exhale, improved mood most and lowered respiratory rate more than meditation.
- Cyclic sighing is a double inhale through the nose, the second topping up the first, then a long exhale through the mouth.
- Zaccaro et al., Front Hum Neurosci 2018;12:353, a systematic review of 15 studies, found that breathing slower than 10 breaths a minute raised heart rate variability and was linked to relaxation and less anxiety.
  The studies that did so centred on about 6 breaths a minute (0.1 Hz).

### The quest

- Default target 5 minutes, unit `min`, allowed from 1 to 60.
- The Targets page lists it (source keys `balban2023`, `zaccaro2018`).
- Product choice: the step lengths of the pacer.
  Balban et al. do not time the steps, so cyclic sighing is 2 seconds in, 1 second of top-up and 5 seconds out, an 8 second breath whose exhale is longer than both inhales together.
  Slow breathing is 5 seconds in and 5 out, which is exactly 6 breaths a minute.
- Product choice: finishing logs the minutes as `breathing_minutes` (wire type `breathing`, unit `minutes`, 1 to 120 per entry), and ending after a minute or more logs the whole minutes breathed.
  Ending inside the first minute logs nothing.

### Sources and the max rule

- Minutes come from two places: Apple Health `mindful_minutes`, already synced, and sessions or minutes logged in the app.
- The day's progress is the larger of the two, never their sum.
- The app never writes to Health, so a session breathed here and one recorded in another mindfulness app are different records of the same practice, and someone may log in both places.
- The cost is that a person who splits their minutes between the two sources sees the larger one only.
- The quest joins the day, like water, once either source has data: Health has synced mindful minutes on or before the day, or minutes were logged that day.

### The session

- A full-screen guided session opens from the log form's "Start 5-minute session", which the quest card's + opens, and from a "Start" button on the breathing step of Today's plan.
- The form chooses between cyclic sighing and slow breathing at 6 a minute.
- A circle grows on the way in and shrinks on the way out, with the step's word and a count down to one.
- Haptics mark each step: light for an inhale, a selection click for the top-up, medium for the exhale, and a heavy tap at the end.
- With Reduce Motion on, the circle stays one size and the words and counts carry the breath.
- The cue text is a live region, so VoiceOver speaks "Breathe in through your nose", "A second sip of air on top" and "Long breath out through your mouth" as the steps change, and the circle itself is hidden from VoiceOver.
- Pause holds the clock, and the back gesture ends the session the same way the close button does.
- The form also takes minutes breathed elsewhere, from 1 to 120.

## Server

- Migration `0026_v17_quests.sql` extends `quest_target_ok` (windows of 15 to 120 minutes, 1 to 30 servings, 1 to 60 minutes, none with a second target), both quest key checks, and the activity type and quantity checks, and backfills the three disabled templates.
- Positions are the end of each person's order, so a migration added in parallel does not clash.
- `db.LoadDayInputs` now also sums servings and breathing minutes, and loads the nights from 7 mornings before the day to the day, with the person's time zone.
- `engine` adds `sleep_regularity`, `produce` and `breathing` to progress, actuals and the Health-fed rule, with the max rule for breathing.
- `api/logs.go` accepts the two new activity types, `api/dayview.go` sends `detail` for the steady bedtime, `api/targets.go` lists the two guideline targets, and `plan` words what is left of fruit and vegetables and of breathing.
- Nothing in the coach, goals or challenge code switches on these quest keys.
  The steady bedtime has no "finish it" line in the plan because last night cannot be changed.

## App

- Quest icons, colours and copy: "Keep a steady bedtime", "Eat 5 a day", "Breathe 5 min".
- The steady bedtime is Health-fed, so its card has no + button and shows the bed and wake time lines against the usual times.
- The fruit and vegetables and breathing cards open their log forms.
- The daily goals picker offers named presets and accepts only what the server accepts.
- The Targets page groups the two guideline targets with their notes.

## Left out

- The window of the steady bedtime is not on the Targets page, because no published rule produces it and the page is for numbers that rest on a source.
- Nothing infers servings from meals, and nothing is written to Apple Health.
- The index in the Sleep insights is not the quest's score, and the quest does not use it.
