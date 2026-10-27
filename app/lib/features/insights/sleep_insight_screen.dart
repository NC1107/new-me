import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../api/models.dart';
import '../../state/insights.dart';
import '../../state/me.dart';
import '../../state/today.dart';
import '../../theme/quest_style.dart';
import '../../theme/tokens.dart';
import '../../theme/typography.dart';
import '../../util/format.dart';
import '../../util/zone_time.dart';
import '../../widgets/app_card.dart';
import '../../widgets/mascot.dart';
import '../../widgets/quest_copy.dart';
import 'insight_charts.dart';
import 'insights_logic.dart';
import 'insights_widgets.dart';

const kSleepChartNights = 14;

/// The last 14 mornings as chart slots ending on [end]; mornings without a night are gaps.
List<BarDatum> sleepSlots(List<SleepNightPoint> nights, String end) {
  final byDate = {for (final n in nights) n.date: n.asleepMin.toDouble()};
  final last = parseLocalDate(end);
  return [
    for (var i = 0; i < kSleepChartNights; i++)
      () {
        final d = last.subtract(Duration(days: kSleepChartNights - 1 - i));
        return BarDatum(label: DateFormat.MMMd().format(d), value: byDate[formatDateKey(d)]);
      }(),
  ];
}

class SleepInsightScreen extends ConsumerWidget {
  const SleepInsightScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final insights = ref.watch(insightsProvider);
    final today = ref.watch(todayProvider.select((v) => v.value?.data.localToday));
    final zone = ref.watch(meProvider.select((v) => v.value?.data.user.timezone));
    return InsightsFrame(
      title: 'Sleep',
      sources: [insights],
      onRetry: ref.read(insightsProvider.notifier).refresh,
      builder: (context) {
        final sleep = insights.value!.data.sleep;
        if (sleep.lastNight == null && sleep.nights.isEmpty) return [const _NoSleep()];
        final tips = sleepTips(sleep);
        return [
          if (sleep.lastNight case final night?) ...[
            _LastNight(night: night, today: today, zone: zone),
            const SizedBox(height: kCardGap),
          ],
          _NightsChart(sleep: sleep),
          const SizedBox(height: kCardGap),
          StatRow(
            children: [
              StatCard(label: '7-night average', value: _duration(sleep.avg7Min)),
              StatCard(label: '30-night average', value: _duration(sleep.avg30Min)),
            ],
          ),
          const SizedBox(height: kCardGap),
          StatRow(
            children: [
              StatCard(label: 'Average bedtime', value: clockLabel(sleep.avgBedtime)),
              StatCard(label: 'Average wake time', value: clockLabel(sleep.avgWake)),
            ],
          ),
          if (sleep.bedtimeSpreadMin case final spread?) ...[
            const SizedBox(height: kCardGap),
            _Consistency(spread: spread),
          ],
          if (tips.isNotEmpty) ...[const SizedBox(height: kCardGap), _Tips(tips: tips)],
        ];
      },
    );
  }
}

String _duration(num? minutes) => minutes == null ? '-' : durationLabel(minutes);

class _NoSleep extends StatelessWidget {
  const _NoSleep();

  @override
  Widget build(BuildContext context) => AppCard(
    padding: const EdgeInsets.all(24),
    child: Column(
      children: [
        const Mascot(size: 88, state: MascotState.sleepy),
        const SizedBox(height: 12),
        const Text('No sleep yet', textAlign: TextAlign.center, style: AppText.headline),
        const SizedBox(height: 6),
        Text(
          'Wear your Watch to bed and the nights show up here after the next Health sync.',
          textAlign: TextAlign.center,
          style: AppText.body.copyWith(color: kInkSecondary),
        ),
      ],
    ),
  );
}

class _LastNight extends StatelessWidget {
  const _LastNight({required this.night, required this.today, required this.zone});

  final SleepNight night;
  final String? today;
  final String? zone;

