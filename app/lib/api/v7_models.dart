// Models for the v7 server additions: streak forgiveness, the schedule, the weight and activity
// insights, progress, the monthly look-back and milestones. Every parser tolerates a missing or
// malformed part, so an older server (or a half-written cache) still parses.

import 'training_models.dart';

typedef _Json = Map<String, dynamic>;

int _int(Object? v, [int fallback = 0]) => v is num ? v.toInt() : fallback;

int? _intOrNull(Object? v) => v is num ? v.toInt() : null;

double? _double(Object? v) => v is num ? v.toDouble() : null;

String _str(Object? v, [String fallback = '']) => v is String ? v : fallback;

_Json? _map(Object? v) => v is Map ? v.cast<String, dynamic>() : null;

List<T> _items<T>(Object? v, T? Function(Object?) parse) => [
  if (v is List)
    for (final item in v) ?parse(item),
];

/// "06:30" to minutes after midnight, or null when it is not a time.
int? parseClock(Object? v) {
  if (v is! String) return null;
  final m = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch(v);
  if (m == null) return null;
  final h = int.parse(m.group(1)!), min = int.parse(m.group(2)!);
  if (h > 23 || min > 59) return null;
  return h * 60 + min;
}

/// Minutes after midnight to "06:30", the wire spelling.
String formatClockWire(int minutes) =>
    '${(minutes ~/ 60).toString().padLeft(2, '0')}:${(minutes % 60).toString().padLeft(2, '0')}';

/// Streak freezes held, and how far the next one is. A person holds at most [kMaxFreezes].
class Freezes {
  const Freezes({this.held = 0, this.earnedTowardNext = 0});

  static Freezes parse(Object? v) {
    final j = _map(v);
    if (j == null) return const Freezes();
    return Freezes(held: _int(j['held']), earnedTowardNext: _int(j['earnedTowardNext']));
  }

  final int held;

  /// Counted days done of the [kDaysPerFreeze] that earn the next freeze.
  final int earnedTowardNext;

  bool get isEmpty => held == 0 && earnedTowardNext == 0;

  Map<String, dynamic> toJson() => {'held': held, 'earnedTowardNext': earnedTowardNext};
}

const kMaxFreezes = 2;
const kDaysPerFreeze = 7;

/// The open window to repair a missed yesterday by reaching 100% today.
class Repair {
  const Repair({required this.date, required this.until, required this.progressPercent});

  static Repair? tryParse(Object? v) {
    final j = _map(v);
    if (j == null || _str(j['date']).isEmpty) return null;
    return Repair(
      date: _str(j['date']),
      until: DateTime.tryParse(_str(j['until'])),
      progressPercent: _int(j['progressPercent']).clamp(0, 100),
    );
  }

  /// The missed day being repaired.
  final String date;

  /// When the window closes (22:00 the next day); null if the server sent nothing usable.
  final DateTime? until;
  final int progressPercent;

  Repair withProgress(int percent) =>
      Repair(date: date, until: until, progressPercent: percent.clamp(0, 100));

  Map<String, dynamic> toJson() => {
    'date': date,
    'until': until?.toUtc().toIso8601String(),
    'progressPercent': progressPercent,
  };
}

/// A span of away days, both ends inclusive.
class AwaySpan {
  const AwaySpan({required this.id, required this.from, required this.to, this.note = ''});

  static AwaySpan? tryParse(Object? v) {
    final j = _map(v);
    if (j == null || _intOrNull(j['id']) == null) return null;
    final from = _str(j['from']), to = _str(j['to']);
    if (from.isEmpty || to.isEmpty) return null;
    return AwaySpan(id: _int(j['id']), from: from, to: to, note: _str(j['note']));
  }

  final int id;
  final String from;
  final String to;
  final String note;

  Map<String, dynamic> toJson() => {'id': id, 'from': from, 'to': to, 'note': note};
}

/// A person's away state: whether today is away, the span around today and the later ones.
class AwayState {
  const AwayState({this.today = false, this.current, this.upcoming = const []});

