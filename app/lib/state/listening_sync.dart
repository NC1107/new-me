import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/api_client.dart';
import 'clock.dart';
import 'me.dart';
import 'session.dart';
import 'today.dart';

/// The server throttles the same call to once a minute per person, so asking sooner only costs a
/// round trip for the stored answer.
const kListeningSyncThrottle = Duration(seconds: 60);

/// Asks the server to read Audiobookshelf now, so listening shows up within seconds of opening
/// the app instead of waiting for the five minute poll.
class ListeningSyncer {
  ListeningSyncer(this._ref);

  final Ref _ref;
  DateTime? _lastAttempt;
  Future<bool>? _inFlight;

  bool get _linked => _ref.read(meProvider).value?.data.audiobookshelf?.linked ?? false;

  /// True when a request was sent. Nothing happens while the person is not linked or the last
  /// attempt was under a minute ago.
  Future<bool> sync() => _inFlight ??= _run().whenComplete(() => _inFlight = null);

  Future<bool> _run() async {
    final client = _ref.read(apiClientProvider);
    if (client == null) return false;
    try {
      await _ref.read(meProvider.future);
    } on Object {
      return false;
    }
    if (!_linked) return false;
    final now = _ref.read(clockProvider)();
    final last = _lastAttempt;
    if (last != null && now.difference(last) < kListeningSyncThrottle) return false;
    _lastAttempt = now;
    try {
      await client.syncAudiobookshelf();
      return true;
    } on ApiException catch (e) {
      debugPrint('[NEWME] listening sync skipped: $e');
      return false;
    }
  }

  /// Syncs, then reloads Today. With [onlyIfSynced] the reload is skipped when no request was
  /// sent, for the app-open call that Today's own first load already covers.
  Future<void> syncThenRefreshToday({bool onlyIfSynced = false}) async {
    final ran = await sync();
    if (onlyIfSynced && !ran) return;
    if (_ref.exists(todayProvider)) await _ref.read(todayProvider.notifier).refresh();
  }
}

final listeningSyncProvider = Provider<ListeningSyncer>((ref) {
  ref.watch(sessionProvider.select((s) => s.session?.userId));
  return ListeningSyncer(ref);
});
