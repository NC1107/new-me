import 'package:intl/intl.dart';

final _whole = NumberFormat('#,##0', 'en_US');
final _tenths = NumberFormat('#,##0.#', 'en_US');

extension FormattedNumber on num {
  /// 1850 as "1,850" and 82.5 as "82.5"; whole numbers never get a decimal.
  String get formatted => (this % 1 == 0 ? _whole : _tenths).format(this);
}

/// "just now", "5m ago", "3h ago" or "2d ago"; a time in the future reads as "just now".
String relativeTime(DateTime then, DateTime now) {
  final elapsed = now.difference(then);
  if (elapsed.inMinutes < 1) return 'just now';
  if (elapsed.inHours < 1) return '${elapsed.inMinutes}m ago';
  if (elapsed.inDays < 1) return '${elapsed.inHours}h ago';
  return '${elapsed.inDays}d ago';
}

/// Parses the server's 'YYYY-MM-DD' into a calendar date with no time zone attached.
DateTime parseLocalDate(String date) {
  final parts = date.split('-').map(int.parse).toList();
  return DateTime.utc(parts[0], parts[1], parts[2]);
}

String formatDateKey(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

String previousDate(String date) {
  final d = parseLocalDate(date);
  return formatDateKey(DateTime.utc(d.year, d.month, d.day - 1));
}

String weekdayShort(String date) => DateFormat.E().format(parseLocalDate(date));

/// "min" for "minutes", so a reading line stays short.
String shortUnit(String unit) => unit == 'minutes' ? 'min' : unit;