  static AwayState parse(Object? v) {
    final j = _map(v);
    if (j == null) return const AwayState();
    return AwayState(
      today: j['today'] as bool? ?? false,
      current: AwaySpan.tryParse(j['current']),
      upcoming: _items(j['upcoming'], AwaySpan.tryParse),
    );
  }

  final bool today;
  final AwaySpan? current;
  final List<AwaySpan> upcoming;

  /// The current span first, then the ones that start later.
  List<AwaySpan> get all => [?current, ...upcoming];

  bool get isEmpty => !today && current == null && upcoming.isEmpty;

  Map<String, dynamic> toJson() => {
    'today': today,
    'current': current?.toJson(),
    'upcoming': [for (final s in upcoming) s.toJson()],
  };
}

/// The answer to POST /away: the new span and the refreshed state.
class AwayCreated {
  const AwayCreated({required this.span, required this.state});

  static AwayCreated parse(Object? v) {
    final j = _map(v) ?? const <String, dynamic>{};
    final span = AwaySpan.tryParse(j['away']);
    if (span == null) throw const FormatException('away');
    return AwayCreated(span: span, state: AwayState.parse(j['state']));
  }

  final AwaySpan span;
  final AwayState state;
}

/// The couple's streak: days on which both counted, froze or were away, and one at least counted.
class SharedStreak {
  const SharedStreak({this.current = 0, this.best = 0});

  static SharedStreak parse(Object? v) {
    final j = _map(v);
    if (j == null) return const SharedStreak();
    return SharedStreak(current: _int(j['current']), best: _int(j['best']));
  }

  final int current;
  final int best;

  bool get isEmpty => current == 0 && best == 0;

  Map<String, dynamic> toJson() => {'current': current, 'best': best};
}

/// One milestone, a streak length or a first. [shared] is the couple's.
class Milestone {
  const Milestone({
    required this.id,
    required this.kind,
    required this.value,
    required this.shared,
    required this.title,
    required this.achievedOn,
  });

  static Milestone? tryParse(Object? v) {
    final j = _map(v);
    if (j == null || _intOrNull(j['id']) == null) return null;
    return Milestone(
      id: _int(j['id']),
      kind: _str(j['kind']),
      value: _int(j['value']),
      shared: j['shared'] as bool? ?? false,
      title: _str(j['title']),
      achievedOn: _str(j['achievedOn']),
    );
  }

  final int id;
  final String kind;
  final int value;
  final bool shared;
  final String title;
  final String achievedOn;

  Map<String, dynamic> toJson() => {
    'id': id,
    'kind': kind,
    'value': value,
    'shared': shared,
    'title': title,
    'achievedOn': achievedOn,
  };
}

List<Milestone> parseMilestones(Object? v) => _items(v, Milestone.tryParse);

/// Wake and bed time for one kind of day, in minutes after midnight.
class DayTimes {
  const DayTimes({required this.wake, required this.bed});

  static DayTimes parse(Object? v, DayTimes fallback) {
    final j = _map(v);
    if (j == null) return fallback;
    return DayTimes(
      wake: parseClock(j['wake']) ?? fallback.wake,
      bed: parseClock(j['bed']) ?? fallback.bed,
    );
  }

  final int wake;
  final int bed;

  DayTimes copyWith({int? wake, int? bed}) =>
      DayTimes(wake: wake ?? this.wake, bed: bed ?? this.bed);

  @override
  bool operator ==(Object other) => other is DayTimes && other.wake == wake && other.bed == bed;

  @override
  int get hashCode => Object.hash(wake, bed);

  Map<String, dynamic> toJson() => {'wake': formatClockWire(wake), 'bed': formatClockWire(bed)};
}

const kDefaultWake = 7 * 60;
const kDefaultBed = 23 * 60;
const kDefaultFirstOffsetMin = 10;
const kMaxFirstOffsetMin = 360;

