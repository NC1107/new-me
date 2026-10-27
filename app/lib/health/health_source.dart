import 'package:flutter/foundation.dart';

import '../api/models.dart';

/// The metric keys shared with the server; see docs/design-v2.md.
abstract final class HealthMetric {
  static const steps = 'steps';
  static const activeEnergy = 'active_energy';
  static const basalEnergy = 'basal_energy';
  static const exerciseMinutes = 'exercise_minutes';
  static const distanceM = 'distance_m';
  static const flights = 'flights';
  static const workouts = 'workouts';
  static const workoutMinutes = 'workout_minutes';
  static const sleepMinutes = 'sleep_minutes';
  static const mindfulMinutes = 'mindful_minutes';
  static const waterMl = 'water_ml';
  static const restingHr = 'resting_hr';
  static const hrvMs = 'hrv_ms';
  static const vo2max = 'vo2max';
  static const weightKg = 'weight_kg';
  static const bodyFatPct = 'body_fat_pct';
  static const leanMassKg = 'lean_mass_kg';

  static const all = [
    steps,
    activeEnergy,
    basalEnergy,
    exerciseMinutes,
    distanceM,
    flights,
    workouts,
    workoutMinutes,
    sleepMinutes,
    mindfulMinutes,
    waterMl,
    restingHr,
    hrvMs,
    vo2max,
    weightKg,
    bodyFatPct,
    leanMassKg,
  ];
}

/// The values Health holds for one window. A metric with no data, or one the person did not
/// share, is absent rather than zero.
@immutable
class HealthTotals {
  HealthTotals(Map<String, double> metrics) : metrics = Map.unmodifiable(metrics);

  final Map<String, double> metrics;

  bool get isEmpty => metrics.isEmpty;

  double? operator [](String key) => metrics[key];

  int? get steps => metrics[HealthMetric.steps]?.round();
  double? get activeEnergyKcal => metrics[HealthMetric.activeEnergy];

  @override
  bool operator ==(Object other) => other is HealthTotals && mapEquals(other.metrics, metrics);

  @override
  int get hashCode =>
      Object.hashAllUnordered(metrics.entries.map((e) => Object.hash(e.key, e.value)));
}

abstract interface class HealthSource {
  /// Shows the system permission sheet when it has not been shown yet.
  Future<bool> requestAccess();

  /// Metrics for the local day that starts at [start], read up to [end]; null when Health
  /// cannot be read at all.
  Future<HealthTotals?> totals(DateTime start, DateTime end);

  /// Workouts that started in [start, end); null when Health cannot be read at all.
  Future<List<WorkoutUpload>?> workouts(DateTime start, DateTime end);

  /// One record per night ending on a local date from [first] to [last] inclusive. Nights with no
  /// asleep data are left out; null when Health cannot be read at all.
  Future<List<SleepNightUpload>?> sleepNights(DateTime first, DateTime last);
}
