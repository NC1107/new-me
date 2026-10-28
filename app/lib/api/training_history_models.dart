// Models for training history (docs/design-v13.md): the month calendar and the per-exercise
// strength chart. Parsers tolerate missing or malformed parts like the rest of the training models.

typedef _Json = Map<String, dynamic>;

_Json? _map(Object? v) => v is Map ? v.cast<String, dynamic>() : null;

int _int(Object? v) => v is num ? v.toInt() : 0;

int? _intOrNull(Object? v) => v is num ? v.toInt() : null;

double? _double(Object? v) => v is num ? v.toDouble() : null;

String _str(Object? v) => v is String ? v : '';

List<T> _list<T>(Object? v, T? Function(Object?) parse) => [
  if (v is List)
    for (final item in v)
      if (parse(item) case final T parsed) parsed,
];

/// One set listed on a calendar day.
class HistorySet {
  const HistorySet({
    required this.exercise,
    required this.name,
    this.reps,
    this.seconds,
    this.loadKg,
  });

  static HistorySet? tryParse(Object? v) {
    final j = _map(v);
    if (j == null || j['exercise'] is! String) return null;
    return HistorySet(
      exercise: _str(j['exercise']),
      name: _str(j['name']),
      reps: _intOrNull(j['reps']),
      seconds: _intOrNull(j['seconds']),
      loadKg: _double(j['loadKg']),
    );
  }

  final String exercise;
  final String name;
  final int? reps;
  final int? seconds;
  final double? loadKg;
}

/// What one calendar day holds. Days with nothing are not listed by the server.
class HistoryDay {
  const HistoryDay({
    required this.date,
    this.sets = 0,
    this.sessionCompleted = false,
    this.yogaMinutes = 0,
    this.workoutTypes = const [],
    this.logged = const [],
  });

  static HistoryDay? tryParse(Object? v) {
    final j = _map(v);
    final date = _str(j?['date']);
    if (j == null || date.isEmpty) return null;
    return HistoryDay(
      date: date,
      sets: _int(j['sets']),
      sessionCompleted: j['sessionCompleted'] == true,
      yogaMinutes: _int(j['yogaMinutes']),
      workoutTypes: [
        if (j['workoutTypes'] case final List types)
          for (final t in types)
            if (t is String) t,
      ],
      logged: _list(j['logged'], HistorySet.tryParse),
    );
  }

  final String date;
  final int sets;
  final bool sessionCompleted;
  final int yogaMinutes;
  final List<String> workoutTypes;
  final List<HistorySet> logged;

  bool get hasSets => sets > 0;
  bool get hasYoga => yogaMinutes > 0;
}

/// GET /training/history: the days of one month with something on them.
class TrainingHistoryMonth {
  const TrainingHistoryMonth({required this.month, this.days = const []});

  factory TrainingHistoryMonth.parse(Object? data) {
    final j = _map(data) ?? const {};
    return TrainingHistoryMonth(
      month: _str(j['month']),
      days: _list(j['days'], HistoryDay.tryParse),
    );
  }

  final String month;
  final List<HistoryDay> days;

  HistoryDay? day(String date) => days.where((d) => d.date == date).firstOrNull;
}

/// One day's best in the chart metric.
class ChartPoint {
  const ChartPoint({required this.date, required this.value});

  static ChartPoint? tryParse(Object? v) {
    final j = _map(v);
    final value = _double(j?['value']);
    final date = _str(j?['date']);
    return j == null || value == null || date.isEmpty ? null : ChartPoint(date: date, value: value);
  }

  final String date;
  final double value;
}

/// A max test on the chart: reps or seconds on a day.
class ChartMaxTest {
  const ChartMaxTest({required this.date, this.reps, this.seconds});

  static ChartMaxTest? tryParse(Object? v) {
    final j = _map(v);
    final date = _str(j?['date']);
    if (j == null || date.isEmpty) return null;
    return ChartMaxTest(date: date, reps: _intOrNull(j['reps']), seconds: _intOrNull(j['seconds']));
  }

  final String date;
  final int? reps;
  final int? seconds;

  double? get value => (seconds ?? reps)?.toDouble();
}

/// What a strength chart plots; the wire names are the server's.
enum ChartMetric {
  e1rm('e1rm_kg'),
  volume('volume_kg'),
  reps('reps'),
  seconds('seconds');

  const ChartMetric(this.wire);

  final String wire;

  static ChartMetric parse(Object? v) =>
      values.where((m) => m.wire == v).firstOrNull ?? ChartMetric.reps;

  /// Whether the values are weights, which follow the person's units.
  bool get isWeight => this == e1rm || this == volume;
}

/// GET /exercises/{key}/history: per-day bests in the chart metric, and the max tests.
class ExerciseHistory {
  const ExerciseHistory({
    required this.metric,
    required this.estimated,
    this.points = const [],
    this.maxTests = const [],
  });

  factory ExerciseHistory.parse(Object? data) {
    final j = _map(data) ?? const {};
    return ExerciseHistory(
      metric: ChartMetric.parse(j['metric']),
      estimated: j['estimated'] == true,
      points: _list(j['points'], ChartPoint.tryParse),
      maxTests: _list(j['maxTests'], ChartMaxTest.tryParse),
    );
  }

  final ChartMetric metric;
  final bool estimated;
  final List<ChartPoint> points;
  final List<ChartMaxTest> maxTests;
}
