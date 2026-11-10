# v28 calorie range

A daily calorie range replaces "Log N meals" as the default food goal.

## Why

Counting meals rewards eating often rather than eating the right amount.
Someone who logs the whole day in one entry before bed got a third of the goal for all of it.
The calorie target the app already works out (Mifflin-St Jeor resting energy, activity, and the weight goal's pace) is the number that matters.

## The goal

- Title: "Eat 2,200 to 2,700 kcal", the range around the person's calorie target.
- The range is the target plus or minus a percentage, 10% by default, rounded to 50 kcal.
- The low end never sits below the least daily energy for the person's sex (1,500 kcal male, 1,200 kcal otherwise, Jensen 2014), the same floor the calorie target uses.
- No published figure sets the width, so the picker says it is the person's call and offers 5, 10, 15 and 20%.
- Losing, maintaining and gaining all use the same rule, because the target already carries the deficit or surplus.

## Scoring

- Under the range, progress is the calories so far toward the low end, like any other goal.
- Inside the range, the goal is done, whether it took one meal or five.
- Over the range, the goal earns nothing, so it can go from done back to not done later in the day; the range is a ceiling as well as a floor.
- The quest's template stores the percentage; a day's snapshot stores the range itself (low end as `target`, high end as `target_alt`, both kcal), so changing the calorie target applies from the next day like every other goal edit.
- With no calorie target set the goal stays out of the day, since there is nothing to measure against.

## Meals logged

- It stays available in Goals, off by default for new people.
- Migration 0042 puts the range in its place for existing people, on when meals logged was on and they have a calorie target, and moves meals logged last and off.
- Days already snapshotted keep their goals, so the change shows from the next day.
