# New Me v8: research-backed targets

Earlier design documents still hold unless a section below changes them.

## Why and the rule

Nick asked for recommendations for calories, macros, sleep, push-ups and workouts.
His rule: every target comes from published formulas, ratios and guidelines, never from numbers tuned to his own data or invented heuristics.
A person's measurements (weight, height, age, sex, steps) are only inputs to those formulas.
Each target in the app shows its formula in one sentence and a source line; the Targets page has one line saying this is general guidance, not medical advice.
Citations were gathered on 2026-10-27; DOIs must be checked before they are shown in the app.

## Inputs

- Weight: latest reading from Apple Health (the smoothed trend from v7 when available).
- Height: Apple Health `HEIGHT`, or entered once in Profile.
- Age: birth year.
- Sex: asked once in Profile; needed by the resting energy equation and the fiber and calorie-floor tables.
- Goal: lose, maintain or gain, with a pace; default maintain.
- Activity band: the 14-day average step count.

Missing inputs are listed on the Targets page with a one-tap way to add them; nothing is guessed.

## Energy

- **Resting energy:** Mifflin-St Jeor: 10 x kg + 6.25 x cm - 5 x age + 5 (male) or - 161 (female).
  Most accurate predictive equation in a systematic review: within 10% of measured RMR in about 82% of non-obese and 70% of obese adults (Frankenfield, Roth-Yousey, Compher, J Am Diet Assoc 2005;105:775; Mifflin et al., Am J Clin Nutr 1990;51:241).
- **Maintenance:** resting energy x physical activity level (PAL).
  PAL bands from FAO/WHO/UNU 2004 (Human Energy Requirements): sedentary or light 1.40 to 1.69, active 1.70 to 1.99, vigorous 2.00 to 2.40.
  The band is chosen from steps using the Tudor-Locke and Bassett step categories (under 7,500 a day: 1.4; 7,500 to 9,999: 1.55; 10,000 to 12,499: 1.7; 12,500 or more: 1.85); the mapping of step bands to PAL values is our convention within the FAO ranges and is labelled as such.
  Wearable active calories are not used: Apple Watch energy expenditure errors of roughly 28 to 43% are reported and no published correction exists (Shcherbina et al., J Pers Med 2017;7:3; Germini et al., J Med Internet Res 2022;24:e30791).
- **Estimated from your logs:** after at least 14 days with 10 or more days of logged intake and 8 or more weigh-ins, maintenance is also estimated by energy balance, intake minus the change in body energy stores (Racette et al., Obesity 2012;20:2404), using 7,700 kcal per kg over a 2 to 4 week window only (Hall et al., Lancet 2011;378:826).
  It is shown next to the formula value, labelled "estimated from your logs", with a note that logged intake is commonly under-reported (Lichtman et al., NEJM 1992;327:1893); the formula value stays the default.
- **Target:** maintenance minus the pace x 7,700 / 7 to lose, plus to gain, rounded to 50 kcal.
  Paces offered: lose 0.25 or 0.5 kg a week, never more than 1% of body weight a week (Helms et al., Int J Sport Nutr Exerc Metab 2014;24:127; Jensen et al., AHA/ACC/TOS guideline, Circulation 2014;129:S102); gain up to 0.5% of body weight a week (Helms 2014).
- **Floor:** never below the larger of resting energy and 1,200 kcal (women) or 1,500 kcal (men) (Jensen 2014).

## Macros

- **Protein:** 1.6 g/kg to maintain, 1.8 g/kg to gain, 2.0 g/kg to lose, rounded to 5 g.
  Inside the ISSN range of 1.4 to 2.0 g/kg (Jäger et al., J Int Soc Sports Nutr 2017;14:20), with 1.6 g/kg the estimated plateau for gains with resistance training (Morton et al., Br J Sports Med 2018;52:376) and higher intakes supported during a deficit (Helms 2014; Longland et al., Am J Clin Nutr 2016;103:738).
  With BMI of 30 or more, the target is capped at 2.2 g/kg of the weight at BMI 25 for the person's height, following common practice of using an adjusted weight (Morton 2018 upper confidence bound; labelled as expert practice).
  Per meal: about 0.4 g/kg across 4 meals (Schoenfeld and Aragon, J Int Soc Sports Nutr 2018;15:10), shown as a tip.
