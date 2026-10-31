# v18: weekly recap clean-up and the mascot app icon

Builds on the recap rules in `design.md` (`internal/recap`) and the v6 recap screen.
No server contract change and no migration.

## The recap screen

The old screen listed the same six rows three times (the couple, then each person) and read as one long scroll with no order of importance.
It now reads top to bottom as the headline, what went well, what to work on, and then each person.

- **Together card.** The couple's points as a large number, how they moved against the week before, and the best day.
  The best-day card is folded into this card.
  A week still running says so and shows last week's total instead of a change.
- **What went well.** Only the couple's rows that went up on the week before (steps, sleep, workouts, reading), and a finished challenge.
  Points are left out because the headline already says how they moved.
  Nothing is listed for a week with nothing that went up, and the heading is then left out too.
- **To work on.** The server's suggestions as before, plus a challenge that was missed or is still open.
  A running week shows no suggestion, because the server's line for it is only encouragement.
- **Each of you.** Name and points on one line, then the other numbers in a three-column grid, each with its change underneath.
  The old rows wrapped and misaligned values such as "6 h 43 min".
- **Changes** carry their own sign ("+4,200", "-16 min", "Same"), so the arrow icons are gone.
  Nothing relies on colour, and the recap still never ranks the two people.
- **Counted days** are shown per person only.
  The couple's total added two people's counts into a number nobody earned.

## Empty and partial weeks

- A week where nothing was recorded shows the sleepy mascot and "A quiet week" instead of a card of zeros.
- An earlier week with nothing in it is never a baseline.
  A first week, or a person who joined mid-week, shows no changes and says "a first week, so nothing to compare yet" instead of "+50,400 steps".
- A person with nothing logged gets one line, not a grid of zeros.
- Sleep with no nights reads "No data".
- Server: a person who joined during the week is not told to "aim for 5 counted days", since they were not there for all of it (`recap.Suggest`, `joinedMidWeek`).
  The remaining rules still apply, and the steps and points rules already skip an empty earlier week.

## App icon

The iPhone icon was a green three-quarter ring on black, which did not match the brand.
It is now the smiling Fern mascot (`widgets/mascot.dart`, happy state) on the green tint from `theme/accent.dart`, centred with its ring at 62% of the icon so it clears the iOS corner mask and the 80% maskable safe zone.
The shadow under the mascot is kept, as part of the character.

- Every file is rendered by `test/app_icon_test.dart`: the 1024 px `AppIcon.appiconset/Icon-1024.png` (the only image the set lists) and the web `favicon.png` (32 px), `icons/Icon-192.png`, `Icon-512.png` and the two maskable ones.
- All are 8-bit RGB PNGs with no alpha channel, which the App Store requires.
- Regenerate with `NEWME_WRITE_ICONS=1 flutter test test/app_icon_test.dart`.
  Without the variable the same test checks that the committed files still match the mascot and have no alpha.
