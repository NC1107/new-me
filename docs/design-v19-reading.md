# v19: reading pages and audiobook minutes

## Why

The reading quest has a minutes target and an alternative pages target.
The pages target was a fixed 15, an arbitrary default, and 15 pages is not much reading next to 30 minutes.
Audiobook listening counted one for one as reading time, although a narrator speaks more slowly than an adult reads.
This change derives the pages figure from the minutes and gives audiobook time a fixed exchange rate.

## The rule in use

The first version below converted by words (238 words a minute, 250 a page, narration at 155).
Nick and Nadia chose a round rule instead, shipped with migration 0037:

- A page for each minute of reading, so 30 minutes is 30 pages.
- An audiobook minute counts as half a reading minute, so 30 pages is 60 minutes of audiobook.

The research below is why the rule is close to honest: 238/250 is 0.95 pages a minute, and narration is about two thirds of reading speed, which the rule rounds down to a half.
The app says plainly that the rule is their choice and quotes the research beside it.
The sections that follow record the research and the first version's reasoning; where they give 0.95 pages or two thirds, the rule above replaced them.

## Research

### Silent reading rate

Brysbaert, M. (2019).
How many words do we read per minute? A review and meta-analysis of reading rate.
Journal of Memory and Language, 109, 104047.
doi:10.1016/j.jml.2019.104047.
A meta-analysis of 190 studies and 18,573 participants found an average adult silent reading rate in English of 238 words a minute for non-fiction and 260 for fiction, and 183 for reading aloud.
The author argues the often quoted 300 words a minute is unrealistic for most people.
The fiction and non-fiction gap is explained by word length.
The studies kept were of reading for fun or comprehension, and of people under 60.

Decision: use 238.
It is the conservative figure, it does not assume the person reads fiction, and the person's own book is not known.

### Audiobook narration rate

ACX (Audible's Audiobook Creation Exchange) production guidance is widely reported as about 9,300 words per finished hour, which is about 155 words a minute.
Findaway Voices is reported to use 9,000.
This is an industry rule of thumb used to budget narration, not a peer reviewed study.
The original ACX page could not be retrieved while writing this, so the figure is cited as repeated by narrators and producers, and the source note in the app says it is not a study.
Brysbaert's reading aloud rate of 183 words a minute is for participants reading aloud in studies, not for audiobook narration, so it is not used.

Decision: use 155.

### Words per printed page

No published measurement of the average words per page of printed books was found.
The 250 words a page figure is the typed manuscript convention, and trade paperbacks are commonly quoted between about 250 and 300.
One author survey, described in too little detail to check, reports 233 for non-fiction and 280 for fiction.
Real pages vary with trim size, type size and margins.

Decision: use 250, say plainly in the app that it is a convention and not a measured average, and state the range of about 230 to 300.
Choosing 250 over 300 errs towards more pages for the same time, so the pages way to finish the quest asks for no less reading than the minutes do.

## The formulas

These were the first version's formulas, replaced by the rule above; the code lives in `server/internal/score/points.go`.

- Pages for minutes: `round(minutes x 238 / 250)`, never below 1.
  20 minutes is 19 pages, 30 is 29, 45 is 43, 60 is 57.
  A silent reading minute is worth 238/250, about 0.95 pages.
- A listened minute is worth 155/238 of a reading minute, about 0.65, which is 155/250, about 0.62 pages.
  60 minutes of audiobook is 9,300 words, which is 39 minutes of silent reading.
  The credit rounds down so a fraction never earns a minute.

The quest score is unchanged: `p = min(1, minutes / targetMinutes + pages / targetPages)`, where minutes are typed minutes plus the listening credit.

## Audiobook minutes: one for one or by words

One for one is simple and generous.
It treats an hour of narration as an hour of reading.
Because a narrator speaks about 155 words a minute against the 238 an adult reads, it credits about 50 percent more words than were heard, and the pages and minutes ways to finish the quest would stop meaning the same amount of reading.

By words is honest.
The quest then measures reading in one currency, words, whichever way it was done.
It costs the listener: 30 minutes of audiobook now earns 19 reading minutes, so a 30 minute goal needs about 46 minutes of listening.
Listening at faster playback is not seen, because Audiobookshelf reports time listened and not words heard, so a person at 1.5 times speed is under credited.
The tradeoff is accepted and the copy says it.

Decision at first: convert by words.
Replaced by the half rule, which keeps the same direction (listening counts less than reading) with a number anyone can check.

## Pages follow the minutes

`quest_templates.target_alt_custom` (migration 0033) records whether the person typed their own pages figure.
Until they do, the pages target is `pages for minutes` and is recomputed whenever the minutes change, in the same patch.
The rule on the server needs no new API field.
When a patch sets `targetAlt`, the template is custom if the figure differs from the derived one, and follows again if it equals it.
Applying the new `reading` target in Me > Targets sets the derived figure and so goes back to following.

New users start at 20 minutes and 20 pages.
Migration 0037 moves every template that follows the minutes to a page a minute; a typed pages figure stays.

## Old data

- `day_quests` rows keep the targets they were snapshotted with, so past days and open days keep their 15 pages and their score.
  A day already scored is not rescored, and the listening credit applies from the first scoring after the release.
- The migration changes only the standing template.
  A reading template still on the old fixed 15 is marked as following and moved to the derived figure, so a 30 minute goal becomes 29 pages.
  Any other pages figure was typed by the person, is marked custom and is left alone.
  A person who had typed exactly 15 on purpose cannot be told apart from the old default.

## Copy

- Quest sheet, Why this goal: "Recommended: 30 pages for your 30 minutes", then "A page for each minute of reading, so 30 minutes is 30 pages, or 60 minutes of audiobook." and the audiobook note.
- Goal picker, under the pages field: "30 pages: a page for each minute, or 60 minutes of audiobook. It follows the minutes unless you type your own."
- Me > Targets, Habits: a "Reading, in pages" target labelled as a convention, with sources `brysbaert2019` and `pagewords`.
- Audiobookshelf page: "Listening counts toward reading at half: an hour of audiobook is 30 minutes of reading."
- Onboarding: "An audiobook minute counts as half a reading minute once you link Audiobookshelf in Me."
- Today plan line: "An audiobook minute counts as half."

## Tests

- `score`: pages for minutes table and monotonic range, listening credit, the quest basis with the credit.
- `engine`: a quest frozen at 15 pages still scores, and the credit is applied.
- `api`: pages follow, custom survives, derived figure re-follows, apply, the target with its details and sources, the Today card with listening, the migration backfill.
- `app`: the picker follows the minutes and says why, the quest sheet shows the formula, note and sources.
