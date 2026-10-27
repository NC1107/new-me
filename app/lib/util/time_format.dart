import 'package:intl/intl.dart';

/// Whether this phone shows times on a 24-hour clock. The app shell copies it from the device
/// setting, because the formatters below are called from places without a BuildContext.
bool use24HourClock = false;

final _clock24 = DateFormat('HH:mm');
final _clock12 = DateFormat('h:mm a');

/// "20:00" or "8:00 PM", the way the person's phone writes it.
String formatClock(DateTime time) => (use24HourClock ? _clock24 : _clock12).format(time);

/// The same for minutes after midnight.
String formatMinutesOfDay(int minutes) =>
    formatClock(DateTime(2000, 1, 1, (minutes ~/ 60) % 24, minutes % 60));
