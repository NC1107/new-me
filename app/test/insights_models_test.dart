import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:newme/api/api_client.dart';
import 'package:newme/api/models.dart';
import 'package:newme/state/insights.dart';
import 'package:newme/state/session.dart';

import 'test_support.dart';

const _insightsJson = {
  'steps': {
    'avg7': 7421.5,
    'avg30': 6900,
    'median14': 7400,
    'trend': 'up',
    'best': {'date': '2026-10-20', 'value': 12044},
    'daysAtGoal30': 11,
    'goal': 8000,
    'suggestion': {
      'target': 8500,
      'median14': 7400,
      'bandLow': 8000,
      'bandHigh': 10000,
      'ageKnown': true,
    },
  },
  'sleep': {
    'avg7Min': 421,
    'avg30Min': 410,
    'targetMin': 450,
    'avgBedtime': '23:10',
    'avgWake': '06:50',
    'bedtimeSpreadMin': 38.5,
    'stages7': {'deepMin': 62, 'remMin': 91, 'coreMin': 240, 'awakeMin': 20},
    'lastNight': {
      'date': '2026-10-27',
      'bedAt': '2026-10-26T22:55:00.000Z',
      'wakeAt': '2026-10-27T06:40:00.000Z',
      'asleepMin': 431,
      'deepMin': 70,
      'remMin': 95,
      'coreMin': 266,
      'awakeMin': 18,
    },
    'nights': [
      {'date': '2026-10-26', 'asleepMin': 400},
      {'date': '2026-10-27', 'asleepMin': 431},
    ],
  },
  'workouts': {
    'week': {'count': 3, 'minutes': 127},
    'last30': {
      'count': 9,
      'minutes': 410,
      'byType': [
        {'type': 'running', 'count': 4, 'minutes': 150},
        {'type': 'strength', 'count': 5, 'minutes': 260},
      ],
    },
  },
};

