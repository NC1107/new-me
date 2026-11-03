import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/models.dart';
import '../../state/training.dart';
import '../../theme/tokens.dart';
import '../../theme/typography.dart';
import '../../widgets/info_note.dart';
import '../../widgets/app_card.dart';
import '../../widgets/app_widgets.dart';
import '../../widgets/page_scaffold.dart';
import 'calisthenics_routines.dart';
import 'guided_page.dart';

/// Calisthenics: four fixed bodyweight routines from beginner to intense on the guided runner.
class CalisthenicsPage extends ConsumerWidget {
  const CalisthenicsPage({super.key});

  void _open(BuildContext context, CalLevel level) {
    HapticFeedback.selectionClick();
    unawaited(pushPage(context, GuidedPage(routine: calisthenicsRoutine(level))));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final catalog = ref.watch(exercisesProvider).value?.data;
    return PageScaffold(
      title: 'Calisthenics',
      children: [
        Text(
          'No equipment. Do one 2 to 3 days a week.',
          style: AppText.body.copyWith(color: kInkSecondary),
        ),
        const SizedBox(height: 16),
        const FieldLabel('Levels'),
        for (final level in kCalLevels) ...[
          _LevelCard(level: level, catalog: catalog, onTap: () => _open(context, level)),
          const SizedBox(height: 10),
        ],
        InfoNote.label(
          'Sources and safety',
          paragraphs: [
            'Rep exercises are at your own pace: tap Done when you finish. Holds count down.',
            kCalOrderNote,
            kCalCitation,
            kCalIntervalNote,
            kCalSizingNote,
            kCalSafety,
          ],
        ),
      ],
    );
  }
}

class _LevelCard extends StatelessWidget {
  const _LevelCard({required this.level, required this.catalog, required this.onTap});

  final CalLevel level;
  final ExerciseCatalog? catalog;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = catalog;
    final holds = c == null ? null : buildCalisthenicsHolds(level, c);
    final ready = holds != null && holds.isNotEmpty;
    final facts = [
      if (ready) 'About ${calMinutes(holds)} min',
      '${level.rounds} rounds',
    ].join(', ');
    return AppCard(
      onTap: onTap,
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(level.name, style: AppText.headline),
                const SizedBox(height: 2),
                Text(facts, style: AppText.caption.copyWith(color: kInkSecondary)),
              ],
            ),
          ),
          const Icon(Icons.chevron_right_rounded, color: kInkMuted),
        ],
      ),
    );
  }
}