  @override
  Widget build(BuildContext context) {
    final palette = questPalette('sleep');
    final bed = night.bedAt == null ? null : timeLabel(inZone(night.bedAt!, zone));
    final wake = night.wakeAt == null ? null : timeLabel(inZone(night.wakeAt!, zone));
    final hasStages = stageTotal(night.stages) > 0;
    final title = switch (relativeDay(night.date, today)) {
      'Today' || 'Yesterday' => 'Last night',
      final other => 'Latest night, $other',
    };
    return AppCard(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              IconDisc(icon: Icons.bedtime_rounded, palette: palette, size: 36),
              const SizedBox(width: 10),
              Expanded(child: Text(title, style: AppText.headline)),
            ],
          ),
          const SizedBox(height: 12),
          Text(durationLabel(night.asleepMin), style: AppText.tabular(AppText.display)),
          const Text('asleep', style: AppText.caption),
          if (bed != null && wake != null) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 24,
              runSpacing: 8,
              children: [
                _Time(icon: Icons.bedtime_outlined, label: 'Bed', time: bed),
                _Time(icon: Icons.wb_sunny_outlined, label: 'Woke', time: wake),
              ],
            ),
          ],
          const SizedBox(height: 16),
          if (hasStages) ...[
            Semantics(
              label:
                  'Sleep stages: ${[for (final s in SleepStage.values) '${sleepStageName(s)} ${durationLabel(stageMinutes(night.stages, s))}'].join(', ')}',
              image: true,
              excludeSemantics: true,
              child: StageBar(minutes: stageMap(night.stages)),
            ),
            const SizedBox(height: 12),
            StageLegend(stages: stageMap(night.stages), label: durationLabel),
          ] else
            Text(
              'Your watch only reported total sleep, so there is no stage breakdown for this night.',
              style: AppText.caption.copyWith(color: kInkSecondary),
            ),
        ],
      ),
    );
  }
}

class _Time extends StatelessWidget {
  const _Time({required this.icon, required this.label, required this.time});

  final IconData icon;
  final String label;
  final String time;

  @override
  Widget build(BuildContext context) => Semantics(
    container: true,
    label: '$label $time',
    excludeSemantics: true,
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 22, color: kInkSecondary),
        const SizedBox(width: 8),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: AppText.caption.copyWith(color: kInkSecondary)),
            Text(time, style: AppText.tabular(AppText.body.copyWith(fontWeight: FontWeight.w800))),
          ],
        ),
      ],
    ),
  );
}

class _NightsChart extends ConsumerWidget {
  const _NightsChart({required this.sleep});

  final SleepInsights sleep;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = questPalette('sleep');
    final today = ref.watch(todayProvider.select((v) => v.value?.data.localToday));
    final lastNight = sleep.nights.isEmpty ? null : sleep.nights.last.date;
    final end = today != null && lastNight != null && today.compareTo(lastNight) > 0
        ? today
        : lastNight;
    if (end == null) return const SizedBox.shrink();
    final slots = sleepSlots(sleep.nights, end);
    final start = parseLocalDate(end).subtract(const Duration(days: kSleepChartNights - 1));
    final target = sleep.targetMin.toDouble();
    final met = sleep.nights.where((n) => n.asleepMin >= sleep.targetMin).length;
    return AppCard(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('Last 14 nights', style: AppText.headline),
          const SizedBox(height: 10),
          Semantics(
            label:
                'Hours asleep over the last 14 nights, ${sleep.nights.length} with data. '
                'Target ${durationLabel(sleep.targetMin)}, reached on $met nights.',
            image: true,
            excludeSemantics: true,
            child: DayBarChart(
              data: slots,
              color: palette.fill,
              format: (v) => durationLabel(v),
              startLabel: DateFormat.MMMd().format(start),
              endLabel: end == today ? 'Today' : DateFormat.MMMd().format(parseLocalDate(end)),
              goal: target,
              goalLabel: 'Target ${durationLabel(sleep.targetMin)}',
            ),
          ),
          const SizedBox(height: 6),
          const Text('Solid bars reached your target.', style: AppText.caption),
        ],
      ),
    );
  }
}

class _Consistency extends StatelessWidget {
  const _Consistency({required this.spread});

  final num spread;

  @override
  Widget build(BuildContext context) {
    final palette = questPalette('sleep');
    return AppCard(
      child: Row(
        children: [
          IconDisc(icon: Icons.schedule_rounded, palette: palette, size: 40),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              consistencyLine(spread),
              style: AppText.body.copyWith(fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
    );
  }
}

class _Tips extends StatelessWidget {
  const _Tips({required this.tips});

  final List<SleepTip> tips;

  @override
  Widget build(BuildContext context) {
    final positive = tips.every((t) => t.positive);
    final palette = questPalette(positive ? 'meals' : 'exercise');
    return AppCard(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(positive ? 'Nicely done' : 'Gentle tips', style: AppText.headline),
          const SizedBox(height: 10),
          for (final (i, tip) in tips.indexed) ...[
            if (i > 0) const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                IconDisc(
                  icon: positive ? Icons.thumb_up_rounded : Icons.lightbulb_rounded,
                  palette: palette,
                  size: 32,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(tip.text, style: AppText.body.copyWith(color: kInkSecondary)),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