/// The person's rhythm: workdays (1 Monday to 7 Sunday), wake and bed for workdays and days
/// off, and how long after waking the first notification may come.
class Schedule {
  const Schedule({
    this.workdays = const [1, 2, 3, 4, 5],
    this.workday = const DayTimes(wake: kDefaultWake, bed: kDefaultBed),
    this.dayOff = const DayTimes(wake: kDefaultWake, bed: kDefaultBed),
    this.firstNotificationOffsetMin = kDefaultFirstOffsetMin,
  });

  static Schedule parse(Object? v) {
    final j = _map(v);
    if (j == null) return const Schedule();
    const base = Schedule();
    final days = _items(j['workdays'], (d) => d is num && d >= 1 && d <= 7 ? d.toInt() : null);
    return Schedule(
      workdays: j['workdays'] is List ? (days.toSet().toList()..sort()) : base.workdays,
      workday: DayTimes.parse(j['workday'], base.workday),
      dayOff: DayTimes.parse(j['dayOff'], base.dayOff),
      firstNotificationOffsetMin: _int(
        j['firstNotificationOffsetMin'],
        kDefaultFirstOffsetMin,
      ).clamp(0, kMaxFirstOffsetMin),
    );
  }

  final List<int> workdays;
  final DayTimes workday;
  final DayTimes dayOff;
  final int firstNotificationOffsetMin;

  /// The times that apply on [weekday] (DateTime.monday is 1).
  DayTimes timesFor(int weekday) => workdays.contains(weekday) ? workday : dayOff;

  Schedule copyWith({
    List<int>? workdays,
    DayTimes? workday,
    DayTimes? dayOff,
    int? firstNotificationOffsetMin,
  }) => Schedule(
    workdays: workdays ?? this.workdays,
    workday: workday ?? this.workday,
    dayOff: dayOff ?? this.dayOff,
    firstNotificationOffsetMin: firstNotificationOffsetMin ?? this.firstNotificationOffsetMin,
  );

  @override
  bool operator ==(Object other) =>
      other is Schedule &&
      other.workday == workday &&
      other.dayOff == dayOff &&
      other.firstNotificationOffsetMin == firstNotificationOffsetMin &&
      other.workdays.length == workdays.length &&
      other.workdays.every(workdays.contains);

  @override
  int get hashCode =>
      Object.hash(workday, dayOff, firstNotificationOffsetMin, Object.hashAll(workdays));

  Map<String, dynamic> toJson() => {
    'workdays': workdays,
    'workday': workday.toJson(),
    'dayOff': dayOff.toJson(),
    'firstNotificationOffsetMin': firstNotificationOffsetMin,
  };
}

/// The protein target explained: per kilogram, the latest weight, and what applies.
class ProteinInfo {
  const ProteinInfo({
    this.perKg = 1.6,
    this.auto = false,
    this.weightKg,
    this.suggested,
    this.effective,
  });

  static ProteinInfo parse(Object? v) {
    final j = _map(v);
    if (j == null) return const ProteinInfo();
    return ProteinInfo(
      perKg: _double(j['perKg']) ?? 1.6,
      auto: j['auto'] as bool? ?? false,
      weightKg: _double(j['weightKg']),
      suggested: _intOrNull(j['suggested']),
      effective: _intOrNull(j['effective']),
    );
  }

  final double perKg;
  final bool auto;
  final double? weightKg;
  final int? suggested;
  final int? effective;

  bool get isEmpty => weightKg == null && suggested == null && effective == null && !auto;

  Map<String, dynamic> toJson() => {
    'perKg': perKg,
    'auto': auto,
    'weightKg': weightKg,
    'suggested': suggested,
    'effective': effective,
  };
}

/// One weigh-in with its smoothed value.
class WeightPoint {
  const WeightPoint({required this.date, required this.kg, required this.smoothed});

