import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:health/health.dart';

import '../api/models.dart';
import 'fake_health_source.dart';
import 'health_math.dart';
import 'health_records.dart';
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

  /// Read for nights only; the daily sleep total leaves them out on purpose.
  static const _stageTypes = [HealthDataType.SLEEP_AWAKE, HealthDataType.SLEEP_IN_BED];

  static final _types = <HealthDataType>[
    HealthDataType.STEPS,
    for (final c in _cumulative.values) c.type,
    ..._pointInTime.values,
    ..._asleep,
    ..._stageTypes,
    HealthDataType.MINDFULNESS,
    HealthDataType.WORKOUT,
    HealthDataType.HEART_RATE,
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

  @override
  Future<List<WorkoutUpload>?> workouts(DateTime start, DateTime end) async {
    final health = await _plugin();
    final List<HealthDataPoint> raw;
    try {
      raw = await health.getHealthDataFromTypes(
        types: [HealthDataType.WORKOUT],
        startTime: start,
        endTime: end,
      );
    } on Object catch (e) {
      debugPrint('[NEWME] workouts unreadable: $e');
      return null;
    }
    final out = <WorkoutUpload>[];
    for (final p in raw) {
      final value = p.value;
      if (value is! WorkoutHealthValue || p.dateFrom.isBefore(start) || !p.dateFrom.isBefore(end)) {
        continue;
      }
      final workout = buildWorkout(
        id: p.uuid,
        activityName: value.workoutActivityType.name,
        start: p.dateFrom,
        end: p.dateTo,
        source: p.sourceName,
        kcal: value.totalEnergyBurned,
        distanceM: value.totalDistance,
        avgHr: await _meanHeartRate(health, p.dateFrom, p.dateTo),
      );
      if (workout != null) out.add(workout);
    }
    return out;
  }

  /// A separate read per workout; a failure only costs that workout its heart rate.
  Future<int?> _meanHeartRate(Health health, DateTime start, DateTime end) async {
    try {
      final samples = await _numeric(health, HealthDataType.HEART_RATE, start, end);
      return meanHeartRate(samples, start, end);
    } on Object catch (e) {
      debugPrint('[NEWME] heart rate unreadable: $e');
      return null;
    }
  }

  @override
  Future<List<SleepNightUpload>?> sleepNights(DateTime first, DateTime last) async {
    final health = await _plugin();
    final from = nightWindow(first).from;
    final to = nightWindow(last).to;
    final byType = <HealthDataType, List<HealthDataPoint>>{};
    var readable = false;
    for (final type in [..._asleep, ..._stageTypes]) {
      try {
        byType[type] = await health.getHealthDataFromTypes(
          types: [type],
          startTime: from,
          endTime: to,
        );
        readable = true;
      } on Object catch (e) {
        debugPrint('[NEWME] sleep $type unreadable: $e');
      }
    }
    if (!readable) return null;

    List<Span> spans(HealthDataType type) => [
      for (final p in byType[type] ?? const <HealthDataPoint>[]) (start: p.dateFrom, end: p.dateTo),
    ];
    final asleep = spans(HealthDataType.SLEEP_ASLEEP);
    final core = spans(HealthDataType.SLEEP_LIGHT);
    final deep = spans(HealthDataType.SLEEP_DEEP);
    final rem = spans(HealthDataType.SLEEP_REM);
    final awake = spans(HealthDataType.SLEEP_AWAKE);
    final inBed = spans(HealthDataType.SLEEP_IN_BED);
    final sourceName = [for (final t in _asleep) ...?byType[t]]
        .map((p) => p.sourceName)
        .firstOrNull;

    final nights = <SleepNightUpload>[];
    for (var day = first; !day.isAfter(last); day = DateTime(day.year, day.month, day.day + 1)) {
      final night = buildNight(
        day: day,
        source: sourceName ?? 'healthkit',
        samples: NightSamples(
          asleep: spansInNight(asleep, day),
          core: spansInNight(core, day),
          deep: spansInNight(deep, day),
          rem: spansInNight(rem, day),
          awake: spansInNight(awake, day),
          inBed: spansInNight(inBed, day),
        ),
      );
      if (night != null) nights.add(night);
    }
    return nights;
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
