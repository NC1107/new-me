import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/models.dart';
import '../../state/training.dart';
import '../../theme/tokens.dart';
import '../../theme/typography.dart';
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
          'Bodyweight workouts with no equipment. Rep exercises are at your own pace: tap Done '
          'when you finish. Holds count down. Do one on 2 to 3 days a week with a day off between.',
          style: AppText.body.copyWith(color: kInkSecondary),
        ),
        const SizedBox(height: 16),
        const FieldLabel('Levels'),
        for (final level in kCalLevels) ...[
          _LevelCard(level: level, catalog: catalog, onTap: () => _open(context, level)),
          const SizedBox(height: 10),
        ],
        const SizedBox(height: 4),
        for (final note in const [
          kCalOrderNote,
          kCalCitation,
          kCalIntervalNote,
          kCalSizingNote,
        ]) ...[
          Text(note, style: AppText.caption.copyWith(color: kInkMuted)),
          const SizedBox(height: 4),
        ],
        const SizedBox(height: 8),
        Text(kCalSafety, style: AppText.caption.copyWith(color: kInkMuted)),
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
    final sized = ready && _usesYourMax(level, c!);
    final facts =
        '${ready ? 'About ${calMinutes(holds)} minutes: ' : ''}warm-up, ${level.rounds} rounds of '
        '${level.circuit.length} exercises, cool-down.';
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
                const SizedBox(height: 2),
                Text(level.blurb, style: AppText.caption.copyWith(color: kInkSecondary)),
                if (sized) ...[
                  const SizedBox(height: 2),
                  Text(
                    'Reps use ${level.maxPercent}% of your max where you have one.',
                    style: AppText.caption.copyWith(color: kInkMuted),
                  ),
                ],
              ],
            ),
          ),
          const Icon(Icons.chevron_right_rounded, color: kInkMuted),
        ],
      ),
    );
  }

  bool _usesYourMax(CalLevel level, ExerciseCatalog catalog) =>
      level.circuit.any((s) => s.sized && (catalog.byKey(s.key)?.maxTest?.reps ?? 0) > 0);
}