  static WeightPoint? tryParse(Object? v) {
    final j = _map(v);
    final kg = _double(j?['kg']);
    if (j == null || kg == null || _str(j['date']).isEmpty) return null;
    return WeightPoint(date: _str(j['date']), kg: kg, smoothed: _double(j['smoothed']) ?? kg);
  }

  final String date;
  final double kg;
  final double smoothed;

  Map<String, dynamic> toJson() => {'date': date, 'kg': kg, 'smoothed': smoothed};
}

/// Weight as a smoothed trend (EWMA, alpha 0.1) with the weekly rate. The raw reading is
/// secondary. The rate is null until there is enough history.
class WeightInsights {
  const WeightInsights({this.latestKg, this.smoothedKg, this.weeklyRateKg, this.points = const []});

  static WeightInsights parse(Object? v) {
    final j = _map(v);
    if (j == null) return const WeightInsights();
    return WeightInsights(
      latestKg: _double(j['latestKg']),
      smoothedKg: _double(j['smoothedKg']),
      weeklyRateKg: _double(j['weeklyRateKg']),
      points: _items(j['points'], WeightPoint.tryParse),
    );
  }

  final double? latestKg;
  final double? smoothedKg;
  final double? weeklyRateKg;
  final List<WeightPoint> points;

  bool get hasData => smoothedKg != null;

  Map<String, dynamic> toJson() => {
    'latestKg': latestKg,
    'smoothedKg': smoothedKg,
    'weeklyRateKg': weeklyRateKg,
    'points': [for (final p in points) p.toJson()],
  };
}

/// The last seven days of workouts against the WHO 2020 guideline.
class ActivitySummary {
  const ActivitySummary({
    this.available = false,
    this.guideline = 'WHO 2020',
    this.moderateMin = 0,
    this.vigorousMin = 0,
    this.moderateEquivalentMin = 0,
    this.strengthDays = 0,
    this.aerobicTargetMinMin = 150,
    this.aerobicTargetMaxMin = 300,
    this.strengthTargetDays = 2,
    this.meetsAerobic = false,
    this.meetsStrength = false,
    this.heartRateIntensityUsed = false,
  });

  static ActivitySummary parse(Object? v) {
    final j = _map(v);
    if (j == null) return const ActivitySummary();
    return ActivitySummary(
      available: true,
      guideline: _str(j['guideline'], 'WHO 2020'),
      moderateMin: _int(j['moderateMin']),
      vigorousMin: _int(j['vigorousMin']),
      moderateEquivalentMin: _int(j['moderateEquivalentMin']),
      strengthDays: _int(j['strengthDays']),
      aerobicTargetMinMin: _int(j['aerobicTargetMinMin'], 150),
      aerobicTargetMaxMin: _int(j['aerobicTargetMaxMin'], 300),
      strengthTargetDays: _int(j['strengthTargetDays'], 2),
      meetsAerobic: j['meetsAerobic'] as bool? ?? false,
      meetsStrength: j['meetsStrength'] as bool? ?? false,
      heartRateIntensityUsed: j['heartRateIntensityUsed'] as bool? ?? false,
    );
  }

  /// False when the server sent no summary at all.
  final bool available;
  final String guideline;
  final int moderateMin;
  final int vigorousMin;
  final int moderateEquivalentMin;
  final int strengthDays;
  final int aerobicTargetMinMin;
  final int aerobicTargetMaxMin;
  final int strengthTargetDays;
  final bool meetsAerobic;
  final bool meetsStrength;

  /// True when sessions were classed by heart-rate reserve rather than by their type.
  final bool heartRateIntensityUsed;

  Map<String, dynamic> toJson() => {
    'guideline': guideline,
    'moderateMin': moderateMin,
    'vigorousMin': vigorousMin,
    'moderateEquivalentMin': moderateEquivalentMin,
    'strengthDays': strengthDays,
    'aerobicTargetMinMin': aerobicTargetMinMin,
    'aerobicTargetMaxMin': aerobicTargetMaxMin,
    'strengthTargetDays': strengthTargetDays,
    'meetsAerobic': meetsAerobic,
    'meetsStrength': meetsStrength,
    'heartRateIntensityUsed': heartRateIntensityUsed,
  };
}

