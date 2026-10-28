import '../api/models.dart';
import 'health_math.dart';

typedef Span = ({DateTime start, DateTime end});

/// HealthKit activity names (the package's `HealthWorkoutActivityType.name`) mapped onto the
/// workout types of docs/design-v4.md. Anything not listed is `other`.
const _workoutTypes = <String, String>{
  'WALKING': WorkoutType.walking,
  'WALKING_TREADMILL': WorkoutType.walking,
  'RUNNING': WorkoutType.running,
  'RUNNING_TREADMILL': WorkoutType.running,
  'BIKING': WorkoutType.cycling,
  'BIKING_STATIONARY': WorkoutType.cycling,
  'HAND_CYCLING': WorkoutType.cycling,
  'TRADITIONAL_STRENGTH_TRAINING': WorkoutType.strength,
  'FUNCTIONAL_STRENGTH_TRAINING': WorkoutType.strength,
  'STRENGTH_TRAINING': WorkoutType.strength,
  'WEIGHTLIFTING': WorkoutType.strength,
  'CORE_TRAINING': WorkoutType.strength,
  'HIGH_INTENSITY_INTERVAL_TRAINING': WorkoutType.hiit,
  'YOGA': WorkoutType.yoga,
  'PILATES': WorkoutType.yoga,
  'FLEXIBILITY': WorkoutType.yoga,
  'MIND_AND_BODY': WorkoutType.yoga,
  'SWIMMING': WorkoutType.swimming,
  'SWIMMING_POOL': WorkoutType.swimming,
  'SWIMMING_OPEN_WATER': WorkoutType.swimming,
  'HIKING': WorkoutType.hiking,
  'CARDIO_DANCE': WorkoutType.dance,
  'SOCIAL_DANCE': WorkoutType.dance,
  'DANCING': WorkoutType.dance,
  'CLIMBING': WorkoutType.climbing,
  'ROCK_CLIMBING': WorkoutType.climbing,
};

String workoutTypeFor(String activityName) => _workoutTypes[activityName] ?? WorkoutType.other;

/// The mean heart rate of [samples] that start inside [start, end), rounded; null with none.
int? meanHeartRate(Iterable<Sample> samples, DateTime start, DateTime end) {
  final inside = [
    for (final s in samples)
      if (!s.start.isBefore(start) && s.start.isBefore(end)) s,
  ];
  final mean = averageValue(inside);
  return mean?.round();
}

/// A positive reading rounded to whole units; Health reports 0 or nothing when it has no value.
int? _positive(num? v) => v == null || !v.isFinite || v <= 0 ? null : v.round();

/// Null for a workout too short to matter or without an id, since the server upserts on it.
WorkoutUpload? buildWorkout({
  required String id,
  required String activityName,
  required DateTime start,
  required DateTime end,
  required String source,
  num? kcal,
  num? distanceM,
  int? avgHr,
}) {
  final minutes = (end.difference(start).inSeconds / 60).round();
  if (id.isEmpty || minutes < 1) return null;
  return WorkoutUpload(
    id: id,
    type: workoutTypeFor(activityName),
    startedAt: start,
    endedAt: end,
    durationMin: minutes,
    kcal: _positive(kcal),
    distanceM: _positive(distanceM),
    avgHr: _positive(avgHr),
    source: source,
  );
}

/// The sleep samples of one night, grouped by the stage HealthKit reported.
class NightSamples {
  const NightSamples({
    this.asleep = const [],
    this.core = const [],
    this.deep = const [],
    this.rem = const [],
    this.awake = const [],
    this.inBed = const [],
  });

  /// Plain "asleep", reported by watches and apps that do not track stages.
  final List<Span> asleep;
  final List<Span> core;
  final List<Span> deep;
  final List<Span> rem;
  final List<Span> awake;
  final List<Span> inBed;

  Iterable<Span> get allAsleep => [...asleep, ...core, ...deep, ...rem];
}

/// The night that ends on [day]: 18:00 the evening before to 12:00 that day.
({DateTime from, DateTime to}) nightWindow(DateTime day) => (
  from: DateTime(day.year, day.month, day.day - 1, 18),
  to: DateTime(day.year, day.month, day.day, 12),
);

Span? _clip(Span s, DateTime from, DateTime to) {
  final start = s.start.isBefore(from) ? from : s.start;
  final end = s.end.isAfter(to) ? to : s.end;
  return end.isAfter(start) ? (start: start, end: end) : null;
}

/// One record for the night ending on [day], or null when no asleep sample falls inside it.
/// Stages are unioned so a watch and a phone recording the same night count once.
SleepNightUpload? buildNight({
  required DateTime day,
  required NightSamples samples,
  required String source,
}) {
  final (:from, :to) = nightWindow(day);
  final asleep = [for (final s in samples.allAsleep) ?_clip(s, from, to)];
  final asleepMin = coveredMinutes(asleep, from, to).round();
  if (asleepMin <= 0) return null;

  final inBed = [for (final s in samples.inBed) ?_clip(s, from, to)];
  final bedAt = [...asleep, ...inBed].map((s) => s.start).reduce((a, b) => a.isBefore(b) ? a : b);
  final wakeAt = asleep.map((s) => s.end).reduce((a, b) => a.isAfter(b) ? a : b);

  int minutes(List<Span> spans) => coveredMinutes(spans, bedAt, wakeAt).round();

  return SleepNightUpload(
    date: formatDate(day),
    bedAt: bedAt,
    wakeAt: wakeAt,
    asleepMin: asleepMin,
    deepMin: minutes(samples.deep),
    remMin: minutes(samples.rem),
    coreMin: minutes(samples.core),
    awakeMin: minutes(samples.awake),
    source: source,
  );
}

String formatDate(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

/// The samples of [all] that overlap the night ending on [day].
List<Span> spansInNight(Iterable<Span> all, DateTime day) {
  final (:from, :to) = nightWindow(day);
  return [
    for (final s in all)
      if (s.end.isAfter(from) && s.start.isBefore(to)) s,
  ];
}
