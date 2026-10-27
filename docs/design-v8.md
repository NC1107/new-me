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