- **Fat:** 28% of target energy, never below 20% (IOM DRI 2005 range 20 to 35%; Thomas et al., ACSM/AND/DC joint position, Med Sci Sports Exerc 2016;48:543), with saturated fat under 10% of energy (Dietary Guidelines for Americans 2020 to 2025; WHO 2023).
- **Carbohydrate:** the remaining energy at 4 kcal/g, never below 130 g a day (IOM DRI 2005 RDA); when the remainder would fall below 130 g, fat is lowered toward its 20% floor first.
  The ACSM sport ranges (3 to 5 g/kg for light activity, 5 to 7 g/kg for about an hour a day) are shown as context (Thomas 2016).
- **Fiber:** 14 g per 1,000 kcal (IOM DRI 2005; DGA), shown with the age and sex adequate intake (men 38 g, women 25 g at 19 to 50; 30 g and 21 g at 51 and over); benefit observed at 25 to 29 g a day (Reynolds et al., Lancet 2019;393:434).

## Sleep

- **Duration:** at least 7 hours (Watson et al., AASM and SRS consensus, Sleep 2015;38:843); 7 to 9 hours recommended for ages 18 to 64 (Hirshkowitz et al., NSF, Sleep Health 2015;1:40).
  Default target 7 h 30 within that range; the person can choose any value from 7 to 9 hours.
- **Bedtime:** wake time minus the target minus 15 minutes, the upper bound of normal sleep onset latency for adults (Ohayon et al., NSF sleep quality consensus, Sleep Health 2017;3:6).
- **Regularity:** the Sleep Regularity Index from the sleep records (Phillips et al., Sci Rep 2017;7:3216); higher regularity is associated with lower all-cause mortality independent of duration (Windred et al., Sleep 2024;47:zsad253).
  Shown as a score with the advice to keep sleep and wake times regular; no invented threshold.
- **Shortfall:** the 7-night shortfall against the target is shown as information only; no recovery promise, because catch-up sleep has weak evidence (Depner et al., Curr Biol 2019).

## Activity

- **Weekly:** 150 to 300 minutes of moderate or 75 to 150 minutes of vigorous activity, plus muscle-strengthening on 2 or more days (WHO 2020, Bull et al., Br J Sports Med 2020;54:1451; US Physical Activity Guidelines 2018, Piercy et al., JAMA 2018;320:2020).
  Insights show this week against the guideline, counting workout minutes (vigorous types counted double) and strength sessions.
- **Steps:** default 7,000 a day (Ding et al., Lancet Public Health 2025;10:e668; inflection around 5,000 to 7,000); the v4 age bands remain the suggestion when the person is already above 7,000 (Paluch et al., Lancet Public Health 2022;7:e219).
  Increases are offered in steps of 1,000 (v4).

## Push-ups

- Each push-up log entry is a set; the person can record a max test (one set to near failure) from the push-up sheet, suggested every 2 to 4 weeks.
- **Daily target:** 3 sets at about 70 to 80% of the latest max (leaving 2 to 3 reps in reserve), derived from reps-in-reserve guidance (Zourdos et al., J Strength Cond Res 2016) and the hypertrophy evidence that sets taken near failure are effective (Schoenfeld et al., J Sports Sci 2017;35:1073); labelled as a derivation, not a published constant.
- **Progression:** increase by 5% (at least 1 rep per set) when every set of the target was completed with 1 to 2 reps to spare on 5 of the last 7 days (ACSM position stand on progression, Med Sci Sports Exerc 2009;41:687: 2 to 10%).
- No acute-to-chronic workload ratio rules (Impellizzeri et al., Int J Sports Physiol Perform 2020;15:907).

## Water

