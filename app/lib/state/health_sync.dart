import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/api_client.dart';
import '../api/models.dart';
import '../health/health_source.dart';
import '../health/health_source_factory.dart';
import 'clock.dart';
import 'local_prefs.dart';
import 'session.dart';
import 'today.dart';

enum SyncTrigger {
  start,
  resume,

  /// Pull to refresh.
  manual,

  /// The first sync right after the user granted access.
  connect,
}

const kResumeSyncInterval = Duration(minutes: 5);

/// Before this local hour, yesterday is still open on the server and gets its final totals.
const kYesterdayGraceHour = 10;

class HealthSyncState {
  const HealthSyncState({this.syncing = false, this.prompted = false, this.lastSyncedAt});

  final bool syncing;

  /// True once the permission sheet has been shown; iOS never reveals read denial.
  final bool prompted;
  final DateTime? lastSyncedAt;

  HealthSyncState copyWith({bool? syncing, bool? prompted, DateTime? lastSyncedAt}) =>
      HealthSyncState(
        syncing: syncing ?? this.syncing,
        prompted: prompted ?? this.prompted,
        lastSyncedAt: lastSyncedAt ?? this.lastSyncedAt,
      );
}

class HealthSyncController extends Notifier<HealthSyncState> {
  final Map<String, double> _pushed = {};
  final Set<String> _closedDates = {};
  Future<bool>? _inFlight;
  DateTime? _lastRun;
  Future<void> _ready = Future.value();
  bool _disposed = false;

  @visibleForTesting
  Future<void> get ready => _ready;

  @visibleForTesting
  Future<bool>? get inFlight => _inFlight;

  @override
  HealthSyncState build() {
    ref.watch(sessionProvider.select((s) => s.session?.userId));
    _disposed = false;
    ref.onDispose(() => _disposed = true);
    _pushed.clear();
    _closedDates.clear();
    _lastRun = null;
    _inFlight = null;
    final listener = AppLifecycleListener(onResume: () => unawaited(sync(SyncTrigger.resume)));
    ref.onDispose(listener.dispose);
    _ready = _restore();
    return const HealthSyncState();
  }

  Future<void> _restore() async {
    final prompted = await LocalPrefs.healthPrompted();
    final lastSyncedAt = await LocalPrefs.lastSyncedAt();
    if (_disposed) return;
    state = HealthSyncState(prompted: prompted, lastSyncedAt: lastSyncedAt);
    await sync(SyncTrigger.start);
  }

  /// Asks for access from an explicit tap, then syncs once without the resume throttle.
  Future<bool> connect() async {
    // A restore still reading prefs would otherwise overwrite the prompt state set below.
    await _ready;
    final bool granted;
    try {
      granted = await ref.read(healthSourceProvider).requestAccess();
    } on Object catch (e) {
      debugPrint('[NEWME] health access failed: $e');
      return false;
    }
    await LocalPrefs.setHealthPrompted();
    if (_disposed) return granted;
    state = state.copyWith(prompted: true);
    await sync(SyncTrigger.connect);
    return granted;
  }

  /// Joins a sync already in progress instead of starting a second one.
  Future<bool> sync(SyncTrigger trigger) {
    final running = _inFlight;
    if (running != null) return running;
    late final Future<bool> flight;
    flight = _run(trigger).whenComplete(() {
      if (identical(_inFlight, flight)) _inFlight = null;
    });
    return _inFlight = flight;
  }

