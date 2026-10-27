# Beta review, October 2026

Six simulated testers reviewed the real screens (158 screenshots from v2 to v5) and the design documents up to v6: Nick, Nadia, a habit-mechanics product designer, a strength coach and dietitian, an iOS accessibility and UX specialist, and a skeptical low-motivation user.
Some testers judged older v2 screenshots, which mixed seeded people (Maya, Sam) and earlier colours; findings that only applied to those are left out.

## Where they agree

### 1. It still feels like homework

Every persona hit the same wall: after onboarding, Today asks for setup (Connect Health, add a habit) and manual entry (push-ups, reading, meals with eight fields) before giving anything back.
Nick: "the same babysitting I complained about, in a nicer coat."
The v6 autopilot work (auto-credit, readiness, plan, photo meals) is the right direction and should ship first; testers added saved meals and "same as yesterday", habits pre-seeded from the focus picks, and widgets so most days need no app launch.

### 2. The streak punishes real life

Two misses in a row reset everything; the weekly rest day expires every Sunday; there is no sick, travel or "I was away" mode; coming back after a break shows "Day 1" next to a partner's big number.
The product designer and the skeptic independently proposed the same fix: earned streak freezes (one per 7 counted days, keep up to 2), a 24-hour repair, a pause for illness or travel, a kind welcome-back screen, and a shared couple streak where one person can cover the other's miss.

### 3. Pass/fail framing and judgement

"0% of 100 points, reach 70% to keep your streak going" on a fresh morning reads as a test already failed; "No streak yet" appears twice on Us; weight, resting heart rate and "burned 287" sit on Today unasked.
Fixes: start-of-streak copy instead of threshold copy, hide weight and calories by default, never show eaten-versus-burned as a net number, celebrate behaviours rather than weight, and per-person control over what the partner sees.

### 4. Fairness between Nick and Nadia

Nadia's 03:00 workdays and horse work are invisible: reminder and habit defaults are evening and mid-shift for her, the midnight day boundary and the 10:00 grace are silent, barn work does not count, paper reading is manual while Nick's audiobooks are automatic, and the pooled weekly step challenge and side-by-side rings read as "Nadia is behind".
Fixes: ask wake time and work days once and drive every time-based default from it, day types (work, horse, rest, off) with their own goals, a three-button "barn work" log credited as exercise, one-tap paper reading, per-person challenge shares, and a personal-pace comparison on Us.

### 5. Notifications will be muted by day 4

Per-slot habit reminders on by default plus five v6 nudge kinds plus cheers adds up to five or more pushes a day.
Consensus: at most two pushes a day across all kinds, habit reminders opt-in per habit, nudges asked on day 3 rather than day 1, and never "you are behind" wording.

## Where they disagree

- **Auto-credit strictness.** Nick wants any strength workout to finish the strength quest; the coach says 15 minutes of anything tagged HIIT is free points.
  Resolution: 20 minutes or more of strength, or 15 minutes of HIIT with an average heart rate above the person's easy zone.
- **Adaptive goals.** Nick likes Monday proposals; the skeptic and the coach warn they ratchet up.
  Resolution: proposals may go up only after two good weeks, go down freely, and never touch calories.
- **Comparison.** Nick is competitive and wants a scoreboard recap; Nadia and the skeptic want comparison optional.
  Resolution: "together" first on Us, a per-person toggle to show the head-to-head, and the recap shows both but leads with the couple.

## Health soundness (coach)

- The counted-day rule can be met with no sleep and no protein; default the sleep and exercise quests on, or require one recovery item.
- Treat a readiness "take it easy" day as an automatic rest day, and never nudge exercise on it.
- Protein target per kilogram (1.4 to 2.0 g/kg from the latest weight) with a 7-day hit rate and an end-of-day protein-gap suggestion from the person's own meals.
- Sleep regularity (bed and wake time variation and a regularity index) rather than chasing hours; shift-aware sleep windows for Nadia.
- Weight and body composition shown only as a smoothed trend (kg per week), with a hide-weight switch.
- Training load: session load from duration and heart rate, acute versus chronic ratio, a deload proposal after rising load or three easy days.
- Safety copy: no calorie deficits, a neutral note on very low targets, a check-in card if intake is very low while exercise is high, one disclaimer line in Insights and onboarding.

## Long-term pull (product designer)

- Seasons of 6 to 8 weeks with a theme and a recap; Season 0 is better named "Preseason".
- A couple tier ladder with cosmetic unlocks (mascot outfits, accents, new challenge kinds).
- Milestones at 7, 14, 30, 50 and 100 days for each person and the couple, plus firsts (first 10k day, first week of good sleep).
- A small weekly mystery bonus quest for variety.
- The weekly challenge chosen together on Sunday from two options, without ratcheting on success.
- A year view for Nick: monthly snapshot cards of weight trend, body composition, VO2 max, best lifts and sleep.

## Screens and accessibility (UX specialist)

- Today order: top bar, greeting whose bubble carries the plan sentence, day card, one "right now" slot (readiness in the morning, goals on Monday, a cheer when one arrives), habits (due only), quests, food, one Body row opening Insights.
- Move the challenge, cheers and recap to Us with a tab badge; give Insights a top-bar entry on Today instead of a Me row.
- Habit pills: group multi-slot habits ("Brush teeth 1/2"), 44 pt, and a shape change for done and overdue, not colour alone.
- Slim the Us person cards (ring, percent, streak, week); unambiguous weekday labels in charts; a labelled 70% marker.
- Contrast of secondary grey text and pale chart bars; VoiceOver labels for rings, pills, cheers and charts with text summaries; reflow the Us cards to one column at large text sizes.
- Microcopy: "Hit 70% today to start your streak", "Start a streak today", "One more and you count today", "Sign out of this phone", locale time formats everywhere, "quests" for daily items and "goals" for settings.

## Privacy

- Plain consent before any meal photo is sent to Claude, and a "never send photos" switch.
- A sharing card per person: what the partner sees (weight and food never by default).
- Say what happens to history when signing out.

## Recommended next batch (v7, "kind and fair")

Ranked by how many testers it helps and how much it moves retention, after v6 ships:

1. Forgiveness: earned streak freezes, 24-hour repair, sick and away pause, welcome-back screen, shared couple streak with cover. (M)
2. Schedule and fairness: wake time and work days in onboarding driving every default, day types, barn work log, one-tap paper reading, per-person challenge shares. (M)
3. Notification budget: two pushes a day maximum, habit reminders opt-in, nudges offered on day 3, kinder wording. (S)
4. Today reorder and the "right now" slot; challenge and cheers to Us with a badge; habit pill grouping and 44 pt. (M)
5. Judgement-free defaults: start-a-streak copy, hide weight and calories by default, no net calories, behaviour celebrations, sharing controls, photo consent. (S to M)
6. Health soundness: sleep and exercise on by default, readiness-easy as rest, protein per kilogram with a gap suggestion, smoothed weight trend. (S to M)
7. Long-term pull: seasons of 6 to 8 weeks, milestones, couple tiers, Sunday challenge pick. (M)
8. Coaching depth: training load with deload, sleep regularity and shift windows, year snapshot cards. (M to L)

Tune the v6 work already in progress: raise the strength auto-credit bar, cap nudges per day, make adaptive goals one-directional upward only after two good weeks.
