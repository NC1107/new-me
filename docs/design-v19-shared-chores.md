# v19: shared chores, an agreed worth and who did it

Nick asked for the laundry to be a shared reward.
When the two of them do it together, they both agree what the task is worth and split it.
This builds on `docs/design-v18-shared-habits.md`.

## The "no shared habits" report

Production had one chore: Laundry, weekdays mask 64, created on a Saturday.
Mask bit 0 is Monday, so 64 is Sunday.
The two day chips in the picker were both lettered "S", and a new chore started with Monday to Friday picked, so landing on Sunday only was an easy mix-up.
A Sunday chore made on Saturday is correctly not due until the next day.
Today's strip shows only chores that are due or done today, so Today showed nothing.
Home on Us listed it, but under the recap and progress links, below the first screen, so it was easy to miss.

Nothing was wrong in the server or the bitmask, which are covered by tests that pin Saturday to 32 and Sunday to 64.
The fixes are about the app.

- The day chips read Mo Tu We Th Fr Sa Su, so Saturday and Sunday are never the same letter.
- A new "Certain days" chore starts with today picked, since it is first due today.
- The picked days are spelled out under the chips ("Due Saturday.").
- Home sits directly under the two people on Us, so an empty Home with "Add your first chore" is on the first screen.

## Worth

Every chore has a worth in gems that both people agree on.
It is 25 until they agree on another number, the same default as before.
The number is any whole gem count from 1 to 100, and the app offers 10, 25, 50, 75 and 100.

One person proposes a worth when creating or editing the chore.
The other person agrees, or counters with a number of their own.

- Creating with a worth other than 25 makes the chore with 25 and the proposal pending.
- `PATCH /api/shared-habits/{id}` with `worth` records a proposal from the caller, replacing any earlier one.
- Repeating the partner's pending number agrees it.
  `POST /api/shared-habits/{id}/worth/accept` does the same, and only the person who did not propose can use it.
- Proposing the agreed number withdraws a pending proposal, or declines the partner's.
- With no partner yet, a worth is simply set.

Until it is agreed, completions pay the current agreed worth, so 25 for a new chore.
A pending worth is shown as pending, never as the price.
The partner gets a `shared_habit` push when a worth is proposed or countered, and the proposer gets one when it is agreed.
They follow the partner-done switch, quiet hours and held-push queue like the other chore pushes.

## Who did it and the split

Marking a chore done asks "Who did it?" with three answers: me, the partner, or together.
The request body is `{"by": "self" | "partner" | "together"}`, and an empty body means `self`.

- `self`: the person who marked it gets the full worth.
- `partner`: the other person gets the full worth and the person who marked it gets nothing.
- `together`: the worth is split evenly and the odd gem goes to whoever marked it, so the halves always sum to the worth.
  Worth 25 is 13 for the marker and 12 for the other person, and 40 is 20 each.

The split is the pure function `score.SharedCredit`, table-tested.
Each person's gems count on their own local day, as a bonus.
Chores still never enter the daily percent, the counted flag, the quest maximum or the streak.

## One completion per due day

The anti-farming rule is unchanged.
A chore done on someone's day is paid once.
A second tap that day, by either person and with any answer, changes nothing and pays nothing.
A chore is due again only when its schedule says so.

## Undo

Undo still removes the caller's own latest mark while its day is writable.
The row carries both people's gems, so both halves leave together and both days are rescored.
Whoever marked it is the only person who can undo it, even when it was marked for the partner.

## Data

Migration `0032_v19_shared_chore_worth.sql` adds columns, and nothing existing changes.

- `shared_habits`: `worth` (default 25), and `proposed_worth`, `proposed_by`, `proposed_at` for the pending number.
- `shared_habit_marks`: `done_by`, and the other person's share as `other_user_id`, `other_local_date` and `other_points`.
  `user_id`, `local_date` and `points` stay the person who marked it and what they earned.

A person's bonus for a day sums both their own marks and the share other people recorded for them.
Writes that touch both people's days take the day locks in user id order, so two simultaneous marks cannot deadlock.

## API changes

| Route | Change |
| --- | --- |
| `POST /api/shared-habits` | Accepts `worth` as a proposal. |
| `PATCH /api/shared-habits/{id}` | Accepts `worth` as a proposal, a counter or an agreement. |
| `POST /api/shared-habits/{id}/worth/accept` | New. Agrees to the partner's pending worth. |
| `POST /api/shared-habits/{id}/done` | Accepts `by`. Answers `gemsEarned` for the caller and `partnerGems`. |

The chore JSON has `gems` (the agreed worth), `proposedWorth`, `proposedBy` and `proposedByName`.
`last` has `together` and `doers`, each with `userId`, `name` and `gems`, so both views show who did it and what each got.

## App

- Tapping the check on a chore asks who did it in a sheet, with what each answer pays: "You earn 25 gems", "Nadia earns 25 gems", "13 for you, 12 for Nadia".
  Dismissing the sheet marks nothing.
  Without a partner the tap marks it for me directly.
- The Home row shows the schedule and the agreed worth, who did it last with the gems each got, and a pending worth.
  A worth waiting on my partner reads "75 gems waiting on Nadia".
  A worth waiting on me reads "Nadia suggests 75 gems" with an "Agree to 75 gems" button.
- The chore sheet has a Worth section, an "Agree" button for a partner's number, and a "Last done" line.
  Picking a different number and saving proposes it, or counters.
  Saving without touching the worth never sends one.
- A done chore in Today's strip reads "Done together", "Done by you" or "Done by Nadia".

## Not in scope

- Weighting the split by effort.
- A way to decline a worth other than countering with the agreed number.
- Different worths per person.
