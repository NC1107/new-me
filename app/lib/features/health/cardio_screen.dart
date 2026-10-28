import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../api/models.dart';
import '../../state/clock.dart';
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
import '../../widgets/units_scope.dart';
import 'health_metrics.dart';
import 'metric_screen.dart';
import 'trend_chart.dart';

/// The longest window the trends endpoint serves; the shorter ones are cut from it here.
const kCardioYearDays = 365;

/// The windows of the trend, in days and the label of each.
const kCardioWindows = [(90, '3 months'), (180, '6 months'), (kCardioYearDays, '12 months')];

const _kVo2max = 'vo2max';

/// Apple Health's exercise minutes in the last seven days.
const _weekKey = (metric: 'exercise_minutes', days: 7);

final cardioFitnessProvider = FutureProvider.autoDispose<CardioFitness>((ref) async {
  final client = ref.watch(apiClientProvider);
  if (client == null) throw StateError('Not signed in');
  return client.cardioFitness();
});

/// The VO2 max trend over 3, 6 and 12 months, where the latest value falls among people of the
/// same sex and age, and what moves it.
class CardioScreen extends ConsumerStatefulWidget {
  const CardioScreen({super.key});

  @override
  ConsumerState<CardioScreen> createState() => _CardioScreenState();
}

class _CardioScreenState extends ConsumerState<CardioScreen> {
  int _days = 90;
  int? _selected;

  static const _trendKey = (metric: _kVo2max, days: kCardioYearDays);

  Future<void> _retry() async {
    ref.invalidate(healthTrendProvider(_trendKey));
    ref.invalidate(cardioFitnessProvider);
  }

  @override
  Widget build(BuildContext context) {
    final trend = ref.watch(healthTrendProvider(_trendKey));
    final cardio = ref.watch(cardioFitnessProvider);
    final palette = _heartPalette;
    return PageScaffold(
      title: 'Cardio fitness',
      subtitle: 'VO2 max from Apple Health',
      children: [
        trend.when(
          skipLoadingOnReload: true,
          loading: () => const _Loading(),
          error: (e, _) =>
              ErrorBlock(title: 'Could not load your VO2 max', error: e, onRetry: _retry),
          data: (data) {
            if (data.points.isEmpty) return const _Empty();
            return _Loaded(
              palette: palette,
              points: data.points,
              days: _days,
              selected: _selected,
              onWindow: (d) => setState(() {
                _days = d;
                _selected = null;
              }),
              onSelect: (i) => setState(() => _selected = i),
              placement: cardio.when(
                skipLoadingOnReload: true,
                loading: () => const SkeletonBlock(height: 120, radius: 16),
                error: (e, _) => ErrorBlock(
                  title: 'Could not compare your VO2 max',
                  error: e,
                  onRetry: () async => ref.invalidate(cardioFitnessProvider),
                ),
                data: (c) => _Placement(cardio: c, palette: palette),
              ),
            );
          },
        ),
        const SizedBox(height: kCardGap),
        const _WhatMovesIt(),
        const SizedBox(height: kCardGap),
        const _Estimate(),
      ],
    );
  }
}

