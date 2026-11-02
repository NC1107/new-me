import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/coach_models.dart';
import '../../state/coach_chat.dart';
import '../../theme/tokens.dart';
import '../../theme/typography.dart';
import '../../util/errors.dart';
import '../../widgets/app_card.dart';
import '../../widgets/pressable.dart';
import '../../widgets/page_scaffold.dart';

/// What the coach has saved about the person, which only they can see. Each fact can be
/// forgotten by swiping it away or tapping its button.
class CoachKnowsPage extends ConsumerWidget {
  const CoachKnowsPage({super.key});

  Future<void> _forget(BuildContext context, WidgetRef ref, CoachFact fact) async {
    HapticFeedback.mediumImpact();
    final messenger = ScaffoldMessenger.maybeOf(context);
    try {
      await ref.read(coachFactsProvider.notifier).remove(fact);
    } on Object catch (e) {
      messenger?.showSnackBar(SnackBar(content: Text(errorCopy(e))));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final facts = ref.watch(coachFactsProvider);
    return PageScaffold(
      title: 'What the coach knows',
      children: [
        Text(
          'Things you told your coach, like an injury or the equipment you have. '
          'Only you can see them. The coach uses them when it answers.',
          style: AppText.label.copyWith(color: kInkSecondary, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 16),
        ...switch (facts) {
          AsyncData(:final value) when value.isEmpty => [
            Text(
              'Nothing yet. Tell your coach something about you, and it appears here.',
              style: AppText.body.copyWith(color: kInkSecondary),
            ),
          ],
          AsyncData(:final value) => [
            AppCard(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  for (final (i, fact) in value.indexed) ...[
                    if (i > 0) const Divider(height: 2, thickness: 2, color: kBorder),
                    _FactRow(fact: fact, onForget: () => _forget(context, ref, fact)),
                  ],
                ],
              ),
            ),
          ],
          AsyncError() => [
            Text(
              'Could not load what the coach knows.',
              style: AppText.body.copyWith(color: kDangerText),
            ),
            const SizedBox(height: 8),
            Pressable(
              onTap: () => ref.invalidate(coachFactsProvider),
              child: const SizedBox(
                height: 44,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text('Try again', style: AppText.button),
                ),
              ),
            ),
          ],
          _ => [const Center(child: CircularProgressIndicator())],
        },
      ],
    );
  }
}

class _FactRow extends StatelessWidget {
  const _FactRow({required this.fact, required this.onForget});

  final CoachFact fact;
  final VoidCallback onForget;

  static String _category(String c) => '${c[0].toUpperCase()}${c.substring(1)}';

  @override
  Widget build(BuildContext context) {
    return Dismissible(
      key: ValueKey('coach-fact-${fact.id}'),
      direction: DismissDirection.endToStart,
      onDismissed: (_) => onForget(),
      background: Container(
        color: kDanger,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        child: const Icon(Icons.delete_rounded, color: Colors.white, size: 26),
      ),
      child: ColoredBox(
        color: kSurface,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 68),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 8, 4, 8),
            child: Row(
              children: [
                Expanded(
                  child: Semantics(
                    container: true,
                    label: '${_category(fact.category)}: ${fact.text}',
                    excludeSemantics: true,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _category(fact.category),
                          style: AppText.caption.copyWith(
                            color: kInkMuted,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        Text(fact.text, style: AppText.body),
                      ],
                    ),
                  ),
                ),
                Semantics(
                  button: true,
                  label: 'Forget: ${fact.text}',
                  excludeSemantics: true,
                  onTap: onForget,
                  child: IconButton(
                    onPressed: onForget,
                    tooltip: 'Forget',
                    constraints: const BoxConstraints.tightFor(width: 48, height: 48),
                    icon: const Icon(Icons.delete_outline_rounded, size: 24, color: kInkSecondary),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
