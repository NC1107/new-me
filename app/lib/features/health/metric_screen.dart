import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../api/models.dart';
import '../../state/session.dart';
import '../../theme/accent.dart';
import '../../theme/tokens.dart';
import '../../theme/typography.dart';
import '../../util/format.dart';
import '../../widgets/app_card.dart';
import '../../widgets/cached_view.dart';
import '../../widgets/mascot.dart';
import '../../widgets/page_scaffold.dart';
import '../../widgets/segmented.dart';
import '../../widgets/skeletons.dart';
import 'health_metrics.dart';
import 'trend_chart.dart';
import '../../widgets/units_scope.dart';

typedef TrendKey = ({String metric, int days});

final healthTrendProvider = FutureProvider.autoDispose.family<HealthTrend, TrendKey>((
  ref,
  key,
) async {
  final client = ref.watch(apiClientProvider);
  if (client == null) throw StateError('Not signed in');
  return client.healthTrends(key.metric, key.days);
});

const kTrendWindows = [30, 90];

/// One metric's 30 or 90 day trend.
class MetricScreen extends ConsumerStatefulWidget {
  const MetricScreen({super.key, required this.metric, required this.group});

  final HealthMetricSpec metric;
  final HealthGroup group;

  @override
  ConsumerState<MetricScreen> createState() => _MetricScreenState();
}

class _MetricScreenState extends ConsumerState<MetricScreen> {
  int _days = 30;
  int? _selected;

  TrendKey get _key => (metric: widget.metric.key, days: _days);

  @override
  Widget build(BuildContext context) {
    final trend = ref.watch(healthTrendProvider(_key));
    final palette = widget.group.palette;
    return PageScaffold(
      title: widget.metric.name,
      children: [
        Segmented<int>(
          options: [for (final d in kTrendWindows) (d, '$d days')],
          selected: _days,
          onChanged: (d) => setState(() {
            _days = d;
            _selected = null;
          }),
        ),
        const SizedBox(height: 16),
        trend.when(
          skipLoadingOnReload: true,
          loading: () => const _Loading(),
          error: (e, _) => ErrorBlock(
            title: 'Could not load the trend',
            error: e,
            onRetry: () async => ref.invalidate(healthTrendProvider(_key)),
          ),
          data: (data) => _Loaded(
            metric: widget.metric,
            palette: palette,
            days: _days,
            trend: data,
            selected: _selected,
            onSelect: (i) => setState(() => _selected = i),
          ),
        ),
      ],
    );
  }
}

class _Loading extends StatelessWidget {
  const _Loading();

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Loading',
    child: const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SkeletonBlock(width: 160, height: 36),
        SizedBox(height: 8),
        SkeletonBlock(width: 100, height: 14),
        SizedBox(height: 16),
        SkeletonBlock(height: 260, radius: 16),
      ],
    ),
  );
}

class _Loaded extends StatelessWidget {
  const _Loaded({
    required this.metric,
    required this.palette,
    required this.days,
    required this.trend,
    required this.selected,
    required this.onSelect,
  });

  final HealthMetricSpec metric;
  final AccentPalette palette;
  final int days;
  final HealthTrend trend;
  final int? selected;
  final ValueChanged<int?> onSelect;

  @override
  Widget build(BuildContext context) {
    final points = placeOnWindow(trend.points, days);
    if (points.isEmpty) return _Empty(metric: metric, days: days);

    final shown = points[(selected ?? points.length - 1).clamp(0, points.length - 1)];
    final values = points.map((p) => p.value).toList();
    final low = values.reduce((a, b) => a < b ? a : b);
    final high = values.reduce((a, b) => a > b ? a : b);
    final average = values.reduce((a, b) => a + b) / values.length;
    final latest = points.last;

    final summary =
        '${metric.name}, last $days days. Latest ${metric.display(latest.value, context.units)} on '
        '${DateFormat.MMMd().format(parseLocalDate(latest.date))}. '
        'Lowest ${metric.display(low, context.units)}, highest ${metric.display(high, context.units)}, '
        '${points.length} ${points.length == 1 ? 'reading' : 'readings'}.';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          metric.display(shown.value, context.units),
          style: AppText.tabular(AppText.display.copyWith(fontSize: 30)),
        ),
        Text(
          selected == null
              ? 'Latest, ${DateFormat.MMMd().format(parseLocalDate(shown.date))}'
              : DateFormat.MMMEd().format(parseLocalDate(shown.date)),
          style: AppText.caption,
        ),
        const SizedBox(height: 12),
        Semantics(
          label: summary,
          image: true,
          excludeSemantics: true,
          child: AppCard(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Column(
              children: [
                TrendChart(
                  points: points,
                  color: palette.fill,
                  format: metric.format,
                  onSelect: onSelect,
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        DateFormat.MMMd().format(
                          parseLocalDate(latest.date).subtract(Duration(days: days - 1)),
                        ),
                        style: AppText.caption,
                      ),
                      const Text('Today', style: AppText.caption),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        if (points.length == 1) ...[
          const SizedBox(height: 8),
          const Text(
            'Only one reading so far. The line fills in as more days arrive.',
            style: AppText.caption,
          ),
        ],
        const SizedBox(height: kCardGap),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _Stat(label: 'Lowest', value: metric.display(low, context.units)),
            ),
            const SizedBox(width: kCardGap),
            Expanded(
              child: _Stat(label: 'Average', value: metric.display(average, context.units)),
            ),
            const SizedBox(width: kCardGap),
            Expanded(
              child: _Stat(label: 'Highest', value: metric.display(high, context.units)),
            ),
          ],
        ),
      ],
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => AppCard(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: AppText.caption),
        const SizedBox(height: 2),
        Text(value, style: AppText.tabular(AppText.label.copyWith(fontWeight: FontWeight.w800))),
      ],
    ),
  );
}

class _Empty extends StatelessWidget {
  const _Empty({required this.metric, required this.days});

  final HealthMetricSpec metric;
  final int days;

  @override
  Widget build(BuildContext context) => AppCard(
    padding: const EdgeInsets.all(24),
    child: Column(
      children: [
        const Mascot(size: 88, state: MascotState.sleepy),
        const SizedBox(height: 12),
        Text(
          'No ${metric.name.toLowerCase()} yet',
          textAlign: TextAlign.center,
          style: AppText.headline,
        ),
        const SizedBox(height: 6),
        Text(
          'Nothing came in over the last $days days. Once Apple Health shares it, the trend '
          'appears here.',
          textAlign: TextAlign.center,
          style: AppText.body.copyWith(color: kInkSecondary),
        ),
      ],
    ),
  );
}
