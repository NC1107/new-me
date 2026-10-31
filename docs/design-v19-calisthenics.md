# New Me v19: guided calisthenics

Earlier design documents still hold unless a section below changes them.
The yoga runner and voice in `design-v18-yoga-voice.md` and the daily reps in `design-v18-daily-reps.md` are the base.

## Why

Nick asked for zero-equipment workouts from beginner to intense, set up like yoga, with a male instructor and the same screen but for reps and time.
The open question was how a count of reps, which a person does at their own pace, sits next to a hold that has a clock.

## The idea in one line

A step is either timed or a number of reps.
A timed step counts down.
A rep step waits for the person, and its big centre button becomes Done.

## Where it lives

- A Calisthenics card on the Train tab, next to Yoga and Mobility, opens a page with four levels: Beginner, Intermediate, Advanced and Intense.
- Each level card shows its length, its rounds and, when the person has a max for an exercise in it, that reps use a share of that max.
- A level opens the shared guided runner (`GuidedPage`), the one Mobility and Yoga use, with a different routine, voice and recording.

## The two kinds of step

| | Timed | Reps | Rest |
| --- | --- | --- | --- |
| Examples | plank 30 s, wall sit, hollow hold, mountain climbers | 10 push-ups, 15 squats | between exercises and between rounds |
| Lead-in | 3 second get-ready | 3 second get-ready | none |
| Clock | counts down, tones or voice at 3, 2, 1 | counts nothing, shows time spent | counts down |
| Centre button | Pause | Done (check) | Pause |
| Ends | at zero, by itself | when the person taps Done | at zero, by itself |

### Rep steps

- The target is shown large with a minus and a plus beside it.
  A quick change before Done is recorded as the reps actually done.
  The default is the target, so a person who does what was asked taps Done once.
- The voice says the setup, then the number and "at your own pace, tap done when you finish", then one form cue.
- Pause moves to the app bar while a rep step is under way, because the centre button is Done.
  Paused, the centre button is Resume again.
- A small clock shows the time spent on the set, counting up, so a long set is visible.
- Previous and Next work as everywhere.
  Next skips the step and its reps are not recorded.
  Previous restarts the step and forgets reps changed on the earlier attempt.
- The rest that follows starts at once, with no get-ready, and shows the next exercise's photo and steps so the person can read them while recovering.
- There are no tempo prompts: the pace is the person's.
  A rep is estimated at 3 seconds only to size the progress bar and the "about N minutes" on the cards, and that figure is New Me's own estimate and not a published tempo.

### Timed steps and rests

- They use the existing countdown, halfway tone and chime.
- With the voice on, the coach counts "three, two, one" aloud over the last three seconds in place of the tick tones.
  With the voice off the tick tones stay.

## The levels

Each level is a fixed routine: a warm-up, circuit rounds and a cool-down of four stretches.
The routines are `kCalLevels` in `app/lib/features/training/calisthenics_routines.dart`.

| Level | Rounds | Circuit | Rest between exercises, between rounds | Share of max |
| --- | --- | --- | --- | --- |
| Beginner | 3 | knee push-ups 8, squats 10, glute bridges 12, plank 20 s, crunches 10 | 30 s, 60 s | 50% |
| Intermediate | 3 | push-ups 10, squats 15, lunges 8 a side, plank 30 s, mountain climbers 30 s | 30 s, 60 s | 60% |
| Advanced | 4 | push-ups 15, split squats 10 a side, pike push-ups 8, wall sit 45 s, hollow hold 30 s, mountain climbers 40 s | 30 s, 60 s | 70% |
| Intense | 4 | burpees 10, decline push-ups 12, jump squats 15, mountain climbers 40 s, pike push-ups 10, hollow hold 40 s, side plank 30 s a side | 20 s, 60 s | 75% |

- The warm-up is jumping jacks (30 to 60 s), the cat stretch and a few light reps of squats, push-ups or burpees.
- The cool-down is child's pose, the kneeling hip flexor stretch, the seated hamstring stretch and the cross-body shoulder stretch, 30 seconds a hold and each side for the one-sided ones.
- The reps in the table are used when the person has no max for the exercise.

