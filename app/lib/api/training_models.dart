// Models for v9 training (docs/design-v9.md): the exercise library, logged sets, the training
// profile, Claude-designed plans and today's session with its progression targets. Every parser
// tolerates a missing or malformed part, so an older server or a half-written cache still parses.

import 'models.dart';

typedef _Json = Map<String, dynamic>;

int? _intOrNull(Object? v) => v is num ? v.toInt() : null;

int _int(Object? v, [int fallback = 0]) => v is num ? v.toInt() : fallback;

double? _double(Object? v) => v is num ? v.toDouble() : null;

String _str(Object? v, [String fallback = '']) => v is String ? v : fallback;

String? _strOrNull(Object? v) => v is String && v.isNotEmpty ? v : null;

_Json? _map(Object? v) => v is Map ? v.cast<String, dynamic>() : null;

List<String> _strings(Object? v) => [
  if (v is List)
    for (final item in v)
      if (item is String) item,
];

List<T> _list<T>(Object? v, T? Function(Object?) parse) => [
  if (v is List)
    for (final item in v)
      if (parse(item) case final T parsed) parsed,
];

/// Whether an exercise counts reps or holds for seconds.
enum Measure {
  reps,
  seconds;

  static Measure parse(Object? v) => v == 'seconds' ? Measure.seconds : Measure.reps;
}

/// Bodyweight work, or work with an external load in kg.
enum LoadKind {
  bodyweight,
  external;

  static LoadKind parse(Object? v) => v == 'external' ? LoadKind.external : LoadKind.bodyweight;
}

/// One reps-or-seconds amount with an optional load, as best sets and max tests carry it.
class SetAmount {
  const SetAmount({required this.date, this.reps, this.seconds, this.loadKg, this.e1rmKg});

  static SetAmount? tryParse(Object? v) {
    final j = _map(v);
    if (j == null) return null;
    return SetAmount(
      date: _str(j['date']),
      reps: _intOrNull(j['reps']),
      seconds: _intOrNull(j['seconds']),
      loadKg: _double(j['loadKg']),
      e1rmKg: _double(j['e1rmKg']),
    );
  }

  final String date;
  final int? reps;
  final int? seconds;
  final double? loadKg;

  /// The Epley one-rep max estimate, set only for loaded work.
  final double? e1rmKg;

  Map<String, dynamic> toJson() => {
    'date': date,
    'reps': reps,
    'seconds': seconds,
    'loadKg': loadKg,
    'e1rmKg': e1rmKg,
  };
}

enum ExerciseKind {
  strength,
  stretch;

  static ExerciseKind parse(Object? v) => v == 'stretch' ? stretch : strength;
}

class Exercise {
  const Exercise({
    required this.key,
    required this.name,
    this.primaryMuscles = const [],
    this.secondaryMuscles = const [],
    this.measure = Measure.reps,
    this.load = LoadKind.bodyweight,
    this.equipment = const [],
    this.easierKey,
    this.harderKey,
    this.custom = false,
    this.best,
    this.maxTest,
    this.steps = const [],
    this.cues = const [],
    this.imageUrls = const [],
    this.kind = ExerciseKind.strength,
    this.perSide = false,
  });

  static Exercise? tryParse(Object? v) {
    final j = _map(v);
    final key = _strOrNull(j?['key']);
    if (j == null || key == null) return null;
    return Exercise(
      key: key,
      name: _str(j['name'], key),
      primaryMuscles: _strings(j['primaryMuscles']),
      secondaryMuscles: _strings(j['secondaryMuscles']),
      measure: Measure.parse(j['measure']),
      load: LoadKind.parse(j['load']),
      equipment: _strings(j['equipment']),
      easierKey: _strOrNull(j['easierKey']),
      harderKey: _strOrNull(j['harderKey']),
      custom: j['custom'] == true,
      best: SetAmount.tryParse(j['best']),
      maxTest: SetAmount.tryParse(j['maxTest']),
      steps: _strings(j['steps']),
      cues: _strings(j['cues']),
      imageUrls: _strings(j['imageUrls']),
      kind: ExerciseKind.parse(j['kind']),
      perSide: j['perSide'] == true,
    );
  }

