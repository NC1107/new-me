# v19: plain goal reasons, a natural produce title, and fruit and vegetables inside meals

Reported on the quest sheet:

- "Why this goal" on Get stronger was confusing.
  It showed "3 sets x 9 reps, 75% (the middle of 70 to 80%) of your latest max of 12 push-ups, a derivation from reps-in-reserve guidance rather than a published constant", then "Your goal is 30 reps, which is your own pick", then a citation.
  Nothing said that 3 x 9 = 27 was the recommendation and 30 was the person's own number, and the formula sentence was jargon.
- "Eat 5 a day" is not a sentence.
- Logging a meal with vegetables did not move the fruit and vegetables quest.

## Why this goal

The section is built by `questWhy` in `app/lib/features/today/quest_why.dart` from the quest and its target in `GET /api/targets`.
It reads top to bottom in this order:

1. The recommendation as a number in the quest's own unit, for example "Recommended: 27 push-ups a day, 3 sets of 9".
2. One plain line on where the figure comes from, the target's `why`, for example "About three quarters of your best set of 12, so each set ends with some reps left in the tank."
3. How the person's own goal compares, in plain words: "Your goal is 30 push-ups, a little above the recommendation.", "the same as the recommendation", "below the recommendation".
   "A little" means within 20% of the recommendation.
4. The citation, "Source: Zourdos et al., J Strength Cond Res 2016".
5. "How this is worked out", collapsed by default, with the target's precise `formula` behind it.

Each quest key words its recommendation in its own unit:

| Quest | Recommendation line |
| --- | --- |
| steps | Recommended: 7,000 steps a day |
| pushups | Recommended: 27 push-ups a day, 3 sets of 9 (the chosen daily-reps exercise names the reps) |
| sleep | Recommended: 7 h 30 min of sleep a night |
| exercise | Recommended: 22 min a day (the WHO weekly figure spread over seven days) |
| water | Recommended: 2.7 L (91 fl oz) of drinks a day |
| protein | Recommended: 165 g of protein a day |
| produce | Recommended: 5 servings of fruit and veg a day (400 g) |
| breathing | Recommended: 5 min of breathing a day |

Quests with no published figure (reading, meals logged, yoga) say "No published research sets a number for this, so your goal of 3 meals is your own pick."
The steady bedtime says that steady times matter but no research gives a cut-off, and cites Phillips et al. 2017.
When the server cannot work a figure out yet (push-ups before a max test, protein before a weight), the section shows the server's sentence that says what is missing, with no recommendation line.
The exercise quest now reads the daily `exercise` target; before, it read the weekly `activity` target, whose unit never matched the quest.

On the server, `why` and `cite` now exist for push-ups, and the `why` lines for steps, water and fruit and vegetables lost their jargon ("adequate intake").
The push-ups `formula` drops "a derivation from reps-in-reserve guidance" and says the number is worked out from research on stopping a set with reps left in reserve, which the research does not publish itself.
Every number in these lines is the same number as before and keeps its source in `server/internal/targets/sources.go`.

## The produce title

The quest card and sheet title is "Eat fruit and veg", and the progress line is "0 of 5 servings".
The server's name for the quest stays "Fruit and vegetables" (the plan and the coach use it as a noun).

## Fruit and vegetables inside meals

### What a meal carries

A meal log stores only totals: name, kcal, protein, carbs, fat, fiber.
The items of a meal exist while it is being built: the estimate endpoint returns them, and food search returns library foods and database candidates.
So the produce of a meal is worked out where the items are known and sent with the log.

### Where the data comes from

A meal item counts only when its data says it is produce:

- USDA foods carry a food category.
  `server/internal/estimate/produce.go` maps USDA's own category names to a kind: fruit, vegetable, juice or pulse.
  Foundation and SR Legacy file produce under "Fruits and Fruit Juices" and "Vegetables and Vegetable Products".
  FNDDS (what people report eating) has finer categories such as "Citrus fruits", "Tomatoes", "Citrus juice" and "Beans, peas, legumes".
  A category that is not in the table counts for nothing, so a gap undercounts instead of guessing.
- The two SR Legacy and Foundation groups contain juice and potatoes, with no finer category.
  USDA's description always starts with the food, so a head that is juice, a smoothie or a nectar is a juice, and a head of potatoes, cassava, yams or plantains does not count (NHS 5 A Day).
  This is the one place the description is read, and it reads USDA's controlled wording, not the person's words.
- Branded USDA foods and Open Food Facts products never count, because their categories are the manufacturer's shelf and not the food.
- A saved library food keeps the kind its database gave it (`foods.produce_kind`), so logging it again still counts.
- For a food no database knew, the Claude estimator is asked for two more fields, `produceKind` and `produceG`, from the food's composition: the grams of the amount that are fruit, vegetables, juice or pulses, and 0 for potatoes and for dishes where produce is a minor part.
  These grams are an estimate.
  The sheet says so, and a saved food does not keep an estimated kind.

### Counting rule

- A database item counts its whole weight in grams.
  An estimated item counts Claude's produce grams.
- A meal stores three sums: `produce_g` (fruit and vegetables), `juice_g` and `pulse_g`.
- For a day, whole produce adds up without limit, while juice and pulses each add at most 80 g, one serving.
  The counted grams are divided by the 80 g serving of NHS 5 A Day (`targets.ProduceServingGrams`) and rounded down, so half a serving in two meals makes one.
  This is `targets.ServingsFromMeals`.
- The day's servings are the servings from meals plus the servings logged by hand, capped at 30 like the goal itself (`targets.ProduceServingsToday`).
- Potatoes do not count anywhere on this path.
  Sweet potatoes do count when the database classes them as a vegetable, as NHS says.

### Wire and storage

- Migration `0031_v19_meal_produce.sql` adds `meal_logs.produce_g`, `juice_g`, `pulse_g` (0 to 10,000, default 0) and `foods.produce_kind`.
- `POST /api/logs` for a meal takes optional `produceG`, `juiceG` and `pulseG`.
  They come back on the log and on `GET /api/meals/recent`, so a repeated meal still counts.
- `GET /api/foods` and the barcode and search candidates send `produceKind`.
  `POST /api/foods` accepts it.
- `POST /api/meals/estimate` items send `produceKind` and `produceGrams`.
- Editing a meal does not change its produce.
- `quests[].detail` of the produce quest sends `fromMeals` and `logged`.

### In the app

- `MealItem` holds a kind and the produce grams of one unit, so stepping the amount up or down scales them.
- The log sheet sums the items into the meal's `MealProduce` when it logs one meal, and sends each item's own when it logs them separately.
- The quest sheet shows "2 from meals, 1 you logged", a short note on how meals are counted, and lists the meals that have produce in them.
- Meals typed in the manual form, photo estimates and meals logged before v19 have no produce, and the sheet does not pretend they do.

## Limits

- The FNDDS category names in the table come from What We Eat in America and were not all checked against the live API in this change, because the shared demo key was rate limited.
  A wrong name only means that food does not count.
- Dried fruit is counted by its weight, but NHS counts 30 g of dried fruit as a portion, so it is undercounted.
- Mixed dishes such as stews count only when Claude estimated them, and then by its estimate.