### Sizing from the person's max

- If the exercise has a max test (the same maxes as the daily reps), a rep step in the circuit asks for the level's share of it, rounded, and never fewer than 3.
- The shares run from 50% to 75%.
  The daily reps use 75% of the max per set with a 70 to 80% range (`design-v18-daily-reps.md`), so Intense matches that and the easier levels sit below it.
- The warm-up reps and all timed steps ignore the max.
- A max is per exercise, so a person with a push-up max but no squat max gets sized push-ups and squats at the level's numbers.
- A very high max gives a high target on purpose.
  The voice reads up to 50 aloud and sends the person to the screen above that.

## Where the numbers come from, and what is New Me's own

### From published guidance

- Frequency: resistance training on 2 to 3 non-consecutive days a week.
  Garber et al., ACSM position stand, Med Sci Sports Exerc 2011;43:1334.
  The page says so and the app does not nag; it is not a plan.
- Volume and progression: the ACSM position stand on progression models (Med Sci Sports Exerc 2009;41:687) lists, for novices, one to three sets of about 8 to 12 repetitions, and more sets and a wider range of reps for intermediate and advanced training.
  Beginner and Intermediate use three rounds with 8 to 15 reps, Advanced and Intense four.
  This is my reading of a table whose exact numbers depend on the load and the goal, and bodyweight work is not load-matched to a percentage of a one rep maximum, so the match is by range and not by calculation.
- Rest: the same position stand gives rest periods of about 1 to 2 minutes for novice and intermediate work and shorter for muscular endurance.
  A round puts four to six other exercises between two sets of the same one, so each muscle rests longer than the short rest the person sees on screen.
  The rest lengths themselves are New Me's choice.
- Intervals: the Intense level keeps a 2 to 1 work to rest ratio on its timed steps (40 s on, 20 s off).
  The ratio is that of Tabata et al., Med Sci Sports Exerc 1996;28:1327 (20 s on, 10 s off, eight times).
  Tabata's trial used a cycle ergometer, so it supports the ratio and not these exercises, and the page says that.
- The 20 minutes that make a session count as a strength session is the threshold the server already applies to a strength workout from Apple Health (`score.StrengthCreditMinutes`).
- Garber 2011 also recommends 5 to 10 minutes of warm-up and cool-down, which the cool-down meets.
  The warm-ups are 2 to 4 minutes, shorter than that range, and the first round of the circuit is itself light.

Both new sources are in `server/internal/targets/sources.go` (`garber2011`, `tabata1996`) next to the existing `acsm2009`.

### New Me's own, said plainly in the app

- The choice of exercises and their order at each level.
- The rep numbers when there is no max, the hold lengths, the rest lengths and the number of rounds.
- The 3 seconds a rep is assumed to take, used only for the estimated length.
- The shares of max per level, which sit under the daily reps' 75%.

No trial tested these routines as a whole.
The page shows the citations and the notice that the order is New Me's own.

## The male instructor

- Model and tooling are the yoga voice's: Kokoro v1.0 through `kokoro-onnx`, rendered offline by `tools/voice/render.py` into 28 kbit/s mono AAC `.m4a`, normalised to about -18 LUFS.
- Voice: `am_michael`, speed 1.05.
  Kokoro's VOICES.md grades the male American voices.
  As I recall that table, `am_michael`, `am_fenrir` and `am_puck` share the top male grade (C+) and `am_adam` is graded lower, so the grade should be checked against the file before it is quoted again.
  Nobody on the project could listen to the candidates while this was built, so a listen on a phone is worth doing.
  Swapping the voice is one line: the `profiles` entry for `cal.` in `tools/voice/manifest.json`.
- The manifest has a new `profiles` object.
  A clip whose id starts with a prefix listed there uses that profile's voice and speed, so the yoga teacher keeps `af_heart` at 0.8 and the coach uses `am_michael` at 1.05.
- Tone: upbeat, short, with exclamation marks where a coach would have them.
- 149 new clips, about 1.7 MB, so the whole set is 259 clips and 4.3 MB, under the 6 MB test budget.