AccentPalette get _heartPalette {
  for (final g in kHealthGroups) {
    if (g.metrics.any((m) => m.key == _kVo2max)) return g.palette;
  }
  return kHealthGroups.first.palette;
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

class _Empty extends StatelessWidget {
  const _Empty();

  @override
  Widget build(BuildContext context) => AppCard(
    padding: const EdgeInsets.all(24),
    child: Column(
      children: [
        const Mascot(size: 88, state: MascotState.sleepy),
        const SizedBox(height: 12),
        const Text('No VO2 max yet', textAlign: TextAlign.center, style: AppText.headline),
        const SizedBox(height: 6),
        Text(
          'Apple Watch estimates it after an outdoor walk, run or hike. Once Apple Health shares '
          'it, the trend and how it compares appear here.',
          textAlign: TextAlign.center,
          style: AppText.body.copyWith(color: kInkSecondary),
        ),
      ],
    ),
  );
}

class _Loaded extends ConsumerWidget {
  const _Loaded({
    required this.palette,
    required this.points,
    required this.days,
    required this.selected,
    required this.onWindow,
    required this.onSelect,
    required this.placement,
  });

  final AccentPalette palette;
  final List<HealthTrendPoint> points;
  final int days;
  final int? selected;
  final ValueChanged<int> onWindow;
  final ValueChanged<int?> onSelect;
  final Widget placement;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final spec = healthMetricSpec(_kVo2max)!;
    final today = ref.watch(clockProvider)();
    final first = formatDateKey(today.subtract(Duration(days: days - 1)));
    final inWindow = [
      for (final p in points)
        if (p.date.compareTo(first) >= 0) p,
    ];
    final chart = placeOnWindow(inWindow, days);
    final latest = points.last;
    final picked = selected == null || chart.isEmpty
        ? null
        : chart[selected!.clamp(0, chart.length - 1)];
    final shownValue = picked?.value ?? latest.value;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Segmented<int>(
          options: [for (final (d, label) in kCardioWindows) (d, label)],
          selected: days,
          onChanged: onWindow,
        ),
        const SizedBox(height: 16),
        Text(
          spec.display(shownValue, context.units),
          style: AppText.tabular(AppText.display.copyWith(fontSize: 30)),
        ),
        Text(
          picked == null
              ? 'Latest, ${dayShort(latest.date)}'
              : DateFormat.MMMEd().format(parseLocalDate(picked.date)),
          style: AppText.caption,
        ),
        const SizedBox(height: 12),
        if (chart.isEmpty)
          const _Note(
            title: 'No readings in this window',
            body: 'Try a longer window to see older readings.',
          )
        else if (chart.length == 1)
          const _Note(
            title: 'Not enough data yet',
            body: 'Only one reading in this window. The chart appears once a second one arrives.',
          )
        else
          Semantics(
            label:
                'VO2 max, last ${days == kCardioYearDays ? '12' : days ~/ 30} months. '
                'Latest ${spec.display(latest.value, context.units)} on ${dayShort(latest.date)}, '
                '${chart.length} readings.',
            image: true,
            excludeSemantics: true,
            child: AppCard(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Column(
                children: [
                  TrendChart(
                    points: chart,
                    color: palette.fill,
                    format: spec.format,
                    onSelect: onSelect,
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          DateFormat.MMMd().format(today.subtract(Duration(days: days - 1))),
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
        const SizedBox(height: kCardGap),
        placement,
      ],
    );
  }
}

class _Note extends StatelessWidget {
  const _Note({required this.title, required this.body});

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) => AppCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: AppText.headline),
        const SizedBox(height: 4),
        Text(body, style: AppText.caption),
      ],
    ),
  );
}

/// Where the latest value falls among people of the same sex and age decade in the FRIEND
/// registry, or what the comparison is waiting for.
class _Placement extends StatelessWidget {
  const _Placement({required this.cardio, required this.palette});

  final CardioFitness cardio;
  final AccentPalette palette;

  @override
  Widget build(BuildContext context) {
    switch (cardio.status) {
      case CardioStatus.noReading:
        return const SizedBox.shrink();
      case CardioStatus.needsProfile:
        return _Note(
          title: 'Add ${_needsText(cardio.needs)} to compare',
          body:
              'How your VO2 max ranks depends on age and sex, so the comparison waits for '
              '${cardio.needs.length == 1 ? 'it' : 'them'}. Add ${cardio.needs.length == 1 ? 'it' : 'them'} '
              'on your profile in Me. The trend above works without.',
        );
      case CardioStatus.ageOutOfRange:
        return const _Note(
          title: 'No comparison for your age',
          body: 'The reference data covers adults aged 20 to 89.',
        );
      case CardioStatus.ready:
        break;
    }
    final low = cardio.percentileLow ?? 0;
    final high = cardio.percentileHigh ?? 100;
    final headline = switch ((low, high)) {
      (0, _) => 'Below the 10th percentile',
      (_, 100) => 'Above the 90th percentile',
      _ => '${_ordinal(low)} to ${_ordinal(high)} percentile',
    };
    final who = cardio.sex == 'male' ? 'men' : 'women';
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('How you compare', style: AppText.caption),
          const SizedBox(height: 2),
          Text(headline, style: AppText.headline),
          const SizedBox(height: 4),
          Text(
            'Among $who aged ${cardio.ageGroup}, the middle value is '
            '${_tenths(cardio.median ?? 0)} ml/kg/min.',
            style: AppText.body.copyWith(color: kInkSecondary),
          ),
          const SizedBox(height: 12),
          _PercentileBar(low: low, color: palette.fill, label: headline),
          const SizedBox(height: 12),
          const Text(
            'From treadmill lab tests of healthy US adults in the FRIEND registry (Kaminsky et '
            'al., Mayo Clinic Proceedings 2022). A watch estimate is not a lab test, so read the '
            'band as a rough guide.',
            style: AppText.caption,
          ),
        ],
      ),
    );
  }
}

