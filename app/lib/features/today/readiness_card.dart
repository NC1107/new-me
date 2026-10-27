import 'package:flutter/material.dart';

import '../../api/models.dart';
import '../../theme/accent.dart';
import '../../theme/tokens.dart';
import '../../theme/typography.dart';
import '../../widgets/accent_text.dart';
import '../../widgets/app_card.dart';
import '../../widgets/chunky_button.dart';
import '../../widgets/dialogs.dart';
import '../../widgets/dismiss_x.dart';

/// The headline for a readiness level, in plain words.
String readinessTitle(ReadinessLevel level) => switch (level) {
  ReadinessLevel.ready => 'Ready to go',
  ReadinessLevel.normal => 'A normal day',
  ReadinessLevel.easy => 'Take it easy today',
};

IconData readinessIcon(ReadinessLevel level) => switch (level) {
  ReadinessLevel.ready => Icons.bolt_rounded,
  ReadinessLevel.normal => Icons.balance_rounded,
  ReadinessLevel.easy => Icons.spa_rounded,
};

AccentPalette readinessPalette(ReadinessLevel level) => switch (level) {
  ReadinessLevel.ready => accentById('green'),
  ReadinessLevel.normal => accentById('sky'),
  ReadinessLevel.easy => accentById('amber'),
};

/// How rested the body looks this morning, with the one or two reasons. Tapping explains the
/// numbers; the plan is one step further.
class ReadinessCard extends StatelessWidget {
  const ReadinessCard({
    super.key,
    required this.readiness,
    required this.onTap,
    required this.onDismiss,
  });

  final Readiness readiness;
  final VoidCallback onTap;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final level = readiness.level;
    final palette = readinessPalette(level);
    final reasons = readiness.findings.take(2).toList();
    return AppCard(
      onTap: onTap,
      semanticLabel:
          'Readiness: ${readinessTitle(level)}. ${reasons.map((r) => r.text).join('. ')}',
      padding: const EdgeInsets.fromLTRB(14, 6, 2, 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(color: palette.tint, shape: BoxShape.circle),
              child: Icon(readinessIcon(level), size: 24, color: palette.lip),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(readinessTitle(level), style: AppText.headline.copyWith(fontSize: 18)),
                  for (final r in reasons)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(r.text, style: AppText.label.copyWith(color: kInkSecondary)),
                    ),
                  if (readiness.basisNote case final note?)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(note, style: AppText.caption),
                    ),
                  ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: 44),
                    child: Row(
                      children: [
                        Flexible(
                          child: Text(
                            'See why and the plan',
                            style: AppText.label.copyWith(color: context.accentText),
                          ),
                        ),
                        Icon(Icons.chevron_right_rounded, color: context.accentText),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          DismissX(label: 'Dismiss readiness', onPressed: onDismiss),
        ],
      ),
    );
  }
}

Future<void> showReadinessSheet(
  BuildContext context, {
  required Readiness readiness,
  VoidCallback? onOpenPlan,
}) => showAppSheet<void>(
  context,
  builder: (_) => ReadinessSheet(readiness: readiness, onOpenPlan: onOpenPlan),
);

/// What the readiness level is made of, in the words the numbers deserve.
class ReadinessSheet extends StatelessWidget {
  const ReadinessSheet({super.key, required this.readiness, this.onOpenPlan});

  final Readiness readiness;

  /// Closes this sheet and opens the plan; null hides the button.
  final VoidCallback? onOpenPlan;

  @override
  Widget build(BuildContext context) {
    final level = readiness.level;
    final palette = readinessPalette(level);
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(kGutter, 4, kGutter, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(color: palette.tint, shape: BoxShape.circle),
                  child: Icon(readinessIcon(level), size: 24, color: palette.lip),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Semantics(
                    header: true,
                    child: Text(readinessTitle(level), style: AppText.title),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            for (final r in readiness.findings)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Padding(
                      padding: EdgeInsets.only(top: 6, right: 10),
                      child: Icon(Icons.circle, size: 7, color: kInkSecondary),
                    ),
                    Expanded(child: Text(r.text, style: AppText.body)),
                  ],
                ),
              ),
            const SizedBox(height: 8),
            const Text('How it is worked out', style: AppText.headline),
            const SizedBox(height: 6),
            Text(
              'Last night\'s sleep is set against your sleep target. An hour or more short counts '
              'against you, within 15 minutes of it counts for you.',
              style: AppText.body.copyWith(color: kInkSecondary),
            ),
            const SizedBox(height: 8),
            Text(
              'HRV and resting heart rate are set against your own average of the last 30 days. '
              'HRV 15% or more below it, or a resting heart rate 5 bpm or more above it, counts '
              'against you.',
              style: AppText.body.copyWith(color: kInkSecondary),
            ),
            const SizedBox(height: 8),
            Text(
              readiness.basisNote == null
                  ? 'Take it easy is a suggestion. Your points and streak work the same either way.'
                  : '${readiness.basisNote}. HRV and resting heart rate are compared with your own '
                        'usual once there are 7 days of readings. Your points and streak work the '
                        'same either way.',
              style: AppText.body.copyWith(color: kInkSecondary),
            ),
            if (onOpenPlan != null) ...[
              const SizedBox(height: 20),
              ChunkyButton.secondary(label: "See today's plan", onPressed: onOpenPlan),
            ],
          ],
        ),
      ),
    );
  }
}