### The script

Clips are parts that the app joins, so one recording of "ten" serves every exercise.

| Clip id | When it plays |
| --- | --- |
| `cal.welcome` | At Start, with the first exercise's setup. Tells the person how rep steps and holds work. |
| `cal.<exercise>.intro` | The exercise's name and how to set up, when it starts by itself or after a skip or back. |
| `cal.rest_next` and `cal.<exercise>.name` | At the start of a rest: "Rest. Next up, squats." |
| `cal.round.2` to `cal.round.4`, `cal.last_round` | When the first exercise of a round starts. |
| `cal.n.1` to `cal.n.50` and `cal.<exercise>.reps` | After the get-ready of a rep step: "Ten," "push-ups, at your own pace. Tap done when you finish." |
| `cal.n.screen` | In place of the number above 50: "Your target is on the screen." |
| `cal.<exercise>.go` and `cal.t.<seconds>` | After the get-ready of a hold: "Hold the plank." "Thirty seconds." Stretches use `cal.hold_stretch`. |
| `cal.<exercise>.cue` | One form cue a few seconds after that. |
| `cal.count.3` to `cal.count.1` | At each of the last three seconds of a hold. |
| `cal.switch_sides` | When the second side of an exercise starts. |
| `cal.rest.1` to `cal.rest.3` | A line in the middle of a rest when it is long enough. |
| `cal.closing` | In the last hold, ending before the final chime. |

`CalisthenicsVoice` plans the clips as a pure function of the holds, like `GuidedVoice`, and a test checks that no two overlap and that all of them finish before the countdown.
A hold whose clips are missing is left silent and never half spoken.
Regenerating is as for yoga: edit the manifest, run `render.py --models <dir>` (add `--only cal.` to re-render just these), and the generated `voice_clips.dart` updates.

## Recording

- A finished session logs its minutes as a new activity type, `calisthenics` with unit `minutes` (stored as `calisthenics_minutes`, migration `0036_v19_calisthenics.sql`).
- Minutes are active time: lead-ins, sets, holds and rests, but not pauses, as for yoga and Mobility.
- Under 30 seconds nothing is logged.
  Ending early offers to log the minutes so far, as for yoga.
- What it counts toward:
  - Exercise minutes: calisthenics minutes add in full to the exercise quest, like a hard manual activity.
  - Get stronger: a session of 20 minutes or more counts as a strength workout for the push-ups quest, with the same rule and the same "done by" line as an Apple Health strength workout.
    A shorter session still adds its exercise minutes.
    The server turns the minutes into a strength workout span when it loads the day's inputs (`db.LoadDayInputs`), so scoring, rescoring and history need no new rule.
  - Daily reps: the reps the person finished of the quest's own exercise are logged as a push-ups (reps) activity with that exercise, so squats count toward a squat quest and push-ups toward a push-up quest.
    Reps of other exercises are not logged, because they would not count toward the quest anyway.
    The quest's exercise is read when the session ends, since logging the minutes refreshes Today.
- The minutes and each reps log carry their own client operation id made once per session, so a retry after a dropped reply cannot count twice.
- The last screen lists the reps done, says where the minutes went, and says whether the session counted as a strength session.

## Catalog additions

Migration `0036` adds five zero-equipment strength exercises that the levels need, each with steps and cues and no photo: `jumping_jack`, `mountain_climber`, `wall_sit`, `pike_push_up` and `jump_squat`.
They are ordinary strength-kind exercises, so they also appear in the exercise library.
Everything else the levels use was already in the catalog (push-ups, squats, lunges, planks, burpees and the Mobility stretches).
The migration also widens the activity type check for `calisthenics_minutes`.

## Not done

- A calisthenics weekly plan like Yoga's.
  The page recommends 2 to 3 days a week in words only.
- Per-exercise rep history and progression for the circuit.
  The daily reps quest keeps its own progression.
- Photos or video for the new exercises.
- The Training history screen does not list calisthenics sessions yet.
- A server-side voice parameter for live lines.
  Rendering the coach offline worked, so the app does not need it.
