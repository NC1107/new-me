# v19: personal treats

## Why

Shared rewards are claimed once and paid from the pair's bank.
That fits a date night, not a Monster energy drink one of you wants every week.
A treat belongs to one person, is redeemed from that person's own gems, and can be redeemed again.

## What a treat is

A treat is a row in `rewards` with `owner_id` set (migration 0035).
Shared rewards keep `owner_id` null and behave exactly as before.
A treat is never the focus and is never claimed; the database refuses both.
Redeeming writes a row to `treat_redemptions` with the name and price at that moment, so history survives a later price change or a removed treat.

## Pricing: both agree

Neither person may price their own treat cheaply, so a treat reuses the reward proposal flow unchanged.
The owner proposes a name and price, and the partner approves or declines.
Either person may propose a new price for an approved treat; the other answers, and a declined change restores the agreed price.
Only the owner renames a treat or removes it.
When there is no partner on the server, a treat is approved at once, as shared rewards are.
Proposals reach the partner as a reward-proposal push ("Nick wants Monster energy drink as a treat for 1000 gems") and follow the existing Approvals switch.

## Balances

Each person has lifetime gems earned (the sum of their scored days) and gems paid out.
Paid out is the price of every treat they redeemed plus their share of every shared reward claimed.
A person's balance is earned minus paid out, never below zero.
The shared bank is both people's earned gems minus everyone's paid out, which equals the two balances added up.
The bank is what the board, the shared reward bar and the "Reward ready" push read, so they stay consistent with treats.

Neither person can spend gems the other earned on a treat, because a treat is checked against the owner's balance only.

## Paying for a shared reward

A shared reward is paid by both, but not evenly and not by lifetime earnings.
At the moment it is claimed, its price is split in proportion to the balance each person holds, with the odd gems going to the largest fractions.
This is why: an even split could push a person who spent on treats below zero, and a split by lifetime earnings ignores what they already spent.
Splitting by current balance means nobody ever pays more than they hold, the shares add up to the price exactly, and the bank stays equal to the sum of the balances.
The split is stored per claim in `reward_payments`, so balances are exact and never recomputed from a moving ratio.
Rewards claimed before this migration were split by what each person had earned and stored the same way.
A claim still needs the bank to cover the price; the bank already excludes treat spending.

Superseded by v21: a balance below zero now shows as a debt, see docs/design-v21-tasks.md.
In that case the balances can add up to more than the bank; the bank is the figure shared rewards are checked against.

## Redeeming

`POST /api/rewards/{id}/redeem` with `{"requestId": "<8 to 64 chars>"}`.
The app creates the request id once per redemption attempt and keeps it until the server answers, so a double tap or a retry after a lost response redeems once.
The server answers 201 for a new redemption and 200 with the same redemption for a repeat.
It refuses with 403 when the treat belongs to the other person, 409 `insufficient_gems` when the owner's balance is short, and 409 `reward_state` when the treat is not approved.
It runs under the same advisory lock as claims, so a balance is read and spent with nothing in between.
The partner gets a push, "Nick redeemed Monster energy drink", which follows the Reward switch.
Undo is not offered; remove or reprice the treat instead.

## API

`GET /api/rewards` keeps its old fields, with shared rewards only in `rewards`.
It adds `treats` (open treats of both people), `treatHistory` (newest 100 redemptions of both), and `balances` (per person: `userId`, `name`, `earned`, `paid`, `balance`).
Every reward carries `ownerId` and `ownerName`, null and empty for a shared one.
For a treat, `progress` and `ready` are measured against the owner's balance instead of the bank.
`POST /api/rewards` takes `"treat": true` to propose a treat for the caller.
A person keeps at most 30 open treats.

## App

v20 folds the two halves into one Rewards section on Us, because two lists, two add buttons and two histories were more than the idea needed.
In the app a treat is a "solo" reward and a shared one is "shared"; the API keeps its names.

- One balances card: your gems, your partner's and the shared bank.
- The shared focus reward keeps its card with the bar and "We did it".
- One list holds everything else: shared rewards waiting their turn, my solo rewards (Redeem once my own gems cover one, otherwise how many gems to go), my partner's solo rewards read-only, and my proposals that wait or were declined, each marked Shared or Solo.
- One "Add a reward" sheet with a Shared or Solo switch at the top; Shared offers prices from the pair's pace, Solo does not.
- Answers my partner waits on stay in the approval card, worded "Nadia wants a solo reward: Latte for 300 gems".
- "Rewards earned" lists shared rewards reached or enjoyed and solo rewards redeemed by either person, newest first.
- Pushes say "Reward to approve" and "Reward redeemed".

## Not done

There is no suggested treat price, because the pace helper describes the pair's combined gems and no published research prices a treat.
There is no undo for a redemption.
