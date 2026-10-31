# v18: daily reps

The "Get stronger" quest counted push-ups only, with a flat default of 30.
Thirty push-ups is a lot for some people and too little for others, and a person who cannot do a push-up had no way in.
v18 lets the person pick the exercise and sizes the daily target from their own max.

## What changed

The quest key stays `pushups` so every stored row, score, streak and client keeps working.
What the quest counts is now the exercise on the quest template, frozen into each day's snapshot like the target.
Rows written before v18 are push-ups, which is the column default.

| Where | Change |
| --- | --- |
| `quest_templates.exercise`, `day_quests.exercise` | Catalog slug, default `push_up` (migration 0029). |
| `activity_logs.exercise` | The exercise of a rep log, default `push_up`. Only meaningful for type `pushups`. |
| `exercise_max_tests` | Already per exercise since v9, so max tests need no new table. The v8 `pushup_max_tests` table still receives push-up maxes and is read together with the general one. |
| Catalog | Two easier choices, `knee_push_up` and `crunch`, added in 0029 with steps and cues. `incline_push_up` now lists `knee_push_up` as its easier variation. |

## The choices

Defined in `server/internal/db/daily_reps.go` (`RepsExercises`), mirrored by name in `app/lib/util/reps_exercises.dart`.

| Exercise | Slug | Needs |
| --- | --- | --- |
| Knee push-ups | `knee_push_up` | nothing |
| Incline push-ups (hands on a counter) | `incline_push_up` | nothing |
| Push-ups | `push_up` | nothing |
| Squats | `air_squat` | nothing |
| Lunges | `lunge` | nothing |
| Glute bridges | `glute_bridge` | nothing |
| Crunches | `crunch` | nothing |
| Pull-ups | `pull_up` | `pullup_bar` in the training profile |

The pull-up is listed to everyone and disabled until the pull-up bar is set under Training, and the server refuses it without the bar.
A timed hold (plank seconds) was left out: the quest, its snapshot, the log forms and the progression rule all count reps, and a seconds variant would need a second unit through all of them.

## Setting it up

`Me > Daily goals > Get stronger` and the strength goal in onboarding both open the daily reps page (`app/lib/features/me/daily_reps_page.dart`).
The Targets page opens the same page from the push-ups card (renamed after the exercise) and from the max test link.

1. Pick the exercise.
2. Enter the max: the most reps of that exercise in one set, to near failure with good form.
   The page carries "test now" guidance: warm up for a minute, do one set, stop when one or two more is all that is left, count it.
3. The page shows the derived target before anything is saved: 3 sets of N, the daily total, the 70 to 80% range per set, the plain statement that it is a derivation, and the citations.
4. Save records the max as a max test of that exercise and sets the template's exercise and target.

A person who does not know their max picks "Not sure yet".
The app does not suggest a number: no published research gives a starting count that is safe for every person and every exercise, and inventing one would put a made-up figure under a citation.
They type a number they can do with good form and plenty left, the page shows 3 times that, and the Targets page keeps asking for a max test.
Once a max exists the target is derived from it as below.

A change reaches today's quest only while nothing is counted on it yet (so setting up squats in the morning does not leave the day asking for push-ups).
Once reps are logged the day stays frozen and the change starts tomorrow, the same rule every other goal edit follows.
On the join day the onboarding choice applies at once, as before.

## The derivation

Unchanged from v8 and applied per exercise (`server/internal/targets/pushups.go`).

- Three sets at 75% of the latest max for that exercise, rounded, with the 70 to 80% range shown.
  Reps-in-reserve guidance (Zourdos et al., J Strength Cond Res 2016) and the evidence that sets taken near failure drive adaptation (Schoenfeld et al., J Sports Sci 2017) support working well below failure; the 75% midpoint is a derivation, not a published constant, and the page says so.
- Progression: when every set of the current target was completed on 5 of the last 7 days, the reps per set rise by 5%, at least one rep.
  The ACSM position stand (Med Sci Sports Exerc 2009;41:687) allows 2 to 10% increases.
  Only logs of the quest's exercise count toward the completed days.
- Retest every 2 to 4 weeks.

Maxes are not comparable across exercises, so each exercise keeps its own max test history and its own progression.
Changing exercise starts from that exercise's latest max, or asks for one.

## Counting

- A rep log carries `exercise`. A log with none (an older client) takes the exercise the day's quest counts, so it behaves as it always did.
- Reps of another exercise are stored and shown in the day's log, but do not count toward the quest, its progression or its completion.
- Catalog sets (training sessions) count by catalog exercise.
  For push-ups the group stays `incline_push_up`, `push_up`, `decline_push_up` as before v18; for every other choice only that exercise counts.
- The weekly push-ups challenge and the Progress push-ups series count push-ups only.
  A person on squats sees those stay at their push-up total; a per-exercise series is a follow-up.

## API

- `GET /api/daily-reps`: the choices with the latest max of each, the quest's exercise and target, today's frozen exercise, the sets per day and the citations.
- `GET /api/daily-reps/preview?exercise=&max=`: 3 sets at 75% of the max, the range, the daily total, the formula sentence and the citations. Max is 1 to 200 so three sets stay inside the quest's 500 a day.
- `PUT /api/daily-reps` with `exercise` and either `max` (recorded as a max test, then sized) or `repsPerSet` (taken as given, 1 to 150).
- `PATCH /api/me` quest templates accept `exercise` for the `pushups` quest.
- `quests[]` and `questTemplates[]` carry `exercise` for the `pushups` quest, and the title is the exercise name ("Squats").
- `POST /api/logs` accepts `exercise` for type `pushups`.

## Copy

Every place that read "push-ups" for this quest follows the exercise: the Today card ("Get stronger", then "A strength session or 45 squats"), the log sheet and its max test, the day detail log rows, the finish suggestions in the day plan, the partner cheer line, the Targets card and its name.

## Sources

All in `server/internal/targets/sources.go`: zourdos2016, schoenfeld2017, acsm2009.
