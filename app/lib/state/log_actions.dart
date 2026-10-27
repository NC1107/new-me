import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/api_client.dart';
import '../api/models.dart';
import 'board.dart';
import 'session.dart';
import 'today.dart';

/// The write side of the log: every save and delete keeps Today and the Board in step.
class LogActions {
  const LogActions(this._ref);

  final Ref _ref;

  ApiClient get _client {
    final client = _ref.read(apiClientProvider);
    if (client == null) throw StateError('Not signed in');
    return client;
  }

  Future<LogResult> create(LogDraft draft) async {
    final result = await _client.createLog(draft);
    await _ref.read(todayProvider.notifier).applyLog(result);
    _refreshBoard();
    return result;
  }

  Future<void> delete(LogEntry entry) async {
    await _client.deleteLog(entry);
    await _ref.read(todayProvider.notifier).refresh();
    _refreshBoard();
  }

  Future<List<LogEntry>> entriesFor(String date) => _client.logs(date: date);

  Future<List<RecentMeal>> recentMeals() => _client.recentMeals();

  void _refreshBoard() {
    if (_ref.exists(boardProvider)) unawaited(_ref.read(boardProvider.notifier).refresh());
  }
}

final logActionsProvider = Provider<LogActions>(LogActions.new);
