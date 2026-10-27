// Models for the v8 server additions: the research-backed targets, the weight goal and the
// push-up max test (docs/design-v8.md). Every parser tolerates a missing or malformed part, so an
// older server (or a half-written cache) still parses.

typedef _Json = Map<String, dynamic>;

int? _intOrNull(Object? v) => v is num ? v.toInt() : null;

double? _double(Object? v) => v is num ? v.toDouble() : null;

String _str(Object? v, [String fallback = '']) => v is String ? v : fallback;

_Json? _map(Object? v) => v is Map ? v.cast<String, dynamic>() : null;

List<String> _strings(Object? v) => [
  if (v is List)
    for (final item in v)
      if (item is String) item,
];

/// The weight goal a person chose. The pace is kg a week and 0 for maintain.
class GoalSetting {
  const GoalSetting({this.kind = GoalKind.maintain, this.paceKgPerWeek = 0});

  factory GoalSetting.parse(Object? v) {
    final j = _map(v);
    if (j == null) return const GoalSetting();
    final kind = GoalKind.parse(j['kind']);
    return GoalSetting(
      kind: kind,
      paceKgPerWeek: kind == GoalKind.maintain ? 0 : _double(j['paceKgPerWeek']) ?? 0,
    );
  }

  final GoalKind kind;
  final double paceKgPerWeek;

  Map<String, dynamic> toJson() => {'kind': kind.name, 'paceKgPerWeek': paceKgPerWeek};

  @override
  bool operator ==(Object other) =>
      other is GoalSetting && other.kind == kind && other.paceKgPerWeek == paceKgPerWeek;

  @override
  int get hashCode => Object.hash(kind, paceKgPerWeek);
}

enum GoalKind {
  lose,
  maintain,
  gain;

  /// An unknown word from a newer server reads as maintain, which is the server's default.
  static GoalKind parse(Object? v) =>
      GoalKind.values.where((k) => k.name == v).firstOrNull ?? GoalKind.maintain;
}

/// Paces the profile offers, kg a week (docs/design-v8.md: lose 0.25 or 0.5, gain up to 0.5% of
/// body weight, which the server applies when the target is computed).
const kLosePaces = [0.25, 0.5];
const kGainPaces = [0.1, 0.25, 0.5];

/// One input of the formulas and where it came from.
class TargetInput {
  const TargetInput({
    required this.key,
    this.value,
    this.unit = '',
    this.source = 'missing',
    this.note = '',
  });

  static TargetInput? tryParse(Object? v) {
    final j = _map(v);
    if (j == null || j['key'] is! String) return null;
    return TargetInput(
      key: j['key'] as String,
      value: j['value'],
      unit: _str(j['unit']),
      source: _str(j['source'], 'missing'),
      note: _str(j['note']),
    );
  }

  /// weightKg, heightCm, age, sex, goal or steps14.
  final String key;

  /// A number, a word, the goal object, or null while the input is missing.
  final Object? value;
  final String unit;

  /// profile, health or missing.
  final String source;
  final String note;

  bool get isMissing => source == 'missing' || value == null;

  Map<String, dynamic> toJson() => {
    'key': key,
    'value': value,
    if (unit.isNotEmpty) 'unit': unit,
    'source': source,
    if (note.isNotEmpty) 'note': note,
  };
}

/// How firmly a target rests on a published source, as the server labels it.
enum TargetLabel {
  guideline,
  convention,
  derivation;

  static TargetLabel parse(Object? v) =>
      TargetLabel.values.where((l) => l.name == v).firstOrNull ?? TargetLabel.derivation;

  String get title => switch (this) {
    TargetLabel.guideline => 'Guideline',
    TargetLabel.convention => 'Convention',
    TargetLabel.derivation => 'Derivation',
  };
}

/// One target: the formula value, the setting in force and the reasoning behind the number.
class Target {
  const Target({
    required this.key,
    required this.unit,
    required this.formula,
    required this.label,
    this.value,
    this.current,
    this.sources = const [],
    this.missing = const [],
    this.applicable = false,
    this.details = const {},
  });

