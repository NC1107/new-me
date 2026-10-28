# New Me v13: shared rewards, mobility, training history, barcodes, and reliability

Earlier design documents still hold unless a section below changes them.

## Why

Nick's brief for the night of 2026-10-28: focus on Training, Together, and polish and reliability; add barcode scanning; gems become shared rewards. Claude may be used more, but every number must come from the person's data and published research; creative use only where no figure depends on it.

## Shared rewards priced in gems

- Gems stay what they are: the points earned each day. The pair's gem bank is all gems both have earned minus gems spent on claimed rewards.
- Rewards are a wishlist. Either partner proposes a reward with a name and a price; the other approves or declines, like habit gem proposals, and gets one push. The proposer can edit or withdraw a pending reward; after approval either can cancel it, and price changes are proposed again.
- One approved reward is the focus, shown as the bar on Us; the others wait in the list. A reward is ready when the bank covers its price, with one push to both. Claiming it spends the price once, in one transaction, so the bank never goes negative.
- The price helper suggests prices from the pair's own median combined daily gems over the last 14 days times 7, 14 or 30 days ("about 2 weeks at your pace"). No invented numbers.
- Reward screens say gems, not points. `/board` keeps its `reward` field (the focus reward) for older builds.

## Weekly challenges and gentle nudges

- New challenge kinds, all measured from stored data: sleep nights at target, days meals were logged, protein days, push-up reps, yoga minutes, habit marks, active days. Each person's share is 110% of their own last-two-week weekly average, capped at 125% of their best recent week, with day-count kinds capped at 7 minus away days; a kind needs 7 days of history for both people to be eligible.
- The week's kind is picked from eligible kinds, never one used in the last two weeks, favouring the area the pair has done least against their own targets, ties broken by a hash of the week. The reason is stored.
- An unfinished challenge closes as missed at week end, with no penalty, so recaps can mention it.
- Every push except safety-relevant ones respects quiet hours (before wake plus offset or after bedtime) and away days, through one helper in the notify path.
- Gentle partner nudges, at most one a day per person on a separate budget: a cover chance when the partner missed yesterday and you hold a freeze; a cheer prompt when the partner finished a hard quest; reward progress at 50%, 90% and ready; a Thursday challenge check-in for the person under their share. Wording never reports the partner's failure, carries only computed figures, has no emoji, and stays under 90 characters; Claude may vary the wording through the same guard as the plan summary.
- Notification settings gain separate switches for partner nudges, cover, approvals and the partner-counted push, plus quiet hours shown from the schedule. A failed push enqueue releases its claim so it can retry, and shutdown drains the queue.

## Mobility sessions

- Catalog exercises gain a kind: strength or stretch. About a dozen beginner stretches covering the major muscle-tendon groups come from free-exercise-db (Unlicense) with steps and photos, matched by hand as in v12.
- "Mobility 10" is a guided routine: 8 to 10 stretches, 60 seconds per stretch (Garber et al., ACSM position stand, Med Sci Sports Exerc 2011;43:1334), done as two 30-second holds, per side where needed, about 10 to 12 minutes. The order is New Me's own sequence, not from a trial, and the app says so. The ACSM guide is at least two days a week.
- The session runs on a timer with lead-in, auto-advance, skip, haptics and VoiceOver announcements, and on finish logs its minutes to the yoga quest.

## Training history and strength progress

- `GET /api/training/history?month=YYYY-MM` returns, per day, sets logged, whether the session was completed, yoga and mobility minutes, and workout types. The Train tab gains a month calendar: a filled dot for a completed session, a hollow dot for sets without one, a second dot for yoga or mobility; tapping a day lists what was done.
- `GET /api/exercises/{key}/history` returns per-day bests. The chart shows estimated one-rep max for loaded sets of 1 to 10 reps (Epley, labelled an estimate, with person-to-person variation per Nuzzo et al., Sports Med 2024;54:303), volume load for loaded sets above 10 reps, best reps for bodyweight exercises, and best seconds for holds. Max tests are marked. Under two points it shows an empty state.

## Barcode scanning

- The log sheet and My foods gain Scan. The camera opens only while scanning; a barcode looks up Open Food Facts through the server (`GET /api/foods/barcode/{code}`), filling the food with its photo and source, or says it was not found and offers to search or enter it by hand.

## Reliability

- Companion: the Watch and widgets decode `goalPercent` from action responses, show it capped for small gauges, hide the old streak tick, keep a clientOpId per pending Watch save, and read dates in the profile time zone.
- App state: refreshes carry a generation so an older response never overwrites a newer one; habit marks apply only the newest answer and always settle their pending count; the log sheet always leaves busy; resume refreshes Today before slower syncs and follows a changed device time zone; companion snapshots never mix users.
- Server: the plan summary is polished in the background, not inside GET /today; milestone recording leaves the read path.
- The Health history import backs off and resumes on 429 instead of showing the raw error.
- The weekly recap's points are checked against the board for the same week.

## Polish

- Page headers and pinned action bars never overlap content; pinned bars get an opaque background and the scroll area clears them.
- One switch, one segmented control, one date format, US spelling, and 44-point hit areas everywhere.
- Me gets its title and grouped rows; Reminders joins Notifications.
- The signed-in person is listed first everywhere, partners are told apart by name not only colour, and the cheer sheet shows what was sent.
- Progress shows one note while data is sparse instead of the same empty lines on every card.

## Decisions made while building

- Pushes that fall in quiet hours or an away day wait in `held_pushes` and go out at the next allowed minute, collapsed if repeated and dropped after a day or if their switch is turned off meanwhile; claim-based pushes are simply retried later.
- The partner-nudge budget counts only partner nudges (cover, cheer, challenge, reward progress), never the partner-counted push.
- An approved reward whose price is changed keeps its approved price; withdrawing or declining the change restores it.
- Last night's sleep is the night record wherever it exists (Today, Us, quests, readiness and Insights read the same number).
- Stretches never enter strength plans or weekly sets; the exercise library lists strength exercises and Mobility holds the stretches.
- The HRV evidence behind easier sessions comes from endurance training, and a strength trial found no gain (Bittencourt et al., Front Physiol 2024;15:1472702), so the eased session is framed as a cautious default.