  final String key;
  final String name;
  final List<String> primaryMuscles;
  final List<String> secondaryMuscles;
  final Measure measure;
  final LoadKind load;
  final List<String> equipment;
  final String? easierKey;
  final String? harderKey;
  final bool custom;
  final SetAmount? best;
  final SetAmount? maxTest;

  /// The how-to: short numbered steps, form cues and server paths of the start and end photos.
  /// Empty for custom exercises, and for catalog ones without a fitting photo.
  final List<String> steps;
  final List<String> cues;
  final List<String> imageUrls;

  /// Stretches belong to mobility sessions, never to strength plans.
  final ExerciseKind kind;

  /// A stretch done once on each side.
  final bool perSide;

  bool get stretch => kind == ExerciseKind.stretch;

  bool get hasHowTo => steps.isNotEmpty || cues.isNotEmpty || imageUrls.isNotEmpty;

  bool get timed => measure == Measure.seconds;
  bool get loaded => load == LoadKind.external;

  Map<String, dynamic> toJson() => {
    'key': key,
    'name': name,
    'primaryMuscles': primaryMuscles,
    'secondaryMuscles': secondaryMuscles,
    'measure': measure.name,
    'load': load.name,
    'equipment': equipment,
    'easierKey': easierKey,
    'harderKey': harderKey,
    'custom': custom,
    'best': best?.toJson(),
    'maxTest': maxTest?.toJson(),
    'steps': steps,
    'cues': cues,
    'imageUrls': imageUrls,
    'kind': kind.name,
    'perSide': perSide,
  };
}

/// GET /exercises: the catalog plus the caller's custom exercises, and the vocabularies.
class ExerciseCatalog {
  const ExerciseCatalog({
    this.exercises = const [],
    this.muscles = const [],
    this.equipment = const [],
  });

  static ExerciseCatalog parse(Object? v) {
    final j = _map(v) ?? const {};
    return ExerciseCatalog(
      exercises: _list(j['exercises'], Exercise.tryParse),
      muscles: _strings(j['muscles']),
      equipment: _strings(j['equipment']),
    );
  }

  final List<Exercise> exercises;
  final List<String> muscles;
  final List<String> equipment;

  Exercise? byKey(String key) => exercises.where((e) => e.key == key).firstOrNull;

  Map<String, dynamic> toJson() => {
    'exercises': [for (final e in exercises) e.toJson()],
    'muscles': muscles,
    'equipment': equipment,
  };
}

/// One logged set.
class ExerciseSet {
  const ExerciseSet({
    required this.id,
    required this.exercise,
    required this.localDate,
    this.loggedAt,
    this.reps,
    this.seconds,
    this.loadKg,
    this.rir,
    this.sessionId,
  });

  static ExerciseSet? tryParse(Object? v) {
    final j = _map(v);
    final id = _intOrNull(j?['id']);
    if (j == null || id == null) return null;
    return ExerciseSet(
      id: id,
      exercise: _str(j['exercise']),
      localDate: _str(j['localDate']),
      loggedAt: DateTime.tryParse(_str(j['loggedAt'])),
      reps: _intOrNull(j['reps']),
      seconds: _intOrNull(j['seconds']),
      loadKg: _double(j['loadKg']),
      rir: _intOrNull(j['rir']),
      sessionId: _intOrNull(j['sessionId']),
    );
  }

  final int id;
  final String exercise;
  final String localDate;
  final DateTime? loggedAt;
  final int? reps;
  final int? seconds;
  final double? loadKg;
  final int? rir;
  final int? sessionId;

  Map<String, dynamic> toJson() => {
    'id': id,
    'exercise': exercise,
    'localDate': localDate,
    'loggedAt': loggedAt?.toUtc().toIso8601String(),
    'reps': reps,
    'seconds': seconds,
    'loadKg': loadKg,
    'rir': rir,
    'sessionId': sessionId,
  };
}

