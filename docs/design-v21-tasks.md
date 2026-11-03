# v21: agreed tasks

## Why

Some things are not habits: call the vet for the cats, renew the car tag, book the dentist.
Nobody logs them daily, so nothing nudges them, and they slip.
A task puts gems behind a chore.
The two of you agree on a chore, what it is worth in gems, and a deadline.
Finish it in time and you earn those gems.
Miss the deadline and, by default, nothing is lost.
The person who takes a task on for themselves can choose to lose the gems if they miss it (v27, "Lose them if missed").
That choice is never available when proposing a task to the partner, so nobody can put the other person's gems at risk.
The code calls the amount the stake; the app never shows the word.

## What a task is

A task is a row in `tasks` (migration 0039).
It has a title (1 to 60 characters), an assignee (either person), a stake in gems (1 to 100,000, the same ceiling as a reward price), a deadline (a calendar date), a creator and a status.
Migration 0041 adds `lose_if_missed`, the assignee's opt-in, and `lost`, what a miss actually took.
The assignee may be the creator or the partner.
A task for the partner is a request they must accept; a task for yourself is an amount your partner must accept, so neither person sets the amount alone.
The deadline is the last day it counts, on the assignee's calendar: a task due Tuesday is on time at 23:59 on Tuesday in the assignee's zone and missed from Wednesday 00:00.
An optional time of day is not part of v21, because the app's other deadlines are whole local days and one rule is easier to explain.

## Statuses

`proposed` is waiting for the other person.
`declined` means the other person said no; the creator can edit it (which proposes it again) or withdraw it.
`agreed` is live.
`done` and `missed` are final and are the only statuses that move gems; a miss moves gems only when `lose_if_missed` is set.
`withdrawn` is final and moves nothing: the creator withdrew a proposal, or a proposal was never answered before its deadline.

The other person (never the creator) agrees or declines a proposal, as with shared rewards.
Only the creator edits or withdraws, and only while it is `proposed` or `declined`.
An agreed task is a promise both made, so it can be neither edited nor withdrawn.
Agreeing is refused once the deadline has passed.
Alone on the server a task is agreed at once, as rewards are approved at once.
A person keeps at most 30 open tasks they created, and a retried identical proposal returns the existing one.

## Settlement

Done: the assignee marks their own agreed task done before the deadline day ends.
That writes `done` and `settled_at` in one locked transaction, the assignee gains the stake, and the partner gets a push ("Nick finished Call the vet, +40 gems").
Marking a done task done again answers it unchanged and sends nothing.

Missed: `together.Service.SettleTasks` runs inside `Settle`.
`Settle` is called by the scheduler every five minutes, so it happens with nobody in the app, and also before every task and reward list read, so the app never shows a stale balance.
It lists open tasks due by tomorrow's UTC date (no zone is further ahead), judges each on its assignee's own local day with the pure `tasks.Judge`, and moves an overdue agreed task to `missed` and an overdue unanswered proposal to `withdrawn`.

It happens exactly once because each task moves under two locks taken in a fixed order: the wishlist advisory lock that orders every gem change, then the task's row (`SELECT ... FOR UPDATE`).
The verdict is judged again on the locked row, and the update only runs from an open status.
A concurrent pass, a finish racing the deadline, or a restart that replays the pass finds the task already final and changes nothing.

What a miss takes is decided under those same locks, at the moment of settlement: `gems.TaskLoss(loseIfMissed, stake, balance)` is zero unless the assignee opted in, and otherwise the smaller of the stake and the balance they hold then.
That amount is written to `lost`.
The pushes go out only for the call that moved the row, to both people: "You missed Call the vet" and "Nadia missed Call the vet", with ", -40 gems" added only when something was taken.
A crash between commit and push can lose that push, but never charges twice; the app shows the result either way.

Finishing after the deadline is refused with `task_state`, even if the scheduler has not yet run, so the outcome never depends on timing luck.

## Gems

Task gains and losses are a ledger of their own, never day points.
They are not in `day_scores`, so they cannot change a day's score, a streak or the board's day totals.
`db.ReadPersonGems` reads each person's `tasks` as the sum of their `done` stakes minus the `lost` of their `missed` tasks, next to `earned` and `paid`.

