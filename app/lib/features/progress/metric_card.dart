import 'package:flutter/material.dart';

import '../../api/models.dart';
import '../../theme/accent.dart';
import '../../theme/quest_style.dart';
import '../../theme/tokens.dart';
import '../../theme/typography.dart';
import '../../widgets/app_card.dart';
import '../board/person_card.dart' show kSuccessText;
import '../insights/insights_widgets.dart';
import 'progress_logic.dart';
import 'sparkline.dart';

IconData metricIcon(String key) => switch (key) {
  'reading_minutes' => questIcon('reading'),
  'steps' => questIcon('steps'),
  'sleep_minutes' => questIcon('sleep'),
  'workouts' => Icons.fitness_center_rounded,
  'pushups' => questIcon('pushups'),
  'protein_g' => questIcon('protein'),
  'habits_kept' => Icons.checklist_rounded,
  'weight_kg' => Icons.monitor_weight_rounded,
  'body_fat_pct' => Icons.percent_rounded,
  'lean_mass_kg' => Icons.accessibility_new_rounded,
  'vo2max' => Icons.air_rounded,
  'resting_hr' => Icons.favorite_rounded,
  _ => Icons.show_chart_rounded,
};

AccentPalette metricPalette(String key) => switch (key) {
  'reading_minutes' => questPalette('reading'),
  'steps' => questPalette('steps'),
  'sleep_minutes' => questPalette('sleep'),
  'workouts' => questPalette('exercise'),
  'pushups' => questPalette('pushups'),
  'protein_g' => questPalette('protein'),
  'habits_kept' => accentById('teal'),
  'resting_hr' => accentById('rose'),
  _ => accentById('sky'),
};

Color toneColor(Tone tone) => switch (tone) {
  Tone.good => kSuccessText,
  Tone.bad => kDangerText,
  Tone.neutral => kInkSecondary,
};

IconData movementIcon(Movement m) => switch (m) {
  Movement.up => Icons.arrow_upward_rounded,
  Movement.down => Icons.arrow_downward_rounded,
  Movement.flat => Icons.trending_flat_rounded,
};

/// An arrow that points where the number went, green when that is the good direction.
class TrendArrow extends StatelessWidget {
  const TrendArrow({super.key, required this.trend, this.size = 22});

  final Trend trend;
  final double size;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: Icon(movementIcon(trend.movement), size: size, color: toneColor(trend.tone)),
  );
}

/// One metric of the Progress screen: its 30-day average, the arrow, a sparkline, the plain
/// sentence and the two comparisons.
class MetricCard extends StatelessWidget {
  const MetricCard({super.key, required this.metric, required this.window, required this.color});

  final ProgressMetric metric;
  final int window;

  /// The person's colour, for the sparkline.
  final Color color;

  @override
  Widget build(BuildContext context) {
    final m = metric;
    final palette = metricPalette(m.key);
    final trend = trendOf(headlineChange(m));
    final sentence = metricSentence(m, window: window);
    final value = m.current == null ? null : formatMetricValue(m.key, m.current!);
    final windowName = window == 30 ? '30-day' : '$window-day';
    return AppCard(
      padding: const EdgeInsets.all(16),
      child: MergeSemantics(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                IconDisc(icon: metricIcon(m.key), palette: palette, size: 40),
                const SizedBox(width: 12),
                Expanded(child: Text(m.title, style: AppText.headline)),
                if (m.current != null && headlineChange(m) != null)
                  TrendArrow(trend: trend, size: 28),
              ],
            ),
            const SizedBox(height: 12),
            if (value == null)
              Text('No data yet', style: AppText.title.copyWith(color: kInkMuted))
            else
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Flexible(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        value,
                        style: AppText.tabular(AppText.display.copyWith(color: palette.lip)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      '${metricUnit(m.key, m.unit)} ($windowName average)',
                      style: AppText.caption,
                    ),
                  ),
                ],
              ),
            if (m.current == null)
              const Padding(
                padding: EdgeInsets.only(top: 4),
                child: Text('Shows up once there is a reading.', style: AppText.caption),
              )
            else ...[
              const SizedBox(height: 8),
              Sparkline(
                values: [for (final p in m.series) p.value],
                color: color,
                semanticLabel: seriesSummary(m),
              ),
              const SizedBox(height: 10),
              Text(sentence, style: AppText.label.copyWith(fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              if (m.changeFromPrevious == null && m.changeFromFirst == null)
                const Text(
                  'Comparisons appear once there is a full month to compare.',
                  style: AppText.caption,
                )
              else ...[
                _Comparison(
                  metricKey: m.key,
                  against: previousWindowLabel(window),
                  change: m.changeFromPrevious,
                ),
                const SizedBox(height: 4),
                _Comparison(
                  metricKey: m.key,
                  against: firstWindowLabel(window),
                  change: m.changeFromFirst,
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

class _Comparison extends StatelessWidget {
  const _Comparison({required this.metricKey, required this.against, required this.change});

  final String metricKey;
  final String against;
  final MetricChange? change;

  @override
  Widget build(BuildContext context) {
    final trend = trendOf(change);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 1),
          child: TrendArrow(trend: trend, size: 18),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            comparisonLabel(metricKey, against, change),
            style: AppText.caption.copyWith(color: change == null ? kInkMuted : kInkSecondary),
          ),
        ),
      ],
    );
  }
}