- No water target; the EFSA 2010 adequate intakes (2.0 L for women, 2.5 L for men of total water, including food) are shown as a population reference only, and drinking to thirst is the guidance in most settings (Sawka et al., ACSM, Med Sci Sports Exerc 2007;39:377).

## Where it shows

- **Me > Targets:** every target with the recommendation, the current value, its one-sentence formula and source, and "Use this"; "Use all" applies them through the existing goal and target endpoints.
- **Today:** the food card shows what is left of each macro.
- **Monday goal proposals (v6):** include a target whose formula value changed because an input changed (for example weight or step band), never because of tuning.

## Server

- `GET /api/targets`: the inputs and which are missing, and for each target its value, the current setting, the formula text and the source keys.
- `PATCH /api/me` gains `heightCm`, `sex` and `goal {kind, paceKgPerWeek}`; `POST /api/targets/apply` with the keys to apply; `POST /api/pushups/max` records a max test.
- Pure functions with table tests reproducing worked examples from the cited sources where they give them.

## Server decisions

Implemented in `server/` (migrations 0011 and 0012, package `internal/targets`); endpoint shapes are in `docs/design.md` (Endpoints, v8 additions).
Where this document left a choice open, the server does the following.

### Inputs

- Weight is the v7 smoothed trend (rounded to 0.1 kg), so one heavy morning does not move a target.
- Height is the profile value, else the newest Health `height_cm` on or before today; the input says which one it used.
- Age is the calendar year minus the birth year, as in v4.
- The activity band needs at least 5 days with steps in the 14 complete days before today (today is unfinished); fewer is a missing input.
- Nothing is guessed: with an input missing the dependent targets have a null value, a `missing` list and a formula sentence that says what is needed.
  Maintenance therefore needs steps, and every food target needs maintenance.
- The goal defaults to maintain.
  Lose is 0.25 or 0.5 kg a week; gain is a multiple of 0.05 up to 1 at the API, and the 0.5% of body weight cap (rounded to 0.05) is applied when the target is computed, because the weight changes after the goal is chosen.
  A lose pace is likewise limited to 1% of body weight.
  A capped pace is named in the formula sentence.

### Labels

- `guideline`: resting energy, protein, fat, saturated fat, carbohydrate, fiber, sleep, activity and steps, which rest directly on a cited formula, ratio or guideline.
- `convention`: maintenance, because the PAL value inside each FAO/WHO/UNU range is ours; the formula sentence says "our convention".
- `derivation`: calories (maintenance moved by a published energy density, so it inherits the convention), the estimate from logs, and push-ups.
- The BMI 30 protein cap is called expert practice in its sentence, as in the text above.
- Water has no target and is not in the response.
- The citations are worded as in this document and carry no DOIs, which still have to be checked before the app shows them.

### Energy and macros

- Calories are rounded to the nearest 50 kcal.
  The floor is the larger of resting energy and 1,200 (women) or 1,500 (men), rounded up to 50 so the rounded floor is never below resting energy.
- The estimate from logs looks at weigh-ins and logged days in the 28 days up to today.
  It needs a span of at least 14 days between the first and last weigh-in, 8 weigh-ins, and 10 days with logged intake between them (today excluded).
  The body-energy change is the v7 smoothed weight at the last weigh-in minus the one at the first, times 7,700 kcal per kg, over the span in days.
  Average intake is over the days with logged intake.
  It is shown beside maintenance and never replaces it.
- Protein per kg is applied to the smoothed weight and rounded to 5 g.
  The BMI 30 cap needs a height; without one no cap is applied and `details.capNote` says so.
  The per-meal tip is 0.4 g/kg rounded to a gram.
- Fat is 28% of the calorie target.
  When carbohydrate would fall under 130 g, fat is lowered to leave 130 g, but never under 20%; if carbohydrate is still under 130 g it is set to the floor and the macros add up to a little more than the calories (the sentence says so).
  Fat is rounded to a gram and carbohydrate is the rounded remainder, so the macros add up to the calorie target within 3 kcal whenever the floor does not apply.
