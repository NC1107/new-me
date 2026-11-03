import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/shared_habit_models.dart';
import 'habit_proposals.dart';
import 'session.dart';
import 'shared_habits.dart';
import 'tasks.dart';
import 'together.dart';

/// What my partner asked of me that is still unanswered, by kind. These are the things the Action
/// needed card on Us lists and the Us tab badge counts.
class ActionNeeded {
  const ActionNeeded({this.habits = 0, this.rewards = 0, this.tasks = 0, this.chores = const []});

  final int habits;
  final int rewards;
  final int tasks;

  /// Chores whose worth my partner suggested.
  final List<SharedHabit> chores;

  int get count => habits + rewards + tasks + chores.length;
  bool get isEmpty => count == 0;
}

final actionNeededProvider = Provider<ActionNeeded>((ref) {
  final userId = ref.watch(sessionProvider.select((s) => s.session?.userId));
  return ActionNeeded(
    habits: ref.watch(habitProposalsProvider).value?.items.length ?? 0,
    rewards: ref.watch(rewardsProvider).value?.proposalsFor(userId).length ?? 0,
    tasks: ref.watch(tasksProvider).value?.proposalsFor(userId).length ?? 0,
    chores: [
      for (final h in ref.watch(sharedHabitsProvider).value ?? const <SharedHabit>[])
        if (h.proposalForMe(userId)) h,
    ],
  );
});
