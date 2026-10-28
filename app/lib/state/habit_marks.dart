import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/api_client.dart';
import '../api/habit_models.dart';
import 'board.dart';
import 'session.dart';
import 'today.dart';

/// Marking habits off. The strip changes before the request leaves, and the server's answer only
/// adds the points; a refusal puts the habit back.
class HabitMarks {
  HabitMarks(this._ref);

  final Ref _ref;

  /// Requests in flight per habit. While one is pending a failure must not undo the newer tap.
  final _pending = <int, int>{};

  /// Numbers each request; only the newest answer may set the day and quests.
  int _requests = 0;

  ApiClient get _client {
    final client = _ref.read(apiClientProvider);
    if (client == null) throw StateError('Not signed in');
    return client;
  }

  /// Sets a slot done or undone. Returns false when the server refused and the tap was undone.
  Future<bool> setSlot(int habitId, int slot, {required bool done}) => _mark(
    habitId,
    (h) => h.withSlotDone(slot, done),
    (client, date) => client.markHabitSlot(habitId, date, slot: slot, done: done),
  );

  Future<bool> setCount(int habitId, int count) => _mark(
    habitId,
    (h) => h.withCount(count),
    (client, date) => client.markHabitCount(habitId, date, count),
  );

  /// For a day other than today, which Today does not hold. Throws what the API throws.
  Future<HabitMarkResult> markOtherDay(
    String date,
    int habitId, {
    int? slot,
    bool? done,
    int? count,
  }) async {
    final result = count != null
        ? await _client.markHabitCount(habitId, date, count)
        : await _client.markHabitSlot(habitId, date, slot: slot!, done: done!);
    unawaited(_ref.read(todayProvider.notifier).refresh());
    _refreshBoard();
    return result;
  }

  Future<bool> _mark(
    int habitId,
    HabitState Function(HabitState) change,
    Future<HabitMarkResult> Function(ApiClient client, String date) send,
  ) async {
    final notifier = _ref.read(todayProvider.notifier);
    final today = _ref.read(todayProvider).value?.data;
    final before = today?.habits.where((h) => h.id == habitId).firstOrNull;
    if (today == null || before == null) return false;
    final date = today.localToday;

    unawaited(notifier.replace(today.copyWith(habits: _swap(today.habits, change(before)))));
    _pending[habitId] = (_pending[habitId] ?? 0) + 1;
    final request = ++_requests;
    var settled = false;
    void settleOnce() {
      if (settled) return;
      settled = true;
      _settle(habitId);
    }

    try {
      final result = await send(_client, date);
      settleOnce();
      final newest = request == _requests;
      // An older answer's score is skipped in favour of the newest; if the newest then fails,
      // nothing would ever show the server's score, so Today is reloaded instead.
      _scoreSkipped = !newest;
      await _apply(notifier, date, result, habitId, newest: newest);
      _refreshBoard();
      return true;
    } on ApiException {
      settleOnce();
      if (!_stillPending(habitId)) await _revert(notifier, date, before);
      if (request == _requests && _scoreSkipped) {
        _scoreSkipped = false;
        unawaited(notifier.refresh());
      }
      return false;
    } finally {
      settleOnce();
    }
  }

  bool _scoreSkipped = false;

  void _settle(int habitId) => _pending[habitId] = (_pending[habitId] ?? 1) - 1;

  bool _stillPending(int habitId) => (_pending[habitId] ?? 0) > 0;

  Future<void> _apply(
    TodayNotifier notifier,
    String date,
    HabitMarkResult result,
    int habitId, {
    required bool newest,
  }) async {
    final current = _ref.read(todayProvider).value?.data;
    if (current == null) return;
    if (current.localToday != date) return notifier.refresh();
    final answered = result.habits.where((h) => h.id == habitId).firstOrNull;
    final replaceHabit = answered != null && !_stillPending(habitId);
    await notifier.replace(
      current.copyWith(
        day: newest ? result.day.score : null,
        quests: newest ? result.day.quests : null,
        habits: replaceHabit ? _swap(current.habits, answered) : null,
      ),
    );
  }

  Future<void> _revert(TodayNotifier notifier, String date, HabitState before) async {
    final current = _ref.read(todayProvider).value?.data;
    if (current == null || current.localToday != date) return;
    await notifier.replace(current.copyWith(habits: _swap(current.habits, before)));
  }

  List<HabitState> _swap(List<HabitState> habits, HabitState next) => [
    for (final h in habits) h.id == next.id ? next : h,
  ];

  void _refreshBoard() {
    if (_ref.exists(boardProvider)) unawaited(_ref.read(boardProvider.notifier).refresh());
  }
}

final habitMarksProvider = Provider<HabitMarks>(HabitMarks.new);
