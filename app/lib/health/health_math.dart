/// A timed value read from Health, free of the plugin types so the maths can be tested.
typedef Sample = ({DateTime start, DateTime end, double value});

/// Minutes covered by [samples] inside [from, to). Overlaps count once, because a watch and a
/// phone can both record the same night.
double coveredMinutes(
  Iterable<({DateTime start, DateTime end})> samples,
  DateTime from,
  DateTime to,
) {
  final clipped = [
    for (final s in samples)
      (start: s.start.isBefore(from) ? from : s.start, end: s.end.isAfter(to) ? to : s.end),
  ].where((s) => s.end.isAfter(s.start)).toList()..sort((a, b) => a.start.compareTo(b.start));
  var total = Duration.zero;
  DateTime? runStart;
  DateTime? runEnd;
  for (final s in clipped) {
    if (runEnd != null && !s.start.isAfter(runEnd)) {
      if (s.end.isAfter(runEnd)) runEnd = s.end;
      continue;
    }
    if (runStart != null) total += runEnd!.difference(runStart);
    runStart = s.start;
    runEnd = s.end;
  }
  if (runStart != null) total += runEnd!.difference(runStart);
  return total.inMicroseconds / Duration.microsecondsPerMinute;
}

/// The value of the sample that ended last.
double? latestValue(Iterable<Sample> samples) {
  Sample? latest;
  for (final s in samples) {
    if (latest == null || s.end.isAfter(latest.end)) latest = s;
  }
  return latest?.value;
}

double? averageValue(Iterable<Sample> samples) {
  if (samples.isEmpty) return null;
  return samples.fold<double>(0, (a, s) => a + s.value) / samples.length;
}

/// HealthKit reports body fat as a fraction (0.182); the server stores percent.
double bodyFatPercent(double raw) => raw <= 1 ? raw * 100 : raw;

/// HealthKit reports height in metres; the server takes 100 to 250 cm and a reading outside that
/// is dropped rather than clamped, because it is a typing slip and not a height.
double? heightCm(double metres) {
  final cm = metres * 100;
  return cm >= 100 && cm <= 250 ? cm : null;
}

/// Reads each metric on its own, so one that throws only drops itself.
Future<Map<String, double>> readEach(
  Map<String, Future<double?> Function()> readers, {
  void Function(String key, Object error)? onError,
}) async {
  final out = <String, double>{};
  for (final entry in readers.entries) {
    try {
      final value = await entry.value();
      if (value != null && value.isFinite) out[entry.key] = value;
    } on Object catch (e) {
      onError?.call(entry.key, e);
    }
  }
  return out;
}
