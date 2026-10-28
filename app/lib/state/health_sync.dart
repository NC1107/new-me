import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/api_client.dart';
import '../api/models.dart';
import '../health/background_health_bridge.dart';
import '../health/health_records.dart';
import '../health/health_source.dart';
import '../health/health_source_factory.dart';
import 'clock.dart';
import 'insights.dart';
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

/// The upload items for one local day's Health totals; nothing for an unreadable day.
List<HealthItem> healthItemsFor(DateTime day, HealthTotals? totals, DateTime measuredAt) {
  if (totals == null) return [];
  final date = formatLocalDate(day);
  return [
    for (final key in HealthMetric.all)
      if (totals[key] case final value?)
        HealthItem(
          date: date,
          metric: key,
          value: _roundHealth(key, value),
          source: 'healthkit',
          measuredAt: measuredAt,
        ),
  ];
}

/// Body composition and fitness readings carry a meaningful decimal; the rest are whole.
const _tenths = {
  HealthMetric.weightKg,
  HealthMetric.leanMassKg,
  HealthMetric.bodyFatPct,
  HealthMetric.vo2max,
  HealthMetric.heightCm,
};

double _roundHealth(String key, double value) =>
    _tenths.contains(key) ? (value * 10).roundToDouble() / 10 : value.roundToDouble();

/// Workouts and sleep nights are re-read for this many days on every sync.
const kWorkoutSyncDays = 14;

/// The server accepts at most this many workouts per request.
const kWorkoutChunk = 100;

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

  /// What the server already has this session: workout id and night date to the JSON sent.
  final Map<String, String> _sentWorkouts = {};
  final Map<String, String> _sentNights = {};
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
    // The native side reads this when HealthKit wakes the app, so it must track token changes.
    ref.listen(sessionProvider.select((s) => (s.session?.baseUrl, s.session?.token)), (_, next) {
      _syncBackgroundConfig(next.$1, next.$2);
    }, fireImmediately: true);
    _disposed = false;
    ref.onDispose(() => _disposed = true);
    _pushed.clear();
    _closedDates.clear();
    _sentWorkouts.clear();
    _sentNights.clear();
    _lastRun = null;
    _inFlight = null;
    final listener = AppLifecycleListener(onResume: () => unawaited(sync(SyncTrigger.resume)));
    ref.onDispose(listener.dispose);
    _ready = _restore();
    return const HealthSyncState();
  }

  void _syncBackgroundConfig(String? baseUrl, String? token) {
    final bridge = ref.read(backgroundHealthBridgeProvider);
    if (baseUrl == null || token == null) {
      unawaited(bridge.clear());
    } else {
      unawaited(bridge.configure(baseUrl: baseUrl, token: token));
    }
  }

  Future<void> _restore() async {
    final prompted = await LocalPrefs.healthPrompted();
    final lastSyncedAt = await LocalPrefs.lastSyncedAt();
    if (_disposed) return;
    state = HealthSyncState(prompted: prompted, lastSyncedAt: lastSyncedAt);
    // Observers must be registered on every launch for HealthKit to keep delivering.
    if (prompted) unawaited(ref.read(backgroundHealthBridgeProvider).enable());
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
    if (granted) unawaited(ref.read(backgroundHealthBridgeProvider).enable());
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
      await _pushExtras(client, now);
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

  /// Workouts and sleep nights ride along with the daily push, but a failure here never fails it.
  Future<void> _pushExtras(ApiClient client, DateTime now) async {
    final source = ref.read(healthSourceProvider);
    final today = DateTime(now.year, now.month, now.day);
    final first = DateTime(today.year, today.month, today.day - (kWorkoutSyncDays - 1));
    var sentWorkouts = false;
    var sentNights = false;
    try {
      final workouts = await source.workouts(first, now);
      if (workouts != null && identical(ref.read(apiClientProvider), client)) {
        sentWorkouts = await _sendChanged<WorkoutUpload>(
          workouts,
          _sentWorkouts,
          (w) => w.id,
          (w) => jsonEncode(w.toJson()),
          client.putHealthWorkouts,
        );
      }
    } on Object catch (e) {
      debugPrint('[NEWME] workout sync failed: $e');
    }
    try {
      final nights = await source.sleepNights(first, today);
      if (nights != null && identical(ref.read(apiClientProvider), client)) {
        sentNights = await _sendChanged<SleepNightUpload>(
          nights,
          _sentNights,
          (n) => n.date,
          (n) => jsonEncode(n.toJson()),
          client.putHealthSleep,
        );
      }
    } on Object catch (e) {
      debugPrint('[NEWME] sleep sync failed: $e');
    }
    if (_disposed) return;
    // Screens built on these providers would otherwise show the numbers from before this sync.
    if (sentWorkouts || sentNights) ref.invalidate(insightsProvider);
    if (sentWorkouts) ref.invalidate(workoutsProvider);
  }

  /// Sends the items whose content differs from what this session sent, in chunks, and records
  /// each chunk only once the server has accepted it.
  Future<bool> _sendChanged<T>(
    List<T> items,
    Map<String, String> sent,
    String Function(T) keyOf,
    String Function(T) fingerprintOf,
    Future<int> Function(List<T>) put,
  ) async {
    var any = false;
    final changed = [
      for (final item in items)
        if (sent[keyOf(item)] != fingerprintOf(item)) item,
    ];
    for (var i = 0; i < changed.length; i += kWorkoutChunk) {
      final chunk = changed.sublist(i, min(i + kWorkoutChunk, changed.length));
      await put(chunk);
      any = true;
      for (final item in chunk) {
        sent[keyOf(item)] = fingerprintOf(item);
      }
    }
    return any;
  }

  Future<List<HealthItem>> _readItems(DateTime now) async {
    final source = ref.read(healthSourceProvider);
    final midnight = DateTime(now.year, now.month, now.day);
    final items = healthItemsFor(midnight, await source.totals(midnight, now), now);
    if (now.hour < kYesterdayGraceHour) {
      final yesterday = DateTime(now.year, now.month, now.day - 1);
      items.addAll(healthItemsFor(yesterday, await source.totals(yesterday, midnight), now));
    }
    return items;
  }

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

String formatLocalDate(DateTime d) => formatDate(d);

final healthSyncProvider = NotifierProvider<HealthSyncController, HealthSyncState>(
  HealthSyncController.new,
);
