import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:newme/health/fake_health_source.dart';
import 'package:newme/health/health_source_factory.dart';
import 'package:newme/state/clock.dart';
import 'package:newme/state/health_history.dart';
import 'package:newme/state/health_sync.dart';
import 'package:newme/state/local_prefs.dart';
import 'package:newme/state/session.dart';

import 'fixtures.dart';
import 'test_support.dart';

void main() {
  late StubAdapter server;
  late FakeHealthSource health;
  late ProviderContainer container;
  final now = DateTime(2026, 11, 2, 12);
  final uploads = <List<dynamic>>[];

  setUp(() async {
    FakeStorage().install();
    await LocalPrefs.setHealthPrompted();
    uploads.clear();
    server = fullServer()
      ..routes['PUT /api/health/history'] = (req) {
        final items = (req.data as Map)['items'] as List;
        uploads.add(items);
        return StubResponse(200, {'stored': items.length, 'received': items.length});
      };
    health = FakeHealthSource()..dataSince = DateTime(2026, 10, 21);
    container = testContainer(
      overrides: [
        sessionProvider.overrideWith(() => SessionController.seeded(testSession)),
        apiClientFactoryProvider.overrideWithValue(stubFactory(server)),
        clockProvider.overrideWithValue(() => now),
        healthSourceProvider.overrideWithValue(health),
      ],
    );
    container.read(healthSyncProvider);
    await Future<void>.delayed(Duration.zero);
  });

  test('imports closed days newest first and stops after 90 empty days', () async {
    await container.read(healthHistoryProvider.notifier).run();
    final dates = [
      for (final batch in uploads)
        for (final item in batch) (item as Map)['date'] as String,
    ];
    expect(dates.first, '2026-10-31', reason: 'today and yesterday belong to the regular sync');
    expect(dates.toSet(), hasLength(11), reason: '31 October back to 21 October');
    expect(dates.last, '2026-10-21');
    expect(dates.contains('2026-11-01'), isFalse);
    for (final batch in uploads) {
      expect(batch.length, lessThanOrEqualTo(kHistoryBatch));
    }
    final state = container.read(healthHistoryProvider);
    expect(state.done, isTrue);
    expect(state.running, isFalse);
    expect((await LocalPrefs.healthHistory()).done, isTrue);
    final historyReads = health.reads.where((r) => r.start.isBefore(DateTime(2026, 11)));
    expect(historyReads, hasLength(11 + kHistoryEmptyStop));
  });

  test('a finished import does not run again unless restarted', () async {
    await container.read(healthHistoryProvider.notifier).run();
    final reads = health.reads.length;
    await container.read(healthHistoryProvider.notifier).run();
    expect(health.reads.length, reads);
    await container.read(healthHistoryProvider.notifier).run(restart: true);
    expect(health.reads.length, greaterThan(reads));
  });

  test('a stopped import resumes from the oldest day it reached', () async {
    await LocalPrefs.setHealthHistory(reached: '2026-10-25', done: false);
    await container.read(healthHistoryProvider.notifier).run();
    final dates = {
      for (final batch in uploads)
        for (final item in batch) (item as Map)['date'] as String,
    };
    expect(dates.contains('2026-10-25'), isFalse);
    expect(dates.contains('2026-10-24'), isTrue);
  });
}
