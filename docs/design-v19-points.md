# v19: points follow effort

Nick asked how much a point should be worth, because some quests take a lot of energy and were worth the same as drinking water.
Before, every quest had a fixed worth: 100 for steps, push-ups, reading and exercise, 50 for everything else.
Now a quest is worth the deliberate effort it asks.

## The rule

One point is one MET-minute above rest.
A MET-minute above rest is the minutes the quest asks, times the activity's MET value minus 1.
The MET value comes from the 2024 Adult Compendium of Physical Activities (Herrmann et al., J Sport Health Sci 2024;13(1):6-12), where 1 MET is rest.
The result is rounded to the nearest 5 and kept between 20 and 100.

The floor of 20, the cap of 100, the rounding step of 5, the 30 minute default strength session and the least a seated minute counts for are game design choices.
They are not research, and the quest sheet says so ("Worth 20, the least any goal earns", "Worth 100, the most any goal earns").
The MET values and the cadence below are published.

| Quest | Minutes it asks | MET used | Source |
| --- | --- | --- | --- |
| Steps | steps / 100 | 3.8 | About 100 steps a minute reaches moderate intensity (Marshall et al., Am J Prev Med 2009;36(5):410-415); Compendium 17190, walking 2.8 to 3.4 mph, moderate pace |
| Exercise | the target minutes | 3.8 | Compendium 17190, the same moderate walking pace; Apple counts brisk activity as exercise minutes |
| Strength (the push-ups and reps quest, any exercise) | the person's planned strength session, 30 minutes if none | 3.5 | Compendium 02054, resistance (weight) training, multiple exercises, 8-15 reps at varied resistance |
| Yoga | the target minutes | 2.3 | Compendium 02150, yoga, Hatha |
| Breathing | the target minutes | 1.0 | Compendium 07075, meditating |
| Reading | the target minutes | 1.0 | Compendium 07021, sitting quietly |

A seated minute (reading, breathing) would be worth nothing above rest, so every deliberate minute counts for at least 1 point.
That minimum is a game design choice.

The strength quest also accepts a completed strength session, so it is priced as that session and not by its reps target.
The session length is the one in the person's training profile (20 to 90 minutes).
Until they have one, 30 minutes is assumed, which is a game default and is worded as one in the app.
Saving the training profile reprices the quest and applies to today.

Water, meals logged, protein, fruit and vegetables, sleep and steady bedtime have no MET value, and no published figure for the deliberate time they take was found.
They are worth the floor of 20.

## Where it applies

- The points are stored on the quest template and follow the person's own targets and training profile.
  Changing a target, or saving the training profile, recomputes the template's points in the same write (`db.UpsertQuestTemplate`, `db.RepriceStrength`).
- The change applies to today like every other goal edit: `resnapshotToday` drops today's snapshot and rescores it, so the card, the percent of today and the possible points follow at once.
- Days before today keep the points they were frozen with in `day_quests`.
  A frozen day sends no `pointsWhy`, because its points no longer match the rule.
- Migration `0034_v19_effort_points.sql` recomputes the current templates with the same rule in SQL, reading the training profile.
  A test runs the migration against many targets and session lengths and checks it gives the same worth as the Go rule.
- The new-user defaults are computed from the same function, so they cannot drift from the rule.

## What shows it

- The quest sheet keeps "+N points, X% of today" and adds one line under it, for example "Worth 85: about 30 min of moderate effort."
  For strength: "Worth 75: priced as your 30 min strength session, which this goal also accepts."
  Without a plan: "Worth 75: priced as a 30 min strength session (a game default), which this goal also accepts."
  At the floor or cap it says so: "Worth 100, the most any goal earns: about 70 min of walking at a moderate pace."
- The chip on a card shows the same number as before, `+N`.
- The coach reads each quest as "Worth N points: ..." and is told the rule, including that the floor, the cap and the default session are game choices.
- The partner cheer prompt counted a "hard" quest as one worth 100 points.
  It now counts quests worth 60 or more, the points of 30 minutes at 3 MET, which is the bottom of moderate intensity and the daily amount Garber et al. 2011 recommend.
  That is steps, exercise and a strength session of 30 minutes or more; yoga, reading and the rest stay below it.
  (v0.24 used 80, which left out a 30 minute strength session worth 75.)

## What did not change

- The day percent is still earned base points over possible base points, the bonus is still one fifth of a quest's points, and a day still counts toward the streak at 70 percent.
- Gems, the weekly recap and challenges read stored day totals, so old weeks keep their numbers.
- Reward and challenge bonuses are fixed amounts and are not affected.

## What people will notice

With the default targets a full day is worth 360 base points, and steps are 100 of them.
A day with no steps at all can reach 72 percent, so steps are no longer needed to count, and the cap is what keeps them from dominating.

## Resulting points

Nick (male, imperial): steps 7000, push-ups 30 reps, reading 30 min, meals 3, exercise 30 min, sleep 450 min, water 3000 ml.
Nadia: water 1065 ml and push-ups 10 reps, everything else at the defaults.
Neither has a saved training profile, so the strength quest uses the 30 minute default.

| Quest | Nick target | Nick points | Nadia target | Nadia points |
| --- | --- | --- | --- | --- |
| Steps | 7000 | 100 | 8000 | 100 |
| Strength (push-ups) | 30 reps | 75 | 10 reps | 75 |
| Reading | 30 min | 30 | 20 min | 20 |
| Meals | 3 | 20 | 2 | 20 |
| Protein | his target | 20 | her target | 20 |
| Exercise | 30 min | 85 | 30 min | 85 |
| Sleep | 450 min | 20 | 420 min | 20 |
| Water | 3000 ml | 20 | 1065 ml | 20 |
| Day total | | 370 | | 360 |

Nick's steps come to 70 minutes at 3.8 METs, 196 MET-minutes above rest, which the cap holds at 100.
Strength is 30 minutes at 3.5 METs, 75 MET-minutes above rest.
A 20 minute planned session is worth 50, and 40 minutes or more reaches the cap of 100.
Nick's reading is 30 minutes at the 1 point a minute minimum.

## Sources

`herrmann2024` and `marshall2009` in `server/internal/targets/sources.go`.
The Marshall et al. volume and issue were checked online; the 100 steps a minute figure is the paper's headline cadence, and its cut points range from 92 to 115 steps a minute by sex and method.
