# New Me v18: personal goal recommendations and a clearer Targets page

Earlier design documents still hold unless a section below changes them.

## What was wrong

- Every daily goal picker offered four presets named Casual, Regular, Serious and Intense.
  For water, sleep or protein those names mean nothing, and the numbers behind them were not tied to the person or to research.
- The Targets page was one identical tall card per number, with an info button, "Use this" chips and a "Changes start tomorrow" note.
- "5 servings" of fruit and vegetables gave no hint of what a serving is.

## Goal pickers

- The tier names are gone everywhere.
- A picker leads with "Recommended for you": the personal figure from `GET /api/targets`, one plain line on where it comes from, and a short citation ("Source: National Academies 2005").
- Under it, "Other published figures" lists further numbers from the literature, each saying what it is (for example "EFSA: 2.5 L of total water for men, the drinks part").
- "Or type your own" stays for any other number.
- Goals with no research figure (reading, meals logged, yoga, the steady bedtime window) say so plainly and show plain numbers.
  The push-ups picker keeps plain numbers too; another change owns how push-ups are sized.
- Without a loaded recommendation (offline, or an input the server still needs) the picker says so and shows the plain numbers.

## One source of truth on the server

- Each goal target in `GET /api/targets` now carries `why` (one plain line), `cite` (short citation) and `alternatives` (`value` and `label`).
  They are built in `server/internal/api/targets_advice.go` and `server/internal/targets/advice.go`.
- Onboarding needs no new endpoint.
  By the daily goals step the profile answers (units, body, weight goal, schedule) are already saved, so `GET /api/targets` is computed from what onboarding collected.
  The app mirrors no formula.
- Alternatives and where they come from:
  - Water: EFSA 2010 total water (2.5 L men, 2.0 L women) times the 81% that comes from drinks, rounded to 100 ml.
  - Sleep: the 7 and 9 hour ends of the recommended range (Watson 2015, Hirshkowitz 2015).
  - Steps: the age band where the benefit levels off (Paluch 2022).
  - Protein: the RDA of 0.8 g/kg and the ISSN range of 1.4 to 2.0 g/kg (Jäger 2017), rounded to 5 g.
  - Fruit and vegetables: 800 g, where risk was still falling (Aune 2017).
  - Exercise: 300 minutes a week, the top of the WHO range, as daily minutes.

## Exercise minutes

- A new `exercise` target (unit min, applicable) is the WHO 2020 and US 2018 guideline of 150 minutes of moderate activity a week spread over seven days and rounded up: 22 minutes a day.
- Its text says the guideline is a weekly figure, so a rest day is fine as long as the week adds up.
- Applying it sets the exercise quest goal.
  The weekly `activity` target stays as the place to see this week's minutes.

## Fruit and vegetables

- Servings are shown with grams everywhere in the goal and target copy: "5 servings (400 g)".
- The picker, onboarding and the Targets sheet list what one 80 g serving looks like, from NHS 5 A Day: a medium apple, banana, pear or orange; 2 plums, kiwis or satsumas; 3 heaped tablespoons of cooked vegetables; a cereal bowl of salad.
  The server sends them as `details.servingExamples`.
- The logging pane is untouched.

## Targets page

- Four sections: Your body (resting energy and maintenance, estimates only), Food, Move and rest, Habits.
- One card per section with compact rows: the name, "Yours" and "Recommended" side by side, and a chevron.
  A row whose recommendation differs from the person's setting shows it in an accent pill; a matching setting shows a check.
- Tapping a row opens a sheet with both figures large, the plain reason, the formula, other published figures, sources and a "Use" button.
- "Use all recommended (n)" stays at the top, with "Changes apply today."
- At large text sizes the two columns stack under the name.
- The disclaimer stays under the title.

## Copy

- Daily goals and the Targets toast say changes apply today, matching the change that applies quest and target edits to the current day.
- Every Daily goals row opens its picker and has an on/off switch, whether the quest is on or off.

## Tests

- Server: `targets/advice_test.go`, `api/targets_advice_test.go`.
- App: `goal_picker_test.dart` (picker, advice mapping, onboarding goals), plus the updated Targets page, Me, onboarding and model tests.
