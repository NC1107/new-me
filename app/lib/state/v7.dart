import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/api_client.dart';
import '../api/models.dart';
import 'board.dart';
import 'session.dart';
import 'today.dart';

/// GET /progress for the rolling window; fetched fresh each time the screen opens.
final progressProvider = FutureProvider.autoDispose.family<Progress, int>((ref, window) {
  final client = ref.watch(apiClientProvider);
  if (client == null) return Future.error(StateError('Not signed in'));
  return client.progress(window: window);
});

/// GET /lookback; [month] null asks for the last completed month.
final lookbackProvider = FutureProvider.autoDispose.family<Lookback, String?>((ref, month) {
  final client = ref.watch(apiClientProvider);
  if (client == null) return Future.error(StateError('Not signed in'));
  return client.lookback(month: month);
});

/// GET /milestones, the caller's and the couple's, newest first.
final milestonesProvider = FutureProvider.autoDispose<List<Milestone>>((ref) {
  final client = ref.watch(apiClientProvider);
  if (client == null) return Future.error(StateError('Not signed in'));
  return client.milestones();
});

/// The writes of streak forgiveness. Each one reloads Today and Us, because freezes, repair and
/// the shared streak are derived by the server.
class StreakActions {
  StreakActions(this._ref);

  final Ref _ref;

  ApiClient get _client => _ref.read(apiClientProvider) ?? (throw StateError('Not signed in'));

  Future<void> _reload() async {
    if (_ref.exists(todayProvider)) unawaited(_ref.read(todayProvider.notifier).refresh());
    if (_ref.exists(boardProvider)) unawaited(_ref.read(boardProvider.notifier).refresh());
  }

  Future<AwayCreated> createAway({
    required String from,
    required String to,
    String note = '',
  }) async {
    final created = await _client.createAway(from: from, to: to, note: note);
    await _reload();
    return created;
  }

  Future<void> deleteAway(int id) async {
    await _client.deleteAway(id);
    await _reload();
  }

  /// Spends one of the caller's freezes on the partner's missed [date].
  Future<Freezes> cover(String date) async {
    final freezes = await _client.coverStreak(date);
    await _reload();
    return freezes;
  }
}

final streakActionsProvider = Provider<StreakActions>(StreakActions.new);