/// How often the protein target was hit in the last seven days.
class ProteinHitRate {
  const ProteinHitRate({
    this.available = false,
    this.targetG,
    this.perKg,
    this.weightKg,
    this.suggestedG,
    this.daysHit7 = 0,
    this.days7 = 0,
    this.hitRate7,
  });

  static ProteinHitRate parse(Object? v) {
    final j = _map(v);
    if (j == null) return const ProteinHitRate();
    return ProteinHitRate(
      available: true,
      targetG: _intOrNull(j['targetG']),
      perKg: _double(j['perKg']),
      weightKg: _double(j['weightKg']),
      suggestedG: _intOrNull(j['suggestedG']),
      daysHit7: _int(j['daysHit7']),
      days7: _int(j['days7']),
      hitRate7: _double(j['hitRate7']),
    );
  }

  final bool available;
  final int? targetG;
  final double? perKg;
  final double? weightKg;
  final int? suggestedG;
  final int daysHit7;
  final int days7;

  /// 0 to 1, or null with no days logged.
  final double? hitRate7;

  Map<String, dynamic> toJson() => {
    'targetG': targetG,
    'perKg': perKg,
    'weightKg': weightKg,
    'suggestedG': suggestedG,
    'daysHit7': daysHit7,
    'days7': days7,
    'hitRate7': hitRate7,
  };
}

/// One person's slice of the weekly challenge.
class ChallengeShare {
  const ChallengeShare({
    required this.userId,
    required this.name,
    required this.color,
    required this.target,
    required this.progress,
    required this.done,
  });

  static ChallengeShare? tryParse(Object? v) {
    final j = _map(v);
    if (j == null || _int(j['target']) < 1) return null;
    return ChallengeShare(
      userId: _int(j['userId']),
      name: _str(j['name']),
      color: _str(j['color']),
      target: _int(j['target']),
      progress: _int(j['progress']),
      done: j['done'] as bool? ?? false,
    );
  }

  final int userId;
  final String name;
  final String color;
  final int target;
  final int progress;
  final bool done;

  double get fraction => (progress / target).clamp(0.0, 1.0);

  Map<String, dynamic> toJson() => {
    'userId': userId,
    'name': name,
    'color': color,
    'target': target,
    'progress': progress,
    'done': done,
  };
}

/// A change between two windows. [better] is null when there is no good direction or the change
/// is under 1%.
class MetricChange {
  const MetricChange({required this.abs, this.pct, this.better});

  static MetricChange? tryParse(Object? v) {
    final j = _map(v);
    final abs = _double(j?['abs']);
    if (j == null || abs == null) return null;
    return MetricChange(abs: abs, pct: _double(j['pct']), better: j['better'] as bool?);
  }

  final double abs;
  final double? pct;
  final bool? better;

  Map<String, dynamic> toJson() => {'abs': abs, 'pct': pct, 'better': better};
}

/// Which way is good for a metric: more, less, or neither (weight).
enum GoodDirection {
  up,
  down,
  none;

  static GoodDirection parse(Object? v) => switch (v) {
    'up' => GoodDirection.up,
    'down' => GoodDirection.down,
    _ => GoodDirection.none,
  };
}

class SeriesPoint {
  const SeriesPoint({required this.weekStart, this.value});

  static SeriesPoint? tryParse(Object? v) {
    final j = _map(v);
    if (j == null) return null;
    return SeriesPoint(weekStart: _str(j['weekStart']), value: _double(j['value']));
  }

  final String weekStart;
  final double? value;

  Map<String, dynamic> toJson() => {'weekStart': weekStart, 'value': value};
}

/// One metric of the Progress screen: the rolling window, the one before it, the first one, and
/// a weekly series for the sparkline.
class ProgressMetric {
  const ProgressMetric({
    required this.key,
    required this.title,
    required this.unit,
    required this.goodDirection,
    this.current,
    this.previous,
    this.first,
    this.changeFromPrevious,
    this.changeFromFirst,
    this.series = const [],
    this.summary = '',
  });

