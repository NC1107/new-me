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

/// "25 gems", the worth both of you agreed on and what a completion pays now.
String sharedWorthLabel(SharedHabit h) => plural(h.gems, 'gem', 'gems');

/// "40 gems waiting on Sam" for a suggestion of mine the partner has not answered, null
/// when nothing of mine is waiting.
String? sharedPendingLabel(SharedHabit h, int? myId, String? partner) {
  final proposed = h.proposedWorth;
  if (proposed == null || h.proposalForMe(myId)) return null;
  return '${plural(proposed, 'gem', 'gems')} ${partner == null ? 'pending' : 'waiting on $partner'}';
}

/// Who a chore that was done today counted for: "Done together", "Done by you" or "Done by Sam".
String sharedDoneByLabel(SharedHabit h, int? myId) {
  final last = h.last;
  if (last == null) return 'Done';
  if (last.together) return 'Done together';
  final doer = last.doers.length == 1 ? last.doers.first : null;
  final id = doer?.userId ?? last.userId;
  return id == myId ? 'Done by you' : 'Done by ${doer?.name ?? last.name}';
}

String _who(SharedDoer d, int? myId) => d.userId == myId ? 'You' : d.name;

/// "Sam, 25 gems, 2 d ago", "You 13 + Sam 12 gems, 3 h ago" or "Not done yet". The viewer comes
/// first, and a chore done together shows what each of them got.
String sharedLastLabel(SharedHabit h, int? myId, DateTime now) {
  final last = h.last;
  if (last == null) return 'Not done yet';
  final ago = agoLabel(last.at, now);
  final doers = [...last.doers]
    ..sort((a, b) => (a.userId == myId ? 0 : 1) - (b.userId == myId ? 0 : 1));
  switch (doers.length) {
    case 0:
      return '${last.userId == myId ? 'You' : last.name}, $ago';
    case 1:
      return '${_who(doers.first, myId)}, ${plural(doers.first.gems, 'gem', 'gems')}, $ago';
    default:
      final shares = doers.map((d) => '${_who(d, myId)} ${d.gems}').join(' + ');
      return '$shares gems, $ago';
  }
}
