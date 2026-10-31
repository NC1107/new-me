# v18: quest sheet and switches that apply today

Reported on the Today screen: a quest could not be removed, no card said what finishing it was worth, and tapping any quest only showed the day's meals and sets.

## The quest sheet

Tapping a quest card opens a sheet about that quest alone (`app/lib/features/today/quest_sheet.dart`).
The old behaviour, a list of every entry of the day, stays behind "What I logged today" on the day card.

The sheet shows, top to bottom:

- The quest's title and where its number comes from: Apple Health, what the person logs, or both.
- Progress against the target, with the bar.
- What finishing it is worth: "+100 points, 24% of today", the share computed from today's total possible points (`day.maxBase`).
  Once the quest is done it reads "Earned +100 points, 24% of today", with the bonus on the line below.
- Today's entries for this quest only.
  Meals feed Meals and Protein, and an activity feeds the quest of its own type.
  Entries reuse the day sheet's list (`EntryList`), so swipe to delete, Undo and the meal editor work the same.
  Health-fed quests have nothing to log and say where the number comes from instead.
- The last 7 days: a bar per day filled to how far the quest got, a check on days it was done, and a dash on days it was not part of the day.
  The data comes from `GET /api/quests/{key}/history?days=7`, which reads the stored day snapshots and never writes.
- "Why this goal": the formula and first source from `GET /api/targets` where a matching target exists (steps, protein, sleep, water, fruit and vegetables, breathing, exercise, push-ups).
  Quests with no published research behind the number say so plainly.
  When the goal differs from the formula, the sheet says the goal is the person's own pick.
- Actions: log (the existing log sheet for the quest's `LogKind`), "Change goal" (the existing `GoalPickerPage`, saved through the `questTemplates` patch of `PATCH /api/me`) and "Turn off this quest".

Turning a quest off asks first, then shows an Undo snack bar on Today.
Quests that are off are not on Today, so a quiet "N quests are off" line under the cards opens a sheet that turns any of them back on.
Together these make every quest switchable from where the person sees it.

Each quest card also carries a small "+100" chip.
It is quiet while the quest is open and takes the person's colour once the points are earned.

## Switches apply today

Before, a template edit (on or off, or a new target) froze the open days and applied from tomorrow, except on the join day.
People expect a switch to take effect when they flip it, so `PATCH /api/me` now re-snapshots today after writing templates or targets.
`resnapshotToday` takes the day lock, drops today's snapshot with `db.ResetDaySnapshot`, and rescores it, so the quest list and the possible points follow at once.
The same rule applies when a goal proposal is accepted and when targets are applied.
Logs and Health data for today are kept, because scoring reads them live.
Days before today, including yesterday while its grace window is open, are frozen by the rescore that runs first and are never rewritten.

The tradeoff is accepted: someone could lower a target after the fact to finish a quest.
This is a private app for two people who share the aim of using it honestly, and a switch that waits until tomorrow reads as a bug.

## Server

- `GET /api/quests/{key}/history?days=7` (1 to 31): `{"key", "days": [{"date", "tracked", "actual", "target", "unit", "done"}]}`, oldest first, only days from the join date on.
  `tracked` is false when the quest was not in that day's snapshot.
  An unknown key is a 404.
- `resnapshotToday` replaces `resnapshotJoinDay` and no longer checks for the join day.