  Future<bool> _run(SyncTrigger trigger) async {
    final client = ref.read(apiClientProvider);
    if (client == null || !state.prompted) return false;

    final now = ref.read(clockProvider)();
    final last = _lastRun;
    if (trigger == SyncTrigger.resume &&
        last != null &&
        now.difference(last) < kResumeSyncInterval) {
      return false;
    }

    state = state.copyWith(syncing: true);
    try {
      final items = await _readItems(now);
      // Health answering with nothing is not a sync, and the next resume should try again.
      if (items.isEmpty) return false;
      // The session changed while Health was being read; these totals belong to the old one.
      if (!identical(ref.read(apiClientProvider), client)) return false;
      await _push(client, items);
      _lastRun = now;
      await LocalPrefs.setLastSyncedAt(now);
      if (!_disposed) state = state.copyWith(lastSyncedAt: now);
      return true;
    } on ApiException catch (e) {
      debugPrint('[NEWME] health push failed: $e');
      return false;
    } on Object catch (e) {
      debugPrint('[NEWME] health read failed: $e');
      return false;
    } finally {
      if (!_disposed) state = state.copyWith(syncing: false);
    }
  }

  Future<List<HealthItem>> _readItems(DateTime now) async {
    final source = ref.read(healthSourceProvider);
    final midnight = DateTime(now.year, now.month, now.day);
    final items = _itemsFor(midnight, await source.totals(midnight, now), now);
    if (now.hour < kYesterdayGraceHour) {
      final yesterday = DateTime(now.year, now.month, now.day - 1);
      items.addAll(_itemsFor(yesterday, await source.totals(yesterday, midnight), now));
    }
    return items;
  }

  List<HealthItem> _itemsFor(DateTime day, HealthTotals? totals, DateTime measuredAt) {
    if (totals == null) return [];
    final date = formatLocalDate(day);
    return [
      for (final key in HealthMetric.all)
        if (totals[key] case final value?)
          HealthItem(
            date: date,
            metric: key,
            value: _round(key, value),
            source: 'healthkit',
            measuredAt: measuredAt,
          ),
    ];
  }

  /// Body composition and fitness readings carry a meaningful decimal; the rest are whole.
  static const _tenths = {
    HealthMetric.weightKg,
    HealthMetric.leanMassKg,
    HealthMetric.bodyFatPct,
    HealthMetric.vo2max,
  };

  double _round(String key, double value) =>
      _tenths.contains(key) ? (value * 10).roundToDouble() / 10 : value.roundToDouble();

  String _keyOf(HealthItem item) => '${item.date}|${item.metric}';

  Future<void> _push(ApiClient client, List<HealthItem> items) async {
    final changed = [
      for (final item in items)
        if (!_closedDates.contains(item.date) && _pushed[_keyOf(item)] != item.value) item,
    ];
    if (changed.isEmpty) return;

    final (:sent, :result) = await _putWithGraceFallback(client, changed);
    for (final item in sent) {
      _pushed[_keyOf(item)] = item.value;
    }
    if (ref.exists(todayProvider)) {
      await ref
          .read(todayProvider.notifier)
          .applyRescored(
            result,
            burnedByDate: {
              for (final item in sent)
                if (item.metric == HealthMetric.activeEnergy) item.date: item.value,
            },
            metricsByDate: {
              for (final item in sent)
                item.date: {
                  for (final i in sent)
                    if (i.date == item.date) i.metric: i.value,
                },
            },
          );
    }
  }

  /// The batch is one transaction, so a closed yesterday would also drop today's totals.
  Future<({List<HealthItem> sent, HealthDailyResult result})> _putWithGraceFallback(
    ApiClient client,
    List<HealthItem> items,
  ) async {
    try {
      return (sent: items, result: await client.putHealthDaily(items));
    } on ApiException catch (e) {
      if (e.kind != ApiErrorKind.dateClosed) rethrow;
      final newest = items.map((i) => i.date).reduce((a, b) => a.compareTo(b) > 0 ? a : b);
      final todayOnly = [
        for (final item in items)
          if (item.date == newest) item,
      ];
      if (todayOnly.length == items.length) rethrow;
      _closedDates.addAll(items.map((i) => i.date).where((d) => d != newest));
      return (sent: todayOnly, result: await client.putHealthDaily(todayOnly));
    }
  }
}

String formatLocalDate(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

final healthSyncProvider = NotifierProvider<HealthSyncController, HealthSyncState>(
  HealthSyncController.new,
);
