import 'package:flutter/material.dart';

import '../../api/models.dart';
import '../../util/format.dart';
import '../../widgets/quest_copy.dart';

/// "+1,200", "-300" or "Same" for a week-on-week change.
String signedChange(num delta, {String unit = ''}) {
  if (delta == 0) return 'Same';
  return '${delta > 0 ? '+' : '-'}${delta.abs().formatted}${unit.isEmpty ? '' : ' $unit'}';
}

/// One line for the Today card: the couple's points and how they moved. It reads the same for a
/// good week and a slow one, because the recap is a mirror, not a grade.
String recapHeadline(Recap recap) {
  final now = recap.pair.thisWeek.points;
  final before = recap.pair.previous.points;
  final points = '${now.formatted} ${now == 1 ? 'point' : 'points'}';
  final base = recap.complete
      ? 'Together you earned $points.'
      : 'Together you have $points so far.';
  if (before == 0 || now == before) return base;
  final diff = (now - before).abs().formatted;
  return '$base That is $diff ${now > before ? 'more' : 'fewer'} than the week before.';
}

/// "Oct 19 - Oct 25" for the recap's week.
String recapRange(Recap recap, String Function(String date) day) =>
    '${day(recap.from)} to ${day(recap.to)}';

/// True when nothing was recorded, so there is no week to read or compare against.
bool statsEmpty(RecapStats s) =>
    s.points == 0 &&
    s.countedDays == 0 &&
    s.steps == 0 &&
    s.sleepNights == 0 &&
    s.workouts == 0 &&
    s.readingMinutes == 0;

/// How the couple's points moved, for the headline card: "120 more than the week before", "Same
/// as the week before", or null when there is no earlier week to compare with. A week that is
/// still running shows last week's total instead, because a partial week is not comparable.
String? recapDelta(Recap recap) {
  final now = recap.pair.thisWeek.points;
  final before = recap.pair.previous.points;
  if (before == 0) return null;
  if (!recap.complete) return 'Last week ${before.formatted}';
  if (now == before) return 'Same as the week before';
  final diff = (now - before).abs().formatted;
  return '$diff ${now > before ? 'more' : 'fewer'} than the week before';
}

/// How a number moved against the week before. [direction] is -1, 0 or 1, and [change] always
/// carries its own sign, so a screen never has to rely on colour or an arrow alone.
class RecapRow {
  const RecapRow({
    required this.label,
    required this.icon,
    required this.value,
    required this.change,
    required this.direction,
  });

  final String label;
  final IconData icon;
  final String value;
  final String? change;
  final int direction;
}

/// The rows that moved up on the week before: what went well, said as numbers.
List<RecapRow> recapGains(Iterable<RecapRow> rows) => [
  for (final r in rows)
    if (r.direction > 0 && r.change != null) r,
];

RecapRow _row(
  String label,
  IconData icon,
  String value,
  num now,
  num before, {
  String unit = '',
  bool show = true,
  bool complete = true,
}) {
  final delta = now - before;
  final compared = show && complete;
  return RecapRow(
    label: label,
    icon: icon,
    value: value,
    change: compared ? signedChange(delta, unit: unit) : null,
    direction: !compared || delta == 0 ? 0 : (delta > 0 ? 1 : -1),
  );
}

/// The week's numbers for a person or the pair, in the order the recap lists them. A week that
/// is [complete] is compared with the one before; one still running shows its numbers only,
/// because a partial week set against a whole one would always read as a slump.
/// An empty [before] (a first week, or a person who joined mid-week) is never compared, so no
/// row reads as a jump from zero. The [pair] leaves out counted days, a per-person count that
/// adds up to a number nobody earned.
List<RecapRow> recapRows(
  RecapStats now,
  RecapStats before, {
  bool complete = true,
  bool pair = false,
}) {
  final compare = !statsEmpty(before);
  final hasSleep = now.sleepNights > 0;
  final compareSleep = compare && hasSleep && before.sleepNights > 0;
  return [
    _row(
      'Points',
      Icons.diamond_rounded,
      now.points.formatted,
      now.points,
      before.points,
      show: compare,
      complete: complete,
    ),
    if (!pair)
      _row(
        'Counted days',
        Icons.local_fire_department_rounded,
        '${now.countedDays}',
        now.countedDays,
        before.countedDays,
        show: compare,
        complete: complete,
      ),
    _row(
      'Steps',
      Icons.directions_walk_rounded,
      now.steps.formatted,
      now.steps,
      before.steps,
      show: compare,
      complete: complete,
    ),
    _row(
      'Sleep a night',
      Icons.bedtime_rounded,
      hasSleep ? durationLabel(now.sleepAvgMin) : 'No data',
      now.sleepAvgMin,
      before.sleepAvgMin,
      unit: 'min',
      show: compareSleep,
      complete: complete,
    ),
    _row(
      'Workouts',
      Icons.fitness_center_rounded,
      '${now.workouts}',
      now.workouts,
      before.workouts,
      show: compare,
      complete: complete,
    ),
    _row(
      'Reading',
      Icons.menu_book_rounded,
      '${now.readingMinutes.formatted} min',
      now.readingMinutes,
      before.readingMinutes,
      unit: 'min',
      show: compare,
      complete: complete,
    ),
  ];
}
