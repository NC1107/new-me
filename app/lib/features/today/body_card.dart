import 'package:flutter/material.dart';

import '../../api/models.dart';
import '../../theme/quest_style.dart';
import '../../theme/tokens.dart';
import '../../theme/typography.dart';
import '../../widgets/app_card.dart';
import '../../widgets/quest_copy.dart';
import '../insights/body_insights.dart';

/// What the Body row says under its title: last night's sleep and this week's workouts when
/// there is data, else a plain pointer to what Insights holds. The smoothed weight rides on the
/// row as its own tile; heart readings stay under Insights and Me.
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
  const BodyRow({super.key, required this.summary, required this.onTap, this.weight});

  final String summary;
  final VoidCallback onTap;

  /// The smoothed weight and its trend; Nick wants weight visible on Today.
  final WeightInsights? weight;

  @override
  Widget build(BuildContext context) {
    final palette = questPalette('exercise');
    return AppCard(
      onTap: onTap,
      semanticLabel: 'Body, $summary${_weightWords(weight)}, open Insights',
      padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ConstrainedBox(
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
          if (weight case final w? when w.hasData)
            Padding(
              padding: const EdgeInsets.only(left: 56, top: 6, right: 4),
              child: WeightTile(weight: w),
            ),
        ],
      ),
    );
  }
}

String _weightWords(WeightInsights? w) {
  if (w == null || !w.hasData) return '';
  final trend = weightTrendLabel(w);
  return ', weight ${weightLabel(w.smoothedKg!)}${trend == null ? '' : ', $trend'}';
}

/// The smoothed weight with its trend arrow and weekly rate, as a small tile on the Body row.
class WeightTile extends StatelessWidget {
  const WeightTile({super.key, required this.weight});

  final WeightInsights weight;

  @override
  Widget build(BuildContext context) {
    final trend = weightTrendLabel(weight);
    return ExcludeSemantics(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(color: kSunken, borderRadius: BorderRadius.circular(10)),
        child: Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 8,
          runSpacing: 2,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.monitor_weight_rounded, size: 18, color: kInkSecondary),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    weightLabel(weight.smoothedKg!),
                    style: AppText.tabular(AppText.label.copyWith(fontWeight: FontWeight.w900)),
                  ),
                ),
              ],
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(weightTrendIcon(weight), size: 18, color: kInkSecondary),
                const SizedBox(width: 4),
                Flexible(
                  child: Text(
                    trend ?? 'trend after a week',
                    style: AppText.caption.copyWith(color: kInkSecondary),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
