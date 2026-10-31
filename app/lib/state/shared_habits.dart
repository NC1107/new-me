import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/api_client.dart';
import '../api/shared_habit_models.dart';
import 'board.dart';
import 'clock.dart';
import 'me.dart';
import 'session.dart';
import 'today.dart';

/// The household's shared habits as I see them, due ones first. Doing one shows at once and a
/// refusal puts it back; the gems it pays land on Today and Us, which are refreshed after.
class SharedHabitsNotifier extends AsyncNotifier<List<SharedHabit>> {
  @override
  Future<List<SharedHabit>> build() {
    final client = ref.watch(apiClientProvider);
    if (client == null) return Future.error(StateError('Not signed in'));
    return client.sharedHabits();
  }

  ApiClient get _client {
    final client = ref.read(apiClientProvider);
    if (client == null) throw StateError('Not signed in');
    return client;
  }

  List<SharedHabit> get _current => state.value ?? const [];

  Future<void> refresh() async {
    final client = ref.read(apiClientProvider);
    if (client == null) return;
    try {
      state = AsyncData(await client.sharedHabits());
    } on Object {
      // The list is an extra on Us and Today; a failed refresh keeps what is shown.
    }
  }

  /// A change moves a chore between due and done, so the list is re-read from the server rather
  /// than patched, which also keeps its order right.
  Future<void> _reload() async {
    state = AsyncData(await _client.sharedHabits());
  }

  Future<void> create(String name, String icon, SharedSchedule schedule) async {
    await _client.createSharedHabit({'name': name, 'icon': icon, 'schedule': schedule.toJson()});
    await _reload();
  }

  Future<void> save(int id, String name, String icon, SharedSchedule schedule) async {
    await _client.patchSharedHabit(id, {'name': name, 'icon': icon, 'schedule': schedule.toJson()});
    await _reload();
  }

  Future<void> delete(int id) async {
    await _client.deleteSharedHabit(id);
    await _reload();
  }

  /// Marks a chore done by me. Throws when the server refuses, after putting the list back.
  Future<void> markDone(int id) async {
    final before = _current;
    final userId = ref.read(sessionProvider).session?.userId;
    final name = ref.read(meProvider).value?.data.user.name ?? '';
    final now = ref.read(clockProvider)();
    if (userId != null) {
      state = AsyncData([
        for (final h in before)
          h.id == id ? h.markedDoneBy(SharedLast(userId: userId, name: name, at: now)) : h,
      ]);
    }
    try {
      await _client.doneSharedHabit(id);
      await _reload();
    } on Object {
      state = AsyncData(before);
      rethrow;
    }
    _refreshGems();
  }

  Future<void> undo(int id) async {
    await _client.undoSharedHabit(id);
    await _reload();
    _refreshGems();
  }

  void _refreshGems() {
    if (ref.exists(todayProvider)) unawaited(ref.read(todayProvider.notifier).refresh());
    if (ref.exists(boardProvider)) unawaited(ref.read(boardProvider.notifier).refresh());
  }
}

final sharedHabitsProvider = AsyncNotifierProvider<SharedHabitsNotifier, List<SharedHabit>>(
  SharedHabitsNotifier.new,
);