  static ProgressMetric? tryParse(Object? v) {
    final j = _map(v);
    if (j == null || _str(j['key']).isEmpty) return null;
    return ProgressMetric(
      key: _str(j['key']),
      title: _str(j['title'], _str(j['key'])),
      unit: _str(j['unit']),
      goodDirection: GoodDirection.parse(j['goodDirection']),
      current: _double(j['current']),
      previous: _double(j['previous']),
      first: _double(j['first']),
      changeFromPrevious: MetricChange.tryParse(j['changeFromPrevious']),
      changeFromFirst: MetricChange.tryParse(j['changeFromFirst']),
      series: _items(j['series'], SeriesPoint.tryParse),
      summary: _str(j['summary']),
    );
  }

  final String key;
  final String title;
  final String unit;
  final GoodDirection goodDirection;
  final double? current;
  final double? previous;
  final double? first;
  final MetricChange? changeFromPrevious;
  final MetricChange? changeFromFirst;
  final List<SeriesPoint> series;

  /// The server's plain sentence; the app builds its own when this is empty.
  final String summary;

  Map<String, dynamic> toJson() => {
    'key': key,
    'title': title,
    'unit': unit,
    'goodDirection': goodDirection.name,
    'current': current,
    'previous': previous,
    'first': first,
    'changeFromPrevious': changeFromPrevious?.toJson(),
    'changeFromFirst': changeFromFirst?.toJson(),
    'series': [for (final s in series) s.toJson()],
    'summary': summary,
  };
}

class PersonProgress {
  const PersonProgress({
    required this.userId,
    required this.name,
    required this.color,
    this.joinedOn = '',
    this.metrics = const [],
  });

  static PersonProgress? tryParse(Object? v) {
    final j = _map(v);
    if (j == null) return null;
    return PersonProgress(
      userId: _int(j['userId']),
      name: _str(j['name']),
      color: _str(j['color']),
      joinedOn: _str(j['joinedOn']),
      metrics: _items(j['metrics'], ProgressMetric.tryParse),
    );
  }

  final int userId;
  final String name;
  final String color;
  final String joinedOn;
  final List<ProgressMetric> metrics;

  Map<String, dynamic> toJson() => {
    'userId': userId,
    'name': name,
    'color': color,
    'joinedOn': joinedOn,
    'metrics': [for (final m in metrics) m.toJson()],
  };
}

/// GET /progress.
class Progress {
  const Progress({this.window = 30, this.today = '', this.people = const []});

  static Progress parse(Object? v) {
    final j = _map(v) ?? const <String, dynamic>{};
    return Progress(
      window: _int(j['window'], 30),
      today: _str(j['today']),
      people: _items(j['people'], PersonProgress.tryParse),
    );
  }

  final int window;
  final String today;
  final List<PersonProgress> people;

  Map<String, dynamic> toJson() => {
    'window': window,
    'today': today,
    'people': [for (final p in people) p.toJson()],
  };
}

/// One of the three biggest improvements of a month.
class Improvement {
  const Improvement({
    required this.key,
    required this.title,
    required this.unit,
    required this.value,
    required this.previous,
    required this.pct,
    required this.summary,
  });

  static Improvement? tryParse(Object? v) {
    final j = _map(v);
    if (j == null || _str(j['key']).isEmpty) return null;
    return Improvement(
      key: _str(j['key']),
      title: _str(j['title']),
      unit: _str(j['unit']),
      value: _double(j['value']) ?? 0,
      previous: _double(j['previous']) ?? 0,
      pct: _double(j['pct']) ?? 0,
      summary: _str(j['summary']),
    );
  }

  final String key;
  final String title;
  final String unit;
  final double value;
  final double previous;
  final double pct;
  final String summary;

