import 'package:flutter/material.dart';

import '../../api/models.dart';
import '../../theme/accent.dart';
import '../../theme/quest_style.dart';
import '../../theme/tokens.dart';
import '../../theme/typography.dart';
import '../../widgets/app_card.dart';
import '../../widgets/thick_progress_bar.dart';
import '../board/person_card.dart' show kSuccessText;
import '../progress/progress_logic.dart';
import '../progress/sparkline.dart';
import 'insights_widgets.dart';
import '../../widgets/units_scope.dart';

/// "82.4 kg" or "181.7 lb": the smoothed weight, which is the number people should read.
String weightLabel(double kg, Units units) => units.weight(kg);

/// How the smoothed weight is moving, in words: "down 0.3 kg a week", "steady", or null while
/// there is too little history for a rate.
String? weightTrendLabel(WeightInsights w, Units units) => weeklyRateLabel(w.weeklyRateKg, units);

IconData weightTrendIcon(WeightInsights w) {
  final rate = w.weeklyRateKg;
  if (rate == null || (rate.abs() * 10).round() == 0) return Icons.trending_flat_rounded;
  return rate > 0 ? Icons.trending_up_rounded : Icons.trending_down_rounded;
}

/// Where the last seven days of aerobic minutes sit against the WHO range.
enum AerobicBand { below, inRange, above }

AerobicBand aerobicBand(ActivitySummary a) {
  if (a.moderateEquivalentMin < a.aerobicTargetMinMin) return AerobicBand.below;
  return a.moderateEquivalentMin <= a.aerobicTargetMaxMin ? AerobicBand.inRange : AerobicBand.above;
}

/// "Short by 40 min", "In the 150 to 300 range" or "Above the range".
String aerobicStatus(ActivitySummary a) => switch (aerobicBand(a)) {
  AerobicBand.below => 'Short by ${a.aerobicTargetMinMin - a.moderateEquivalentMin} min',
  AerobicBand.inRange => 'In the ${a.aerobicTargetMinMin} to ${a.aerobicTargetMaxMin} range',
  AerobicBand.above => 'Above the range',
};

String strengthStatus(ActivitySummary a) {
  if (a.strengthDays >= a.strengthTargetDays) return 'Done';
  final left = a.strengthTargetDays - a.strengthDays;
  return left == 1 ? '1 more day' : '$left more days';
}

/// The whole card as one sentence, for screen readers.
String activitySentence(ActivitySummary a) =>
    '${a.moderateEquivalentMin} moderate-equivalent minutes against ${a.aerobicTargetMinMin} to '
    '${a.aerobicTargetMaxMin} (${aerobicStatus(a)}), and ${a.strengthDays} strength '
    '${a.strengthDays == 1 ? 'day' : 'days'} against ${a.strengthTargetDays}.';

/// "5 of the last 7 days" for the protein hit rate.
String proteinHitLabel(ProteinHitRate p) =>
    p.days7 == 1 ? '${p.daysHit7} of 1 logged day' : '${p.daysHit7} of the last ${p.days7} days';

/// "Target 100 g. At 1.6 g per kg and 82.4 kg the default would be 130 g.", or just the target
/// when it already is the default or there is no weight to work it out from.
String? proteinBasis(ProteinHitRate p, Units units) {
  final target = p.targetG;
  if (target == null) return null;
  final suggested = p.suggestedG;
  if (suggested == null || suggested == target || p.weightKg == null || p.perKg == null) {
    return 'Target $target g a day.';
  }
  final rate = units.isImperial
      ? '${(p.perKg! * kKgPerLb * 100).round() / 100} g per lb'
      : '${p.perKg} g per kg';
  return 'Target $target g. At $rate and ${weightLabel(p.weightKg!, units)} the default '
      'would be $suggested g.';
}

/// Weight as a smoothed trend with its weekly rate; the latest reading is secondary.
class WeightInsightCard extends StatelessWidget {
  const WeightInsightCard({super.key, required this.weight});

  final WeightInsights weight;

  @override
  Widget build(BuildContext context) {
    final palette = accentById('sky');
    final smoothed = weight.smoothedKg;
    final trend = weightTrendLabel(weight, context.units);
    final latest = weight.latestKg;
    final showLatest = latest != null && smoothed != null && (latest - smoothed).abs() >= 0.05;
    final points = weight.points.length > 30
        ? weight.points.sublist(weight.points.length - 30)
        : weight.points;
    final label = smoothed == null
        ? 'Weight, no weigh-ins yet'
        : 'Weight, ${weightLabel(smoothed, context.units)} smoothed${trend == null ? '' : ', $trend'}';
    return AppCard(
      padding: const EdgeInsets.all(18),
      child: Semantics(
        container: true,
        label: label,
        excludeSemantics: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                IconDisc(icon: Icons.monitor_weight_rounded, palette: palette, size: 40),
                const SizedBox(width: 12),
                const Expanded(child: Text('Weight', style: AppText.headline)),
              ],
            ),
            const SizedBox(height: 14),
            if (smoothed == null)
              Text(
                'No weigh-ins yet. Weight from Apple Health shows up here as a smoothed trend.',
                style: AppText.label.copyWith(color: kInkSecondary),
              )
            else ...[
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  weightLabel(smoothed, context.units),
                  style: AppText.tabular(AppText.display.copyWith(color: palette.lip)),
                ),
              ),
              const Text('smoothed trend', style: AppText.caption),
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(weightTrendIcon(weight), size: 22, color: kInkSecondary),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      trend ?? 'A weekly rate shows after a week of weigh-ins',
                      style: AppText.label.copyWith(color: kInkSecondary),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              if (points.length > 1) ...[
                Sparkline(
                  values: [for (final p in points) p.smoothed],
                  color: palette.fill,
                  semanticLabel: 'Smoothed weight over the last ${points.length} weigh-ins',
                ),
              ],
              if (showLatest)
                Text(
                  'Latest reading ${weightLabel(latest, context.units)}. A single weigh-in moves with water and '
                  'meals, so the trend is the number to follow.',
                  style: AppText.caption,
                ),
            ],
          ],
        ),
      ),
    );
  }
}