A person's balance is `earned + tasks - paid`.

### No debt

A balance never reads below zero, and no task leaves a hidden debt.
`Person.Balance()` clamps at zero.
A loss is capped at the balance when the deadline passes, so a person with 30 gems who misses a 100-gem task they opted into loses 30 and holds 0, and the next gems they earn are spendable at once.
A re-score that drops earnings below what was paid reads zero too, as in v19.

Spending uses the balance directly.
A treat is checked against the owner's balance, and a shared reward's price is split in proportion to each person's balance, so nobody pays more than they hold.
The shared bank is the two balances added up.

This replaces the first v21 rule, where a missed stake could take a balance below zero and show "In debt".
That rule was dropped in v27 because it was the harshest message in the app and gave the stake no guide.

## Pushes

A proposal reaches the other person as `task_proposal` ("Nick asks you to do "Call the vet" for 40 gems by Wed Nov 4", or "Nick will Call the vet for 40 gems by Wed Nov 4, and will lose them if it is missed" when it is the creator's own task) and follows the Approvals switch, like habit and reward proposals.
Done and missed pushes are `task` and follow the Reward switch.
Quiet hours and away days hold them like any other push.

## API

All under `/api/tasks`, with the usual app key and bearer token.
`GET /api/tasks` settles first, then answers `tasks` (open: proposed, declined and agreed, soonest deadline first), `history` (the newest 50 done and missed), `bank` and `balances`.
`POST /api/tasks` takes `title`, `assigneeId`, `stake`, `deadline` (`YYYY-MM-DD`) and optionally `loseIfMissed`.
`loseIfMissed: true` is refused with 422 unless the assignee is the creator, and handing a task to the partner on edit clears it.
`PATCH /api/tasks/{id}` edits any of those on the creator's own proposal.
`DELETE /api/tasks/{id}` withdraws it (204).
`POST /api/tasks/{id}/agree`, `/decline` and `/done`.
`POST /api/tasks/{id}/counter` takes a new `stake` from the person who did not propose.
The task stays `proposed`, the person who countered becomes its creator, and the original proposer is asked to agree, decline or counter back.
Every write answers `{"task", "bank", "balances"}`.
A task carries `loseIfMissed`, `lost` and `daysLeft`, counted from the assignee's today, so the app words "due today" or "overdue" without doing zone arithmetic.
Refusals use `{"error", "code"}`: 422 `invalid_request`, 403 `forbidden`, 404 `not_found`, 409 `task_state` or `tasks_full`.
`balances` gains `tasks`, the net inside `balance`; `balance` is never negative.

## App

Us gains a Tasks section below Rewards.
Agreed tasks of both people show with the assignee, the amount and "due Tue", "due today" or "overdue" ("lost if missed" when the assignee opted in), and a Done button on my own tasks while they are on time.
My proposals that wait or were declined are listed under them and open the same sheet for edit or withdraw.
With no tasks at all the section shows the mascot, "No tasks yet" and one "Add a task" button.
"Add a task" opens a sheet with the title, who does it (me or my partner), the gems, and the deadline as Today, Tomorrow, In a week or a date picker.
When it is for me the sheet also shows "Lose them if missed", off by default.
"Tasks settled" lists the last five finished or missed tasks with "+40 gems", and "-30 gems" only when a miss took something.

A proposal waiting for my answer appears in the Action needed card, the first card on Us, together with my partner's habit, reward and chore-worth proposals.
A task there has Agree, "Change the amount" (a counter-offer through `/counter`) and Not now (`/decline`).
The Us tab in the bottom bar shows the number of things waiting on me.

## Not done

There are no suggested amounts, since the two of you agree the worth of each chore yourselves.
The loss opt-in is fixed once a task is agreed; it cannot be switched off later, because an agreed task is a promise both made.
The shared reward price helper multiplies the pair's daily pace by 7, 14 and 30 days, which prices a reward, not a chore, and no research prices a task, so the stake is a free choice.
There is no undo for a finished task and no way to cancel an agreed one.
There is no time of day on a deadline.
