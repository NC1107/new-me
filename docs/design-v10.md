# New Me v10: habits that count, units, a gentler setup, and Health history

Earlier design documents still hold unless a section below changes them.

## Why

Nick's feedback after v0.9.0:

- Habits did not count toward the daily goal; he wants each habit to have a relative worth, set when it is created.
- Setup asked for calories and protein numbers that most people do not know; it should start from what people know and work the numbers out.
- Americans think in pounds, feet and inches, so units must be chosen at the start of sign-up.
- Nadia saw a 404 on the birth-year screen and Health connect looked like it timed out.
- There was no way to bring in Health history or to ask for Health access again.

## The 404

- Nadia signed up while v0.9.0 was being deployed; Watchtower stopped the old container at 19:18:41 and started the new one at 19:18:42.
- In that gap Traefik answers a plain-text 404, which the app showed as a raw error.
- Fix: a 404, 502, 503 or 504 without the server's JSON error envelope means "New Me is updating" and is treated like being offline, and idempotent requests (GET, PUT, PATCH, DELETE) retry once after 1.5 seconds.

## Habits count toward the day

- Each habit has a worth: Just track (0), Small (10), Medium (25) or Big (50) points; quests are worth 50 or 100.
- A habit due on a day adds its worth to the day's possible points and the share it completed (slots done over slots, or count over target, capped at 1) to the day's points, so habits count toward the 70% line like quests.
- The flat 5 bonus points per habit slot is replaced by this; finalized days keep what they were finalized with.
- Existing habits become Medium; the worth is chosen when a habit is created and can be changed later.

## Units

- `users.units` is `metric` or `imperial`, chosen right after the name at sign-up and changeable in Profile; the default follows the phone's region (United States, Liberia and Myanmar default to imperial).
- The server stores everything metric; the app converts for display and input: weight in lb, height in feet and inches, loads in lb, the weight goal pace in lb a week.
- Server-written text (target formulas, goal reasons, progress summaries, training reasons) shows the person's units, keeping the metric value where a formula is defined in metric (Mifflin-St Jeor is defined in kg and cm).
- Weight-goal paces: the server accepts a losing pace from 0.2 to 0.5 kg a week and a gaining pace from 0.05 to 1 kg a week, so the imperial choices (lose 0.5 or 1 lb, gain 0.25, 0.5 or 1 lb) store exactly.
- Training load steps for imperial people are 5 lb for dumbbells and a barbell (two 2.5 lb plates), the common US increments; metric steps are unchanged.

## Setup starts from what people know

The new-profile path is: name, colour, units, Apple Health, about you (birth year, sex, height, weight, weight goal), schedule, what to work on, your daily targets, reminders.

- Apple Health comes before "about you" so a height and weight it shares are already filled in; connecting asks for access and moves on at once, with the sync running in the background.
- The separate screens asking for a step, meal, protein and calorie number are gone.
- "Your daily targets" lists a target for each chosen focus, worked out by the v8 formulas from the answers (calories, protein, steps, sleep, activity), each with one line saying where it comes from and a minus and plus to adjust it.
- A target the formulas cannot give yet (push-ups before a max test, reading, meals) starts from a stated convention and says so.
- "Use these" saves the quests and food targets in one step; the Targets page in Me keeps the full formulas and sources.

## Get stronger is not push-ups only

- Since v9 the strength quest is completed by a planned training session, a Health strength workout of 20 minutes or more, or the push-up count; the app now says so.
- The quest reads "Get stronger" with "A strength workout, a training session, or 30 push-ups" beneath it, and the push-up count is the fallback, not the requirement.
- Choosing "Get stronger" at sign-up asks for no number; the push-up fallback starts at the v8 convention and a training plan can be set up later from Me.

## A shorter setup

- About you is one screen (birth year, sex, height, weight) plus one for the weight goal, instead of five.
- The per-focus number screens are replaced by the single targets review.
- New-profile screens drop from about seventeen to ten: name, colour, units, Apple Health, about you, weight goal, schedule, focus, daily targets, reminders.

## Health history and access

- Apple Health only shows its permission sheet once for each kind of data, so the Apple Health page offers "Ask again", which shows the sheet for anything not yet decided, and explains the Settings path (Settings, Health, Data Access and Devices, New Me) for anything already turned off.
- After connecting, and from a button on the Apple Health page, the app imports every day Apple Health holds, up to ten years, in the background, paced to the server's limits.
- `PUT /api/health/history` stores readings for days before yesterday, up to ten years back, only where no reading exists, and never rescores a day, so history fills insights and look-backs without changing any score.

## Reinstalling

- The session token is in the iOS Keychain, which survives deleting the app, so a reinstall signs straight back in.
- If it ever does not, "I have been here before" with an invite code picks the existing profile; all data lives on the server.
