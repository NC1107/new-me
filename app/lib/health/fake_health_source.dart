import 'health_source.dart';

/// Stands in for HealthKit on web and in tests. Each call is recorded so tests can assert on them.
class FakeHealthSource implements HealthSource {
  FakeHealthSource({
    this.granted = true,
    int steps = 4321,
    double activeEnergyKcal = 287,
    Map<String, double>? metrics,
    this.latency = Duration.zero,
  }) : metrics = {
         ...defaults,
         HealthMetric.steps: steps.toDouble(),
         HealthMetric.activeEnergy: activeEnergyKcal,
         ...?metrics,
       };

  static const defaults = <String, double>{
    HealthMetric.steps: 4321,
    HealthMetric.activeEnergy: 287,
    HealthMetric.basalEnergy: 1650,
    HealthMetric.exerciseMinutes: 23,
    HealthMetric.distanceM: 3200,
    HealthMetric.flights: 6,
    HealthMetric.workouts: 1,
    HealthMetric.workoutMinutes: 34,
    HealthMetric.sleepMinutes: 432,
    HealthMetric.mindfulMinutes: 10,
    HealthMetric.waterMl: 1500,
    HealthMetric.restingHr: 58,
    HealthMetric.hrvMs: 46,
    HealthMetric.vo2max: 41.5,
    HealthMetric.weightKg: 82.4,
    HealthMetric.bodyFatPct: 18.2,
    HealthMetric.leanMassKg: 67.4,
  };

  bool granted;

  /// What every read answers with; remove a key to play a type with no data or no permission.
  final Map<String, double> metrics;

  int get steps => metrics[HealthMetric.steps]?.round() ?? 0;
  set steps(int v) => metrics[HealthMetric.steps] = v.toDouble();

  double get activeEnergyKcal => metrics[HealthMetric.activeEnergy] ?? 0;
  set activeEnergyKcal(double v) => metrics[HealthMetric.activeEnergy] = v;

  /// Lets a test hold a read open to exercise single-flight.
  Duration latency;

  /// Answers every read with null, like HealthKit does when it has nothing it may share.
  bool unreadable = false;

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
    if (unreadable) return null;
    return HealthTotals(metrics);
  }
}
