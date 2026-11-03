import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/shared_habit_models.dart';
import '../../state/action_needed.dart';
import '../../theme/tokens.dart';
import '../../theme/typography.dart';
import '../../util/format.dart';
import '../../widgets/app_card.dart';
import '../../widgets/chunky_button.dart';
import '../habits/habit_proposals_card.dart';
import '../shared_habits/shared_habit_sheet.dart';
import 'reward_proposals_card.dart';
import 'task_proposals_card.dart';

/// The first card on Us: everything my partner asked of me that waits for an answer, in one
/// place. Shows nothing when there is nothing to answer, so Us stays quiet.
class ActionNeededCard extends ConsumerWidget {
  const ActionNeededCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final needed = ref.watch(actionNeededProvider);
    if (needed.isEmpty) return const SizedBox.shrink();
    final groups = <Widget>[
      if (needed.habits > 0) const HabitProposalRows(),
      if (needed.rewards > 0) const RewardProposalRows(),
      if (needed.tasks > 0) const TaskProposalRows(),
      if (needed.chores.isNotEmpty) _ChoreRows(chores: needed.chores),
    ];
    return Padding(
      padding: const EdgeInsets.only(bottom: kCardGap),
      child: AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Semantics(header: true, child: const Text('Action needed', style: AppText.headline)),
            const SizedBox(height: 12),
            for (final (i, group) in groups.indexed) ...[
              if (i > 0) const Divider(height: 24, thickness: 2, color: kBorder),
              group,
            ],
          ],
        ),
      ),
    );
  }
}

/// Chores whose worth my partner suggested. The number is agreed or countered in the chore's own
/// sheet, so the row opens it.
class _ChoreRows extends StatelessWidget {
  const _ChoreRows({required this.chores});

  final List<SharedHabit> chores;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      for (final (i, h) in chores.indexed) ...[
        if (i > 0) const Divider(height: 24, thickness: 2, color: kBorder),
        Row(
          children: [
            Expanded(
              child: Text(
                '${h.proposedByName.isEmpty ? 'Your partner' : h.proposedByName} suggests '
                '${plural(h.proposedWorth ?? h.gems, 'gem', 'gems')} for ${h.name}',
                style: AppText.label.copyWith(fontWeight: FontWeight.w800),
              ),
            ),
            const SizedBox(width: 12),
            SizedBox(
              width: 104,
              child: ChunkyButton.secondary(
                label: 'Review',
                onPressed: () {
                  HapticFeedback.selectionClick();
                  showSharedHabitSheet(context, habit: h);
                },
              ),
            ),
          ],
        ),
      ],
    ],
  );
}