  Map<String, dynamic> toJson() => {
    'key': key,
    'title': title,
    'unit': unit,
    'value': value,
    'previous': previous,
    'pct': pct,
    'summary': summary,
  };
}

/// A metric over one month: the month's value against the month before and the first 30 days.
class MonthMetric {
  const MonthMetric({
    required this.key,
    required this.title,
    required this.unit,
    required this.goodDirection,
    this.value,
    this.previous,
    this.first,
    this.changeFromPrevious,
    this.changeFromFirst,
  });

  static MonthMetric? tryParse(Object? v) {
    final j = _map(v);
    if (j == null || _str(j['key']).isEmpty) return null;
    return MonthMetric(
      key: _str(j['key']),
      title: _str(j['title'], _str(j['key'])),
      unit: _str(j['unit']),
      goodDirection: GoodDirection.parse(j['goodDirection']),
      value: _double(j['value']),
      previous: _double(j['previous']),
      first: _double(j['first']),
      changeFromPrevious: MetricChange.tryParse(j['changeFromPrevious']),
      changeFromFirst: MetricChange.tryParse(j['changeFromFirst']),
    );
  }

  final String key;
  final String title;
  final String unit;
  final GoodDirection goodDirection;
  final double? value;
  final double? previous;
  final double? first;
  final MetricChange? changeFromPrevious;
  final MetricChange? changeFromFirst;
}

class PersonMonth {
  const PersonMonth({
    required this.userId,
    required this.name,
    required this.color,
    this.points = 0,
    this.countedDays = 0,
    this.metrics = const [],
    this.improvements = const [],
    this.lifts = const [],
  });

  static PersonMonth? tryParse(Object? v) {
    final j = _map(v);
    if (j == null) return null;
    return PersonMonth(
      userId: _int(j['userId']),
      name: _str(j['name']),
      color: _str(j['color']),
      points: _int(j['points']),
      countedDays: _int(j['countedDays']),
      metrics: _items(j['metrics'], MonthMetric.tryParse),
      improvements: _items(j['improvements'], Improvement.tryParse),
      lifts: parseLifts(j['lifts']),
    );
  }

  final int userId;
  final String name;
  final String color;
  final int points;
  final int countedDays;
  final List<MonthMetric> metrics;
  final List<Improvement> improvements;

  /// v9: the month's exercises with their best set against the first month.
  final List<Lift> lifts;
}

class CoupleMonth {
  const CoupleMonth({
    this.points = 0,
    this.bothCountedDays = 0,
    this.metrics = const [],
    this.improvements = const [],
  });

  static CoupleMonth parse(Object? v) {
    final j = _map(v);
    if (j == null) return const CoupleMonth();
    return CoupleMonth(
      points: _int(j['points']),
      bothCountedDays: _int(j['bothCountedDays']),
      metrics: _items(j['metrics'], MonthMetric.tryParse),
      improvements: _items(j['improvements'], Improvement.tryParse),
    );
  }

  final int points;
  final int bothCountedDays;
  final List<MonthMetric> metrics;
  final List<Improvement> improvements;
}

/// GET /lookback.
class Lookback {
  const Lookback({
    required this.month,
    required this.label,
    this.from = '',
    this.to = '',
    this.complete = false,
    this.people = const [],
    this.couple = const CoupleMonth(),
  });

  static Lookback parse(Object? v) {
    final j = _map(v) ?? const <String, dynamic>{};
    return Lookback(
      month: _str(j['month']),
      label: _str(j['label']),
      from: _str(j['from']),
      to: _str(j['to']),
      complete: j['complete'] as bool? ?? false,
      people: _items(j['people'], PersonMonth.tryParse),
      couple: CoupleMonth.parse(j['couple']),
    );
  }

  final String month;
  final String label;
  final String from;
  final String to;
  final bool complete;
  final List<PersonMonth> people;
  final CoupleMonth couple;

  bool get hasImprovements =>
      couple.improvements.isNotEmpty || people.any((p) => p.improvements.isNotEmpty);
}