- Saturated fat is a maximum of 10% of calories, in grams.
- Fiber is 14 g per 1,000 kcal of the calorie target, rounded to a gram, with the age and sex adequate intake in `details` and the sentence (none under 19).

### Sleep

- The recommended value is always the 7 h 30 default (450 minutes); `current` is the person's quest target and `details.rangeMin` and `rangeMax` are 420 and 540.
- Bedtime is the schedule's wake time minus the target minus 15 minutes, for workdays and days off, modulo midnight.
- The 7-night shortfall is the net total: nights with sleep in the last 7 days, target times that count minus the minutes slept, never below 0.
  It is information only and has no recovery advice.
- The Sleep Regularity Index follows Phillips 2017: the share of minutes that are in the same state (asleep or awake) 24 hours apart, scaled to -100..100, so a perfectly regular schedule is 100.
  `sleep_nights` holds one sleep episode per night and the app defines a night as 18:00 the day before to 12:00, so only those 1,080 minutes of two consecutive recorded nights are compared; the afternoon is not observed and is not assumed awake.
  Asleep means between `bed_at` and `wake_at`, at minute resolution, compared by wall-clock time so a daylight saving change does not shift one night against the next.
  It uses the last 14 days and needs 5 nights with sleep and at least one pair of consecutive nights; otherwise the score is null and `missing` says what is lacking.

### Activity and steps

- Activity reports the v7 WHO 2020 week against 150 to 300 minutes and 2 strength days; the value is the 150 minute minimum.
  It cannot be applied: turning a weekly total into a daily exercise quest would need a conversion the sources do not give.
- Steps are 7,000 unless the 14-day median is above 7,000 (and at least 5 days exist), in which case the v4 age band suggestion is the target.
  Increases are offered in steps of 1,000, as in v4.

### Push-ups

- The daily target is 3 sets, and the quest target (total reps) is 3 times the reps per set.
- Reps per set are 75% of the latest max, the middle of the 70 to 80% range, rounded, at least 1; the range is in `details.rangePerSet`.
  The latest max is the test on the newest date.
- Each push-up log entry is a set, as before.
  A day is complete when at least 3 entries have at least the current reps per set, where the current reps per set are the quest target divided by 3.
  The "1 to 2 reps to spare" condition cannot be observed from a log of reps and is not checked.
- Progression looks at the 7 complete days before today.
  With 5 or more complete days, reps per set rise by 5% (at least 1), and the target is never lower than the value from the max.
- Null until a max exists.

### Applying

- `POST /api/targets/apply` is all or nothing.
  Calories, protein, fat and carbs go to the profile targets, steps, sleep and push-ups to the quest templates; it does not change whether a quest is enabled.
  It is the `PATCH /api/me` code path, so open days are scored first and the change applies from tomorrow, except on the join day.
- Applying calories or protein also records the baseline described next.

### Monday proposals

- Calories (a profile target, offered only when the person has one) and protein get a formula baseline: the formula value and the inputs behind it, stored when the target is applied through `/api/targets/apply`, when a proposal is accepted or dismissed, and otherwise the first time the proposals are listed.
  Nothing is proposed before an input has moved.
- A proposal appears when the value moved by more than 5% (more than 100 kcal for calories) since the baseline, the target in force differs, and at least one input differs; the reason names the inputs that changed and carries the formula sentence.
- The protein rule of v7 (the target is 20% or more away from the formula) stays, now measured against the goal-aware protein formula.
- Dismissing a proposal makes the current formula value the new baseline, so it is not offered again until the value moves another 5%.

## Meal estimate and the food library

Nick's complaint: "an apple, a chomp meat stick, and a hotpocket" came back as one blended meal with numbers the model made up.
The fix is that AI only reads the sentence; the numbers come from real databases, and a food the household has already confirmed always has the same numbers.

### Pipeline for typed text

1. **Library fast path.** A single phrase (no comma, "and", "&", "+", "with") that exactly names a saved food, optionally with a leading amount ("2 apples"), is sized from the library with no Claude call.
2. **Parse.** Claude (same key and model, forced tool `split_meal`) only splits the text into items `{text, label, food, brand|null, quantity, unit, grams|null, kind: generic|branded}`.
   The prompt forbids giving nutrition and the tool schema has no nutrition fields.
   `grams` is only a weight the person stated.
