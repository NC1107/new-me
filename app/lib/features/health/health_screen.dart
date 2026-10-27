import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../api/models.dart';
import '../../state/today.dart';
import '../../theme/tokens.dart';
import '../../theme/typography.dart';
import '../../util/format.dart';
import '../../widgets/app_card.dart';
import '../../widgets/cached_view.dart';
import '../../widgets/page_scaffold.dart';
import '../../widgets/pressable.dart';
import '../../widgets/skeletons.dart';
import 'health_metrics.dart';
import 'metric_screen.dart';

/// Every metric New Me reads from Apple Health with today's value; a tap opens its trend.
class HealthScreen extends ConsumerWidget {
  const HealthScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(todayProvider.notifier);
    return CachedView<Today>(
      value: ref.watch(todayProvider),
      skeleton: const _HealthLoading(),
      errorTitle: 'Could not load your health numbers',
      onRetry: notifier.refresh,
      builder: (context, today, offline) {
        final synced = today.health.syncedAt;
        return PageScaffold(
          title: 'Health',
          subtitle: synced == null
              ? 'Nothing synced from Apple Health yet'
              : 'Today, from Apple Health',
          children: [
            for (final (i, group) in kHealthGroups.indexed) ...[
              if (i > 0) const SizedBox(height: 20),
              _GroupHeader(group: group),
              const SizedBox(height: 8),
              AppCard(
                padding: EdgeInsets.zero,
                child: Column(
                  children: [
                    for (final (j, metric) in group.metrics.indexed) ...[
                      if (j > 0) const Divider(height: 2, thickness: 2, color: kBorder),
                      _MetricRow(metric: metric, group: group, health: today.health),
                    ],
                  ],
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}

class _HealthLoading extends StatelessWidget {
  const _HealthLoading();

  @override
  Widget build(BuildContext context) => const PageScaffold(
    title: 'Health',
    children: [SizedBox(height: 360, child: MeSkeleton())],
  );
}

class _GroupHeader extends StatelessWidget {
  const _GroupHeader({required this.group});

  final HealthGroup group;

  @override
  Widget build(BuildContext context) => Semantics(
    header: true,
    child: Row(
      children: [
        Icon(group.icon, size: 20, color: group.palette.lip),
        const SizedBox(width: 8),
        Expanded(child: Text(group.name, style: AppText.headline.copyWith(fontSize: 18))),
      ],
    ),
  );
}

class _MetricRow extends StatelessWidget {
  const _MetricRow({required this.metric, required this.group, required this.health});

  final HealthMetricSpec metric;
  final HealthGroup group;
  final HealthStatus health;

  @override
  Widget build(BuildContext context) {
    final today = health.metrics[metric.key];
    final latest = health.latest[metric.key];
    final value = today ?? latest?.value;
    final asOf = today == null && latest != null
        ? DateFormat.MMMd().format(parseLocalDate(latest.date))
        : null;
    final text = value == null ? null : metric.format(value);
    final palette = group.palette;
    return Semantics(
      button: true,
      excludeSemantics: true,
      label: '${metric.name}, ${text ?? 'no data yet'}${asOf == null ? '' : ', as of $asOf'}',
      onTap: () => pushPage(context, MetricScreen(metric: metric, group: group)),
      child: Pressable(
        scale: 0.99,
        onTap: () => pushPage(context, MetricScreen(metric: metric, group: group)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 64),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(color: palette.tint, shape: BoxShape.circle),
                  child: Icon(metric.icon, size: 22, color: palette.lip),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(metric.name, style: AppText.label),
                      if (asOf != null) Text('As of $asOf', style: AppText.caption),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerRight,
                    child: Text(
                      text ?? '-',
                      maxLines: 1,
                      style: AppText.tabular(
                        AppText.body.copyWith(
                          fontWeight: FontWeight.w800,
                          color: text == null ? kInkMuted : kInk,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                const Icon(Icons.chevron_right_rounded, color: kInkMuted),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
