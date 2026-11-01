# v20: cleanup and polish

Earlier design documents still hold unless a section below changes them.

## Today's top

Nick found the top of Today busy: an avatar row with the streak and a gem count, a greeting with the coach button, the mascot with a speech bubble, and only then the day card.
The first quest sat near the bottom of the screen.

- One row: the greeting and date on the left, then the streak flame (opens the streak sheet), the coach button when the server has one, and the partner's ringed avatar (opens Us).
- The own avatar is gone from Today, because the Me tab is one tap away in the tab bar.
- The gem count is gone, because it showed today's points, which the day card already shows.
- The mascot sits in the day card beside the percent and smiles once the day counts.
- Its speech bubble is gone; the day card's one sentence already says where the day stands.
- The day card ends with two links, "Today's plan" (when there is one) and "What I logged".
- The invitation to add a first habit moves below the quests, so an empty strip never pushes them down.

## Words that meant two things

- The day card said "Reach 100% today" while the streak sheet said a day counts at the goal.
  Both now say "fill the bar".
- The repair card showed a percent of all possible points next to the day card's percent of the goal, two different scales for one day.
  It now counts points, "153 of 360 points", because a repair needs every point and not just the goal.
- The streak sheet says a repair needs "every point today, not just the goal", and prints the closing time in the phone's clock style.

## Rewards

Treats and shared rewards are one Rewards section; see the App section of `design-v19-treats.md`.

## Us showed 0 while Today showed progress

The board read each person's stored day row, which is only written when something scores the day.
A new day has no row until then, so in the morning Us could show 0 points and 0% while Today showed 60%.
The board now rescores each person's today before it reads it, as the partner's Today already does; scoring is deterministic, so this changes nothing else.

## Smaller fixes

- The goal proposal card's Accept and Not now wrap at large text instead of overflowing.
- The flame and the partner avatar are their own VoiceOver elements, so a tap on either lands on it.
- The training history page asks for the app clock's month before Today loads, instead of the phone's.

## Left for Nick to decide

- Habits and chores are priced in "gems" while quests say "points", for the same day score.
  One word should win.
