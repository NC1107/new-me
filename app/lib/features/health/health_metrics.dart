import 'package:flutter/material.dart';

import '../../health/health_source.dart';
import '../../theme/accent.dart';
import '../../util/format.dart';
import '../../util/units.dart';

/// "7 h 12 min", "45 min" or "2 h".
String formatDuration(num minutes) {
  final total = minutes.round();
  final h = total ~/ 60;
  final m = total % 60;
  if (h == 0) return '$m min';
  return m == 0 ? '$h h' : '$h h $m min';
}

String _plural(num v, String one, String many) => '${v.formatted} ${v.round() == 1 ? one : many}';

String _tenths(num v) => double.parse(v.toStringAsFixed(1)).formatted;

/// A metric Apple Health supplies: what to call it, where it sits and how a number reads.
class HealthMetricSpec {
  const HealthMetricSpec({
    required this.key,
    required this.name,
    required this.icon,
    required this.format,
    this.imperial,
  });

  final String key;
  final String name;
  final IconData icon;

  /// "82.4 kg": the value in the stored metric unit.
  final String Function(num value) format;

  /// "181.7 lb": the same value for an imperial person, when the metric word differs.
  final String Function(num value)? imperial;

  /// The value the way the person reads it.
  String display(num value, Units units) =>
      units.isImperial && imperial != null ? imperial!(value) : format(value);
}

/// A band of the Health list, matching the groups onboarding shows.
class HealthGroup {
  const HealthGroup({
    required this.name,
    required this.icon,
    required this.paletteId,
    required this.metrics,
  });

  final String name;
  final IconData icon;
  final String paletteId;
  final List<HealthMetricSpec> metrics;

  AccentPalette get palette => accentById(paletteId);
}

final kHealthGroups = <HealthGroup>[
  HealthGroup(
    name: 'Activity',
    icon: Icons.directions_run_rounded,
    paletteId: 'sky',
    metrics: [
      HealthMetricSpec(
        key: HealthMetric.steps,
        name: 'Steps',
        icon: Icons.directions_walk_rounded,
        format: (v) => _plural(v, 'step', 'steps'),
      ),
      HealthMetricSpec(
        key: HealthMetric.distanceM,
        name: 'Distance',
        icon: Icons.route_rounded,
        format: (v) => v < 1000 ? '${v.round()} m' : '${_tenths(v / 1000)} km',
        imperial: (v) => v < 160.9 ? '${(v / 0.9144).round()} yd' : '${_tenths(v / 1609.344)} mi',
      ),
      HealthMetricSpec(
        key: HealthMetric.flights,
        name: 'Flights climbed',
        icon: Icons.stairs_rounded,
        format: (v) => _plural(v, 'flight', 'flights'),
      ),
      HealthMetricSpec(
        key: HealthMetric.activeEnergy,
        name: 'Active energy',
        icon: Icons.bolt_rounded,
        format: (v) => '${v.round().formatted} kcal',
      ),
      HealthMetricSpec(
        key: HealthMetric.basalEnergy,
        name: 'Resting energy',
        icon: Icons.local_fire_department_rounded,
        format: (v) => '${v.round().formatted} kcal',
      ),
    ],
  ),
  HealthGroup(
    name: 'Workouts',
    icon: Icons.fitness_center_rounded,
    paletteId: 'rose',
    metrics: [
      const HealthMetricSpec(
        key: HealthMetric.exerciseMinutes,
        name: 'Exercise',
        icon: Icons.timer_rounded,
        format: formatDuration,
      ),
      HealthMetricSpec(
        key: HealthMetric.workouts,
        name: 'Workouts',
        icon: Icons.sports_gymnastics_rounded,
        format: (v) => _plural(v, 'workout', 'workouts'),
      ),
      const HealthMetricSpec(
        key: HealthMetric.workoutMinutes,
        name: 'Workout time',
        icon: Icons.hourglass_bottom_rounded,
        format: formatDuration,
      ),
    ],
  ),
  const HealthGroup(
    name: 'Sleep',
    icon: Icons.bedtime_rounded,
    paletteId: 'violet',
    metrics: [
      HealthMetricSpec(
        key: HealthMetric.sleepMinutes,
        name: 'Sleep',
        icon: Icons.bedtime_rounded,
        format: formatDuration,
      ),
    ],
  ),
  HealthGroup(
    name: 'Heart',
    icon: Icons.favorite_rounded,
    paletteId: 'amber',
    metrics: [
      HealthMetricSpec(
        key: HealthMetric.restingHr,
        name: 'Resting heart rate',
        icon: Icons.favorite_rounded,
        format: (v) => '${v.round()} bpm',
      ),
      HealthMetricSpec(
        key: HealthMetric.hrvMs,
        name: 'Heart rate variability',
        icon: Icons.monitor_heart_rounded,
        format: (v) => '${v.round()} ms',
      ),
      HealthMetricSpec(
        key: HealthMetric.vo2max,
        name: 'VO2 max',
        icon: Icons.air_rounded,
        format: (v) => '${_tenths(v)} ml/kg/min',
      ),
    ],
  ),
  HealthGroup(
    name: 'Body',
    icon: Icons.monitor_weight_rounded,
    paletteId: 'teal',
    metrics: [
      HealthMetricSpec(
        key: HealthMetric.weightKg,
        name: 'Weight',
        icon: Icons.monitor_weight_rounded,
        format: (v) => '${_tenths(v)} kg',
        imperial: (v) => '${_tenths(v / kKgPerLb)} lb',
      ),
      HealthMetricSpec(
        key: HealthMetric.bodyFatPct,
        name: 'Body fat',
        icon: Icons.percent_rounded,
        format: (v) => '${_tenths(v)}%',
      ),
      HealthMetricSpec(
        key: HealthMetric.leanMassKg,
        name: 'Lean mass',
        icon: Icons.accessibility_new_rounded,
        format: (v) => '${_tenths(v)} kg',
        imperial: (v) => '${_tenths(v / kKgPerLb)} lb',
      ),
    ],
  ),
  HealthGroup(
    name: 'Mindfulness and water',
    icon: Icons.spa_rounded,
    paletteId: 'green',
    metrics: [
      const HealthMetricSpec(
        key: HealthMetric.mindfulMinutes,
        name: 'Mindful minutes',
        icon: Icons.self_improvement_rounded,
        format: formatDuration,
      ),
      HealthMetricSpec(
        key: HealthMetric.waterMl,
        name: 'Water',
        icon: Icons.water_drop_rounded,
        format: (v) => v < 1000 ? '${v.round()} ml' : '${_tenths(v / 1000)} L',
      ),
    ],
  ),
];

HealthMetricSpec? healthMetricSpec(String key) {
  for (final g in kHealthGroups) {
    for (final m in g.metrics) {
      if (m.key == key) return m;
    }
  }
  return null;
}

HealthGroup healthGroupOf(String key) =>
    kHealthGroups.firstWhere((g) => g.metrics.any((m) => m.key == key));
