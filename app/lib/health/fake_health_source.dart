import 'health_source.dart';

/// Stands in for HealthKit on web and in tests. Each call is recorded so tests can assert on them.
class FakeHealthSource implements HealthSource {
  FakeHealthSource({
    this.granted = true,
    this.steps = 4321,
    this.activeEnergyKcal = 287,
    this.latency = Duration.zero,
  });

  bool granted;
  int steps;
  double activeEnergyKcal;

  /// Lets a test hold a read open to exercise single-flight.
  Duration latency;

  int accessRequests = 0;
  final List<({DateTime start, DateTime end})> reads = [];

  @override
  Future<bool> requestAccess() async {
    accessRequests++;
    return granted;
  }

  @override
  Future<HealthTotals?> totals(DateTime start, DateTime end) async {
    reads.add((start: start, end: end));
    if (latency > Duration.zero) await Future<void>.delayed(latency);
    return HealthTotals(steps: steps, activeEnergyKcal: activeEnergyKcal);
  }
}
