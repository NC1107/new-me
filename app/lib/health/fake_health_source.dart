import '../api/models.dart';
import 'health_records.dart';
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

  /// Replaces the generated workouts; remove the list's items to play an empty Health.
  List<WorkoutUpload>? workoutList;

  /// Replaces the generated nights.
  List<SleepNightUpload>? nightList;

  /// Answers null for workouts, like HealthKit does when the type cannot be read.
  bool workoutsUnreadable = false;
  bool sleepUnreadable = false;

  int workoutReads = 0;
  int sleepReads = 0;

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

  @override
  Future<List<WorkoutUpload>?> workouts(DateTime start, DateTime end) async {
    workoutReads++;
    if (latency > Duration.zero) await Future<void>.delayed(latency);
    if (workoutsUnreadable) return null;
    final all = workoutList ?? sampleWorkouts(end);
    return [
      for (final w in all)
        if (!w.startedAt.isBefore(start) && w.startedAt.isBefore(end)) w,
    ];
  }

  @override
  Future<List<SleepNightUpload>?> sleepNights(DateTime first, DateTime last) async {
    sleepReads++;
    if (latency > Duration.zero) await Future<void>.delayed(latency);
    if (sleepUnreadable) return null;
    final all = nightList ?? sampleNights(last);
    final firstDate = formatDate(first);
    final lastDate = formatDate(last);
    return [
      for (final n in all)
        if (n.date.compareTo(firstDate) >= 0 && n.date.compareTo(lastDate) <= 0) n,
    ];
  }

  /// A run, a strength session and a walk in the week before [now], with ids stable per day.
  static List<WorkoutUpload> sampleWorkouts(DateTime now) {
    DateTime at(int daysAgo, int hour, int minute) =>
        DateTime(now.year, now.month, now.day - daysAgo, hour, minute);
    WorkoutUpload make(
      String kind,
      String type,
      DateTime start,
      int min,
      int kcal,
      int? m,
      int hr,
    ) {
      return WorkoutUpload(
        id: 'fake-$kind-${formatDate(start)}',
        type: type,
        startedAt: start,
        endedAt: start.add(Duration(minutes: min)),
        durationMin: min,
        kcal: kcal,
        distanceM: m,
        avgHr: hr,
        source: 'Apple Watch',
      );
    }

    return [
      make('run', WorkoutType.running, at(1, 7, 10), 34, 362, 5480, 158),
      make('strength', WorkoutType.strength, at(3, 18, 5), 52, 281, null, 118),
      make('walk', WorkoutType.walking, at(5, 12, 30), 41, 168, 3350, 104),
    ];
  }

  /// Fourteen nights ending on [last], with bedtimes drifting around 23:00 and a few short ones.
  static List<SleepNightUpload> sampleNights(DateTime last) {
    const bedOffsets = [-10, 25, 5, 40, -5, 70, 55, 0, 15, 30, -15, 20, 45, 10];
    const asleepMins = [452, 418, 441, 389, 463, 352, 371, 448, 430, 405, 470, 426, 380, 437];
    return [
      for (var i = 0; i < 14; i++)
        () {
          final day = DateTime(last.year, last.month, last.day - 13 + i);
          final bed = DateTime(
            day.year,
            day.month,
            day.day - 1,
            23,
          ).add(Duration(minutes: bedOffsets[i]));
          final asleep = asleepMins[i];
          final awake = 18 + (i * 7) % 20;
          final deep = (asleep * 0.16).round();
          final rem = (asleep * 0.22).round();
          return SleepNightUpload(
            date: formatDate(day),
            bedAt: bed,
            wakeAt: bed.add(Duration(minutes: asleep + awake + 6)),
            asleepMin: asleep,
            deepMin: deep,
            remMin: rem,
            coreMin: asleep - deep - rem,
            awakeMin: awake,
            source: 'Apple Watch',
          );
        }(),
    ];
  }
}
