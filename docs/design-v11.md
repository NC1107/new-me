# New Me v11: the goal is 100%, habits paid by the minute, readiness that changes training

Earlier design documents still hold unless a section below changes them.

## Why

Nick's feedback after v0.11.0:

- Reaching 70% is hard enough that it should read as a full day: 70% of the day's points is the new 100%.
- A habit's gems should come from the time it takes, and the partner should approve them.
- In-person yoga classes should be easy to log as time.
- Readiness should change something real, the audit found repeated information on Today and Me, and branded foods could show a photo.

## The goal is 100%

- Scoring is unchanged: a day counts when its base points reach 70% of the possible base points (`score.CountedPercent`).
- The goal is `ceil(maxBase * 70 / 100)` points, and `goalPercent = basePoints * 100 / goal`, so a counted day is exactly `goalPercent >= 100`.
- `goalPercent` may go above 100 (up to about 142 when every point is earned); the app shows it as is, with the part above 100 as bonus.
- Every day the API returns (`day`, the board's `today` and `last7`) gains `goalPercent`; `percent` stays for older builds.
- The app shows `goalPercent` everywhere a day's percent was shown: the progress bar is full at the goal and a bonus segment follows it, with no 70% flag.
- Repair still needs every base point today; its copy says "every point" instead of a percent.

## Habits are paid by the minute, and the partner approves

- A habit records how many minutes it takes, from 1 to 30, or none for one that is only tracked.
- Gems are 3 a minute, capped at 100. The rate is the timed quests' own (yoga 50 for 20 minutes is 2.5, exercise 100 for 30 is 3.3, reading 100 for 20 is 5; the median is 3.3, rounded down to keep habits from outpaying quests).
- When someone with a partner creates a habit or changes its minutes, the new gems are proposed: the habit keeps its current gems (a new one is only tracked) until the partner approves. Declining keeps the current gems. Without a partner the change applies at once.
- The partner sees the proposal on Us and gets one push; approving or declining is one tap.
- An approved change rescores the days still open, today included; finalized days keep their values.
- Existing habits keep their gems; their minutes are unset until edited.

## Yoga and stretching

- The Stretch focus becomes Yoga or stretching. Minutes logged by hand count, with choices up to class length (15, 30, 45, 60, 75, 90), and Apple Health yoga, Pilates, flexibility and mind-and-body workouts still count.

## Readiness changes the session

- On an Easy readiness morning, the day's training session drops one set from each exercise (never below one) and holds every load and rep target where it was instead of progressing.
- This is HRV-guided training: adjusting load on mornings when HRV is below its baseline (Kiviniemi et al., Eur J Appl Physiol 2007;101:743; Manresa-Rocamora et al., Int J Environ Res Public Health 2021;18:10299).
- The session says why in one line, and a person can take the full session instead with one tap.

## Food photos

- Branded results from Open Food Facts show the product's front photo and the source, linked to the product page; photos are CC BY-SA and the data ODbL, which the attribution satisfies. USDA results have no photos.
- Photos load from Open Food Facts directly and are cached on the phone; nothing is stored on the server but the URL.

## Less repetition

- Today's speech bubble is one short line plus the plan link; it no longer restates quest progress.
- Quest cards show the title and bar; the "x of y" line goes, and the Apple Health chip is shown once in the list rather than on every card.
- Me merges Profile into About you, Time zone into Schedule, and Food targets into Targets.
