# v21: agreed tasks

## Why

Some things are not habits: call the vet for the cats, renew the car tag, book the dentist.
Nobody logs them daily, so nothing nudges them, and they slip.
A task puts gems on the line.
The two of you agree on a chore, a stake and a deadline.
Finish it in time and you win the stake; miss the deadline and you lose it.

## What a task is

A task is a row in `tasks` (migration 0039).
It has a title (1 to 60 characters), an assignee (either person), a stake in gems (1 to 100,000, the same ceiling as a reward price), a deadline (a calendar date), a creator and a status.
The assignee may be the creator or the partner.
A task for the partner is a request they must accept; a task for yourself is a stake your partner must accept, so neither person sets their own stakes alone.
The deadline is the last day it counts, on the assignee's calendar: a task due Tuesday is on time at 23:59 on Tuesday in the assignee's zone and missed from Wednesday 00:00.
An optional time of day is not part of v21, because the app's other deadlines are whole local days and one rule is easier to explain.

## Statuses

`proposed` is waiting for the other person.
`declined` means the other person said no; the creator can edit it (which proposes it again) or withdraw it.
`agreed` is live, with the stake at risk.
`done` and `missed` are final and are the only statuses that move gems.
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
The push goes out only for the call that moved the row, to both people ("You missed Call the vet, -40 gems" and "Nadia missed Call the vet, -40 gems").
A crash between commit and push can lose that push, but never charges twice; the app shows the result either way.

Finishing after the deadline is refused with `task_state`, even if the scheduler has not yet run, so the outcome never depends on timing luck.

## Gems

Task gains and losses are a ledger of their own, never day points.
They are not in `day_scores`, so they cannot change a day's score, a streak or the board's day totals.
`db.ReadPersonGems` reads each person's `tasks` as the sum of their `done` stakes minus their `missed` stakes, next to `earned` and `paid`.

A person's balance is `earned + tasks - paid`.

### Negative balances

A loss that takes a balance below zero is a debt, and the debt shows.
`Person.Balance()` no longer clamps at zero: a person with 30 gems who misses a 100-gem task reads -70.
Gems they earn afterwards pay the debt down before anything is spendable, which is the same arithmetic as any other balance.
Forgiving the debt silently would let a missed task cost nothing past the balance, which defeats the stake.

Spending never uses a debt.
`Person.Spendable()` is `max(balance, 0)`.
A treat is checked against the owner's spendable gems, so a person in debt cannot redeem.
A shared reward's price is split in proportion to each person's spendable gems, so a person in debt pays nothing toward it and nobody pays more than they hold.

The shared bank is the two balances added up, floored at zero.
One person's debt is therefore covered by the other's gems first.
With Nick at 200 and Nadia at -70 the bank is 130, and a 120-gem reward can be claimed, paid entirely by Nick.
That leaves Nick at 80, Nadia still at -70 and a bank of 10, so the bank still equals the sum of the balances.
Because the price can never exceed the sum of spendable gems, the split never asks anyone for more than they hold.

This replaces the v19 rule that a re-score below the amount paid reads zero.
The same arithmetic now lets that case show as a debt too.

The balances card on Us shows a debt in the danger colour with "In debt, gems you earn pay it down".

## Pushes

A proposal reaches the other person as `task_proposal` ("Nick asks you to do "Call the vet" for 40 gems by Wed Nov 4", or "Nick staked 40 gems on ... by ..." when it is the creator's own task) and follows the Approvals switch, like habit and reward proposals.
Done and missed pushes are `task` and follow the Reward switch.
Quiet hours and away days hold them like any other push.

## API

All under `/api/tasks`, with the usual app key and bearer token.
`GET /api/tasks` settles first, then answers `tasks` (open: proposed, declined and agreed, soonest deadline first), `history` (the newest 50 done and missed), `bank` and `balances`.
`POST /api/tasks` takes `title`, `assigneeId`, `stake` and `deadline` (`YYYY-MM-DD`).
`PATCH /api/tasks/{id}` edits any of those on the creator's own proposal.
`DELETE /api/tasks/{id}` withdraws it (204).
`POST /api/tasks/{id}/agree`, `/decline` and `/done`.
Every write answers `{"task", "bank", "balances"}`.
A task carries `daysLeft`, counted from the assignee's today, so the app words "due today" or "overdue" without doing zone arithmetic.
Refusals use `{"error", "code"}`: 422 `invalid_request`, 403 `forbidden`, 404 `not_found`, 409 `task_state` or `tasks_full`.
`balances` gains `tasks`, the net inside `balance`, and `balance` may now be negative.

## App

Us gains a Tasks section below Treats.
Agreed tasks of both people show with the assignee, the stake and "due Tue", "due today" or "overdue", and a Done button on my own tasks while they are on time.
My proposals that wait or were declined are listed under them and open the same sheet for edit or withdraw.
A proposal waiting for my answer appears with Agree and Decline in an approval card at the top of Together, next to the reward approvals.
"Add a task" opens a sheet with the title, who does it (me or my partner), the stake as round chips or a typed number, and the deadline as Today, Tomorrow, In a week or a date picker.
"Tasks settled" lists the last five finished or missed tasks with "+40 gems" or "-40 gems".

## Not done

There is no suggested stake.
The shared reward price helper multiplies the pair's daily pace by 7, 14 and 30 days, which prices a reward, not a chore, and no research prices a task, so the stake is a free choice.
There is no undo for a finished task and no way to cancel an agreed one.
There is no time of day on a deadline.