/// What POST /sets sends.
class SetDraft {
  const SetDraft({
    required this.clientOpId,
    required this.exercise,
    this.reps,
    this.seconds,
    this.loadKg,
    this.rir,
    this.sessionId,
  });

  final String clientOpId;
  final String exercise;
  final int? reps;
  final int? seconds;
  final double? loadKg;
  final int? rir;
  final int? sessionId;

  Map<String, dynamic> toJson() => {
    'clientOpId': clientOpId,
    'exercise': exercise,
    'reps': ?reps,
    'seconds': ?seconds,
    'loadKg': ?loadKg,
    'rir': ?rir,
    'sessionId': ?sessionId,
  };
}

/// The answer to POST /sets and DELETE /sets/{id}: the set (absent on delete) and the rescored
/// day.
class SetResult {
  const SetResult({this.set, required this.day});

  static SetResult parse(Object? v) {
    final j = _map(v) ?? const {};
    return SetResult(
      set: ExerciseSet.tryParse(j['set']),
      day: DayDetail.fromJson(_map(j['day']) ?? const {}),
    );
  }

  final ExerciseSet? set;
  final DayDetail day;
}

/// The experience levels a training profile offers.
enum Experience {
  newcomer('new', 'New to it'),
  some('some', 'Some experience'),
  experienced('experienced', 'Experienced');

  const Experience(this.wire, this.label);

  final String wire;
  final String label;

  static Experience parse(Object? v) =>
      Experience.values.where((e) => e.wire == v).firstOrNull ?? Experience.newcomer;
}

/// Equipment keys the server accepts, in the order the profile shows them.
const kEquipmentKeys = [
  'pullup_bar',
  'dumbbells',
  'barbell',
  'bench',
  'bands',
  'dip_bars',
  'hangboard',
  'gym',
];

String equipmentLabel(String key) => switch (key) {
  'pullup_bar' => 'Pull-up bar',
  'dumbbells' => 'Dumbbells',
  'barbell' => 'Barbell',
  'bench' => 'Bench, box or sturdy chair',
  'bands' => 'Resistance bands',
  'dip_bars' => 'Dip bars',
  'hangboard' => 'Hangboard',
  'gym' => 'Full gym',
  _ => key,
};

String muscleLabel(String key) => switch (key) {
  'hamstrings' => 'Hamstrings',
  'glutes' => 'Glutes',
  'quads' => 'Quads',
  _ => key.isEmpty ? key : '${key[0].toUpperCase()}${key.substring(1)}',
};

class TrainingProfile {
  const TrainingProfile({
    this.equipment = const [],
    this.dumbbellMaxKg,
    this.daysPerWeek = 3,
    this.sessionMinutes = 45,
    this.experience = Experience.newcomer,
    this.focus = '',
  });

  static TrainingProfile? tryParse(Object? v) {
    final j = _map(v);
    if (j == null) return null;
    return TrainingProfile(
      equipment: _strings(j['equipment']),
      dumbbellMaxKg: _double(j['dumbbellMaxKg']),
      daysPerWeek: _int(j['daysPerWeek'], 3),
      sessionMinutes: _int(j['sessionMinutes'], 45),
      experience: Experience.parse(j['experience']),
      focus: _str(j['focus']),
    );
  }

  final List<String> equipment;
  final double? dumbbellMaxKg;
  final int daysPerWeek;
  final int sessionMinutes;
  final Experience experience;
  final String focus;

  Map<String, dynamic> toJson() => {
    'equipment': equipment,
    'dumbbellMaxKg': dumbbellMaxKg,
    'daysPerWeek': daysPerWeek,
    'sessionMinutes': sessionMinutes,
    'experience': experience.wire,
    'focus': focus,
  };
}

