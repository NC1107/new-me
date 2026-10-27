# New Me v9: training

Earlier design documents still hold unless a section below changes them.

## Why

Nick asked how pull-ups would get added and whether AI could design workouts.
Today only push-ups are a scored exercise, and strength training is either a Health workout or a push-up count.
This phase makes exercises first-class data: a library, sets logged with reps or seconds and optional load, plans designed by Claude within research-backed limits the server enforces, and day-to-day progression decided by published rules rather than AI.
The v8 rule still applies: every number the app recommends comes from a cited guideline or is labelled as a convention or derivation.

## Exercise library

- A seeded catalog of about 35 exercises, each with a key, name, primary and secondary muscle groups, measure (reps or seconds), load type (bodyweight or external) and the equipment it needs.
  Bodyweight: push-up, incline push-up, decline push-up, pull-up, chin-up, negative pull-up, band-assisted pull-up, inverted row, dip, bench dip, air squat, split squat, Bulgarian split squat, lunge, step-up, glute bridge, single-leg glute bridge, hip hinge good morning, calf raise, plank (s), side plank (s), hollow hold (s), dead hang (s), burpee.
  Equipment: goblet squat, dumbbell Romanian deadlift, dumbbell bench press, dumbbell row, dumbbell overhead press, lateral raise, biceps curl, triceps extension, barbell back squat, barbell deadlift, barbell bench press, overhead press, hangboard hang (s).
- Progressions link easier and harder variations (incline push-up, push-up, decline push-up; band-assisted pull-up, negative, pull-up).
- Each person can add custom exercises with the same fields.
- Equipment profile per person: none, pull-up bar, dumbbells (heaviest pair in kg), barbell, bench, resistance bands, full gym.

## Logging

- `POST /api/sets` with `{exercise, reps | seconds, loadKg?, rir?, date?, sessionId?}`; the same open-day rules as logs.
- Existing push-up logs count as push-up sets, and the push-up quest keeps working from sets.
- Best set per exercise; for loaded sets an estimated one-rep max by the Epley formula (load x (1 + reps / 30)), labelled as an estimate.
- Max tests for any bodyweight exercise (one set to near failure), generalising the v8 push-up max.

## Plans

- **Inputs:** goal (from v8), days per week (2 to 6), minutes per session (20 to 90), experience (new, some, experienced), equipment, preferred workdays from the v7 schedule, and a free-text focus ("first set of 10 pull-ups", "bigger back", "climbing on Saturdays").
- **Generation:** Claude (`claude-sonnet-4-6`, forced tool) returns a block of 4 to 6 weeks: training days, each with exercises from the catalog, sets, a rep or seconds range, target reps in reserve and rest.
- **Server validation (rejects or repairs before saving):**
  - every exercise exists in the catalog and its equipment is available;
  - the number of training days matches the request;
  - muscle-strengthening work on at least 2 days a week (WHO 2020);
  - weekly hard sets per major muscle group between 10 and 20 for experienced people and between 4 and 12 for new people, from the dose-response evidence (Schoenfeld, Ogborn and Krieger, J Sports Sci 2017;35:1073), labelled as the evidence range;
  - estimated session time (sets x (40 s work + rest)) within the requested minutes plus 10%;
  - reps in reserve between 0 and 4 (Zourdos et al., J Strength Cond Res 2016);
  - one repair round: violations are sent back to Claude once; if still invalid, the server trims or rejects with a clear message.
- The plan is stored; Claude is not called again until the person asks for a change or the block ends.

## Progression (deterministic, no AI)

- Double progression within the prescribed range (ACSM position stand, Med Sci Sports Exerc 2009;41:687):
  - when every set of an exercise reached the top of its range at or above the target reps in reserve, the next session adds load: 2 to 5% for upper-body and 5 to 10% for lower-body exercises, rounded to the available dumbbell or plate increment;
  - for bodyweight exercises, add 1 to 2 reps per set within the range, then move to the harder variation when the top of the range is reached on all sets in two sessions;
  - when the bottom of the range is missed on two consecutive sessions, the next session lowers load by 5 to 10% or moves to the easier variation.
- Each change is explained on the session screen ("Pull-ups: 4 x 6 last time at 2 in reserve, so 4 x 7 today; ACSM progression").

## Changes on request

- From the plan screen: "Swap an exercise", "Bodyweight only this week", "Shorter sessions", "Something hurts" (with the area), "New block".
- Claude rewrites only the affected part, under the same validation; the progression history carries over by exercise.

## Today and the quest

- A "Today's session" card shows the planned exercises, with Start opening the session screen: each exercise with its target sets, a stepper per set prefilled with the target, an optional load, a reps-in-reserve chip (0 to 4), a rest timer, and Done.
- The "Get stronger" quest is completed by finishing today's planned session, by a Health strength workout of 20 minutes or more (v6), or, without a plan, by the push-up target.
- Rest days in the plan show "Rest day" instead of the card.

## Progress

- Per exercise: best set, estimated one-rep max for loaded lifts, and a sparkline.
- Weekly hard sets per muscle group against the evidence range.
- Look-backs (v7) add "Pull-ups: best set 8, up from 3 in your first month".

## API

- `GET /api/exercises` (catalog plus custom), `POST/PATCH/DELETE /api/exercises/{id}` for custom ones.
- `GET/PUT /api/training/profile` (equipment, days, minutes, experience, focus).
- `POST /api/training/plan` (generate), `GET /api/training/plan`, `POST /api/training/plan/change {kind, detail}`, `DELETE /api/training/plan`.
- `GET /api/training/today` (today's session with targets and progression reasons), `POST /api/training/sessions/{id}/complete`.
- `POST /api/sets`, `DELETE /api/sets/{id}`, `GET /api/sets?exercise=&days=`.
- `GET /api/training/progress` (per exercise and per muscle group).
