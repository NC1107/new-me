import 'models.dart';

int _int(Object? v, [int fallback = 0]) => (v as num?)?.toInt() ?? fallback;

String _str(Object? v, [String fallback = '']) => v as String? ?? fallback;

/// Reads a list leniently: an entry that is not an object is skipped instead of failing the
/// whole screen, since habits are an add-on to the day.
List<T> _items<T>(Object? v, T Function(Json) parse) => [
  for (final item in v as List? ?? const [])
    if (item is Map<String, dynamic>) parse(item),
];

abstract final class HabitKind {
  static const check = 'check';
  static const count = 'count';
}

const kMaxHabitSlots = 8;
const kMaxSlotLabel = 24;
const kMaxHabitTarget = 50;
const kMaxMarkCount = 1000;

/// "07:30" as minutes after midnight, or null for anything else.
int? parseSlotTime(String? hhmm) {
  final m = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch(hhmm ?? '');
  if (m == null) return null;
  final h = int.parse(m[1]!);
  final min = int.parse(m[2]!);
  return h > 23 || min > 59 ? null : h * 60 + min;
}

String slotTimeString(int minutes) =>
    '${(minutes ~/ 60).toString().padLeft(2, '0')}:${(minutes % 60).toString().padLeft(2, '0')}';

/// A slot as saved on a habit: a label and an optional time.
class HabitSlot {
  const HabitSlot({required this.label, this.time});

  factory HabitSlot.fromJson(Json j) =>
      HabitSlot(label: _str(j['label']), time: j['time'] as String?);

  final String label;

  /// "HH:MM" on the person's own clock, or null for a slot with no time.
  final String? time;

  int? get minutes => parseSlotTime(time);

  Json toJson() => {'label': label, 'time': time};
}

/// A habit as the management screens see it, paused ones included.
/// Habit worths toward the daily goal (v10); quests are worth 50 or 100.
enum HabitWorth {
  track(0, 'Just track', 'Does not count toward your day'),
  small(10, 'Small', '10 points'),
  medium(25, 'Medium', '25 points'),
  big(50, 'Big', '50 points, like half a quest');

  const HabitWorth(this.points, this.label, this.detail);

  final int points;
  final String label;
  final String detail;

  static HabitWorth of(int points) =>
      HabitWorth.values.where((w) => w.points == points).firstOrNull ?? HabitWorth.medium;
}

const kDefaultHabitPoints = 25;

class Habit {
  const Habit({
    required this.id,
    required this.name,
    required this.icon,
    required this.kind,
    required this.weekdays,
    required this.slots,
    required this.target,
    required this.position,
    required this.paused,
    this.points = kDefaultHabitPoints,
  });

  factory Habit.fromJson(Json j) => Habit(
    id: _int(j['id']),
    name: _str(j['name']),
    icon: _str(j['icon']),
    kind: _str(j['kind'], HabitKind.check),
    weekdays: [
      for (final d in j['weekdays'] as List? ?? const [1, 2, 3, 4, 5, 6, 7])
        if (d is num && d >= 1 && d <= 7) d.toInt(),
    ],
    slots: _items(j['slots'], HabitSlot.fromJson),
    target: (j['target'] as num?)?.toInt(),
    position: _int(j['position']),
    paused: j['paused'] as bool? ?? false,
    points: _int(j['points'], kDefaultHabitPoints),
  );

  final int id;
  final String name;
  final String icon;
  final String kind;

  /// ISO numbers, 1 for Monday to 7 for Sunday.
  final List<int> weekdays;
  final List<HabitSlot> slots;
  final int? target;
  final int position;
  final bool paused;

  /// The habit's worth toward the daily goal (v10): 0, 10, 25 or 50.
  final int points;

  bool get isCount => kind == HabitKind.count;

  bool get everyDay => weekdays.toSet().length == 7;

  bool dueOn(int isoWeekday) => weekdays.contains(isoWeekday);

  Habit copyWith({bool? paused, int? position}) => Habit(
    id: id,
    name: name,
    icon: icon,
    kind: kind,
    weekdays: weekdays,
    slots: slots,
    target: target,
    position: position ?? this.position,
    paused: paused ?? this.paused,
    points: points,
  );