/// How a plan asks for one exercise on a training day.
class Prescription {
  const Prescription({
    required this.exercise,
    this.sets = 0,
    this.min = 0,
    this.max = 0,
    this.rir = 0,
    this.restSec = 90,
  });

  static Prescription? tryParse(Object? v) {
    final j = _map(v);
    final key = _strOrNull(j?['exercise']);
    if (j == null || key == null) return null;
    return Prescription(
      exercise: key,
      sets: _int(j['sets']),
      min: _int(j['min']),
      max: _int(j['max']),
      rir: _int(j['rir']),
      restSec: _int(j['restSec'], 90),
    );
  }

  final String exercise;
  final int sets;
  final int min;
  final int max;
  final int rir;
  final int restSec;

  Map<String, dynamic> toJson() => {
    'exercise': exercise,
    'sets': sets,
    'min': min,
    'max': max,
    'rir': rir,
    'restSec': restSec,
  };
}

class PlanDay {
  const PlanDay({required this.label, required this.weekday, this.exercises = const []});

  static PlanDay? tryParse(Object? v) {
    final j = _map(v);
    if (j == null) return null;
    return PlanDay(
      label: _str(j['label']),
      weekday: _int(j['weekday']),
      exercises: _list(j['exercises'], Prescription.tryParse),
    );
  }

  final String label;

  /// ISO weekday: 1 is Monday.
  final int weekday;
  final List<Prescription> exercises;

  Map<String, dynamic> toJson() => {
    'label': label,
    'weekday': weekday,
    'exercises': [for (final e in exercises) e.toJson()],
  };
}

class TrainingPlan {
  const TrainingPlan({
    required this.id,
    required this.startsOn,
    required this.endsOn,
    this.weeks = 4,
    this.notes = '',
    this.days = const [],
  });

  static TrainingPlan? tryParse(Object? v) {
    final j = _map(v);
    final id = _intOrNull(j?['id']);
    if (j == null || id == null) return null;
    return TrainingPlan(
      id: id,
      startsOn: _str(j['startsOn']),
      endsOn: _str(j['endsOn']),
      weeks: _int(j['weeks'], 4),
      notes: _str(j['notes']),
      days: _list(j['days'], PlanDay.tryParse),
    );
  }

  final int id;
  final String startsOn;
  final String endsOn;
  final int weeks;
  final String notes;
  final List<PlanDay> days;

  Map<String, dynamic> toJson() => {
    'id': id,
    'startsOn': startsOn,
    'endsOn': endsOn,
    'weeks': weeks,
    'notes': notes,
    'days': [for (final d in days) d.toJson()],
  };
}

/// A rule a rejected plan broke, as the server words it.
class PlanViolation {
  const PlanViolation({required this.rule, required this.message});

  static PlanViolation? tryParse(Object? v) {
    final j = _map(v);
    if (j == null) return null;
    return PlanViolation(rule: _str(j['rule']), message: _str(j['message']));
  }

  final String rule;
  final String message;
}

List<PlanViolation> parseViolations(Object? body) =>
    _list(_map(body)?['violations'], PlanViolation.tryParse);

/// Plan changes a person can ask for.
enum PlanChange {
  swap('swap', 'Swap an exercise', 'Which exercise?'),
  bodyweight('bodyweight', 'Bodyweight only for now', null),
  shorter('shorter', 'Shorter sessions', null),
  pain('pain', 'Something hurts', 'Where does it hurt?'),
  newBlock('new_block', 'New block', null);

  const PlanChange(this.wire, this.label, this.detailPrompt);

  final String wire;
  final String label;

  /// Set when the change needs a short detail from the person.
  final String? detailPrompt;
}

/// What the next session asks for on one exercise.
class SessionTarget {
  const SessionTarget({required this.exercise, this.sets = 0, this.amount = 0, this.loadKg});

  static SessionTarget parse(Object? v, String fallbackKey) {
    final j = _map(v) ?? const {};
    return SessionTarget(
      exercise: _str(j['exercise'], fallbackKey),
      sets: _int(j['sets']),
      amount: _int(j['amount']),
      loadKg: _double(j['loadKg']),
    );
  }

