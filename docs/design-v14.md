# New Me v14: closing the v13 gaps

Earlier design documents still hold unless a section below changes them.

## Why

After v13, Nick asked to close the known gaps and keep going.
The gaps were a generic food search that ranked "Chicken spread" first, no way to train on a rest day, and a few audit items.

## Food search: the survey default first

- A bare food name such as "chicken" or "milk" now shows the USDA survey default first, named "Chicken, any kind".
- The default is the FNDDS food whose every descriptor is "NFS" (not further specified) or "NS as to ..." (not specified), such as "Milk, NFS" or "Chicken, NS as to part and cooking method, NS as to skin eaten".
- FNDDS 2021-2023 documentation, section "NFS and NS food codes": these are the codes chosen when a survey participant cannot give details, and their nutrients and portion weights come from how often each kind is reported in What We Eat in America, from food supply statistics and from industry publications.
  That makes them the best published answer to a name with no detail, and no ranking rule of ours decides it.
- A default that names a preparation ("Potato, boiled, NFS") is not promoted, because the person did not say how it was cooked.
- When no such default exists (for example "eggs" or "chicken breast"), the ranking is unchanged.
- The default is found with one extra USDA call, `<words> AND (NFS OR NS)` over Survey (FNDDS), cached for an hour like the other searches.
- Survey foods now keep their household measures: FNDDS puts a numeric portion code in `modifier` and the wording in `disseminationText`, so the text is used, measures are ordered by USDA's `rank`, and the coding aids "Guideline amount per ..." and "Quantity not specified" are skipped.

## Food search: reliability

- USDA's GET `/foods/search` intermittently answered 400 from its proxy when the query or the "Survey (FNDDS)" data type carried parentheses, while the POST form of the same search answered every time.
  The client now posts the search as JSON.
- Open Food Facts names and brands in capitals are tidied like USDA ones ("Sportyfeel Spicy Chicken & 'Nduja Pizza").

## Training on a rest day

- The rest-day card on Train now says Train and opens a sheet of the plan's sessions, the next one first, with "Log single sets instead" below.
- Picking one calls `POST /training/today/pull {"dayIndex": n}`, which starts that plan day as today's session and opens it.
- The plan keeps that day on its own weekday as well; pulling a session forward does not move or skip it.
- Only a rest day can pull (409 `session_exists` on a training day, or when today already holds a different session); repeating the same pull returns the same session.
- `GET /training/today` on a rest day now returns a session pulled into it, with `restDay` still true.
- Nothing about training on an extra day is recommended or discouraged; it is the person's choice, so the sheet carries no advice.

## Polish

- The habit editor's minutes control reads "None" instead of "Track" for a habit with no minutes; VoiceOver reads "No minutes, only track".
- Exercise photos get the 2 px border every card has, so the photographs sit inside the app's outlined style.
  Drawn illustrations would need a licensed set, which the app does not have.
- The Mobility card uses the same tinted icon tile as the training card above it.
- The how-to sheet writes muscles in lower case inside its sentence ("Works chest").
