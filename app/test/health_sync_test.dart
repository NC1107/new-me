import 'dart:ui';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:newme/health/fake_health_source.dart';
import 'package:newme/health/health_source_factory.dart';
import 'package:newme/state/clock.dart';
import 'package:newme/state/health_sync.dart';
import 'package:newme/state/local_prefs.dart';
import 'package:newme/state/session.dart';
import 'package:newme/state/today.dart';

import 'test_support.dart';

class _Harness {
  _Harness({DateTime? start}) : now = start ?? DateTime(2026, 10, 26, 14);

  DateTime now;
  final source = FakeHealthSource();
  final adapter = StubAdapter()..on('PUT /api/health/daily', const StubResponse(200, {'days': []}));

  late final ProviderContainer container = testContainer(
    overrides: [
      sessionProvider.overrideWith(() => SessionController.seeded(testSession)),
      apiClientFactoryProvider.overrideWithValue(stubFactory(adapter)),
      healthSourceProvider.overrideWithValue(source),
      clockProvider.overrideWithValue(() => now),
    ],
  );

  HealthSyncController get sync => container.read(healthSyncProvider.notifier);

  Future<void> boot() async {
    container.listen(healthSyncProvider, (_, _) {});
    await sync.ready;
  }

  List<Map<String, dynamic>> get pushed => [
    for (final r in adapter.to('PUT /api/health/daily'))
      for (final item in (r.data as Map)['items'] as List) item as Map<String, dynamic>,
  ];

  List<Map<String, dynamic>> get lastPut => [
    for (final item in (adapter.to('PUT /api/health/daily').last.data as Map)['items'] as List)
      (item as Map).cast<String, dynamic>(),
  ];

  int get puts => adapter.to('PUT /api/health/daily').length;
}

