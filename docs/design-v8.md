# New Me v8: personal targets and recommendations

Earlier design documents still hold unless a section below changes them.

## Why

Nick: "need some more recommendations based on data for calories, sleep, push-ups and workouts, based on my weight, height, intake, how much fat I should be eating and what my macros should be daily."
The app records plenty; this phase turns it into numbers each person should aim for, explains each one in a sentence, keeps them current as the data changes, and applies them with one tap.
It is general guidance from established formulas, not medical advice, and the copy says so once on the Targets page.

## Inputs

- Weight: smoothed trend (v7 EWMA) from Apple Health, falling back to the latest reading.
- Height: Apple Health `HEIGHT` (the app adds it to the read request), or entered once in Profile.
- Age: birth year (v4).
- Sex for the energy formula: asked once in Profile (male, female); used only for the resting energy equation.
- Goal: lose, maintain or gain, with a pace (lose 0.25 or 0.5 kg a week, gain 0.25 kg a week), asked once on the Targets page; default maintain.
- Activity: average Apple active energy over the last 14 days (at least 7 days of data), else a lightly active assumption.
- Intake: logged meals (kcal and macros) for the adaptive estimate.

Until height, age, sex or weight are known, the Targets page shows what is missing and a one-tap way to add it; nothing is guessed silently.

## Calories

- Resting energy (Mifflin-St Jeor): 10 x weight kg + 6.25 x height cm - 5 x age + 5 (male) or - 161 (female).
- Starting maintenance: resting energy x 1.2 plus 80% of the 14-day average active energy (the 80% corrects for wearables over-counting); without active energy data, resting x 1.4.
- Adaptive maintenance, once there are 14+ days with at least 10 days of logged intake and 8+ weigh-ins: average daily intake minus the smoothed weight change per day x 7,700 kcal; shown as "learned from your data" and preferred over the starting estimate when the two differ by more than 150 kcal.
- Target: maintenance minus (pace kg a week x 7,700 / 7) to lose, plus it to gain, rounded to 50 kcal.
- Floors: never below resting energy x 1.1, and losing faster than 1% of body weight a week is not offered.

## Macros

- Protein: 1.6 g/kg to maintain, 2.0 g/kg while losing, 1.8 g/kg while gaining; when body fat percentage is known and above 25% (male) or 32% (female), use lean mass x 2.2 instead so targets are not inflated; rounded to 5 g.
- Fat: 28% of target calories, never below 0.6 g/kg; rounded to 5 g.
- Carbs: the remaining calories at 4 kcal/g; rounded to 5 g.
- Fiber: 14 g per 1,000 kcal.
- Each number shows its reason ("Protein 165 g: 2.0 g per kg while losing, at 82 kg").

## Sleep

- Need: 7 to 9 hours for adults; the recommendation starts from the 14-night average: below 7 h, aim for 7 h 30; between 7 and 9, keep it.
- Bedtime: wake time from the schedule (v7) minus the target minus 15 minutes to fall asleep.
- Sleep debt: the 7-night shortfall against the target, shown with "an extra 30 minutes for the next 4 nights clears it".
- Consistency: when bedtime varies by more than 45 minutes, recommend a fixed bedtime window first.

## Push-ups and strength

- Each push-up log entry is a set.
- Best set: the largest set in the last 14 days.
- Daily target: three sets at about 60% of the best set (rounded to 5), at least 10 total.
- Progression: when the daily target was met on 5 of the last 7 days, propose +10% (at least +5) the next week; after two weeks without meeting it, propose -10%.
- Workouts: the weekly guideline is 150 minutes of moderate activity (or 75 vigorous) plus 2 strength sessions; Insights shows this week against it and the recommendation for the rest of the week ("1 strength session to go; you usually lift on Thursday").

## Where it shows

- Me > Targets: calories, protein, fat, carbs, fiber, sleep, steps, push-ups and weekly workouts, each with the current target, the recommendation, the reason, and "Use this"; "Use all" applies everything in one tap through the existing goal and target endpoints.
- Today: the food card shows what is left for each macro; after 17:00, when protein is more than 25 g short, a line suggests one of the person's own recent meals that covers it.
- Monday goal proposals (v6) also include target changes when the recommendation moved by more than 5% (calories more than 100 kcal), so targets stay current without visiting the page.

## Server

- `GET /api/targets` returns inputs (with which are missing), calories (resting, maintenance with its basis starting or adaptive, target), macros, sleep (need, bedtime, debt, consistency note), push-ups (best set, daily target, proposal), workouts (week so far against the guideline, recommendation), each with value, current and reason.
- `PATCH /api/me` gains `heightCm`, `sex`, and `goal {kind, paceKgPerWeek}`.
- `POST /api/targets/apply` with the keys to apply.
- All computations are pure functions with table tests.
