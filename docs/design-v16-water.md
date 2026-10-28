# New Me v16: the water quest

Earlier design documents still hold unless a section below changes them.

## Why

Drinking enough is one of the cheapest daily habits to track, and Apple Health already holds the data for people who log water there.
The quest gives the pair a shared, low-effort daily target next to protein and sleep.
It follows the project rule that every number comes from the person's data or published research.

## Target

- The target comes from published guidance, not from body weight.
- The National Academies Dietary Reference Intakes for water (IOM 2004, report 2005) set an Adequate Intake of total water of 3.7 L a day for men and 2.7 L a day for women aged 19 and over.
- About 81% of total water comes from drinking water and other beverages, and the rest from food.
- The quest counts drinks, so the target is 81% of the total: 3000 ml for sex "male" and 2200 ml for "female".
- With no sex set the target is 2200 ml, the lower figure, and the Targets page says that setting sex in About you personalizes it.
- EFSA (2010) also fixes the figure by sex, at 2.5 L (men) and 2.0 L (women) of total water.
- The Academies report that needs rise with activity and in heat.
- The Targets page says so in its source note, and no formula adjusts for it, because no published rule turns activity or weather into a number.
- Both citations live in `server/internal/targets/sources.go` as `nasem2005` and `efsa2010`.
- The pure function is `targets.ComputeWater` in `server/internal/targets/water.go`.
- The Targets page lists Water as a target that can be used like steps and sleep, and using it sets the quest target from the next day.

## The quest

- Key `water`, unit `ml`, 50 points like protein, on by default for new people.
- Migration `0025_v16_water.sql` adds the key to the quest checks, allows a target of 250 to 6000 ml with no second target, and adds the quest enabled at the end of every existing person's order.
- The backfilled target is computed in SQL from the person's sex: 3000 for male, 2200 otherwise.
- Days already in progress keep the quests they started with, like any other template change.

## Sources and the max rule

- Water comes from two places: Apple Health, already synced as the `water_ml` metric, and drinks logged in the app as the activity type `water_ml`.
- The day's progress is the larger of the Health amount and the sum of what was logged, never the two added together.
- Both sources describe the same water, so someone who records a drink in both places must not count it twice.
- The cost is that a person who logs part of their water by hand and part in Health sees the larger source only.
- The quest is part of the day, and so counts toward the day's maximum, once either source has data: Health has synced water on or before the day, or a drink was logged that day.
- This follows the existing Health-fed pattern for exercise, so someone who never shares water and never logs it is not scored against a number they cannot produce.

## Logging

- Log water is an entry in the log sheet with quick-add chips that save at once, and a typed amount with a stepper for anything else.
- Metric chips are 250 ml and 500 ml, imperial chips are 8 fl oz and 16 fl oz, and the typed amount is in ml or fl oz to match.
- Every entry is stored in ml, from 1 to 5000 per entry, and the app asks first above 2 L in one go.
- The log is an ordinary activity log, so it can be undone from the snackbar and deleted from the day's entries, which show the amount in the person's units.
- The quest card on Today has the same + button as the other hand-logged quests and opens this form.

## Units

- Metric shows litres with one decimal: "Drink 3.0 L" and "1.2 of 3.0 L".
- Imperial shows US fluid ounces rounded, at 29.5735 ml each: "Drink 101 fl oz" and "41 of 101 fl oz".
- The same units apply to the log form, the day's entries, the Targets page, and the daily goal picker.
- The server's coach and plan text always says litres, because it does not know the person's units.
