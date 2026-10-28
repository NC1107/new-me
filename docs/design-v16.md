# New Me v16: the numbers match the food

Earlier design documents still hold unless a section below changes them.

## Why

Nick logged "2 scoops of Huel with 12 oz of whole milk" and got 1,317 kcal.
The milk had matched USDA's "Cheese, mozzarella, whole milk", so 12 oz of milk counted as 12 oz of cheese.
The Jimmy Dean sausage and Gala apple he had picked from search were gone, because describing the Huel replaced the list.
Checking 30 common foods against live USDA found the same kinds of faults: 8 fl oz of orange juice as 2.1 kg, an orange as orange peel, 2% milk as egg custard, and a sandwich with no amounts taking a cup of mayonnaise.

## Describing adds to the list

- "Describe it" adds its items below the ones already picked from search, so a food the databases lack can be described after the rest were found.

## Matching a food

- Generic lookups search USDA's FNDDS survey foods alongside Foundation and SR Legacy, in a separate query so the reference rows cannot crowd them out of one page.
- FNDDS describes foods as people report eating them, such as "Milk, whole", and takes its nutrients from Foundation and SR Legacy foods or recipes built on them (FNDDS 2021-2023 documentation, "Nutrient values"), so it ranks equal to them.
- USDA generic descriptions lead with the food and add descriptors after commas.
  A candidate whose leading segment holds a word the person did not use is a different food and is rejected: "whole milk" is not "Cheese, mozzarella, whole milk", "avocado" is not "Avocado dressing", "mustard" is not "Mustard greens".
- FNDDS "NFS" and "NS as to ..." descriptors do not count as extra words, since they say the detail was not given (FNDDS documentation, "NFS and NS food codes"), so "almonds" is "Almonds, NFS".
- Stand-ins such as imitation or meatless foods rank below the real food unless asked for, as the food search already did.
- USDA's "(Includes foods for ...)" notes are dropped from names, while descriptors such as the "(2%)" in "Milk, reduced fat (2%)" stay.
- The food search box draws on the same FNDDS results, so typing "whole milk" shows milk.

## Amounts

- A volume converts through a portion of the food measured by volume alone, using the US customary units of NIST Handbook 44, Appendix C, so 8 fl oz of juice is the cup's weight.
  A note inside a portion label, as in "cup (8 fl oz)", no longer makes it answer for fl oz.
- A volume with no volume portion is estimated instead of taking the first measure, which may be a quart.
- Portion labels are read with the same unit spellings as the item, so "tbsp" meets "tablespoon".
- "1 whole" or "1 each" uses the measure FNDDS names after the item ("banana", "egg") or "fruit".
- An item with no amount uses the FNDDS "Quantity not specified" weight, the amount a dietary survey records when someone names a food without one, at medium confidence.
  A food without that weight or a label serving is estimated instead of taking its first measure.
- The split step writes a drink's ounces as fl oz.

## Open Food Facts limits

- Open Food Facts allows 10 searches and 15 product reads per minute per IP address and answers 503, or bans the address, beyond that (API documentation, "Rate limits").
- The server now holds itself to those numbers over any sliding minute and skips Open Food Facts for a call past them, which the search and the estimate already treat as no answer.
- Search-a-licious, the newer full-text search, was not adopted: its index has no serving sizes or photos.

## Production data

- The saved foods "Whole Milk", "Sour Cream", "Colby Jack Cheese", "Mayonnaise" and "Mustard" were corrected to the rows and amounts the new lookup chooses.
- "Egg Bites" (a McDonald's biscuit) and "Egg Sandwich" (a meatball sub) had no correct match and were removed from My foods.
- Nick's Huel meal and Nadia's sandwich of 2026-10-28 were recomputed from the corrected items.

## Habit approvals say what the habit is

- A proposal now carries the whole habit, and the card on Us shows its icon, the gems and minutes asked for, what it is worth now when it already counts, and its days and reminder times.
- The push names the days too, such as "Nadia wants Check litter worth 30 gems (10 min), every day".

## The partner's day

- GET /api/partner/today scores the partner's own local today and returns their quests, day, streak and habits, without their food, health or plan.
- Only quests that are part of their day are listed, so a Health-fed quest they have not connected never reads as missed.
- The sheet behind the partner's card on Us lists each quest and habit with how far along it is, in the viewer's units.
- This shows what each person has done, which both people asked to see; it still never shows the other person's targets page or lets one person change the other's data.

## Water in onboarding

- "Drink enough water" is a focus of its own, and its daily goal starts from the person's National Academies figure, in their units.
- The About you review applies the water target with the others.

## USDA results get a category icon

- USDA publishes no food photos, and of 12 branded USDA barcodes checked against Open Food Facts only one had a photo, so borrowing photos by barcode would spend the shared Open Food Facts read budget for little.
- USDA's food category ("Sausages, Hotdogs & Brats", "Fruits and Fruit Juices", "Coffee") now travels with each USDA candidate, and the app draws it as a Material food icon in the photo's place.
- Words match at the start of a word, in a fixed order, so "Fruit & Vegetable Juice" is a drink and "veggie" never reads as egg; a category without a fitting icon keeps the plain food icon.
- USDA serving text drops the package count ("1.96 OZ SERVING, About 82 Servings Per Container" reads "1.96 oz serving (55 g)"), "100 GRAM (100 g)" reads "100 g", and a shouted brand at the start of a name gets normal capitals.

## Health import

- Workout minutes for a day are the time workouts cover within that day, not their summed lengths, so overlapping recordings count once and an overnight or forgotten workout cannot put more than a day on one date, which the server rejected along with the rest of that day.

## Matching measured against a corpus

- `TestLiveCorpus` (run by hand with `-tags live`) holds 46 everyday foods, worded as the split step words them, each with the USDA row it must land on and a believable calorie range; every matching change is checked against it.
- Rows that lead with a class ("Fish, salmon, baked", "Soft drink, cola", "Potato, french fries") count when their second part is the food the person led with; a restaurant's name ("APPLEBEE'S, french fries") is not a class.
- When no row names the food with the person's descriptors ("coffee, black", "oatmeal, cooked"), the FNDDS not-further-specified food for its name is used at low confidence.
- "Non-dairy" and "non-alcoholic" foods rank as stand-ins, below the food they stand in for.
- Of several measures with the item's unit, the one whose other words the person used wins ("cup, shredded" for shredded cheddar, 28 g a quarter cup instead of the melted cup's 61 g), then the plainest.
- Among the top five rows, one that converts the unit exactly beats a better named one that can only guess; one whole item or the FNDDS unspecified amount counts as a standard answer, not a guess.
- A size USDA does not list takes one whole item, or the first measure only when that is itself a size, so "1 medium" french fries is never a single fry.
- Plurals ending in "-oes" and "-ies" meet their singulars ("Tomatoes" and "tomato").
- Still estimated today: steamed broccoli, 93/7 ground beef, cheese pizza by the slice and protein shakes, which no row names closely enough.
