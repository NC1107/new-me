import '../api/models.dart';

/// Whether [at] falls in the person's quiet hours: from bedtime until the first notification
/// of the day (wake plus the offset). A bedtime after midnight leaves only the morning part,
/// matching the server, which ends that window at midnight.
bool inQuietHours(DateTime at, Schedule schedule) {
  final times = schedule.timesFor(at.weekday);
  final minute = at.hour * 60 + at.minute;
  if (minute < times.wake + schedule.firstNotificationOffsetMin) return true;
  return times.bed >= times.wake && minute >= times.bed;
}
