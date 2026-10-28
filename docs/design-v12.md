# New Me v12: exercises you can follow, food search everywhere, a quieter Us

Earlier design documents still hold unless a section below changes them.

## Why

Nick's feedback after v0.12.0:

- A session lists exercise names, but someone who does not know an exercise has no picture, no steps, no timer for holds and no way to count reps.
- Food search for new foods was not discoverable: My foods could only create foods, and the log sheet searched the databases only after a second tap.
- Saved foods logged before the name tidy still read "Totino's GENERAL MILLS SALES INC. Totino's Cheese Party Pizza".
- Streak freezes are shown more than they matter, and Us has many extra words.

## Exercises you can follow

- Every catalog exercise has a how-to: 3 to 6 short numbered steps, one or two form cues, and two photos (start and end position).
- Steps and photos come from free-exercise-db (github.com/yuhonas/free-exercise-db), released under the Unlicense (public domain), matched by hand to each catalog key; steps are rewritten short where the source is long. Exercises without a good match get steps written from the same source family and no photo, never an invented diagram.
- Photos are served by the New Me server from its own image files (copied into the repo at build time), so the app does not depend on a third-party host.
- The session page opens an exercise's how-to from its card. Logging a set offers a rep counter (tap anywhere to count, with haptics) for rep exercises and a countdown with a 3-second lead-in and a finish haptic for timed holds; the counted or timed value fills the set form. The existing rest timer stays.

## Food search everywhere

- Typing in the log sheet's search looks in saved foods first and then, after a short pause, in USDA and Open Food Facts on its own; no second tap.
- My foods gains the same search, so a database food can be saved without logging it.
- Saved foods that came from a database have their names tidied once (brand owner removed, no shouting capitals) by a boot-time data fix that uses the same tidy rules; names a person typed are never touched.

## A quieter Us

- Each person card shows the name, the points ring, the goal percent and the streak. Freezes, "synced ... ago", workouts and season move to a sheet opened by tapping the card. "Counted" is shown by the ring's colour and a check, not a word.
- "Together: N points this week" goes; the shared streak card says it once.
- Freezes leave the Today top bar; they are shown in the streak sheet, which explains them.
