import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/api_client.dart';
import '../api/habit_models.dart';
import 'board.dart';
import 'cached_notifier.dart';
import 'cached_resource.dart';
import 'caches.dart';
import 'session.dart';
import 'today.dart';

/// The caller's habits for the management screens and for planning reminders. Every change goes
/// to the server first and then refreshes Today, whose due list it can alter.
class HabitsNotifier extends CachedNotifier<HabitList> {
  @override
  ResponseCache<HabitList> get cache => habitsCache;

  @override
  Future<HabitList> fetch(ApiClient client) async => HabitList(await client.habits());

  ApiClient get _client {
    final client = ref.read(apiClientProvider);
    if (client == null) throw StateError('Not signed in');
    return client;
  }

  List<Habit> get _current => state.value?.data.habits ?? const [];

  Future<Habit> create(HabitDraft draft) async {
    final created = await _client.createHabit(draft);
    await replace(HabitList([..._current, created]));
    _refreshToday();
    return created;
  }

  Future<void> save(int id, HabitDraft draft) async {
    final saved = await _client.patchHabit(id, draft.toPatchJson());
    await _swap(saved);
  }

  Future<void> setPaused(int id, bool paused) async {
    final saved = await _client.patchHabit(id, {'paused': paused});
    await _swap(saved);
  }

  Future<void> delete(int id) async {
    await _client.deleteHabit(id);
    await replace(
      HabitList([
        for (final h in _current)
          if (h.id != id) h,
      ]),
    );
    _refreshToday();
  }

  /// The list moves at once; a refused order puts the server's back.
  Future<void> reorder(List<int> ids) async {
    final byId = {for (final h in _current) h.id: h};
    unawaited(replace(HabitList([for (final id in ids) ?byId[id]])));
    try {
      await replace(HabitList(await _client.orderHabits(ids)));
    } on Object {
      await refresh();
      rethrow;
    } finally {
      _refreshToday();
    }
  }

  Future<void> _swap(Habit saved) async {
    await replace(HabitList([for (final h in _current) h.id == saved.id ? saved : h]));
    _refreshToday();
  }

  void _refreshToday() {
    unawaited(ref.read(todayProvider.notifier).refresh());
    if (ref.exists(boardProvider)) unawaited(ref.read(boardProvider.notifier).refresh());
  }
}

final habitsProvider = AsyncNotifierProvider<HabitsNotifier, Cached<HabitList>>(HabitsNotifier.new);