  Json toJson() => {
    'id': id,
    'name': name,
    'icon': icon,
    'kind': kind,
    'weekdays': weekdays,
    'slots': [for (final s in slots) s.toJson()],
    'target': target,
    'position': position,
    'paused': paused,
    'points': points,
  };
}

/// What a create or full edit sends.
class HabitDraft {
  const HabitDraft({
    required this.name,
    required this.icon,
    required this.kind,
    required this.weekdays,
    this.slots = const [],
    this.target,
    this.points = kDefaultHabitPoints,
  });

  final String name;
  final String icon;
  final String kind;
  final List<int> weekdays;
  final List<HabitSlot> slots;
  final int? target;
  final int points;

  Json toJson() => {
    'name': name,
    'icon': icon,
    'kind': kind,
    'weekdays': weekdays,
    if (kind == HabitKind.check) 'slots': [for (final s in slots) s.toJson()],
    if (kind == HabitKind.count) 'target': target,
    'points': points,
  };

  /// A PATCH cannot change the kind, so it leaves it out.
  Json toPatchJson() => {...toJson()}..remove('kind');
}

class HabitStateSlot {
  const HabitStateSlot({required this.index, required this.label, this.time, required this.done});

  factory HabitStateSlot.fromJson(Json j) => HabitStateSlot(
    index: _int(j['index']),
    label: _str(j['label']),
    time: j['time'] as String?,
    done: j['done'] as bool? ?? false,
  );

  final int index;
  final String label;
  final String? time;
  final bool done;

  int? get minutes => parseSlotTime(time);

  HabitStateSlot withDone(bool value) =>
      HabitStateSlot(index: index, label: label, time: time, done: value);

  Json toJson() => {'index': index, 'label': label, 'time': time, 'done': done};
}

/// A habit due on a day with what has been done on it.
class HabitState {
  const HabitState({
    required this.id,
    required this.name,
    required this.icon,
    required this.kind,
    required this.slots,
    this.target,
    this.count = 0,
  });

  factory HabitState.fromJson(Json j) => HabitState(
    id: _int(j['id']),
    name: _str(j['name']),
    icon: _str(j['icon']),
    kind: _str(j['kind'], HabitKind.check),
    slots: _items(j['slots'], HabitStateSlot.fromJson),
    target: (j['target'] as num?)?.toInt(),
    count: _int(j['count']),
  );

  final int id;
  final String name;
  final String icon;
  final String kind;
  final List<HabitStateSlot> slots;
  final int? target;
  final int count;

  bool get isCount => kind == HabitKind.count;

  bool get countDone => target != null && count >= target!;

  HabitState withSlotDone(int index, bool done) => HabitState(
    id: id,
    name: name,
    icon: icon,
    kind: kind,
    slots: [for (final s in slots) s.index == index ? s.withDone(done) : s],
    target: target,
    count: count,
  );

  HabitState withCount(int value) => HabitState(
    id: id,
    name: name,
    icon: icon,
    kind: kind,
    slots: slots,
    target: target,
    count: value,
  );

  Json toJson() => {
    'id': id,
    'name': name,
    'icon': icon,
    'kind': kind,
    'slots': [for (final s in slots) s.toJson()],
    'target': target,
    'count': count,
  };
}

/// What a mark answers: the day's habit state and the rescored day.
class HabitMarkResult {
  const HabitMarkResult({required this.date, required this.habits, required this.day});

  factory HabitMarkResult.fromJson(Json j) => HabitMarkResult(
    date: _str(j['date']),
    habits: _items(j['habits'], HabitState.fromJson),
    day: DayDetail.fromJson(j['day'] as Json),
  );

  final String date;
  final List<HabitState> habits;
  final DayDetail day;
}

List<HabitState> parseHabitStates(Object? v) => _items(v, HabitState.fromJson);

/// The caller's habits, in their own order.
class HabitList {
  const HabitList(this.habits);

  factory HabitList.fromJson(Json j) => HabitList(_items(j['habits'], Habit.fromJson));

  final List<Habit> habits;

  Json toJson() => {
    'habits': [for (final h in habits) h.toJson()],
  };
}
