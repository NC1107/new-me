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

## Gems, not points

Habits and chores were priced in "gems" while quests and the day card said "points", for the same thing.
A person's gems earned are the sum of every day's base and bonus points (`db.ReadPersonGems`), so one point is one gem.
Nick chose gems, so every place the app or server talks to a person now says gems: quest chips and sheets, the day and repair cards, the streak sheet, Us, the recap, the look-back, the weekly push, the coach, and the iOS widget descriptions.
Code and the API keep the name points.

## Recent meals
The meal sheet listed recent meals as chips capped at 200 px.
Real names are often whole ingredient lists, "Dave's Killer Toast, Butter, Chicken Breakfast Sausage, Scrambled Eggs", so several chips read "Dave's Killer Toast, ..." and could not be told apart.
They are now rows like the food search results: the whole name on up to two lines, then kcal and protein.
Five show at first and "Show N more" opens the rest, so the form below stays in reach.

## Last night
A night of sleep is stored under the morning it ends, so the sleep quests already count for the day you wake into.
They differ from every other quest because the night is over by the time the app opens: nothing done today can change them.
- A sleep or steady bedtime quest that met its goal leads the quest list, so a good night is the first thing ticked off in the morning.
- One that fell short leaves the list for a quiet note under the quests, "Slept 5 h 34 min of 7 h 30 min", with what it still earned, "Last night, 40 of 50 gems".
  Every quest pays in proportion, so a short night still earns most of its gems; only the finish bonus needs the whole goal.
- Before the night arrives from Health the quest stays an open card that says "No night from Health yet".
