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
    '${day(recap.from)} - ${day(recap.to)}';

/// How a number moved against the week before. [direction] is -1, 0 or 1, so a screen can add an
/// icon and never rely on colour alone.
class RecapRow {
  const RecapRow({
    required this.label,
    required this.icon,
    required this.value,
    required this.change,
    required this.direction,
    this.before,
  });

  final String label;
  final IconData icon;
  final String value;
  final String? change;
  final int direction;

  /// The week before, as words, for a week that is still running: its total so far is not
  /// comparable with a whole week, so the screen shows this instead of a change.
  final String? before;
}

RecapRow _row(
  String label,
  IconData icon,
  String value,
  num now,
  num before, {
  String unit = '',
  bool show = true,
  String? beforeText,
  bool complete = true,
}) {
  final delta = now - before;
  if (!complete) {
    return RecapRow(
      label: label,
      icon: icon,
      value: value,
      change: null,
      direction: 0,
      before: show ? (beforeText ?? before.formatted) : null,
    );
  }
  return RecapRow(
    label: label,
    icon: icon,
    value: value,
    change: show ? signedChange(delta, unit: unit) : null,
    direction: !show || delta == 0 ? 0 : (delta > 0 ? 1 : -1),
  );
}

/// The week's numbers for a person or the pair, in the order the recap lists them. A week that
/// is [complete] is compared with the one before; one still running shows that week's number.
List<RecapRow> recapRows(RecapStats now, RecapStats before, {bool complete = true}) {
  final hasSleep = now.sleepNights > 0;
  final compareSleep = hasSleep && before.sleepNights > 0;
  return [
    _row(
      'Points',
      Icons.diamond_rounded,
      now.points.formatted,
      now.points,
      before.points,
      complete: complete,
    ),
    _row(
      'Counted days',
      Icons.local_fire_department_rounded,
      '${now.countedDays}',
      now.countedDays,
      before.countedDays,
      complete: complete,
    ),
    _row(
      'Steps',
      Icons.directions_walk_rounded,
      now.steps.formatted,
      now.steps,
      before.steps,
      complete: complete,
    ),
    _row(
      'Sleep a night',
      Icons.bedtime_rounded,
      hasSleep ? durationLabel(now.sleepAvgMin) : 'None recorded',
      now.sleepAvgMin,
      before.sleepAvgMin,
      unit: 'min',
      show: compareSleep,
      beforeText: durationLabel(before.sleepAvgMin),
      complete: complete,
    ),
    _row(
      'Workouts',
      Icons.fitness_center_rounded,
      '${now.workouts}',
      now.workouts,
      before.workouts,
      complete: complete,
    ),
    _row(
      'Reading',
      Icons.menu_book_rounded,
      '${now.readingMinutes.formatted} min',
      now.readingMinutes,
      before.readingMinutes,
      unit: 'min',
      beforeText: '${before.readingMinutes.formatted} min',
      complete: complete,
    ),
  ];
}