3. **Look each item up**, at most three at a time, with a 5 second timeout per call and an in-memory cache of an hour (failed calls are never cached):
   1. The household library first: the name must match exactly or differ only by descriptor words (raw, medium, plain...), and the brand must agree on both sides.
      "apple pie" never matches a saved "Apple".
   2. Branded items: Open Food Facts `cgi/search.pl` (five results, User-Agent `NewMe/<version> (self-hosted)`), per-serving numbers when present, else per 100 g with the serving size; then USDA Branded.
   3. Generic items: USDA FoodData Central with Foundation and SR Legacy data.
      Energy comes from nutrient 1008, else the Atwater values 2047 and 2048, else kilojoules.
      Household measures come from the food's `foodPortions` (a detail call, cached), since search results do not carry them.
   4. Matching is a tested score: share of the item's name tokens found, share of the candidate's name that was asked for, a bonus when the first word agrees ("Rose-apples" is not "Apples"), and data type preference (Foundation and SR Legacy over Branded for generic foods).
      At least 60% of the name tokens must match and every brand word must match, so Jack Link's can never answer for Chomps.
   5. The unit is converted in this order: a weight unit, a household measure whose words contain the unit ("medium" in "medium (3" dia)"), the label's serving, the stated grams, the first household measure.
4. **Fallback.** An item no database accepts, or whose lookups all failed, gets a Claude estimate for that one item (`source: "estimated"`).
   If even that fails the item is returned at zero for the person to fill in; the request fails (502) only when the text cannot be split or no item could be sized.
5. **Scale and clamp.** Numbers are scaled to the quantity and clamped to the meal log bounds (kcal 0 to 10000, grams 0 to 5000). Nothing is stored.

### How accuracy is reported

- Every item carries `source`, the matched database name and id, and a confidence: `high` when the whole name matched and the unit converted exactly, `medium` when a word was missing or the unit was a guess, `low` otherwise.
- `databaseShare` is the percent of the meal's kcal from USDA, Open Food Facts or a saved food whose numbers began as one.
  The app shows it as "N% from nutrition databases" and recomputes it as amounts change.
- Source chips: "USDA", "Label" (Open Food Facts or typed from a label), "Saved" (library), "Estimated" (AI).

### The library

- Table `foods` (migration 0010), shared by the household: name, brand, serving text ("1 medium (182 g)"), serving grams, kcal and macros per serving, optional alternate servings (a label and a weight, converted through the weight), source, source id, creator, use count, last used.
  A database food is saved once (unique on source and source id), so saving twice returns the saved copy.
- Saving: foods from USDA or Open Food Facts are saved automatically when a meal using them is logged; estimated items are saved only when the person taps "Keep in My foods" on the row (an AI guess is not made permanent without asking).
  The app also records a use of every saved food that was logged, which ranks it in search.
- The meal sheet's "Search your foods" lists saved foods (most used first); "Search USDA and Open Food Facts" adds unsaved candidates below, on request only, because the shared demo key allows few calls.
- Me > My foods lists, edits (serving, nutrients, other servings) and deletes saved foods and adds a new one from a label.
- Items carry a numeric amount the person can step or type; numbers always scale from the per-unit values, so stepping up and down never drifts.
- "Log as one meal" logs the sum with the names joined; "Log separately" logs one meal per item, each with its own `clientOpId`, in order, stopping at the first failure and resuming without repeating the ones already saved.

### Configuration and limits

- `NEWME_USDA_API_KEY`; empty uses `DEMO_KEY`, which USDA currently limits to about 10 calls an hour per IP.
  A three-item meal costs up to six calls, so set a real key.
- Open Food Facts search is slow and sometimes answers 503; that item then falls back to USDA Branded and then to an estimate.
- The 20 estimates an hour per person limit still applies; one estimate may make several Claude calls (one split, plus one per unmatched item).

