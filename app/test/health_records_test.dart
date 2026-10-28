import 'package:flutter_test/flutter_test.dart';
import 'package:newme/api/models.dart';
import 'package:newme/health/health_math.dart';
import 'package:newme/health/health_records.dart';

Span span(DateTime start, int minutes) =>
    (start: start, end: start.add(Duration(minutes: minutes)));

void main() {
  group('workoutTypeFor', () {
    test('maps HealthKit activity names onto the documented types', () {
      const expected = {
        'WALKING': 'walking',
        'RUNNING': 'running',
        'BIKING': 'cycling',
        'TRADITIONAL_STRENGTH_TRAINING': 'strength',
        'FUNCTIONAL_STRENGTH_TRAINING': 'strength',
        'CORE_TRAINING': 'strength',
        'HIGH_INTENSITY_INTERVAL_TRAINING': 'hiit',
        'YOGA': 'yoga',
        'PILATES': 'yoga',
        'FLEXIBILITY': 'yoga',
        'MIND_AND_BODY': 'yoga',
        'SWIMMING': 'swimming',
        'HIKING': 'hiking',
        'SOCIAL_DANCE': 'dance',
        'CARDIO_DANCE': 'dance',
        'CLIMBING': 'climbing',
        'TENNIS': 'other',
        'OTHER': 'other',
        'SOMETHING_NEW': 'other',
      };
      for (final e in expected.entries) {
        expect(workoutTypeFor(e.key), e.value, reason: e.key);
      }
      expect(expected.values.toSet().difference(WorkoutType.all.toSet()), isEmpty);
    });
  });

  group('meanHeartRate', () {
    final start = DateTime(2026, 10, 26, 7);
    final end = DateTime(2026, 10, 26, 8);
    Sample hr(DateTime at, double v) => (start: at, end: at, value: v);

    test('averages samples inside the workout and rounds', () {
      final samples = [
        hr(start, 120),
        hr(start.add(const Duration(minutes: 30)), 151),
        hr(start.subtract(const Duration(minutes: 1)), 60),
        hr(end, 60),
      ];
      expect(meanHeartRate(samples, start, end), 136);
    });

    test('is null with no samples in the window', () {
      expect(meanHeartRate(const [], start, end), isNull);
      expect(meanHeartRate([hr(end, 90)], start, end), isNull);
    });
  });

  group('buildWorkout', () {
    final start = DateTime(2026, 10, 26, 7);

    test('fills the contract fields', () {
      final w = buildWorkout(
        id: 'U-1',
        activityName: 'RUNNING',
        start: start,
        end: start.add(const Duration(minutes: 34, seconds: 20)),
        source: 'Apple Watch',
        kcal: 361.6,
        distanceM: 5480,
        avgHr: 158,
      )!;
      expect(w.toJson(), {
        'id': 'U-1',
        'type': 'running',
        'startedAt': start.toUtc().toIso8601String(),
        'endedAt': start.add(const Duration(minutes: 34, seconds: 20)).toUtc().toIso8601String(),
        'durationMin': 34,
        'kcal': 362,
        'distanceM': 5480,
        'avgHr': 158,
        'source': 'Apple Watch',
      });
    });

    test('zero or missing energy, distance and heart rate become null', () {
      final w = buildWorkout(
        id: 'U-2',
        activityName: 'YOGA',
        start: start,
        end: start.add(const Duration(minutes: 20)),
        source: 'Fitness',
        kcal: 0,
        distanceM: null,
      )!;
      expect(w.kcal, isNull);
      expect(w.distanceM, isNull);
      expect(w.avgHr, isNull);
      expect(w.toJson()['kcal'], isNull);
    });

    test('drops a workout without an id or under a minute', () {
      expect(
        buildWorkout(
          id: '',
          activityName: 'RUNNING',
          start: start,
          end: start.add(const Duration(hours: 1)),
          source: 's',
        ),
        isNull,
      );
      expect(
        buildWorkout(
          id: 'x',
          activityName: 'RUNNING',
          start: start,
          end: start.add(const Duration(seconds: 20)),
          source: 's',
        ),
        isNull,
      );
    });
  });

  group('buildNight', () {
    final day = DateTime(2026, 10, 26);
    final evening = DateTime(2026, 10, 25, 23);

    test('unions stages, finds bed and wake and counts awake time', () {
      final night = buildNight(
        day: day,
        source: 'Apple Watch',
        samples: NightSamples(
          inBed: [span(DateTime(2026, 10, 25, 22, 50), 480)],
          core: [span(evening, 120), span(evening.add(const Duration(minutes: 150)), 200)],
          deep: [span(evening.add(const Duration(minutes: 120)), 30)],
          rem: [span(evening.add(const Duration(minutes: 350)), 60)],
          awake: [span(evening.add(const Duration(minutes: 410)), 10)],
        ),
      )!;
      expect(night.date, '2026-10-26');
      expect(night.bedAt, DateTime(2026, 10, 25, 22, 50));
      expect(night.wakeAt, evening.add(const Duration(minutes: 410)));
      expect(night.asleepMin, 410);
      expect(night.deepMin, 30);
      expect(night.remMin, 60);
      expect(night.coreMin, 320);
      expect(night.awakeMin, 0);
      expect(night.source, 'Apple Watch');
    });

    test('overlapping asleep samples from two devices count once', () {
      final night = buildNight(
        day: day,
        source: 's',
        samples: NightSamples(
          asleep: [span(evening, 400), span(evening.add(const Duration(minutes: 30)), 400)],
        ),
      )!;
      expect(night.asleepMin, 430);
      expect(night.bedAt, evening);
      expect(night.wakeAt, evening.add(const Duration(minutes: 430)));
    });

    test('plain asleep leaves the stage minutes at zero', () {
      final night = buildNight(
        day: day,
        source: 's',
        samples: NightSamples(asleep: [span(evening, 420)]),
      )!;
      expect([night.deepMin, night.remMin, night.coreMin, night.awakeMin], [0, 0, 0, 0]);
    });

    test('awake inside the night is counted but awake after waking is not', () {
      final night = buildNight(
        day: day,
        source: 's',
        samples: NightSamples(
          core: [span(evening, 200), span(evening.add(const Duration(minutes: 230)), 200)],
          awake: [
            span(evening.add(const Duration(minutes: 200)), 30),
            span(evening.add(const Duration(minutes: 440)), 15),
          ],
        ),
      )!;
      expect(night.awakeMin, 30);
      expect(night.asleepMin, 400);
    });

    test('is clipped to 18:00 the evening before and 12:00', () {
      final night = buildNight(
        day: day,
        source: 's',
        samples: NightSamples(
          asleep: [span(DateTime(2026, 10, 25, 17), 120), span(DateTime(2026, 10, 26, 11), 120)],
        ),
      )!;
      expect(night.bedAt, DateTime(2026, 10, 25, 18));
      expect(night.wakeAt, DateTime(2026, 10, 26, 12));
      expect(night.asleepMin, 60 + 60);
    });

    test('a night with only in-bed or awake data is skipped', () {
      expect(
        buildNight(
          day: day,
          source: 's',
          samples: NightSamples(inBed: [span(evening, 480)], awake: [span(evening, 10)]),
        ),
        isNull,
      );
    });
  });

  test('spansInNight keeps only samples overlapping the window', () {
    final day = DateTime(2026, 10, 26);
    final inside = span(DateTime(2026, 10, 26, 2), 60);
    final before = span(DateTime(2026, 10, 25, 10), 60);
    final after = span(DateTime(2026, 10, 26, 13), 60);
    expect(spansInNight([inside, before, after], day), [inside]);
  });
}