  static Target? tryParse(Object? v) {
    final j = _map(v);
    if (j == null || j['key'] is! String) return null;
    return Target(
      key: j['key'] as String,
      value: _intOrNull(j['value']),
      unit: _str(j['unit']),
      current: _intOrNull(j['current']),
      formula: _str(j['formula']),
      sources: _strings(j['sources']),
      label: TargetLabel.parse(j['label']),
      missing: _strings(j['missing']),
      applicable: j['applicable'] as bool? ?? false,
      details: _map(j['details']) ?? const {},
    );
  }

  final String key;
  final int? value;
  final String unit;

  /// The setting in force today, or null when the person has none.
  final int? current;

  /// One plain sentence with the person's numbers plugged in.
  final String formula;

  /// Keys into [TargetsReport.sources].
  final List<String> sources;
  final TargetLabel label;

  /// Inputs or data the value is still waiting for.
  final List<String> missing;

  /// True for the targets POST /api/targets/apply can set.
  final bool applicable;
  final Map<String, dynamic> details;

  bool get hasValue => value != null;

  /// The formula value already is the setting in force.
  bool get isApplied => value != null && value == current;

  /// "Use this" needs a value, support for applying and a setting that differs.
  bool get canUse => applicable && value != null && value != current;

  Map<String, dynamic> toJson() => {
    'key': key,
    'value': value,
    'unit': unit,
    'current': current,
    'formula': formula,
    'sources': sources,
    'label': label.name,
    'missing': missing,
    'applicable': applicable,
    if (details.isNotEmpty) 'details': details,
  };
}

/// GET /api/targets.
class TargetsReport {
  const TargetsReport({
    this.asOf = '',
    this.disclaimer = '',
    this.inputs = const [],
    this.targets = const [],
    this.sources = const {},
  });

  factory TargetsReport.parse(Object? v) {
    final j = _map(v) ?? const <String, dynamic>{};
    final sources = _map(j['sources']);
    return TargetsReport(
      asOf: _str(j['asOf']),
      disclaimer: _str(j['disclaimer']),
      inputs: [
        if (j['inputs'] is List)
          for (final i in j['inputs'] as List) ?TargetInput.tryParse(i),
      ],
      targets: [
        if (j['targets'] is List)
          for (final t in j['targets'] as List) ?Target.tryParse(t),
      ],
      sources: {
        if (sources != null)
          for (final e in sources.entries)
            if (e.value is String) e.key: e.value as String,
      },
    );
  }

  final String asOf;

  /// Shown once on the page, never per target.
  final String disclaimer;
  final List<TargetInput> inputs;
  final List<Target> targets;
  final Map<String, String> sources;

  Target? target(String key) => targets.where((t) => t.key == key).firstOrNull;

  TargetInput? input(String key) => inputs.where((i) => i.key == key).firstOrNull;

  /// The inputs that block at least one target, in the server's order.
  List<TargetInput> get missingInputs => [
    for (final i in inputs)
      if (i.key != 'goal' && i.isMissing) i,
  ];

  /// The citation for a source key; a key the server did not explain is shown as it is.
  String citation(String key) => sources[key] ?? key;

  Map<String, dynamic> toJson() => {
    'asOf': asOf,
    'disclaimer': disclaimer,
    'inputs': [for (final i in inputs) i.toJson()],
    'targets': [for (final t in targets) t.toJson()],
    'sources': sources,
  };
}

/// POST /api/pushups/max.
class PushupMaxResult {
  const PushupMaxResult({required this.date, required this.reps});

  factory PushupMaxResult.parse(Object? v) {
    final j = _map(v);
    return PushupMaxResult(date: _str(j?['date']), reps: _intOrNull(j?['reps']) ?? 0);
  }

  final String date;
  final int reps;
}

/// The keys POST /api/targets/apply answered with, from the `applied` list.
List<String> parseApplied(Object? v) => _strings(_map(v)?['applied']);