/// Ten steps, one per band of the table, with the person's band filled.
class _PercentileBar extends StatelessWidget {
  const _PercentileBar({required this.low, required this.color, required this.label});

  final int low;
  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    final at = (low ~/ 10).clamp(0, 9);
    return Semantics(
      label: label,
      image: true,
      excludeSemantics: true,
      child: Row(
        children: [
          for (var i = 0; i < 10; i++) ...[
            if (i > 0) const SizedBox(width: 3),
            Expanded(
              child: AnimatedContainer(
                duration: kMotionDuration,
                height: 12,
                decoration: BoxDecoration(
                  color: i == at ? color : kSunken,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _WhatMovesIt extends ConsumerWidget {
  const _WhatMovesIt();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final week = ref.watch(healthTrendProvider(_weekKey)).asData?.value;
    final minutes = week?.points.fold<num>(0, (sum, p) => sum + p.value);
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('What moves it', style: AppText.headline),
          const SizedBox(height: 4),
          Text(
            'Regular aerobic activity. The World Health Organization advises 150 to 300 minutes '
            'of moderate or 75 to 150 minutes of vigorous activity a week, and the American '
            'College of Sports Medicine gives similar targets (WHO guidelines, Br J Sports Med '
            '2020).',
            style: AppText.body.copyWith(color: kInkSecondary),
          ),
          if (minutes != null) ...[
            const SizedBox(height: 8),
            Text(
              'Apple Health counted ${_minutes(minutes)} of exercise in the last 7 days. That '
              'includes all brisk activity, not only vigorous.',
              style: AppText.body,
            ),
          ],
          const SizedBox(height: 8),
          const Text(
            'Fitness is worth building: each 1 MET higher (3.5 ml/kg/min) goes with about 13% '
            'lower risk of death from any cause (Kodama et al., JAMA 2009).',
            style: AppText.caption,
          ),
        ],
      ),
    );
  }
}

class _Estimate extends StatelessWidget {
  const _Estimate();

  @override
  Widget build(BuildContext context) => AppCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('An estimate, not a lab test', style: AppText.headline),
        const SizedBox(height: 4),
        Text(
          'Apple Watch infers VO2 max from heart rate and pace. Independent tests against a '
          'lab gas analyzer found a typical error of 13 to 16 percent (Lambe et al., PLOS ONE '
          '2025, 28 adults; Caserman et al., JMIR Biomedical Engineering 2024, 19 adults). '
          'Changes of a point or two are noise, so watch the direction over months.',
          style: AppText.body.copyWith(color: kInkSecondary),
        ),
      ],
    ),
  );
}

String _needsText(List<String> needs) {
  final names = [
    for (final n in needs)
      switch (n) {
        'birthYear' => 'your birth year',
        'sex' => 'your sex',
        _ => n,
      },
  ];
  return names.join(' and ');
}

String _ordinal(int n) => switch (n % 10) {
  1 when n % 100 != 11 => '${n}st',
  2 when n % 100 != 12 => '${n}nd',
  3 when n % 100 != 13 => '${n}rd',
  _ => '${n}th',
};

String _tenths(num v) => v.toStringAsFixed(1);

String _minutes(num m) {
  final n = m.round();
  return n == 1 ? '1 minute' : '$n minutes';
}
