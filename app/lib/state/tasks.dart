import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/api_client.dart';
import '../api/models.dart';
import 'board.dart';
import 'session.dart';
import 'together.dart';

/// Agreed tasks of both people and the history of finished ones. Not cached: the Tasks part of
/// Us stays hidden until this loads.
class TasksNotifier extends AsyncNotifier<TaskList> {
  @override
  Future<TaskList> build() async {
    final client = ref.watch(apiClientProvider);
    if (client == null) return const TaskList();
    return client.tasks();
  }

  Future<void> refresh() async {
    final client = ref.read(apiClientProvider);
    if (client == null) return;
    try {
      state = AsyncData(await client.tasks());
    } on ApiException catch (e) {
      debugPrint('[NEWME] tasks refresh failed: $e');
    }
  }

  ApiClient _client() => ref.read(apiClientProvider) ?? (throw StateError('Not signed in'));

  /// Runs one change and reloads, also when it was refused, because a refusal means the other
  /// phone changed the task first. Throws [ApiException].
  Future<void> _change(Future<Object?> Function(ApiClient client) call) async {
    final client = _client();
    try {
      await call(client);
    } on ApiException {
      await _reload();
      rethrow;
    }
    await _reload();
  }

  /// Proposes a task; the other person agrees first unless I am alone on the server.
  Future<void> propose({
    required String title,
    required int assigneeId,
    required int stake,
    required String deadline,
  }) => _change(
    (c) => c.createTask(title: title, assigneeId: assigneeId, stake: stake, deadline: deadline),
  );

  Future<void> edit(int id, {String? title, int? assigneeId, int? stake, String? deadline}) =>
      _change(
        (c) =>
            c.patchTask(id, title: title, assigneeId: assigneeId, stake: stake, deadline: deadline),
      );

  Future<void> withdraw(int id) => _change((c) => c.withdrawTask(id));

  Future<void> answer(int id, {required bool agree}) =>
      _change((c) => c.answerTask(id, agree: agree));

  /// Marks my task done, which wins its stake in gems.
  Future<void> finish(int id) => _change((c) => c.finishTask(id));

  // Gems move with a task, so the balances on Us and the reward bar follow it.
  Future<void> _reload() async {
    await Future.wait([
      refresh(),
      ref.read(rewardsProvider.notifier).refresh(),
      ref.read(boardProvider.notifier).refresh(),
    ]);
  }
}

final tasksProvider = AsyncNotifierProvider<TasksNotifier, TaskList>(TasksNotifier.new);
