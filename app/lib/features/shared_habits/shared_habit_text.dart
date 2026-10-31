import '../../api/shared_habit_models.dart';
import '../../util/format.dart';
import '../habits/habits_page.dart';

/// "Every day", "Mon, Wed, Fri", "Every week" or "Every 3 days".
String sharedScheduleLabel(SharedSchedule s) => switch (s.kind) {
  SharedKind.daily => 'Every day',
  SharedKind.weekly => 'Every week',
  SharedKind.everyN => 'Every ${s.everyDays} days',
  _ => daysSummary(s.weekdays),
};

/// When it is next due, in my own days: "Overdue by 2 days", "Due today", "Due tomorrow".
String sharedDueLabel(SharedHabit h) {
  final n = h.daysFromToday;
  if (h.overdue) return 'Overdue by ${plural(-n, 'day', 'days')}';
  if (h.state == SharedState.today) return 'Due today';
  if (n == 1) return 'Due tomorrow';
  return 'Due in $n days';
}

/// "Nadia, 3 h ago", "You, 2 d ago" or "Not done yet".
String sharedLastLabel(SharedHabit h, int? myId, DateTime now) {
  final last = h.last;
  if (last == null) return 'Not done yet';
  final who = last.userId == myId ? 'You' : last.name;
  return '$who, ${agoLabel(last.at, now)}';
}