void main() {
  setUp(FakeStorage().install);

  group('Insights', () {
    test('parses the full shape and round trips', () {
      final i = Insights.fromJson(_insightsJson);
      expect(i.steps.avg7, 7421.5);
      expect(i.steps.trend, 'up');
      expect(i.steps.best?.value, 12044);
      expect(i.steps.suggestion?.target, 8500);
      expect(i.steps.suggestion?.ageKnown, isTrue);
      expect(i.sleep.avgBedtime, '23:10');
      expect(i.sleep.bedtimeSpreadMin, 38.5);
      expect(i.sleep.stages7?.remMin, 91);
      expect(i.sleep.lastNight?.asleepMin, 431);
      expect(i.sleep.lastNight?.bedAt, DateTime.utc(2026, 10, 26, 22, 55));
      expect(i.sleep.lastNight?.stages.coreMin, 266);
      expect(i.sleep.nights.map((n) => n.asleepMin), [400, 431]);
      expect(i.workouts.week.count, 3);
      expect(i.workouts.last30.minutes, 410);
      expect(i.workouts.byType.map((t) => t.type), ['running', 'strength']);
      expect(jsonDecode(jsonEncode(i.toJson())), _insightsJson);
    });

    test('nullable parts stay null', () {
      final i = Insights.fromJson({
        'steps': {
          'avg7': null,
          'avg30': null,
          'median14': null,
          'trend': 'flat',
          'best': null,
          'daysAtGoal30': 0,
          'goal': 8000,
          'suggestion': null,
        },
        'sleep': {
          'avg7Min': null,
          'avg30Min': null,
          'targetMin': 420,
          'avgBedtime': null,
          'avgWake': null,
          'bedtimeSpreadMin': null,
          'stages7': null,
          'lastNight': null,
          'nights': [],
        },
        'workouts': {
          'week': {'count': 0, 'minutes': 0},
          'last30': {'count': 0, 'minutes': 0, 'byType': []},
        },
      });
      expect(i.steps.best, isNull);
      expect(i.steps.suggestion, isNull);
      expect(i.sleep.stages7, isNull);
      expect(i.sleep.lastNight, isNull);
      expect(i.sleep.nights, isEmpty);
      expect(i.workouts.byType, isEmpty);
    });

    test('an older server answering with nothing still parses', () {
      final i = Insights.fromJson(const {});
      expect(i.steps.suggestion, isNull);
      expect(i.steps.trend, 'flat');
      expect(i.sleep.targetMin, 420);
      expect(i.workouts.week.count, 0);
    });
  });

  group('workouts', () {
    test('GET /workouts parses, tolerating absent optional fields', () {
      final list = WorkoutList.fromJson({
        'workouts': [
          {
            'id': 'a',
            'type': 'running',
            'date': '2026-10-26',
            'startedAt': '2026-10-26T07:00:00Z',
            'endedAt': '2026-10-26T07:34:00Z',
            'durationMin': 34,
            'kcal': 362,
            'distanceM': 5480,
            'avgHr': 158,
          },
          {
            'id': 'b',
            'type': 'yoga',
            'date': '2026-10-25',
            'startedAt': '2026-10-25T07:00:00Z',
            'endedAt': '2026-10-25T07:20:00Z',
            'durationMin': 20,
            'kcal': null,
          },
        ],
        'week': {'count': 2, 'minutes': 54},
      });
      expect(list.workouts.first.distanceM, 5480);
      expect(list.workouts.last.kcal, isNull);
      expect(list.workouts.last.avgHr, isNull);
      expect(list.week.minutes, 54);
      expect(WorkoutList.fromJson(const {}).workouts, isEmpty);
      expect(WorkoutList.fromJson(jsonDecode(jsonEncode(list.toJson())) as Json).week.count, 2);
    });
  });

  group('Me and Board additions', () {
    final meJson = {
      'user': {'id': 1, 'name': 'Sam', 'color': 'violet', 'timezone': 'UTC', 'isAdmin': false},
      'targets': <String, dynamic>{},
      'questTemplates': [],
      'localToday': '2026-10-27',
      'serverNow': '2026-10-27T10:00:00Z',
    };

    test('birthYear is read when present and absent on older servers', () {
      expect(Me.fromJson(meJson).user.birthYear, isNull);
      final withYear = Me.fromJson({
        ...meJson,
        'user': {...(meJson['user']! as Map<String, dynamic>), 'birthYear': 1990},
      });
      expect(withYear.user.birthYear, 1990);
      expect(withYear.toJson()['user'], containsPair('birthYear', 1990));
      expect(Me.fromJson(meJson).toJson()['user'], isNot(contains('birthYear')));
    });

    test('MePatch sends birthYear, null to clear, and nothing by default', () {
      expect(const MePatch(birthYear: 1990).toJson(), {'birthYear': 1990});
      expect(const MePatch(clearBirthYear: true).toJson(), {'birthYear': null});
      expect(const MePatch(name: 'A').toJson(), {'name': 'A'});
    });

    test('board members carry workoutsThisWeek when the server sends it', () {
      Json user(Map<String, dynamic> extra) => {
        'id': 1,
        'name': 'Sam',
        'color': 'violet',
        'today': {'points': 0, 'complete': false, 'doneCount': 0, 'questCount': 0},
        'week': {'points': 5},
        'season': {'points': 9},
        'streak': {'current': 2},
        'last7': [],
        ...extra,
      };
      expect(BoardUser.fromJson(user({})).workoutsThisWeek, isNull);
      final u = BoardUser.fromJson(user({'workoutsThisWeek': 3}));
      expect(u.workoutsThisWeek, 3);
      expect(u.toJson()['workoutsThisWeek'], 3);
    });
  });

  group('ApiClient', () {
    test('PUT /health/workouts and /health/sleep send the contract bodies', () async {
      final adapter = StubAdapter()
        ..on('PUT /api/health/workouts', const StubResponse(200, {'saved': 1}))
        ..on('PUT /api/health/sleep', const StubResponse(200, {'saved': 1}));
      final client = ApiClient(baseUrl: 'https://x.invalid', token: 't', adapter: adapter);
      final at = DateTime.utc(2026, 10, 26, 7);
      final saved = await client.putHealthWorkouts([
        WorkoutUpload(
          id: 'u',
          type: 'running',
          startedAt: at,
          endedAt: at.add(const Duration(minutes: 30)),
          durationMin: 30,
          source: 'Watch',
        ),
      ]);
      expect(saved, 1);
      expect((adapter.last!.data as Map)['items'], [
        {
          'id': 'u',
          'type': 'running',
          'startedAt': '2026-10-26T07:00:00.000Z',
          'endedAt': '2026-10-26T07:30:00.000Z',
          'durationMin': 30,
          'kcal': null,
          'distanceM': null,
          'avgHr': null,
          'source': 'Watch',
        },
      ]);
      await client.putHealthSleep([
        SleepNightUpload(
          date: '2026-10-26',
          bedAt: at,
          wakeAt: at.add(const Duration(hours: 7)),
          asleepMin: 400,
          source: 'Watch',
        ),
      ]);
      final night = ((adapter.last!.data as Map)['nights'] as List).single as Map;
      expect(night.keys, [
        'date',
        'bedAt',
        'wakeAt',
        'asleepMin',
        'deepMin',
        'remMin',
        'coreMin',
        'awakeMin',
        'source',
      ]);
      expect(night['deepMin'], 0);
    });

    test('GET /workouts passes days and GET /insights parses', () async {
      final adapter = StubAdapter()
        ..on('GET /api/workouts', const StubResponse(200, {'workouts': [], 'week': {}}))
        ..on('GET /api/insights', const StubResponse(200, _insightsJson));
      final client = ApiClient(baseUrl: 'https://x.invalid', token: 't', adapter: adapter);
      await client.workouts(days: 90);
      expect(adapter.last!.queryParameters, {'days': 90});
      expect((await client.insights()).steps.goal, 8000);
    });
  });

  group('providers', () {
    ProviderContainer container(StubAdapter adapter) => testContainer(
      overrides: [
        sessionProvider.overrideWith(() => SessionController.seeded(testSession)),
        apiClientFactoryProvider.overrideWithValue(stubFactory(adapter)),
      ],
    );

    test('insightsProvider loads, then serves the cache while the server is down', () async {
      final adapter = StubAdapter()
        ..on('GET /api/insights', const StubResponse(200, _insightsJson));
      final first = await container(adapter).read(insightsProvider.future);
      expect(first.data.steps.goal, 8000);
      expect(first.offline, isNull);

      adapter.on('GET /api/insights', const StubResponse(503, {'error': 'down'}));
      final c = container(adapter);
      final cached = await c.read(insightsProvider.future);
      expect(cached.data.sleep.lastNight?.asleepMin, 431);
      expect(cached.offline, isNotNull);
    });

    test('workoutsProvider is keyed by days with its own cache', () async {
      final adapter = StubAdapter()
        ..on(
          'GET /api/workouts',
          const StubResponse(200, {
            'workouts': [],
            'week': {'count': 1, 'minutes': 30},
          }),
        );
      final c = container(adapter);
      final seven = await c.read(workoutsProvider(7).future);
      expect(seven.data.week.count, 1);
      expect(adapter.last!.queryParameters, {'days': 7});

      adapter.on('GET /api/workouts', const StubResponse(503, {'error': 'down'}));
      final other = container(adapter);
      expect(
        () => other.read(workoutsProvider(30).future),
        throwsA(isA<ApiException>()),
        reason: 'a 7 day cache must not answer for 30 days',
      );
      final cached = await other.read(workoutsProvider(7).future);
      expect(cached.offline, isNotNull);

      await container(adapter).read(workoutsProvider(7).notifier).refresh();
    });
  });
}
