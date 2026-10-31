import 'dart:math' as math;

/// The reading quest's round rule, mirrored from the server (score.PagesForMinutes) so the goal
/// picker can follow the minutes as they are typed: a page for each minute of reading.
const kPagesPerReadingMinute = 1;

/// An audiobook minute counts as half a reading minute.
const kListeningMinutesPerReadingMinute = 2;

/// The pages that match [minutes] of reading, never below one.
int pagesForMinutes(int minutes) => math.max(1, minutes * kPagesPerReadingMinute);