/// The last seven days of workouts against the WHO 2020 guideline. It reports and never advises
/// training less.
class ActivitySummaryCard extends StatelessWidget {
  const ActivitySummaryCard({super.key, required this.activity});

  final ActivitySummary activity;

  @override
  Widget build(BuildContext context) {
    final a = activity;
    final palette = questPalette('exercise');
    final aerobicOk = aerobicBand(a) != AerobicBand.below;
    return AppCard(
      padding: const EdgeInsets.all(18),
      child: Semantics(
        container: true,
        label: 'Activity this week. ${activitySentence(a)}',
        excludeSemantics: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                IconDisc(icon: Icons.directions_run_rounded, palette: palette, size: 40),
                const SizedBox(width: 12),
                const Expanded(child: Text('Activity this week', style: AppText.headline)),
              ],
            ),
            const Padding(
              padding: EdgeInsets.only(top: 2, left: 52),
              child: Text('WHO guideline, last 7 days', style: AppText.caption),
            ),
            const SizedBox(height: 16),
            _Measure(
              title: 'Aerobic',
              value: '${a.moderateEquivalentMin}',
              of: 'of ${a.aerobicTargetMinMin} to ${a.aerobicTargetMaxMin} min',
              fraction: a.moderateEquivalentMin / a.aerobicTargetMaxMin,
              marker: a.aerobicTargetMinMin / a.aerobicTargetMaxMin,
              status: aerobicStatus(a),
              good: aerobicOk,
              color: context.accent,
            ),
            const SizedBox(height: 16),
            _Measure(
              title: 'Strength',
              value: '${a.strengthDays}',
              of: 'of ${a.strengthTargetDays} days',
              fraction: a.strengthDays / a.strengthTargetDays,
              status: strengthStatus(a),
              good: a.meetsStrength,
              color: context.accent,
            ),
            const SizedBox(height: 12),
            Text(
              'Hard minutes count double. ${a.moderateMin} moderate and ${a.vigorousMin} hard '
              'minutes this week.',
              style: AppText.caption,
            ),
          ],
        ),
      ),
    );
  }
}

class _Measure extends StatelessWidget {
  const _Measure({
    required this.title,
    required this.value,
    required this.of,
    required this.fraction,
    required this.status,
    required this.good,
    required this.color,
    this.marker,
  });

  final String title;
  final String value;
  final String of;
  final double fraction;
  final double? marker;
  final String status;
  final bool good;
  final Color color;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Wrap(
        crossAxisAlignment: WrapCrossAlignment.end,
        spacing: 8,
        children: [
          Text(title, style: AppText.label.copyWith(fontWeight: FontWeight.w800)),
          Text(value, style: AppText.tabular(AppText.title.copyWith(fontWeight: FontWeight.w900))),
          Text(of, style: AppText.caption),
        ],
      ),
      const SizedBox(height: 6),
      ThickProgressBar(value: fraction, color: color, markerAt: marker),
      const SizedBox(height: 6),
      Row(
        children: [
          if (good) ...[
            const Icon(Icons.check_circle_rounded, size: 18, color: kSuccessText),
            const SizedBox(width: 4),
          ],
          Expanded(
            child: Text(
              status,
              style: AppText.label.copyWith(
                color: good ? kSuccessText : kInkSecondary,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    ],
  );
}

/// How often the protein target was hit in the last 7 days, and where the target comes from.
class ProteinHitCard extends StatelessWidget {
  const ProteinHitCard({super.key, required this.protein});

  final ProteinHitRate protein;

  @override
  Widget build(BuildContext context) {
    final p = protein;
    final palette = questPalette('protein');
    final rate = p.hitRate7;
    final basis = proteinBasis(p, context.units);
    return AppCard(
      padding: const EdgeInsets.all(18),
      child: Semantics(
        container: true,
        label: p.days7 == 0
            ? 'Protein, nothing logged in the last 7 days'
            : 'Protein, target hit on ${proteinHitLabel(p)}',
        excludeSemantics: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                IconDisc(icon: questIcon('protein'), palette: palette, size: 40),
                const SizedBox(width: 12),
                const Expanded(child: Text('Protein', style: AppText.headline)),
              ],
            ),
            const SizedBox(height: 14),
            if (p.days7 == 0)
              Text(
                'No protein logged in the last 7 days.',
                style: AppText.label.copyWith(color: kInkSecondary),
              )
            else ...[
              Text('Target hit on', style: AppText.caption.copyWith(color: kInkSecondary)),
              Text(
                proteinHitLabel(p),
                style: AppText.tabular(AppText.title.copyWith(fontWeight: FontWeight.w900)),
              ),
              const SizedBox(height: 8),
              ThickProgressBar(value: rate ?? 0, color: palette.fill),
              if (rate != null) ...[
                const SizedBox(height: 4),
                Text('${(rate * 100).round()}% of days', style: AppText.caption),
              ],
            ],
            if (basis != null) ...[const SizedBox(height: 8), Text(basis, style: AppText.caption)],
          ],
        ),
      ),
    );
  }
}
