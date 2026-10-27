import 'package:flutter/material.dart';

import '../../api/models.dart';
import '../../theme/accent.dart';
import '../../theme/quest_style.dart';
import '../../theme/tokens.dart';
import '../../theme/typography.dart';
import '../../widgets/dialogs.dart';
import 'readiness_card.dart';

Future<void> showPlanSheet(BuildContext context, {required Plan plan, Readiness? readiness}) =>
    showAppSheet<void>(
      context,
      builder: (_) => PlanSheet(plan: plan, readiness: readiness),
    );

/// The day laid out: what the data already did, what is left and the easiest way to finish it,
/// and the habits by time.
class PlanSheet extends StatelessWidget {
  const PlanSheet({super.key, required this.plan, this.readiness});

  final Plan plan;
  final Readiness? readiness;

  List<PlanItem> _of(PlanItemKind kind) => [
    for (final i in plan.items)
      if (i.kind == kind) i,
  ];

  @override
  Widget build(BuildContext context) {
    final groups = [
      ('Already done', _of(PlanItemKind.done)),
      ('Still to do', _of(PlanItemKind.todo)),
      ('Habits, by time', _of(PlanItemKind.habit)),
    ];
    final r = readiness;
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(kGutter, 4, kGutter, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Semantics(header: true, child: const Text("Today's plan", style: AppText.title)),
            if (plan.summary.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(plan.summary, style: AppText.body.copyWith(color: kInkSecondary)),
            ],
            if (r != null) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  Icon(readinessIcon(r.level), size: 20, color: readinessPalette(r.level).lip),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      readinessTitle(r.level),
                      style: AppText.label.copyWith(fontWeight: FontWeight.w800),
                    ),
                  ),
                ],
              ),
            ],
            if (plan.items.isEmpty) ...[
              const SizedBox(height: 16),
              Text(
                'Nothing planned. Enjoy the day.',
                style: AppText.body.copyWith(color: kInkSecondary),
              ),
            ],
            for (final (title, items) in groups)
              if (items.isNotEmpty) ...[
                const SizedBox(height: 18),
                Semantics(header: true, child: Text(title, style: AppText.headline)),
                const SizedBox(height: 4),
                for (final item in items) _PlanRow(item: item),
              ],
          ],
        ),
      ),
    );
  }
}

class _PlanRow extends StatelessWidget {
  const _PlanRow({required this.item});

  final PlanItem item;

  @override
  Widget build(BuildContext context) {
    final palette = item.kind == PlanItemKind.habit ? accentById('teal') : questPalette(item.key);
    final icon = switch (item.kind) {
      PlanItemKind.done => Icons.check_circle_rounded,
      PlanItemKind.todo => Icons.radio_button_unchecked_rounded,
      PlanItemKind.habit => Icons.repeat_rounded,
    };
    final color = item.kind == PlanItemKind.done ? kSuccess : palette.lip;
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 44),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 1),
              child: Icon(icon, size: 22, color: color),
            ),
            const SizedBox(width: 12),
            Expanded(child: Text(item.text, style: AppText.body)),
          ],
        ),
      ),
    );
  }
}
