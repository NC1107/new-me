import 'package:flutter_test/flutter_test.dart';
import 'package:newme/health/health_math.dart';
import 'package:newme/health/health_source.dart';

DateTime _t(int day, int hour, [int minute = 0]) => DateTime(2026, 10, day, hour, minute);

void main() {
  group('coveredMinutes', () {
    test('sums disjoint spans', () {
      final minutes = coveredMinutes(
        [(start: _t(25, 23), end: _t(26, 2)), (start: _t(26, 3), end: _t(26, 5, 30))],
        _t(25, 18),
        _t(26, 12),
      );
      expect(minutes, 330);
    });

    test('counts overlapping sources once', () {
      final minutes = coveredMinutes(
        [
          (start: _t(25, 23), end: _t(26, 3)),
          (start: _t(26, 1), end: _t(26, 6)),
          (start: _t(26, 2), end: _t(26, 4)),
        ],
        _t(25, 18),
        _t(26, 12),
      );
      expect(minutes, 420);
    });

    test('clips to the window', () {
      final minutes = coveredMinutes(
        [(start: _t(25, 16), end: _t(25, 19)), (start: _t(26, 11), end: _t(26, 14))],
        _t(25, 18),
        _t(26, 12),
      );
      expect(minutes, 120);
    });

    test('nothing in the window is zero', () {
      expect(coveredMinutes([(start: _t(24, 1), end: _t(24, 2))], _t(25, 18), _t(26, 12)), 0);
      expect(coveredMinutes(const [], _t(25, 18), _t(26, 12)), 0);
    });
  });

  test('latestValue picks the sample that ended last, not the last listed', () {
    expect(
      latestValue([
        (start: _t(26, 8), end: _t(26, 8, 1), value: 82.0),
        (start: _t(26, 7), end: _t(26, 7, 1), value: 83.0),
      ]),
      82.0,
    );
    expect(latestValue(const []), isNull);
  });

  test('averageValue', () {
    expect(
      averageValue([
        (start: _t(26, 1), end: _t(26, 1), value: 40),
        (start: _t(26, 2), end: _t(26, 2), value: 52),
      ]),
      46,
    );
    expect(averageValue(const []), isNull);
  });

  test('body fat fractions become percent, percent values are kept', () {
    expect(bodyFatPercent(0.182), closeTo(18.2, 1e-9));
    expect(bodyFatPercent(18.2), 18.2);
  });

  group('readEach', () {
    test('a type that throws is omitted and the others still read', () async {
      final failed = <String>[];
      final out = await readEach({
        HealthMetric.steps: () async => 100,
        HealthMetric.sleepMinutes: () async => throw StateError('denied'),
        HealthMetric.waterMl: () async => 250,
      }, onError: (key, _) => failed.add(key));
      expect(out, {'steps': 100, 'water_ml': 250});
      expect(failed, ['sleep_minutes']);
    });

    test('null and non-finite readings are omitted', () async {
      final out = await readEach({
        HealthMetric.steps: () async => null,
        HealthMetric.flights: () async => double.nan,
        HealthMetric.workouts: () async => 0,
      });
      expect(out, {'workouts': 0});
    });
  });
}
