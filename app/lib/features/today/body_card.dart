import 'package:flutter/material.dart';

import '../../api/models.dart';
import '../../theme/quest_style.dart';
import '../../theme/tokens.dart';
import '../../theme/typography.dart';
import '../../widgets/app_card.dart';
import '../../widgets/quest_copy.dart';

/// What the Body row says under its title: last night's sleep and this week's workouts when
/// there is data, else a plain pointer to what Insights holds. Weight and heart readings stay off
/// Today; they live under Insights and Me.
String bodySummary(HealthStatus health, Insights? insights) {
  final week = insights?.workouts.week.count ?? 0;
  final parts = [
    if (health.metrics['sleep_minutes'] case final minutes?) 'Slept ${durationLabel(minutes)}',
    if (week > 0) '$week ${week == 1 ? 'workout' : 'workouts'} this week',
  ];
  return parts.isEmpty ? 'Steps, sleep and workouts' : parts.join(' - ');
}

/// One slim row that opens Insights, where the body numbers and their trends are.
class BodyRow extends StatelessWidget {
  const BodyRow({super.key, required this.summary, required this.onTap});

  final String summary;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = questPalette('exercise');
    return AppCard(
      onTap: onTap,
      semanticLabel: 'Body, $summary, open Insights',
      padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 48),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(color: palette.tint, shape: BoxShape.circle),
              child: Icon(Icons.monitor_heart_rounded, size: 24, color: palette.lip),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Body', style: AppText.headline),
                  Text(summary, style: AppText.caption.copyWith(color: kInkSecondary)),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: kInkMuted),
          ],
        ),
      ),
    );
  }
}
