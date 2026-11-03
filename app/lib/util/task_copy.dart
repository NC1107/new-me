import 'package:intl/intl.dart';

import 'format.dart';

/// "overdue", "due today", "due tomorrow", "due Tue" within the week, else "due Nov 12". [daysLeft]
/// comes from the server, counted on the assignee's calendar, so a phone in another zone agrees.
String dueLabel(int daysLeft, String deadline) {
  if (daysLeft < 0) return 'overdue';
  if (daysLeft == 0) return 'due today';
  if (daysLeft == 1) return 'due tomorrow';
  final date = parseLocalDate(deadline);
  if (daysLeft < 7) return 'due ${DateFormat('EEE', 'en_US').format(date)}';
  return 'due ${dayShort(deadline)}';
}

/// The wire form of a calendar date, "2026-11-03".
String isoDate(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-'
    '${date.day.toString().padLeft(2, '0')}';
