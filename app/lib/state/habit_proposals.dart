import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/habit_models.dart';
import 'board.dart';
import 'session.dart';
import 'today.dart';

/// The partner's habit changes waiting for me. Answering one removes it at once; a refused
/// answer puts the server's list back.
class HabitProposalsNotifier extends AsyncNotifier<HabitProposals> {
  @override
  Future<HabitProposals> build() {
    final client = ref.watch(apiClientProvider);
    if (client == null) return Future.error(StateError('Not signed in'));
    return client.habitProposals();
  }

  Future<void> refresh() async {
    final client = ref.read(apiClientProvider);
    if (client == null) return;
    try {
      state = AsyncData(await client.habitProposals());
    } on Object {
      // The card is an extra on Us; a failed refresh keeps what is shown.
    }
  }

  Future<void> answer(int habitId, {required bool approve}) async {
    final client = ref.read(apiClientProvider);
    if (client == null) throw StateError('Not signed in');
    final before = state.value;
    if (before != null) state = AsyncData(before.without(habitId));
    try {
      await client.answerHabitProposal(habitId, approve: approve);
    } on Object {
      await refresh();
      rethrow;
    }
    if (approve) {
      if (ref.exists(todayProvider)) unawaited(ref.read(todayProvider.notifier).refresh());
      if (ref.exists(boardProvider)) unawaited(ref.read(boardProvider.notifier).refresh());
    }
  }
}

final habitProposalsProvider = AsyncNotifierProvider<HabitProposalsNotifier, HabitProposals>(
  HabitProposalsNotifier.new,
);

/// My partner's name for "Waiting for Nadia", or null while I have none.
final partnerNameProvider = Provider<String?>((ref) {
  final users = ref.watch(boardProvider.select((b) => b.value?.data.users));
  return users != null && users.length > 1 ? users[1].name : null;
});
