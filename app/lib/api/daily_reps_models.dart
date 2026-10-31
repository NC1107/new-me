// Models for the daily-reps quest (docs/design-v18-daily-reps.md): the exercises it can count,
// the person's latest max of each, and the target a max would give. Every parser tolerates a
// missing or malformed part.

int? _intOrNull(Object? v) => v is num ? v.toInt() : null;

int _int(Object? v) => _intOrNull(v) ?? 0;

String _str(Object? v, [String fallback = '']) => v is String ? v : fallback;

Map<String, dynamic>? _map(Object? v) => v is Map ? v.cast<String, dynamic>() : null;

List<T> _list<T>(Object? v, T Function(Map<String, dynamic>) parse) => [
  if (v is List)
    for (final item in v)
      if (_map(item) case final m?) parse(m),
];

/// A citation behind the derived target.
class RepsSource {
  const RepsSource({required this.key, required this.text});

  factory RepsSource.parse(Map<String, dynamic> j) =>
      RepsSource(key: _str(j['key']), text: _str(j['text']));

  final String key;
  final String text;
}

/// A recorded max test of one exercise.
class RepsMax {
  const RepsMax({required this.date, required this.reps});

  final String date;
  final int reps;
}

/// One exercise the quest can count.
class RepsExerciseOption {
  const RepsExerciseOption({
    required this.key,
    required this.name,
    required this.noun,
    required this.singular,
    required this.hint,
    required this.available,
    this.needs,
    this.latestMax,
  });

  factory RepsExerciseOption.parse(Map<String, dynamic> j) {
    final max = _map(j['latestMax']);
    final reps = _intOrNull(max?['reps']);
    return RepsExerciseOption(
      key: _str(j['key']),
      name: _str(j['name']),
      noun: _str(j['noun']),
      singular: _str(j['singular']),
      hint: _str(j['hint']),
      available: j['available'] as bool? ?? true,
      needs: j['needs'] as String?,
      latestMax: reps == null ? null : RepsMax(date: _str(max?['date']), reps: reps),
    );
  }

  final String key;

  /// "Squats".
  final String name;

  /// "squats".
  final String noun;

  /// "squat".
  final String singular;
  final String hint;

  /// False for an exercise that needs equipment the person has not set in their training profile.
  final bool available;

  /// The equipment tag it needs, such as `pullup_bar`.
  final String? needs;
  final RepsMax? latestMax;
}

/// GET and PUT /api/daily-reps.
class DailyReps {
  const DailyReps({
    required this.exercise,
    required this.target,
    required this.dayExercise,
    required this.sets,
    required this.exercises,
    required this.sources,
  });

  factory DailyReps.parse(Object? v) {
    final j = _map(v) ?? const <String, dynamic>{};
    return DailyReps(
      exercise: _str(j['exercise'], 'push_up'),
      target: _int(j['target']),
      dayExercise: _str(j['dayExercise'], _str(j['exercise'], 'push_up')),
      sets: _intOrNull(j['sets']) ?? 3,
      exercises: _list(j['exercises'], RepsExerciseOption.parse),
      sources: _list(j['sources'], RepsSource.parse),
    );
  }

  /// The exercise of the standing quest.
  final String exercise;

  /// Reps a day, over all sets.
  final int target;

  /// What today's frozen quest counts; differs from [exercise] while a change waits for tomorrow.
  final String dayExercise;
  final int sets;
  final List<RepsExerciseOption> exercises;
  final List<RepsSource> sources;

  RepsExerciseOption? option(String key) => exercises.where((e) => e.key == key).firstOrNull;
}

/// GET /api/daily-reps/preview: the target a max gives.
class RepsPreview {
  const RepsPreview({
    required this.exercise,
    required this.max,
    required this.sets,
    required this.repsPerSet,
    required this.low,
    required this.high,
    required this.daily,
    required this.formula,
    required this.sources,
  });

  factory RepsPreview.parse(Object? v) {
    final j = _map(v) ?? const <String, dynamic>{};
    return RepsPreview(
      exercise: _str(j['exercise']),
      max: _int(j['max']),
      sets: _int(j['sets']),
      repsPerSet: _int(j['repsPerSet']),
      low: _int(j['low']),
      high: _int(j['high']),
      daily: _int(j['daily']),
      formula: _str(j['formula']),
      sources: _list(j['sources'], RepsSource.parse),
    );
  }

  final String exercise;
  final int max;
  final int sets;
  final int repsPerSet;
  final int low;
  final int high;
  final int daily;
  final String formula;
  final List<RepsSource> sources;
}
