// Models for the weekly yoga plan (docs/design-v17-yoga.md). Parsers tolerate missing or
// malformed parts like the rest of the training models.

typedef _Json = Map<String, dynamic>;

_Json? _map(Object? v) => v is Map ? v.cast<String, dynamic>() : null;

int _int(Object? v, [int fallback = 0]) => v is num ? v.toInt() : fallback;

bool _flag(Object? v) => v == true;

String _str(Object? v) => v is String ? v : '';

List<int> _ints(Object? v) => [
  if (v is List)
    for (final item in v)
      if (item is num) item.toInt(),
];

List<T> _list<T>(Object? v, T? Function(Object?) parse) => [
  if (v is List)
    for (final item in v)
      if (parse(item) case final T parsed) parsed,
];

/// How many days and which flow, with the weekdays (1 is Monday) the server chose.
class YogaPlan {
  const YogaPlan({required this.daysPerWeek, required this.flowMinutes, this.weekdays = const []});

  static YogaPlan? tryParse(Object? v) {
    final j = _map(v);
    if (j == null || j['daysPerWeek'] is! num || j['flowMinutes'] is! num) return null;
    return YogaPlan(
      daysPerWeek: _int(j['daysPerWeek']),
      flowMinutes: _int(j['flowMinutes']),
      weekdays: _ints(j['weekdays']),
    );
  }

  final int daysPerWeek;
  final int flowMinutes;
  final List<int> weekdays;
}

class YogaWeekDay {
  const YogaWeekDay({
    required this.date,
    required this.weekday,
    required this.planned,
    required this.done,
  });

  static YogaWeekDay? tryParse(Object? v) {
    final j = _map(v);
    if (j == null) return null;
    return YogaWeekDay(
      date: _str(j['date']),
      weekday: _int(j['weekday']),
      planned: _flag(j['planned']),
      done: _flag(j['done']),
    );
  }

  final String date;
  final int weekday;
  final bool planned;
  final bool done;
}

/// This week against the plan: "Yoga this week: 1 of 3".
class YogaWeek {
  const YogaWeek({required this.planned, required this.done, this.days = const []});

  static YogaWeek? tryParse(Object? v) {
    final j = _map(v);
    if (j == null) return null;
    return YogaWeek(
      planned: _int(j['planned']),
      done: _int(j['done']),
      days: _list(j['days'], YogaWeekDay.tryParse),
    );
  }

  final int planned;
  final int done;
  final List<YogaWeekDay> days;
}

/// GET and PUT /yoga/plan.
class YogaPlanState {
  const YogaPlanState({
    this.plan,
    required this.suggested,
    this.week,
    this.todayPlanned = false,
    this.todayDone = false,
    this.offerMinutes,
    this.citation = '',
    this.avoidedDays = const [],
  });

  static YogaPlanState parse(Object? v) {
    final j = _map(v) ?? const {};
    final progression = _map(j['progression']);
    final today = _map(j['today']);
    return YogaPlanState(
      plan: YogaPlan.tryParse(j['plan']),
      suggested:
          YogaPlan.tryParse(j['suggested']) ?? const YogaPlan(daysPerWeek: 3, flowMinutes: 10),
      week: YogaWeek.tryParse(j['week']),
      todayPlanned: _flag(today?['planned']),
      todayDone: _flag(today?['done']),
      offerMinutes: _flag(progression?['offer']) ? _int(progression?['nextMinutes']) : null,
      citation: _str(j['citation']),
      avoidedDays: _ints(j['avoidedDays']),
    );
  }

  /// Null until the person saves one.
  final YogaPlan? plan;

  /// What a new plan would use: the ACSM default days on days clear of heavy leg sessions.
  final YogaPlan suggested;
  final YogaWeek? week;
  final bool todayPlanned;
  final bool todayDone;

  /// The next longer flow on offer, or null.
  final int? offerMinutes;
  final String citation;

  /// Weekdays kept free for heavy lower-body strength sessions.
  final List<int> avoidedDays;
}