  final String exercise;
  final int sets;
  final int amount;
  final double? loadKg;

  Map<String, dynamic> toJson() => {
    'exercise': exercise,
    'sets': sets,
    'amount': amount,
    'loadKg': loadKg,
  };
}

class SessionExercise {
  const SessionExercise({
    required this.exercise,
    required this.name,
    this.measure = Measure.reps,
    this.load = LoadKind.bodyweight,
    required this.plan,
    this.planName = '',
    required this.target,
    this.reason = '',
    this.logged = const [],
  });

  static SessionExercise? tryParse(Object? v) {
    final j = _map(v);
    final key = _strOrNull(j?['exercise']);
    if (j == null || key == null) return null;
    return SessionExercise(
      exercise: key,
      name: _str(j['name'], key),
      measure: Measure.parse(j['measure']),
      load: LoadKind.parse(j['load']),
      plan: Prescription.tryParse(j['plan']) ?? Prescription(exercise: key),
      planName: _str(j['planName']),
      target: SessionTarget.parse(j['target'], key),
      reason: _str(j['reason']),
      logged: _list(j['logged'], ExerciseSet.tryParse),
    );
  }

  /// The exercise to do today: the planned one or the variation progression moved to.
  final String exercise;
  final String name;
  final Measure measure;
  final LoadKind load;
  final Prescription plan;

  /// The planned exercise's name, which differs from [name] after a move to a variation.
  final String planName;
  final SessionTarget target;
  final String reason;
  final List<ExerciseSet> logged;

  bool get timed => measure == Measure.seconds;
  bool get loaded => load == LoadKind.external;
  bool get complete => target.sets > 0 && logged.length >= target.sets;

  SessionExercise withLogged(List<ExerciseSet> sets) => SessionExercise(
    exercise: exercise,
    name: name,
    measure: measure,
    load: load,
    plan: plan,
    planName: planName,
    target: target,
    reason: reason,
    logged: sets,
  );

  Map<String, dynamic> toJson() => {
    'exercise': exercise,
    'name': name,
    'measure': measure.name,
    'load': load.name,
    'plan': plan.toJson(),
    'planName': planName,
    'target': target.toJson(),
    'reason': reason,
    'logged': [for (final s in logged) s.toJson()],
  };
}

class TrainingSession {
  const TrainingSession({
    required this.id,
    required this.date,
    required this.label,
    this.completed = false,
    this.exercises = const [],
    this.eased = false,
    this.easedReason = '',
  });

  static TrainingSession? tryParse(Object? v) {
    final j = _map(v);
    final id = _intOrNull(j?['id']);
    if (j == null || id == null) return null;
    return TrainingSession(
      id: id,
      date: _str(j['date']),
      label: _str(j['label'], 'Training'),
      completed: j['completed'] == true,
      exercises: _list(j['exercises'], SessionExercise.tryParse),
      eased: j['eased'] == true,
      easedReason: _str(j['easedReason']),
    );
  }

  final int id;
  final String date;
  final String label;
  final bool completed;
  final List<SessionExercise> exercises;

  /// True when an Easy readiness morning made the session one set lighter per exercise;
  /// [easedReason] says why in one line.
  final bool eased;
  final String easedReason;

  /// Whether "Do the full session" still applies: once a set is logged the session stays as it was.
  bool get canTakeFull => eased && !completed && setsLogged == 0;

  int get setsLogged => exercises.fold(0, (n, e) => n + e.logged.length);
  int get setsPlanned => exercises.fold(0, (n, e) => n + e.target.sets);

  TrainingSession copyWith({bool? completed, List<SessionExercise>? exercises}) => TrainingSession(
    id: id,
    date: date,
    label: label,
    completed: completed ?? this.completed,
    exercises: exercises ?? this.exercises,
    eased: eased,
    easedReason: easedReason,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'date': date,
    'label': label,
    'completed': completed,
    'exercises': [for (final e in exercises) e.toJson()],
    'eased': eased,
    'easedReason': easedReason,
  };
}

