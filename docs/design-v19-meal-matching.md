# v19: meal descriptions that use saved foods and USDA's own amounts

## Why

Nick and Nadia found estimates that felt high or ignored foods they had already saved.
Production data from 2026-10-31 showed four causes:

- "Dave's Killer Bread" was saved with the brand as its name, and the name match stripped the brand from both sides, left nothing to compare and missed it, so the next meal picked a different USDA bread and saved a second copy.
- "2 pieces of buttered toast" sized the butter at USDA's "Quantity not specified" weight (14 g, a tablespoon) for each piece, about 200 kcal, because the per-slice amount USDA lists for spreads was filtered out as a survey coding aid.
- "Slice" with no size took the first slice measure with the fewest extra words, which was the 9 g snack-size slice.
- Plain "toast" matched "Bread, egg, toasted", because USDA's own not-specified row ("Bread, NS as to major flour, toasted") was only tried after every named kind failed.

## Changes

- The split step sees the household's saved foods (id, name, brand, serving; the 80 most used) and may set `savedFoodId` when the person's words name or plainly mean one.
  The server only accepts an id that is in the list it sent, and then uses the saved food's own numbers.
  Name matching stays as the second check.
- A saved food named after its brand matches when the brand is in the description.
- `Guideline amount per slice of bread/roll` is kept as a portion, because it is the amount the USDA dietary survey codes for a spread when no amount was reported.
  The other guideline amounts and "Quantity not specified" stay filtered from the portion list.
- The split step gives a spread or topping on bread with no amount the unit "slice of bread", one per slice or piece.
  A food with no per-slice portion (cream cheese) falls back to the survey's "Quantity not specified" weight, as a plain serving does.
- When the person names no size, a measure FNDDS calls "medium" or "regular" wins over smaller or larger ones.
- The survey's not-specified rows for the food's lead word join the candidate list on every generic lookup, so a description without a kind lands on the unspecified row.
  This costs one more USDA search per new food, cached for an hour like the others.

## Results against the live APIs on 2026-10-31

| Description | Before | After |
| --- | --- | --- |
| 2 slices of white toast | 53 kcal | 147 kcal |
| 2 pieces of buttered toast | toast plus 2 tablespoons of butter (about 200 kcal of butter) | 147 + 104 = 251 kcal |
| toast with peanut butter | estimated | 73 + 96 = 169 kcal, both USDA |
| 2 slices of daves bread toasted and 2 fried eggs | a different USDA bread | the saved bread (180) and saved fried eggs (204) |

"Egg, whole, fried" in FNDDS already includes the cooking fat, about 102 kcal an egg, so butter logged for frying counts that fat twice.

## Tests

- `server/internal/estimate/v19_meal_matching_test.go`: the brand-named saved food, the split step seeing the list and its pick being used, an unknown id being ignored, slice and spread portions, and the spread fallback.
- `server/internal/estimate/live_saved_test.go` (build tag `live`): the descriptions above against the real Claude and USDA APIs, run by hand.
