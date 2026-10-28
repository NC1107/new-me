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
    } on ApiException catch (e) {
      debugPrint('[NEWME] health history stopped: $e');
      state = HealthHistoryState(reached: state.reached, error: e.message);
    } finally {
      if (state.running) state = HealthHistoryState(reached: state.reached, done: state.done);
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
        await client.putHealthHistory(List.of(batch));
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