/// GET /training/today.
class TrainingToday {
  const TrainingToday({
    required this.date,
    this.plan,
    this.session,
    this.restDay = false,
    this.blockEnded = false,
  });

  static TrainingToday parse(Object? v) {
    final j = _map(v) ?? const {};
    return TrainingToday(
      date: _str(j['date']),
      plan: TrainingPlan.tryParse(j['plan']),
      session: TrainingSession.tryParse(j['session']),
      restDay: j['restDay'] == true,
      blockEnded: j['blockEnded'] == true,
    );
  }

  final String date;
  final TrainingPlan? plan;
  final TrainingSession? session;
  final bool restDay;
  final bool blockEnded;

  TrainingToday withSession(TrainingSession? session) => TrainingToday(
    date: date,
    plan: plan,
    session: session,
    restDay: restDay,
    blockEnded: blockEnded,
  );

  Map<String, dynamic> toJson() => {
    'date': date,
    'plan': plan?.toJson(),
    'session': session?.toJson(),
    'restDay': restDay,
    'blockEnded': blockEnded,
  };
}

class MuscleVolume {
  const MuscleVolume({required this.muscle, this.weeks = const []});

  static MuscleVolume? tryParse(Object? v) {
    final j = _map(v);
    final muscle = _strOrNull(j?['muscle']);
    if (j == null || muscle == null) return null;
    return MuscleVolume(
      muscle: muscle,
      weeks: [
        if (j['weeks'] is List)
          for (final w in j['weeks'] as List) _int(w),
      ],
    );
  }

  final String muscle;

  /// Hard sets per ISO week, oldest first, ending with this week.
  final List<int> weeks;

  int get thisWeek => weeks.isEmpty ? 0 : weeks.last;
}

/// GET /training/progress: weekly sets per muscle against the evidence range.
class TrainingProgress {
  const TrainingProgress({
    this.weeksStart = '',
    this.muscles = const [],
    this.rangeMin = 0,
    this.rangeMax = 0,
    this.rangeLabel = '',
    this.source = '',
  });

  static TrainingProgress parse(Object? v) {
    final j = _map(v) ?? const {};
    final range = _map(j['range']) ?? const {};
    return TrainingProgress(
      weeksStart: _str(j['weeksStart']),
      muscles: _list(j['muscles'], MuscleVolume.tryParse),
      rangeMin: _int(range['min']),
      rangeMax: _int(range['max']),
      rangeLabel: _str(range['label']),
      source: _str(range['source']),
    );
  }

  final String weeksStart;
  final List<MuscleVolume> muscles;
  final int rangeMin;
  final int rangeMax;
  final String rangeLabel;
  final String source;
}

/// A look-back's exercise: the month's best set against the first month it was logged.
class Lift {
  const Lift({
    required this.key,
    required this.name,
    required this.measure,
    required this.value,
    this.best,
    this.first,
    this.firstMonth,
  });

  static Lift? tryParse(Object? v) {
    final j = _map(v);
    final key = _strOrNull(j?['key']);
    final value = _double(j?['value']);
    if (j == null || key == null || value == null) return null;
    return Lift(
      key: key,
      name: _str(j['name'], key),
      measure: _str(j['measure'], 'reps'),
      value: value,
      best: SetAmount.tryParse(j['best']),
      first: _double(j['first']),
      firstMonth: _strOrNull(j['firstMonth']),
    );
  }

  final String key;
  final String name;

  /// reps, seconds or e1rm (kg).
  final String measure;
  final double value;
  final SetAmount? best;
  final double? first;
  final String? firstMonth;

  Map<String, dynamic> toJson() => {
    'key': key,
    'name': name,
    'measure': measure,
    'value': value,
    'best': best?.toJson(),
    'first': first,
    'firstMonth': firstMonth,
  };
}

List<Lift> parseLifts(Object? v) => _list(v, Lift.tryParse);
