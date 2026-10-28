import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import 'time_format.dart';

final _whole = NumberFormat('#,##0', 'en_US');
final _tenths = NumberFormat('#,##0.#', 'en_US');

extension FormattedNumber on num {
  /// 1850 as "1,850" and 82.5 as "82.5"; whole numbers never get a decimal.
  String get formatted => (this % 1 == 0 ? _whole : _tenths).format(this);
}

/// "Oct 28": one date format for the whole app, written US style.
String dayShort(String date) => DateFormat('MMM d', 'en_US').format(parseLocalDate(date));

/// "Wed, Oct 28".
String dayWithWeekday(String date) =>
    DateFormat('EEE, MMM d', 'en_US').format(parseLocalDate(date));

/// "Wednesday, Oct 28".
String dayLong(String date) => DateFormat('EEEE, MMM d', 'en_US').format(parseLocalDate(date));

/// "11:00 PM": a time of day, given as minutes after midnight, the way the rest of the app writes it.
String timeOfDayLabel(int minutes) => formatMinutesOfDay(minutes);

/// "just now", "5m ago", "3h ago" or "2d ago"; a time in the future reads as "just now".
String relativeTime(DateTime then, DateTime now) {
  final elapsed = now.difference(then);
  if (elapsed.inMinutes < 1) return 'just now';
  if (elapsed.inHours < 1) return '${elapsed.inMinutes}m ago';
  if (elapsed.inDays < 1) return '${elapsed.inHours}h ago';
  return '${elapsed.inDays}d ago';
}

/// The server numbers the first, unscored stretch "Season 0"; people see it as the warm-up it is.
String seasonLabel(String name) => name == 'Season 0' ? 'Preseason' : name;

/// "just now", "3 min ago", "2 h ago" or "2 d ago", for lines that have room to spell it out.
String agoLabel(DateTime then, DateTime now) {
  final elapsed = now.difference(then);
  if (elapsed.inMinutes < 1) return 'just now';
  if (elapsed.inHours < 1) return '${elapsed.inMinutes} min ago';
  if (elapsed.inDays < 1) return '${elapsed.inHours} h ago';
  return '${elapsed.inDays} d ago';
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

/// Shows a typed pairing code the way the server prints it: upper case in groups of four.
class InviteCodeFormatter extends TextInputFormatter {
  const InviteCodeFormatter();

  static const _length = 16;

  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    final symbols = newValue.text.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
    final kept = symbols.length > _length ? symbols.substring(0, _length) : symbols;
    final grouped = [
      for (var i = 0; i < kept.length; i += 4)
        kept.substring(i, i + 4 > kept.length ? kept.length : i + 4),
    ].join('-');
    return TextEditingValue(
      text: grouped,
      selection: TextSelection.collapsed(offset: grouped.length),
    );
  }
}
