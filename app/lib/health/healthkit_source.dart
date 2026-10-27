import 'dart:io';

import 'package:health/health.dart';

import 'fake_health_source.dart';
import 'health_source.dart';

HealthSource createPlatformHealthSource() =>
    Platform.isIOS ? HealthKitSource() : FakeHealthSource();

class HealthKitSource implements HealthSource {
  static const _types = [HealthDataType.STEPS, HealthDataType.ACTIVE_ENERGY_BURNED];

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
    return health.requestAuthorization(
      _types,
      permissions: const [HealthDataAccess.READ, HealthDataAccess.READ],
    );
  }

  @override
  Future<HealthTotals?> totals(DateTime start, DateTime end) async {
    final health = await _plugin();
    final steps = await health.getTotalStepsInInterval(start, end, includeManualEntry: false);
    if (steps == null) return null;
    return HealthTotals(steps: steps, activeEnergyKcal: await _activeEnergy(health, start, end));
  }

  /// One statistics bucket spanning the whole window, so HealthKit de-duplicates overlapping
  /// sources instead of the app summing raw samples.
  Future<double> _activeEnergy(Health health, DateTime start, DateTime end) async {
    final seconds = end.difference(start).inSeconds.clamp(1, 1 << 30);
    final points = await health.getHealthIntervalDataFromTypes(
      startDate: start,
      endDate: end,
      types: const [HealthDataType.ACTIVE_ENERGY_BURNED],
      interval: seconds,
      recordingMethodsToFilter: const [RecordingMethod.manual],
    );
    var total = 0.0;
    for (final point in points) {
      final value = point.value;
      if (value is NumericHealthValue) total += value.numericValue;
    }
    return total;
  }
}
