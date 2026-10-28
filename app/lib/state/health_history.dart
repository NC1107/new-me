import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/api_client.dart';
import '../api/models.dart';
import '../health/health_source.dart';
import '../health/health_source_factory.dart';
import '../util/format.dart';
import 'clock.dart';
import 'health_sync.dart';
import 'local_prefs.dart';
import 'session.dart';

/// How far back the import may go, matching the server's limit.
const kHistoryMaxDays = 3650;

/// Consecutive days without any reading that mean Health holds nothing older.
const kHistoryEmptyStop = 90;

/// Readings per upload, the server's batch limit.
const kHistoryBatch = 200;

/// Pause between uploads, so the import stays far inside the server's rate limit.
const kHistoryPause = Duration(milliseconds: 400);

/// How many times one upload is retried after a 429 before the import pauses until next launch.
const kHistoryRateLimitRetries = 6;

/// The first wait after a 429 that names no Retry-After; it doubles up to [kHistoryBackoffMax].
const kHistoryBackoffStart = Duration(seconds: 2);
const kHistoryBackoffMax = Duration(minutes: 2);

/// The wait between rate-limited retries, replaceable so tests need not sit through it.
final historyBackoffWaitProvider = Provider<Future<void> Function(Duration)>(
  (ref) =>
      (d) => Future<void>.delayed(d),
);

class HealthHistoryState {
  const HealthHistoryState({this.running = false, this.reached, this.done = false, this.error});

  final bool running;

  /// The oldest day imported so far (YYYY-MM-DD).
  final String? reached;
  final bool done;
  final String? error;
}

/// Brings in every day Apple Health holds, newest first, up to ten years: one read per day, sent
/// in batches the server stores only where it has nothing yet. Progress is saved, so a closed app
/// picks up where it stopped.
class HealthHistoryImporter extends Notifier<HealthHistoryState> {
  bool _stop = false;

  @override
  HealthHistoryState build() {
    ref.onDispose(() => _stop = true);
    unawaited(_restore());
    return const HealthHistoryState();
  }

  Future<void> _restore() async {
    final saved = await LocalPrefs.healthHistory();
    state = HealthHistoryState(reached: saved.reached, done: saved.done);
  }

  /// Starts or resumes the import; a second call while one runs does nothing.
  Future<void> run({bool restart = false}) async {
    if (state.running) return;
    final client = ref.read(apiClientProvider);
    if (client == null || !ref.read(healthSyncProvider).prompted) return;
    final saved = await LocalPrefs.healthHistory();
    if (saved.done && !restart) return;
    state = HealthHistoryState(running: true, reached: restart ? null : saved.reached);
    try {
      await _import(client, restart ? null : saved.reached);
    } on _Stopped {
      return;
    } on ApiException catch (e) {
      debugPrint('[NEWME] health history stopped: $e');
      state = HealthHistoryState(
        reached: state.reached,
        error: e.isRateLimited
            ? 'The server is busy. History will carry on the next time you open New Me.'
            : e.message,
      );
    } finally {
      if (ref.mounted && state.running) {
        state = HealthHistoryState(reached: state.reached, done: state.done);
      }
    }
  }

  /// A 429 is the server pacing the import, not a failure: wait as long as it asks (or back off
  /// exponentially) and send the same batch again.
  Future<void> _upload(ApiClient client, List<HealthItem> items) async {
    var wait = kHistoryBackoffStart;
    for (var attempt = 0; ; attempt++) {
      try {
        await client.putHealthHistory(items);
        return;
      } on ApiException catch (e) {
        if (!e.isRateLimited || attempt >= kHistoryRateLimitRetries || _stop) rethrow;
        final asked = e.retryAfter;
        // A Retry-After of 0 would otherwise resend at once, in a tight loop.
        final pause = asked == null
            ? wait
            : asked < kHistoryBackoffStart
            ? kHistoryBackoffStart
            : (asked > kHistoryBackoffMax ? kHistoryBackoffMax : asked);
        wait = wait * 2 > kHistoryBackoffMax ? kHistoryBackoffMax : wait * 2;
        await ref.read(historyBackoffWaitProvider)(pause);
        // Signing out or leaving during a long wait must not send with the old client.
        if (_stop || !ref.mounted) throw const _Stopped();
      }
    }
  }

  Future<void> _import(ApiClient client, String? reached) async {
    final source = ref.read(healthSourceProvider);
    final now = ref.read(clockProvider)();
    final today = DateTime(now.year, now.month, now.day);
    // Today and yesterday belong to the regular sync; history starts the day before.
    var day = reached == null
        ? DateTime(today.year, today.month, today.day - 2)
        : parseLocalDate(reached).subtract(const Duration(days: 1));
    final oldest = DateTime(today.year, today.month, today.day - kHistoryMaxDays);
    var empty = 0;
    final batch = <HealthItem>[];
    var batchOldest = day;

    Future<void> flush({required bool done}) async {
      if (batch.isNotEmpty) {
        await _upload(client, List.of(batch));
        batch.clear();
        await Future<void>.delayed(kHistoryPause);
      }
      final through = formatLocalDate(batchOldest);
      await LocalPrefs.setHealthHistory(reached: through, done: done);
      state = HealthHistoryState(running: !done, reached: through, done: done);
    }

    while (!_stop && !day.isBefore(oldest)) {
      final next = DateTime(day.year, day.month, day.day + 1);
      final items = healthItemsFor(day, await source.totals(day, next), next);
      empty = items.isEmpty ? empty + 1 : 0;
      batch.addAll(items);
      batchOldest = day;
      if (empty >= kHistoryEmptyStop) break;
      if (batch.length >= kHistoryBatch - HealthMetric.all.length) await flush(done: false);
      day = DateTime(day.year, day.month, day.day - 1);
    }
    if (!_stop) await flush(done: true);
  }
}

final healthHistoryProvider = NotifierProvider<HealthHistoryImporter, HealthHistoryState>(
  HealthHistoryImporter.new,
);

/// The importer was disposed mid-wait; nothing is reported, the next launch resumes.
class _Stopped implements Exception {
  const _Stopped();
}
