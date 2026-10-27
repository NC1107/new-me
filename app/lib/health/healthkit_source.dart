import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:health/health.dart';

import 'fake_health_source.dart';
import 'health_math.dart';
import 'health_source.dart';

HealthSource createPlatformHealthSource() =>
    Platform.isIOS ? HealthKitSource() : FakeHealthSource();

class HealthKitSource implements HealthSource {
  /// Summed over the day; one statistics bucket lets HealthKit de-duplicate overlapping sources.
  /// Water is mostly typed in by hand, so manual entries stay for it only.
  static const _cumulative = <String, ({HealthDataType type, double scale, bool manual})>{
    HealthMetric.activeEnergy: (type: HealthDataType.ACTIVE_ENERGY_BURNED, scale: 1, manual: false),
    HealthMetric.basalEnergy: (type: HealthDataType.BASAL_ENERGY_BURNED, scale: 1, manual: false),
    HealthMetric.exerciseMinutes: (type: HealthDataType.EXERCISE_TIME, scale: 1, manual: false),
    HealthMetric.distanceM: (
      type: HealthDataType.DISTANCE_WALKING_RUNNING,
      scale: 1,
      manual: false,
    ),
    HealthMetric.flights: (type: HealthDataType.FLIGHTS_CLIMBED, scale: 1, manual: false),
    // The package reads dietary water in litres.
    HealthMetric.waterMl: (type: HealthDataType.WATER, scale: 1000, manual: true),
  };

  /// Weight, body fat and lean mass are often logged by hand, so manual entries count.
  static const _pointInTime = <String, HealthDataType>{
    HealthMetric.restingHr: HealthDataType.RESTING_HEART_RATE,
    HealthMetric.hrvMs: HealthDataType.HEART_RATE_VARIABILITY_SDNN,
    HealthMetric.weightKg: HealthDataType.WEIGHT,
    HealthMetric.bodyFatPct: HealthDataType.BODY_FAT_PERCENTAGE,
    HealthMetric.leanMassKg: HealthDataType.LEAN_BODY_MASS,
  };

  /// Core is the package's SLEEP_LIGHT. In-bed and awake are left out on purpose.
  static const _asleep = [
    HealthDataType.SLEEP_ASLEEP,
    HealthDataType.SLEEP_LIGHT,
    HealthDataType.SLEEP_DEEP,
    HealthDataType.SLEEP_REM,
  ];

  static final _types = <HealthDataType>[
    HealthDataType.STEPS,
    for (final c in _cumulative.values) c.type,
    ..._pointInTime.values,
    ..._asleep,
    HealthDataType.MINDFULNESS,
    HealthDataType.WORKOUT,
  ];

  /// health 13.3.2 has no VO2 max type, so a small bridge in AppDelegate.swift reads it.
  static const _vo2max = MethodChannel('newme/vo2max');

  Health? _health;
  Future<void>? _configured;

  Future<Health> _plugin() async {
    final health = _health ??= Health();
    await (_configured ??= health.configure());
    return health;
  }

  @override
  Future<bool> requestAccess() async {
    final health = await _plugin();
    final granted = await health.requestAuthorization(
      _types,
      permissions: List.filled(_types.length, HealthDataAccess.READ),
    );
    try {
      await _vo2max.invokeMethod<bool>('requestAccess');
    } on PlatformException catch (e) {
      debugPrint('[NEWME] VO2 max access request failed: $e');
    }
    return granted;
  }

