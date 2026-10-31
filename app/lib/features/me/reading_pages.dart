import 'dart:math' as math;

/// The reading rates the server derives the pages goal from (score.PagesForMinutes), mirrored so
/// the goal picker can follow the minutes as they are typed. Brysbaert 2019 for the silent
/// reading rate, a typesetting convention for the page.
const kReadingWpm = 238;
const kWordsPerPage = 250;

/// The pages that take [minutes] of silent reading, never below one.
int pagesForMinutes(int minutes) =>
    math.max(1, (minutes * kReadingWpm + kWordsPerPage ~/ 2) ~/ kWordsPerPage);
