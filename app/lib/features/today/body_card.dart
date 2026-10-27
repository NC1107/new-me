import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../api/models.dart';
import '../../theme/quest_style.dart';
import '../../theme/tokens.dart';
import '../../theme/typography.dart';
import '../../util/format.dart';
import '../../widgets/accent_text.dart';
import '../../widgets/app_card.dart';
import '../../widgets/quest_copy.dart';

enum BodyTrend { up, down }

class BodyTile {
  const BodyTile({
    required this.icon,
    required this.tint,
    required this.ink,
    required this.label,
    required this.value,
    this.unit = '',
    this.trend,
    this.delta,
  });

  final IconData icon;
  final Color tint;
  final Color ink;
  final String label;
  final String value;
  final String unit;
  final BodyTrend? trend;

  /// Signed change over the trend window, e.g. "-0.4".
  final String? delta;
}

/// The weight move over the window, or null when there are fewer than two weigh-ins or the move is
/// too small to call a direction.
({BodyTrend trend, String delta})? weightTrend(HealthTrend? trend) {
  final points = trend?.points ?? const <HealthTrendPoint>[];
  if (points.length < 2) return null;
  final change = points.last.value - points.first.value;
  final rounded = (change * 10).round() / 10;
  if (rounded == 0) return null;
  return (
    trend: rounded > 0 ? BodyTrend.up : BodyTrend.down,
    delta: '${rounded > 0 ? '+' : '-'}${rounded.abs().formatted}',
  );
}

/// Only metrics that have data, in a fixed order.
List<BodyTile> bodyTiles(HealthStatus health, String localToday, HealthTrend? weight) {
  final m = health.metrics;
  num? latest(String key) => health.latest[key]?.value ?? m[key];
  String? asOf(String key) {
    final l = health.latest[key];
    if (l == null || l.date == localToday) return null;
    return DateFormat('MMM d').format(parseLocalDate(l.date));
  }

  BodyTile tile(String key, IconData icon, String label, String value, {String unit = ''}) {
    final p = questPalette(key);
    return BodyTile(icon: icon, tint: p.tint, ink: p.lip, label: label, value: value, unit: unit);
  }

  final move = weightTrend(weight);
  return [
    if (m['sleep_minutes'] case final v?)
      tile('sleep', Icons.bedtime_rounded, 'Sleep', durationLabel(v)),
    if (m['resting_hr'] case final v?)
      tile('exercise', Icons.favorite_rounded, 'Resting HR', v.formatted, unit: 'bpm'),
    if (m['exercise_minutes'] case final v?)
      tile('exercise', Icons.local_fire_department_rounded, 'Exercise', v.formatted, unit: 'min'),
    if (latest('weight_kg') case final v?)
      BodyTile(
        icon: Icons.monitor_weight_rounded,
        tint: questPalette('steps').tint,
        ink: questPalette('steps').lip,
        label: 'Weight',
        value: v.formatted,
        unit: ['kg', ?asOf('weight_kg')].join(' - '),
        trend: move?.trend,
        delta: move?.delta,
      ),
    if (m['hrv_ms'] case final v?)
      tile('protein', Icons.monitor_heart_rounded, 'HRV', v.formatted, unit: 'ms'),
    if (latest('vo2max') case final v?)
      tile(
        'yoga',
        Icons.air_rounded,
        'VO2 max',
        v.formatted,
        unit: ['ml/kg/min', ?asOf('vo2max')].join(' - '),
      ),
  ];
}

/// Two-column tiles for the metrics Apple Health has delivered; tapping opens the Health screen.
class BodyCard extends StatelessWidget {
  const BodyCard({super.key, required this.tiles, required this.onTap});

  final List<BodyTile> tiles;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      onTap: onTap,
      semanticLabel: 'Body, open Health',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Expanded(child: Text('Body', style: AppText.headline)),
              Text('Health', style: AppText.label.copyWith(color: context.accentText)),
              Icon(Icons.chevron_right_rounded, color: context.accentText),
            ],
          ),
          const SizedBox(height: 10),
          LayoutBuilder(
            builder: (context, box) {
              const gap = 10.0;
              final width = (box.maxWidth - gap) / 2;
              return Wrap(
                spacing: gap,
                runSpacing: gap,
                children: [
                  for (final t in tiles)
                    SizedBox(
                      width: width,
                      child: _Tile(tile: t),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({required this.tile});

  final BodyTile tile;

  @override
  Widget build(BuildContext context) {
    final trendIcon = switch (tile.trend) {
      BodyTrend.up => Icons.trending_up_rounded,
      BodyTrend.down => Icons.trending_down_rounded,
      null => null,
    };
    final trendWord = tile.trend == BodyTrend.up ? 'up' : 'down';
    return Semantics(
      container: true,
      label:
          '${tile.label} ${tile.value} ${tile.unit}'
          '${tile.delta == null ? '' : ', $trendWord ${tile.delta!.substring(1)} over 7 days'}',
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: kSunken,
          borderRadius: BorderRadius.circular(kRadiusField),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(color: tile.tint, shape: BoxShape.circle),
                  child: Icon(tile.icon, size: 16, color: tile.ink),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    tile.label,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.caption.copyWith(
                      color: kInkSecondary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(tile.value, style: AppText.tabular(AppText.title.copyWith(height: 1.1))),
                  if (tile.unit.isNotEmpty) ...[
                    const SizedBox(width: 4),
                    Text(tile.unit, style: AppText.caption.copyWith(color: kInkSecondary)),
                  ],
                  if (trendIcon != null) ...[
                    const SizedBox(width: 6),
                    Icon(trendIcon, size: 18, color: kInkSecondary),
                    Text(
                      tile.delta!,
                      style: AppText.tabular(AppText.caption.copyWith(color: kInkSecondary)),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