  @override
  Future<HealthTotals?> totals(DateTime start, DateTime end) async {
    final health = await _plugin();
    final metrics = await readEach({
      HealthMetric.steps: () async {
        final steps = await health.getTotalStepsInInterval(start, end, includeManualEntry: false);
        return steps?.toDouble();
      },
      for (final e in _cumulative.entries)
        e.key: () => _sum(health, e.value.type, start, end, e.value.scale, e.value.manual),
      for (final e in _pointInTime.entries)
        e.key: () => _pointValue(health, e.key, e.value, start, end),
      HealthMetric.sleepMinutes: () => _sleep(health, start),
      HealthMetric.vo2max: () async {
        final value = await _vo2max.invokeMethod<num>('latest', {
          'startMs': start.millisecondsSinceEpoch,
          'endMs': end.millisecondsSinceEpoch,
        });
        return value?.toDouble();
      },
      HealthMetric.mindfulMinutes: () async {
        final points = await _points(health, [HealthDataType.MINDFULNESS], start, end);
        final minutes = coveredMinutes(points, start, end);
        return minutes > 0 ? minutes : null;
      },
      HealthMetric.workouts: () async => _workoutCount(await _workouts(health, start, end)),
      HealthMetric.workoutMinutes: () async {
        final workouts = await _workouts(health, start, end);
        final minutes = workouts.fold<double>(
          0,
          (a, w) => a + w.end.difference(w.start).inSeconds / 60,
        );
        return minutes > 0 ? minutes : null;
      },
    }, onError: (key, e) => debugPrint('[NEWME] health $key unreadable: $e'));
    return HealthTotals(metrics);
  }

  double? _workoutCount(List<({DateTime start, DateTime end})> workouts) =>
      workouts.isEmpty ? null : workouts.length.toDouble();

  Future<double?> _sum(
    Health health,
    HealthDataType type,
    DateTime start,
    DateTime end,
    double scale,
    bool manual,
  ) async {
    final seconds = end.difference(start).inSeconds.clamp(1, 1 << 30);
    final points = await health.getHealthIntervalDataFromTypes(
      startDate: start,
      endDate: end,
      types: [type],
      interval: seconds,
      recordingMethodsToFilter: manual ? const [] : const [RecordingMethod.manual],
    );
    double? total;
    for (final point in points) {
      final value = point.value;
      if (value is NumericHealthValue) total = (total ?? 0) + value.numericValue * scale;
    }
    return total;
  }

  Future<double?> _pointValue(
    Health health,
    String key,
    HealthDataType type,
    DateTime start,
    DateTime end,
  ) async {
    final points = await _numeric(health, type, start, end);
    if (key == HealthMetric.hrvMs) return averageValue(points);
    final latest = latestValue(points);
    if (latest == null) return null;
    return key == HealthMetric.bodyFatPct ? bodyFatPercent(latest) : latest;
  }

  /// The night that ends on [day]: 18:00 the evening before to 12:00 that day.
  Future<double?> _sleep(Health health, DateTime day) async {
    final from = DateTime(day.year, day.month, day.day - 1, 18);
    final to = DateTime(day.year, day.month, day.day, 12);
    final points = await _points(health, _asleep, from, to);
    final minutes = coveredMinutes(points, from, to);
    return minutes > 0 ? minutes : null;
  }

  Future<List<({DateTime start, DateTime end})>> _workouts(
    Health health,
    DateTime start,
    DateTime end,
  ) async {
    final points = await _points(health, [HealthDataType.WORKOUT], start, end);
    return [
      for (final p in points)
        if (!p.start.isBefore(start) && p.start.isBefore(end)) p,
    ];
  }

  Future<List<({DateTime start, DateTime end})>> _points(
    Health health,
    List<HealthDataType> types,
    DateTime start,
    DateTime end,
  ) async {
    final raw = await health.getHealthDataFromTypes(types: types, startTime: start, endTime: end);
    return [for (final p in raw) (start: p.dateFrom, end: p.dateTo)];
  }

  Future<List<Sample>> _numeric(
    Health health,
    HealthDataType type,
    DateTime start,
    DateTime end,
  ) async {
    final raw = await health.getHealthDataFromTypes(types: [type], startTime: start, endTime: end);
    return [
      for (final p in raw)
        if (p.value is NumericHealthValue &&
            !p.dateFrom.isBefore(start) &&
            p.dateFrom.isBefore(end))
          (
            start: p.dateFrom,
            end: p.dateTo,
            value: (p.value as NumericHealthValue).numericValue.toDouble(),
          ),
    ];
  }
}
