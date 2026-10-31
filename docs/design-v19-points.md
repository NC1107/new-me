# v19: points follow effort

Nick asked how much a point should be worth, because some quests take a lot of energy and were worth the same as drinking water.
Before, every quest had a fixed worth: 100 for steps, push-ups, reading and exercise, 50 for everything else.
Now a quest is worth the deliberate effort its own target asks.

## The rule

One point is one MET-minute above rest.
A MET-minute above rest is the minutes the target asks, times the activity's MET value minus 1.
The MET value comes from the 2024 Adult Compendium of Physical Activities (Herrmann et al., J Sport Health Sci 2024;13:6), where 1 MET is rest.
The result is rounded to the nearest 5 and kept between 20 and 150.

The floor of 20, the cap of 150, the rounding step of 5, the tempo of a rep and the least a seated minute counts for are game design choices.
They are not research, and the quest sheet says so ("Worth 20, the game's minimum").
The MET values and the cadence below are published.

| Quest | Minutes the target asks | MET used | Source |
| --- | --- | --- | --- |
| Steps | steps / 100 | 3.8 | 100 steps a minute is moderate walking (Marshall et al., Am J Prev Med 2009;36:410); Compendium 17190, walking 2.8 to 3.4 mph, moderate pace |
| Exercise | the target minutes | 3.8 | Compendium 02022 and 17190, moderate effort; Apple counts brisk activity as exercise minutes |
| Daily reps (push-ups, squats, lunges, pull-ups, knee and incline push-ups) | reps x 10 seconds | 3.8 | Compendium 02022, calisthenics (push-ups, pull-ups, lunges), moderate effort |
| Daily reps (glute bridges) | reps x 10 seconds | 3.0 | Compendium 02056, body weight resistance exercises, general |
| Daily reps (crunches) | reps x 10 seconds | 2.8 | Compendium 02024, calisthenics (curl ups, crunches, plank), light effort |
| Yoga | the target minutes | 2.3 | Compendium 02150, yoga, Hatha |
| Breathing | the target minutes | 1.0 | Compendium 07075, meditating |
| Reading | the target minutes | 1.0 | Compendium 07021, sitting quietly |

A seated minute (reading, breathing) would be worth nothing above rest, so every deliberate minute counts for at least 1 point.
That minimum is a game design choice.

Ten seconds a rep, resting between sets included, is also a game design choice.
No published figure for the time a set of push-ups takes was found, so it is stated as a tempo and not as research.

Water, meals logged, protein, fruit and vegetables, sleep and steady bedtime have no MET value, and no published figure for the deliberate time they take was found.
They are worth the floor of 20.

## Where it applies

- The points are stored on the quest template and follow the person's own target.
  Changing a target, or the daily-reps exercise, recomputes the template's points in the same write (`db.UpsertQuestTemplate`).
- The change applies to today like every other goal edit: `resnapshotToday` drops today's snapshot and rescores it, so the card, the percent of today and the possible points follow at once.
- Days before today keep the points they were frozen with in `day_quests`.
  A frozen day sends no `pointsWhy`, because its points no longer match the rule.
- Migration `0034_v19_effort_points.sql` recomputes the current templates with the same rule in SQL.
  A test runs the migration against many targets and checks it gives the same worth as the Go rule.
- The new-user defaults are computed from the same function, so they cannot drift from the rule.

## What shows it

- The quest sheet keeps "+N points, X% of today" and adds one line under it, for example "Worth 85: about 30 min of moderate effort."
  At the floor or cap it says so: "Worth 150, the game's maximum: about 70 min of walking at a moderate pace."
- The chip on a card shows the same number as before, `+N`.
- The coach reads each quest as "Worth N points: ..." and is told the rule, including that the floor and cap are game choices.
- The partner cheer prompt counted a "hard" quest as one worth 100 points.
  It now counts quests worth 80 or more, about half an hour of moderate effort, which is again steps and exercise.

## What did not change

- The day percent is still earned base points over possible base points, the bonus is still one fifth of a quest's points, and a day still counts toward the streak at 70 percent.
- Gems, the weekly recap and challenges read stored day totals, so old weeks keep their numbers.
- Reward and challenge bonuses are fixed amounts and are not affected.

## What people will notice

With the default targets a full day is worth 355 base points, and steps are 150 of them.
A day with no steps at all can reach at most 58 percent, so the streak line of 70 percent now needs about 30 percent of the steps goal as well as everything else.
That follows from pricing by effort, and the 70 percent line was left alone.

## Resulting points

Nick (male, imperial): steps 7000, push-ups 30 reps, reading 30 min, meals 3, exercise 30 min, sleep 450 min, water 3000 ml.
Nadia: water 1065 ml and push-ups 10 reps, everything else at the defaults.

| Quest | Nick target | Nick points | Nadia target | Nadia points |
| --- | --- | --- | --- | --- |
| Steps | 7000 | 150 | 8000 | 150 |
| Push-ups | 30 reps | 20 | 10 reps | 20 |
| Reading | 30 min | 30 | 20 min | 20 |
| Meals | 3 | 20 | 2 | 20 |
| Protein | his target | 20 | her target | 20 |
| Exercise | 30 min | 85 | 30 min | 85 |
| Sleep | 450 min | 20 | 420 min | 20 |
| Water | 3000 ml | 20 | 1065 ml | 20 |
| Day total | | 365 | | 355 |

Nick's steps come to 70 minutes at 3.8 METs, 196 MET-minutes above rest, which the cap holds at 150.
Nick's reading is 30 minutes at the 1 point a minute minimum.
Push-ups at 30 reps are 5 minutes at 3.8 METs, 14 points, so the floor of 20 applies; a target of 100 reps is worth 45.

## Sources

`herrmann2024` and `marshall2009` in `server/internal/targets/sources.go`.