void main() {
  setUp(FakeStorage().install);

  Future<void> prompted() => LocalPrefs.setHealthPrompted();

  test('nothing is read or sent until the user has been asked for access', () async {
    final h = _Harness();
    await h.boot();
    expect(await h.sync.sync(SyncTrigger.manual), isFalse);
    expect(h.source.reads, isEmpty);
    expect(h.puts, 0);
  });

  test('connect asks once, remembers it, and syncs without waiting', () async {
    final h = _Harness();
    await h.boot();

    expect(await h.sync.connect(), isTrue);

    expect(h.source.accessRequests, 1);
    expect(await LocalPrefs.healthPrompted(), isTrue);
    expect(h.container.read(healthSyncProvider).prompted, isTrue);
    expect(h.puts, 1);
    expect(h.container.read(healthSyncProvider).lastSyncedAt, h.now);
  });

  test('connect right after the controller is built is not undone by the prefs restore', () async {
    final h = _Harness();
    h.container.listen(healthSyncProvider, (_, _) {});

    expect(await h.sync.connect(), isTrue);
    await h.sync.ready;

    expect(h.container.read(healthSyncProvider).prompted, isTrue);
    expect(h.puts, 1);
    expect(h.container.read(healthSyncProvider).lastSyncedAt, h.now);
  });

  test('start pushes today from local midnight to now, in the documented shape', () async {
    await prompted();
    final h = _Harness(start: DateTime(2026, 10, 26, 14, 5));
    h.source.metrics
      ..clear()
      ..addAll({'steps': 5200, 'active_energy': 312.4});
    await h.boot();

    expect(h.source.reads.single, (start: DateTime(2026, 10, 26), end: h.now));
    expect(h.pushed, [
      {
        'date': '2026-10-26',
        'metric': 'steps',
        'value': 5200.0,
        'source': 'healthkit',
        'measuredAt': h.now.toUtc().toIso8601String(),
      },
      {
        'date': '2026-10-26',
        'metric': 'active_energy',
        'value': 312.0,
        'source': 'healthkit',
        'measuredAt': h.now.toUtc().toIso8601String(),
      },
    ]);
  });

  test('before 10:00 yesterday gets its midnight-to-midnight totals too', () async {
    await prompted();
    final h = _Harness(start: DateTime(2026, 10, 26, 9, 59));
    await h.boot();

    expect(h.source.reads, [
      (start: DateTime(2026, 10, 26), end: h.now),
      (start: DateTime(2026, 10, 25), end: DateTime(2026, 10, 26)),
    ]);
    expect({for (final i in h.pushed) i['date']}, {'2026-10-26', '2026-10-25'});
  });

  test('from 10:00 on, yesterday is left alone', () async {
    await prompted();
    final h = _Harness(start: DateTime(2026, 10, 26, 10));
    await h.boot();
    expect({for (final i in h.pushed) i['date']}, {'2026-10-26'});
  });

  test('a value equal to the last pushed one is not sent again', () async {
    await prompted();
    final h = _Harness();
    await h.boot();
    expect(h.puts, 1);

    h.now = h.now.add(const Duration(minutes: 30));
    expect(await h.sync.sync(SyncTrigger.manual), isTrue);
    expect(h.puts, 1, reason: 'nothing changed');

    h.source.steps += 100;
    await h.sync.sync(SyncTrigger.manual);
    expect(h.puts, 2);
    expect(h.lastPut.map((i) => i['metric']), ['steps']);
  });

  test('a failed push is retried because it was never recorded as pushed', () async {
    await prompted();
    final h = _Harness();
    h.adapter.on('PUT /api/health/daily', const StubResponse(503));
    await h.boot();
    expect(h.puts, 1);
    expect(h.container.read(healthSyncProvider).lastSyncedAt, isNull);

    h.adapter.on('PUT /api/health/daily', const StubResponse(200, {'days': []}));
    expect(await h.sync.sync(SyncTrigger.manual), isTrue);
    expect(h.puts, 2);
  });

  test('resume syncs at most every 5 minutes; pull to refresh and connect bypass that', () async {
    await prompted();
    final h = _Harness();
    await h.boot();
    expect(h.source.reads, hasLength(1));

    h.source.steps++;
    h.now = h.now.add(const Duration(minutes: 4, seconds: 59));
    expect(await h.sync.sync(SyncTrigger.resume), isFalse);
    expect(h.source.reads, hasLength(1));

    expect(await h.sync.sync(SyncTrigger.manual), isTrue, reason: 'pull to refresh bypasses');
    expect(h.source.reads, hasLength(2));

    h.source.steps++;
    h.now = h.now.add(const Duration(minutes: 4, seconds: 59));
    expect(await h.sync.sync(SyncTrigger.resume), isFalse);
    h.now = h.now.add(const Duration(seconds: 1));
    expect(await h.sync.sync(SyncTrigger.resume), isTrue);
    expect(h.source.reads, hasLength(3));
  });

  test('the app lifecycle drives resume syncs', () async {
    await prompted();
    final h = _Harness();
    await h.boot();
    h.source.steps++;
    h.now = h.now.add(const Duration(minutes: 6));

    final binding = TestWidgetsFlutterBinding.instance;
    binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);

    expect(h.sync.inFlight, isNotNull, reason: 'resume started a sync');
    await h.sync.inFlight;
    expect(h.source.reads, hasLength(2));
  });

  test('concurrent triggers share a single flight', () async {
    await prompted();
    final h = _Harness();
    h.source.latency = const Duration(milliseconds: 20);
    await h.boot();
    expect(h.source.reads, hasLength(1));

    h.source.steps++;
    final results = await Future.wait([
      h.sync.sync(SyncTrigger.manual),
      h.sync.sync(SyncTrigger.manual),
      h.sync.sync(SyncTrigger.resume),
    ]);

    expect(results, [true, true, true]);
    expect(h.source.reads, hasLength(2), reason: 'one read for all three callers');
    expect(h.puts, 2);
  });

  test('a closed yesterday does not cost today its totals', () async {
    await prompted();
    final h = _Harness(start: DateTime(2026, 10, 26, 9));
    h.adapter.routes['PUT /api/health/daily'] = (request) {
      final items = (request.data as Map)['items'] as List;
      final hasYesterday = items.any((i) => (i as Map)['date'] == '2026-10-25');
      return hasYesterday
          ? const StubResponse(422, {'error': 'closed', 'code': 'date_closed'})
          : const StubResponse(200, {'days': []});
    };
    await h.boot();

    expect(h.puts, 2);
    expect({for (final i in h.lastPut) i['date']}, {'2026-10-26'});
    expect(h.container.read(healthSyncProvider).lastSyncedAt, h.now);

    h.source.steps++;
    await h.sync.sync(SyncTrigger.manual);
    expect(h.puts, 3, reason: 'closed yesterday is not retried');
  });

  test('a push applies the rescored day to Today without another GET', () async {
    await prompted();
    final h = _Harness();
    h.adapter
      ..on('GET /api/today', StubResponse(200, todayJson(points: 120)))
      ..on(
        'PUT /api/health/daily',
        StubResponse(200, {
          'days': [
            {
              'date': '2026-10-26',
              'basePoints': 220,
              'bonusPoints': 0,
              'points': 220,
              'maxBase': 480,
              'percent': 46,
              'counted': false,
              'streakLine': 70,
              'quests': todayJson()['quests'],
            },
          ],
        }),
      );
    await h.container.read(todayProvider.future);
    await h.boot();

    expect(h.container.read(todayProvider).requireValue.data.day.points, 220);
    expect(h.adapter.to('GET /api/today'), hasLength(1));
  });

  test('a push brings the active energy burned to Today without another GET', () async {
    await prompted();
    final h = _Harness();
    h.adapter
      ..on('GET /api/today', StubResponse(200, todayJson()))
      ..on(
        'PUT /api/health/daily',
        StubResponse(200, {
          'days': [
            {
              'date': '2026-10-26',
              'basePoints': 220,
              'bonusPoints': 0,
              'points': 220,
              'maxBase': 480,
              'percent': 46,
              'counted': false,
              'streakLine': 70,
              'quests': todayJson()['quests'],
            },
          ],
        }),
      );
    await h.container.read(todayProvider.future);
    h.source.activeEnergyKcal = 287;
    await h.boot();

    expect(h.container.read(todayProvider).requireValue.data.food.burned, 287);
    expect(h.adapter.to('GET /api/today'), hasLength(1));
  });

  test('a push that makes the day count reloads Today for the streak the server derives', () async {
    await prompted();
    final h = _Harness();
    h.adapter.on('GET /api/today', StubResponse(200, todayJson()));
    await h.container.read(todayProvider.future);
    final counted = todayJson()..['streak'] = {'current': 4, 'restAvailable': true};
    h.adapter
      ..on('GET /api/today', StubResponse(200, counted))
      ..on(
        'PUT /api/health/daily',
        StubResponse(200, {
          'days': [
            {
              'date': '2026-10-26',
              'basePoints': 400,
              'bonusPoints': 0,
              'points': 400,
              'maxBase': 480,
              'percent': 83,
              'counted': true,
              'streakLine': 70,
              'quests': todayJson()['quests'],
            },
          ],
        }),
      );
    await h.boot();
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(h.container.read(todayProvider).requireValue.data.streak.current, 4);
  });

  test(
    'Health answering with nothing is not a sync and is tried again on the next resume',
    () async {
      await prompted();
      final h = _Harness();
      h.source.unreadable = true;
      await h.boot();

      expect(h.puts, 0);
      expect(h.container.read(healthSyncProvider).lastSyncedAt, isNull);
      expect(await LocalPrefs.lastSyncedAt(), isNull);

      h.source.unreadable = false;
      h.now = h.now.add(const Duration(seconds: 30));
      expect(await h.sync.sync(SyncTrigger.resume), isTrue, reason: 'no 5 minute throttle yet');
      expect(h.puts, 1);
    },
  );

  test('totals read for a session that ended are not pushed under the next one', () async {
    await prompted();
    final h = _Harness();
    h.source.latency = const Duration(milliseconds: 20);
    await h.boot();
    h.source.steps++;

    final flight = h.sync.sync(SyncTrigger.manual);
    await h.container
        .read(sessionProvider.notifier)
        .signIn(
          const Session(
            baseUrl: 'https://me.invalid',
            token: 'other',
            userId: 9,
            userName: 'Ana',
            color: 'amber',
          ),
        );
    expect(await flight, isFalse);
    await h.sync.ready;

    final puts = h.adapter.to('PUT /api/health/daily');
    final stale = puts.where((r) => r.headers['Authorization'] == 'Bearer tok');
    expect(stale, hasLength(1), reason: 'only the start sync, before the switch');
    expect(puts.last.headers['Authorization'], 'Bearer other');
  });

  test('every metric Health has is pushed, rounded for its unit', () async {
    await prompted();
    final h = _Harness();
    await h.boot();

    final byMetric = {for (final i in h.pushed) i['metric']: i['value']};
    expect(byMetric.keys.toSet(), FakeHealthSource.defaults.keys.toSet());
    expect(byMetric['weight_kg'], 82.4);
    expect(byMetric['vo2max'], 41.5);
    expect(byMetric['body_fat_pct'], 18.2);
    expect(byMetric['sleep_minutes'], 432.0);
    expect(byMetric['hrv_ms'], 46.0);
  });

  test('a metric Health has no data for is left out, and the rest still go', () async {
    await prompted();
    final h = _Harness();
    h.source.metrics
      ..remove('sleep_minutes')
      ..remove('vo2max');
    await h.boot();

    expect(h.puts, 1);
    final sent = h.pushed.map((i) => i['metric']).toSet();
    expect(sent, isNot(contains('sleep_minutes')));
    expect(sent, isNot(contains('vo2max')));
    expect(sent, containsAll(['steps', 'weight_kg', 'workouts']));
  });

  test('only the metrics that changed are pushed again', () async {
    await prompted();
    final h = _Harness();
    await h.boot();

    h.source.metrics['water_ml'] = 1750;
    h.source.metrics['weight_kg'] = 82.2;
    await h.sync.sync(SyncTrigger.manual);

    expect(h.lastPut.map((i) => i['metric']).toSet(), {'water_ml', 'weight_kg'});
  });

  test('a push keeps the metrics on Today without another GET', () async {
    await prompted();
    final h = _Harness();
    h.adapter.on('GET /api/today', StubResponse(200, todayJson()));
    await h.container.read(todayProvider.future);
    h.adapter.on(
      'PUT /api/health/daily',
      StubResponse(200, {
        'days': [
          {
            'date': '2026-10-26',
            'basePoints': 220,
            'bonusPoints': 0,
            'points': 220,
            'maxBase': 480,
            'percent': 46,
            'counted': false,
            'streakLine': 70,
            'quests': todayJson()['quests'],
          },
        ],
      }),
    );
    await h.boot();

    final health = h.container.read(todayProvider).requireValue.data.health;
    expect(health.metrics['sleep_minutes'], 432);
    expect(health.metrics['steps'], 4321);
  });
}
