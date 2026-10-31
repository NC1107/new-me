import 'models.dart';

/// The schedule kinds of a shared household habit, as the server names them.
abstract final class SharedKind {
  static const daily = 'daily';
  static const weekdays = 'weekdays';
  static const weekly = 'weekly';
  static const everyN = 'every_n';
}

abstract final class SharedState {
  static const overdue = 'overdue';
  static const today = 'today';
  static const upcoming = 'upcoming';
}

const kMaxSharedName = 40;
const kMinEveryDays = 2;
const kMaxEveryDays = 365;

/// How often a shared habit comes round. [weekdays] is used by the weekdays kind only (ISO,
/// Monday 1) and [everyDays] by every_n only.
class SharedSchedule {
  const SharedSchedule({required this.kind, this.weekdays = const [], this.everyDays});

  factory SharedSchedule.fromJson(Json j) => SharedSchedule(
    kind: j['kind'] as String? ?? SharedKind.daily,
    weekdays: [for (final d in j['weekdays'] as List? ?? const []) (d as num).toInt()],
    everyDays: (j['everyDays'] as num?)?.toInt(),
  );

  final String kind;
  final List<int> weekdays;
  final int? everyDays;

  Json toJson() => {
    'kind': kind,
    if (kind == SharedKind.weekdays) 'weekdays': weekdays,
    if (kind == SharedKind.everyN) 'everyDays': everyDays,
  };

  bool get valid => switch (kind) {
    SharedKind.daily || SharedKind.weekly => true,
    SharedKind.weekdays => weekdays.isNotEmpty,
    SharedKind.everyN =>
      everyDays != null && everyDays! >= kMinEveryDays && everyDays! <= kMaxEveryDays,
    _ => false,
  };

  @override
  bool operator ==(Object other) =>
      other is SharedSchedule &&
      other.kind == kind &&
      other.everyDays == everyDays &&
      other.weekdays.length == weekdays.length &&
      other.weekdays.every(weekdays.contains);

  @override
  int get hashCode => Object.hash(kind, everyDays, weekdays.length);
}

/// One person a chore counted for and the gems it paid them.
class SharedDoer {
  const SharedDoer({required this.userId, required this.name, required this.gems});

  factory SharedDoer.fromJson(Json j) => SharedDoer(
    userId: (j['userId'] as num).toInt(),
    name: j['name'] as String? ?? '',
    gems: (j['gems'] as num?)?.toInt() ?? 0,
  );

  final int userId;
  final String name;
  final int gems;
}

/// Who did a shared habit last, and when. [userId] is who marked it, the only person who can take
/// it back; [doers] are the people it counted for, both of them when it was done [together].
class SharedLast {
  const SharedLast({
    required this.userId,
    required this.name,
    required this.at,
    this.together = false,
    this.doers = const [],
  });

  factory SharedLast.fromJson(Json j) => SharedLast(
    userId: (j['userId'] as num).toInt(),
    name: j['name'] as String? ?? '',
    at: DateTime.parse(j['at'] as String),
    together: j['together'] as bool? ?? false,
    doers: [for (final d in j['doers'] as List? ?? const []) SharedDoer.fromJson(d as Json)],
  );

  final int userId;
  final String name;
  final DateTime at;
  final bool together;
  final List<SharedDoer> doers;
}

/// Who a chore was done by, as the server names it, from the point of view of the person who
/// marked it.
abstract final class SharedBy {
  static const self = 'self';
  static const partner = 'partner';
  static const together = 'together';
}

/// What the person who marks a chore and the other person each get for [worth] gems. Done
/// together the worth splits evenly and the odd gem goes to whoever marked it, as on the server.
({int mine, int theirs}) sharedCredit(String by, int worth) => switch (by) {
  SharedBy.partner => (mine: 0, theirs: worth),
  SharedBy.together => (mine: (worth + 1) ~/ 2, theirs: worth ~/ 2),
  _ => (mine: worth, theirs: 0),
};

/// The worths offered for a chore, in gems.
const kSharedWorths = [10, 25, 50, 75, 100];
const kSharedDefaultWorth = 25;

/// A household habit as I see it: due dates are in my own zone, `daysFromToday` negative when
/// overdue.
class SharedHabit {
  const SharedHabit({
    required this.id,
    required this.name,
    required this.icon,
    required this.schedule,
    required this.last,
    required this.state,
    required this.dueOn,
    required this.daysFromToday,
    required this.doneToday,
    required this.doneByMe,
    required this.gems,
    this.proposedWorth,
    this.proposedBy,
    this.proposedByName = '',
  });

  factory SharedHabit.fromJson(Json j) => SharedHabit(
    id: (j['id'] as num).toInt(),
    name: j['name'] as String? ?? '',
    icon: j['icon'] as String? ?? 'check_circle',
    schedule: SharedSchedule.fromJson(j['schedule'] as Json? ?? const {}),
    last: j['last'] is Json ? SharedLast.fromJson(j['last'] as Json) : null,
    state: j['state'] as String? ?? SharedState.upcoming,
    dueOn: j['dueOn'] as String? ?? '',
    daysFromToday: (j['daysFromToday'] as num?)?.toInt() ?? 0,
    doneToday: j['doneToday'] as bool? ?? false,
    doneByMe: j['doneByMe'] as bool? ?? false,
    gems: (j['gems'] as num?)?.toInt() ?? 0,
    proposedWorth: (j['proposedWorth'] as num?)?.toInt(),
    proposedBy: (j['proposedBy'] as num?)?.toInt(),
    proposedByName: j['proposedByName'] as String? ?? '',
  );

  final int id;
  final String name;
  final String icon;
  final SharedSchedule schedule;
  final SharedLast? last;
  final String state;
  final String dueOn;
  final int daysFromToday;
  final bool doneToday;
  final bool doneByMe;

  /// The worth both of you agreed on, which is what a completion pays. [proposedWorth] is a
  /// number one of you suggested that the other has not answered yet.
  final int gems;
  final int? proposedWorth;
  final int? proposedBy;
  final String proposedByName;

  bool get hasProposal => proposedWorth != null && proposedBy != null;

  /// True when the number waiting is my partner's, so it is mine to agree to or counter.
  bool proposalForMe(int? myId) => hasProposal && proposedBy != myId;

  /// The chore as it will read once I have done it today, shown before the server answers.
  SharedHabit markedDoneBy(SharedLast me) => SharedHabit(
    id: id,
    name: name,
    icon: icon,
    schedule: schedule,
    last: me,
    state: SharedState.upcoming,
    dueOn: dueOn,
    daysFromToday: 1,
    doneToday: true,
    doneByMe: true,
    gems: gems,
    proposedWorth: proposedWorth,
    proposedBy: proposedBy,
    proposedByName: proposedByName,
  );

  bool get isDue => state != SharedState.upcoming;
  bool get overdue => state == SharedState.overdue;
}
