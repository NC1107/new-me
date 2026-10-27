import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../api/models.dart';
import '../../state/v7.dart';
import '../../theme/accent.dart';
import '../../theme/tokens.dart';
import '../../theme/typography.dart';
import '../../util/format.dart';
import '../../widgets/app_card.dart';
import '../../widgets/cached_view.dart';
import '../../widgets/page_scaffold.dart';
import '../insights/insights_widgets.dart';
import 'milestone_copy.dart';

IconData milestoneIcon(Milestone m) => switch (m.kind) {
  'streak' => Icons.local_fire_department_rounded,
  'shared_streak' => Icons.favorite_rounded,
  'first_10k_steps' => Icons.directions_walk_rounded,
  'first_all_quests' => Icons.task_alt_rounded,
  _ => Icons.emoji_events_rounded,
};

AccentPalette milestonePalette(Milestone m) => accentById(switch (m.kind) {
  'shared_streak' => 'rose',
  'first_10k_steps' => 'sky',
  'first_all_quests' => 'green',
  _ => 'amber',
});

/// Every milestone earned, yours and the couple's, newest first.
class MilestonesPage extends ConsumerWidget {
  const MilestonesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final milestones = ref.watch(milestonesProvider);
    return PageScaffold(
      title: 'Milestones',
      subtitle: 'Streaks and firsts, each celebrated once',
      children: milestones.when(
        data: (list) => list.isEmpty
            ? [
                Text(
                  'Nothing yet. Your first one is a 7 day streak, or your first 10,000 step day.',
                  style: AppText.body.copyWith(color: kInkSecondary),
                ),
              ]
            : [
                AppCard(
                  padding: EdgeInsets.zero,
                  child: Column(
                    children: [
                      for (final (i, m) in list.indexed) ...[
                        if (i > 0) const Divider(height: 2, thickness: 2, color: kBorder),
                        MilestoneRow(milestone: m),
                      ],
                    ],
                  ),
                ),
              ],
        error: (e, _) => [
          ErrorBlock(
            title: 'Could not load milestones',
            error: e,
            onRetry: () async => ref.invalidate(milestonesProvider),
          ),
        ],
        loading: () => const [Center(child: CircularProgressIndicator.adaptive())],
      ),
    );
  }
}

class MilestoneRow extends StatelessWidget {
  const MilestoneRow({super.key, required this.milestone});

  final Milestone milestone;

  @override
  Widget build(BuildContext context) {
    final m = milestone;
    final date = m.achievedOn.isEmpty
        ? ''
        : DateFormat.yMMMd().format(parseLocalDate(m.achievedOn));
    return Semantics(
      container: true,
      label: '${milestoneOwner(m)}: ${m.title}${date.isEmpty ? '' : ', $date'}',
      excludeSemantics: true,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 68),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            children: [
              IconDisc(icon: milestoneIcon(m), palette: milestonePalette(m), size: 44),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(m.title, style: AppText.body.copyWith(fontWeight: FontWeight.w800)),
                    Text(
                      [milestoneOwner(m), if (date.isNotEmpty) date].join(' - '),
                      style: AppText.caption.copyWith(color: kInkSecondary),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
