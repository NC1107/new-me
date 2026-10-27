import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:newme/api/models.dart';
import 'package:newme/health/fake_health_source.dart';
import 'package:newme/health/health_source_factory.dart';
import 'package:newme/state/clock.dart';
import 'package:newme/state/health_sync.dart';
import 'package:newme/state/insights.dart';
import 'package:newme/state/local_prefs.dart';
import 'package:newme/state/session.dart';

import 'test_support.dart';

class _Harness {
  DateTime now = DateTime(2026, 10, 26, 14);
  final source = FakeHealthSource();
  final adapter = StubAdapter()
    ..on('PUT /api/health/daily', const StubResponse(200, {'days': []}))
    ..on('PUT /api/health/workouts', const StubResponse(200, {'saved': 1}))
    ..on('PUT /api/health/sleep', const StubResponse(200, {'saved': 1}));

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
    await LocalPrefs.setHealthPrompted();
    container.listen(healthSyncProvider, (_, _) {});
    await sync.ready;
  }

  List<Map<String, dynamic>> sent(String route, String key) => [
    for (final r in adapter.to(route))
      for (final item in (r.data as Map)[key] as List) (item as Map).cast<String, dynamic>(),
  ];

  List<Map<String, dynamic>> get workouts => sent('PUT /api/health/workouts', 'items');
  List<Map<String, dynamic>> get nights => sent('PUT /api/health/sleep', 'nights');
}

WorkoutUpload workout(int i, {int kcal = 100, int daysAgo = 1}) {
  final start = DateTime(2026, 10, 26 - daysAgo, 7, i % 50);
  return WorkoutUpload(
    id: 'w$i',
    type: 'running',
    startedAt: start,
    endedAt: start.add(const Duration(minutes: 30)),
    durationMin: 30,
    kcal: kcal,
    source: 'Watch',
  );
}

void main() {
  setUp(FakeStorage().install);

  test('a sync sends the last 14 days of workouts and sleep after the daily push', () async {
    final h = _Harness();
    await h.boot();
    expect(h.workouts.map((w) => w['type']), containsAll(['running', 'strength', 'walking']));
    expect(h.nights, hasLength(14));
    expect(h.nights.first['date'], '2026-10-13');
    expect(h.nights.last['date'], '2026-10-26');
    final order = h.adapter.requests.map((r) => r.path).toList();
    expect(order.indexOf('/api/health/daily'), lessThan(order.indexOf('/api/health/workouts')));
    expect(order.indexOf('/api/health/workouts'), lessThan(order.indexOf('/api/health/sleep')));
    expect(h.source.workoutReads, 1);
  });

  test('unchanged workouts and nights are not sent again in the same session', () async {
    final h = _Harness();
    await h.boot();
    final workoutPuts = h.adapter.to('PUT /api/health/workouts').length;
    final sleepPuts = h.adapter.to('PUT /api/health/sleep').length;

    h.now = h.now.add(const Duration(minutes: 10));
    expect(await h.sync.sync(SyncTrigger.manual), isTrue);

    expect(h.adapter.to('PUT /api/health/workouts'), hasLength(workoutPuts));
    expect(h.adapter.to('PUT /api/health/sleep'), hasLength(sleepPuts));
    expect(h.source.workoutReads, 2);
  });

  test('a workout that changed in Health is sent again, alone', () async {
    final h = _Harness();
    h.source.workoutList = [workout(1), workout(2)];
    await h.boot();
    expect(h.workouts.map((w) => w['id']), ['w1', 'w2']);

    h.source.workoutList = [workout(1), workout(2, kcal: 250)];
    h.now = h.now.add(const Duration(minutes: 10));
    await h.sync.sync(SyncTrigger.manual);

    expect(h.workouts.map((w) => w['id']), ['w1', 'w2', 'w2']);
    expect(h.workouts.last['kcal'], 250);
  });

  test('workouts go out in chunks of at most 100', () async {
    final h = _Harness();
    h.source.workoutList = [for (var i = 0; i < 230; i++) workout(i)];
    await h.boot();
    final puts = h.adapter.to('PUT /api/health/workouts').toList();
    expect([for (final r in puts) ((r.data as Map)['items'] as List).length], [100, 100, 30]);
  });

  test('only workouts inside the 14 day window are read', () async {
    final h = _Harness();
    h.source.workoutList = [workout(1, daysAgo: 20), workout(2, daysAgo: 13)];
    await h.boot();
    expect(h.workouts.map((w) => w['id']), ['w2']);
  });

  test('a failing workout upload neither fails the daily push nor skips sleep', () async {
    final h = _Harness();
    h.adapter.on('PUT /api/health/workouts', const StubResponse(500, {'error': 'boom'}));
    await h.boot();
    expect(h.adapter.to('PUT /api/health/daily'), isNotEmpty);
    expect(h.nights, hasLength(14));
    expect(h.container.read(healthSyncProvider).lastSyncedAt, h.now);

    h.adapter.on('PUT /api/health/workouts', const StubResponse(200, {'saved': 3}));
    h.now = h.now.add(const Duration(minutes: 10));
    await h.sync.sync(SyncTrigger.manual);
    expect(h.workouts.where((w) => w['type'] == 'running'), isNotEmpty);
  });

  test('a failing sleep upload is retried on the next sync', () async {
    final h = _Harness();
    h.adapter.on('PUT /api/health/sleep', const StubResponse(404, {'error': 'no route'}));
    await h.boot();
    expect(await h.sync.sync(SyncTrigger.manual), isTrue);
    expect(h.adapter.to('PUT /api/health/sleep'), hasLength(2));

    h.adapter.on('PUT /api/health/sleep', const StubResponse(200, {'saved': 14}));
    h.now = h.now.add(const Duration(minutes: 10));
    await h.sync.sync(SyncTrigger.manual);
    await h.sync.sync(SyncTrigger.manual);
    expect(h.adapter.to('PUT /api/health/sleep'), hasLength(3));
  });

  test('unreadable workouts and sleep send nothing and the daily push still counts', () async {
    final h = _Harness();
    h.source
      ..workoutsUnreadable = true
      ..sleepUnreadable = true;
    await h.boot();
    expect(h.adapter.to('PUT /api/health/workouts'), isEmpty);
    expect(h.adapter.to('PUT /api/health/sleep'), isEmpty);
    expect(h.container.read(healthSyncProvider).lastSyncedAt, isNotNull);
  });

  test('the resume throttle still holds the extras back', () async {
    final h = _Harness();
    await h.boot();
    h.source.nightList = [];
    h.now = h.now.add(const Duration(minutes: 1));
    expect(await h.sync.sync(SyncTrigger.resume), isFalse);
    expect(h.source.workoutReads, 1);
    expect(h.source.sleepReads, 1);
  });

  test('new data refreshes the insights provider that is on screen', () async {
    final h = _Harness();
    h.adapter.on('GET /api/insights', const StubResponse(200, {}));
    await h.boot();
    final sub = h.container.listen(insightsProvider, (_, _) {});
    await h.container.read(insightsProvider.future);
    final before = h.adapter.to('GET /api/insights').length;

    h.source.workoutList = [workout(9)];
    h.now = h.now.add(const Duration(minutes: 10));
    await h.sync.sync(SyncTrigger.manual);
    await h.container.read(insightsProvider.future);

    expect(h.adapter.to('GET /api/insights').length, before + 1);
    sub.close();
  });
}
