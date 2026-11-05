# v22 partner check-ins (plan)

Two new partner pushes that tell one of you when the other might need a hand: after a short night, and at the middle of a slow day.
Plan only, nothing built yet.

## The two pushes

### Rough night

- Fires once the sleeper's night lands (HealthKit sync or a manual sleep log), not before the partner's first notification of the day.
- Triggers on under 6 hours asleep, or 90 minutes or more under the sleeper's own sleep goal, whichever is stricter for them.
- 6 hours is the line below which the AASM/SRS consensus (Watson et al. 2015) ties sleep to worse mood, focus and health; 7 hours is the recommended floor, so 6 is clearly short, not just a bit under.
- Words carry the figure and an offer, never a judgement: "Nadia slept 5h 20m last night. Maybe an easy one today."
- Naps and in-bed time do not count, only asleep minutes, the same figure the sleep goal already scores.

### Slow day at the midpoint

- The midpoint is halfway between the person's first notification and their bedtime from their own schedule, so a late riser is not judged at noon.
- Triggers when the day has not counted yet and the day's gems are under half of an even pace at that minute (under 25% of the streak line at the exact midpoint).
- Skipped on rest days, away days, and when the person already counted.
- Words: "Nadia is at 40 of 270 gems so far. A message or a walk together could help."
- No "behind", "missed" or "failing" anywhere, checked by together.WordsOK like the other partner pushes.

## Who controls it

- The person being described decides whether it is shared: a new switch in their notification settings, "Let Nadia know on rough days", off by default, because sleep is health data about them.
- The person receiving it can mute it with the existing partner nudges switch.
- Both pushes respect quiet hours and away days through together.Service.Held, like every other push.

## Budget and order

- Today a person gets at most one partner nudge a day (together.PartnerBudget), shared by cover, cheer and challenge.
- Check-ins get their own budget of one a day, so a morning rough-night push never uses up the evening cheer.
- If both check-ins qualify the same day, the rough night wins and the midpoint push is skipped: one "they might need you" message a day is enough.
- Claims go through the existing partner claim table with new kinds (partner_sleep, partner_midpoint) so a retry or two server ticks never send twice.

## Server

- nudge.DecidePartnerCheckIn: a pure function with its own unit tests, taking the sleeper's asleep minutes and goal, the day's gems, streak line, schedule and now.
- The midpoint check rides the existing nudge scheduler tick; the rough-night check runs when sleep is written, then holds until the partner's day has started.
- One migration adds notify_share_checkins (the subject's switch) to users.
- Push kinds are added to together kinds so the app can open Us when one is tapped.

## App

- Settings: the new switch under Notifications, with one line on what it shares.
- Tapping either push opens Us, where the partner's day already is.

## Not in this

- No push about weight, food or mood.
- No second midpoint reminder later in the day, and nothing to the person themselves (they already get their own nudges).
