import 'package:flutter/foundation.dart';

@immutable
class HealthTotals {
  const HealthTotals({required this.steps, required this.activeEnergyKcal});

  final int steps;
  final double activeEnergyKcal;

  @override
  bool operator ==(Object other) =>
      other is HealthTotals && other.steps == steps && other.activeEnergyKcal == activeEnergyKcal;

  @override
  int get hashCode => Object.hash(steps, activeEnergyKcal);
}

abstract interface class HealthSource {
  /// Shows the system permission sheet when it has not been shown yet.
  Future<bool> requestAccess();

  /// Totals for [start, end), or null when Health cannot be read.
  Future<HealthTotals?> totals(DateTime start, DateTime end);
}
