import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../api/models.dart';
import '../../state/clock.dart';
import '../../state/insights.dart';
import '../../state/me.dart';
import '../../state/today.dart';
import '../../theme/accent.dart';
import '../../theme/quest_style.dart';
import '../../theme/tokens.dart';
import '../../theme/typography.dart';
import '../../util/format.dart';
import '../../widgets/app_card.dart';
import '../../widgets/cached_view.dart';
import '../../widgets/chunky_button.dart';
import '../../widgets/mascot.dart';
import '../../widgets/pressable.dart';
import '../../widgets/skeletons.dart';
import '../health/metric_screen.dart';
import '../me/me_support.dart';
import 'birth_year_sheet.dart';
import 'insight_charts.dart';
import 'insights_logic.dart';
import 'insights_widgets.dart';

const kStepsChartDays = 30;

/// The 30 day window of steps as chart slots ending on [end], with a gap for days without data.
List<BarDatum> stepSlots(List<HealthTrendPoint> points, String end, {int days = kStepsChartDays}) {
  final byDate = {for (final p in points) p.date: p.value.toDouble()};
  final last = parseLocalDate(end);
  return [
    for (var i = 0; i < days; i++)
      () {
        final d = last.subtract(Duration(days: days - 1 - i));
        return BarDatum(label: DateFormat.MMMd().format(d), value: byDate[formatDateKey(d)]);
      }(),
  ];
}

class StepsInsightScreen extends ConsumerStatefulWidget {
  const StepsInsightScreen({super.key});

  @override
  ConsumerState<StepsInsightScreen> createState() => _StepsInsightScreenState();
}

class _StepsInsightScreenState extends ConsumerState<StepsInsightScreen> with MeSaving {
  static const _trendKey = (metric: 'steps', days: kStepsChartDays);

  Future<void> _useGoal(int target) async {
    final ok = await saveMe(
      MePatch(
        questTemplates: [QuestEdit(key: 'steps', target: target)],
      ),
    );
    if (!ok || !mounted) return;
    unawaited(ref.read(insightsProvider.notifier).refresh());
    toast('Steps goal set to ${target.formatted}. It starts tomorrow.');
  }

  Future<void> _askBirthYear() async {
    final me = ref.read(meProvider).value?.data;
    final choice = await showBirthYearSheet(
      context,
      currentYear: ref.read(clockProvider)().year,
      initial: me?.user.birthYear,
    );
    if (choice == null || !mounted) return;
    final ok = await saveMe(
      choice.year == null ? const MePatch(clearBirthYear: true) : MePatch(birthYear: choice.year),
    );
    if (ok && mounted) unawaited(ref.read(insightsProvider.notifier).refresh());
  }

  @override
  Widget build(BuildContext context) {
    final insights = ref.watch(insightsProvider);
    final trend = ref.watch(healthTrendProvider(_trendKey));
    final today = ref.watch(todayProvider.select((v) => v.value?.data.localToday));
    final offline = insights.value?.offline != null;
    return InsightsFrame(
      title: 'Steps',
      sources: [insights],
      onRetry: ref.read(insightsProvider.notifier).refresh,
      builder: (context) {
        final steps = insights.value!.data.steps;
        return [
          _Headline(steps: steps),
          const SizedBox(height: 16),
          _ChartCard(
            steps: steps,
            trend: trend,
            end: today,
            onRetry: () async => ref.invalidate(healthTrendProvider(_trendKey)),
          ),
          const SizedBox(height: kCardGap),
          StatRow(
            children: [
              StatCard(label: '7-day average', value: _steps(steps.avg7)),
              StatCard(label: '30-day average', value: _steps(steps.avg30)),
            ],
          ),
          const SizedBox(height: kCardGap),
          StatRow(
            children: [
              StatCard(
                label: 'Best day',
                value: steps.best == null ? '-' : steps.best!.value.formatted,
                note: steps.best == null
                    ? null
                    : DateFormat.MMMd().format(parseLocalDate(steps.best!.date)),
              ),
              StatCard(
                label: 'Days at goal',
                value: steps.goal > 0 ? '${steps.daysAtGoal30} of 30' : '-',
                note: steps.goal > 0 ? 'Goal ${steps.goal.formatted}' : null,
              ),
            ],
          ),
          const SizedBox(height: 20),
          _SuggestionCard(
            steps: steps,
            saving: saving,
            error: saveError,
            offline: offline,
            onUse: _useGoal,
            onBirthYear: _askBirthYear,
          ),
          const SizedBox(height: kCardGap),
          const _Explainer(),
        ];
      },
    );
  }
}

String _steps(num? v) => v == null ? '-' : v.round().formatted;

class _Headline extends StatelessWidget {
  const _Headline({required this.steps});

  final StepInsights steps;

  @override
  Widget build(BuildContext context) {
    final palette = questPalette('steps');
    final icon = switch (steps.trend) {
      'up' => Icons.trending_up_rounded,
      'down' => Icons.trending_down_rounded,
      _ => Icons.trending_flat_rounded,
    };
    final average = steps.avg7;
    return Semantics(
      container: true,
      label: average == null
          ? 'No steps in the last 7 days'
          : 'Averaging ${average.round().formatted} steps a day over the last 7 days. '
                '${trendLabel(steps.trend)}.',
      excludeSemantics: true,
      child: Row(
        children: [
          IconDisc(icon: Icons.directions_walk_rounded, palette: palette, size: 56),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  average == null ? 'No steps yet' : average.round().formatted,
                  style: AppText.tabular(AppText.display),
                ),
                if (average != null) const Text('steps a day, last 7 days', style: AppText.caption),
                if (average != null) ...[
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Icon(icon, size: 20, color: palette.lip),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          trendLabel(steps.trend),
                          style: AppText.label.copyWith(color: palette.lip),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ChartCard extends StatelessWidget {
  const _ChartCard({
    required this.steps,
    required this.trend,
    required this.end,
    required this.onRetry,
  });

  final StepInsights steps;
  final AsyncValue<HealthTrend> trend;
  final String? end;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    final palette = questPalette('steps');
    return AppCard(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('Last 30 days', style: AppText.headline),
          const SizedBox(height: 10),
          trend.when(
            skipLoadingOnReload: true,
            loading: () => const SkeletonBlock(height: 190, radius: 12),
            error: (e, _) =>
                ErrorBlock(title: 'Could not load your steps', error: e, onRetry: onRetry),
            data: (data) {
              final last = data.points.isEmpty ? null : data.points.last.date;
              final endDate = end ?? last;
              if (endDate == null) {
                return const _NoSteps();
              }
              final slots = stepSlots(data.points, endDate);
              final withData = slots.where((s) => (s.value ?? 0) > 0).length;
              if (withData == 0) return const _NoSteps();
              final goal = steps.goal > 0 ? steps.goal.toDouble() : null;
              final start = parseLocalDate(endDate)
                  .subtract(const Duration(days: kStepsChartDays - 1));
              final summary =
                  'Steps for the last 30 days, $withData days with data. '
                  '${steps.best == null ? '' : 'Best day ${steps.best!.value.formatted}. '}'
                  '${goal == null ? '' : 'Goal ${steps.goal.formatted}, reached on ${steps.daysAtGoal30} days.'}';
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Semantics(
                    label: summary,
                    image: true,
                    excludeSemantics: true,
                    child: DayBarChart(
                      data: slots,
                      color: palette.fill,
                      format: (v) => '${v.round().formatted} steps',
                      startLabel: DateFormat.MMMd().format(start),
                      endLabel: endDate == end
                          ? 'Today'
                          : DateFormat.MMMd().format(parseLocalDate(endDate)),
                      goal: goal,
                      goalLabel: goal == null ? null : 'Goal ${steps.goal.formatted}',
                    ),
                  ),
                  if (goal != null) ...[
                    const SizedBox(height: 6),
                    const Text('Solid bars reached your goal.', style: AppText.caption),
                  ],
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _NoSteps extends StatelessWidget {
  const _NoSteps();

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 12),
    child: Column(
      children: [
        const Mascot(size: 72, state: MascotState.sleepy),
        const SizedBox(height: 10),
        Text(
          'No steps in the last 30 days. Once Apple Health shares them, the bars appear here.',
          textAlign: TextAlign.center,
          style: AppText.body.copyWith(color: kInkSecondary),
        ),
      ],
    ),
  );
}

class _SuggestionCard extends StatelessWidget {
  const _SuggestionCard({
    required this.steps,
    required this.saving,
    required this.error,
    required this.offline,
    required this.onUse,
    required this.onBirthYear,
  });

  final StepInsights steps;
  final bool saving;
  final String? error;
  final bool offline;
  final Future<void> Function(int target) onUse;
  final VoidCallback onBirthYear;

  @override
  Widget build(BuildContext context) {
    final palette = questPalette('steps');
    final suggestion = steps.suggestion;
    return AppCard(
      borderColor: palette.fill,
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              IconDisc(icon: Icons.flag_rounded, palette: palette, size: 36),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Suggested goal',
                  style: AppText.label.copyWith(color: palette.lip, fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (suggestion == null) ...[
            const Text('Not enough steps yet', style: AppText.title),
            const SizedBox(height: 6),
            Text(
              'Wear your phone or Watch for a week and New Me will suggest a goal from your own days.',
              style: AppText.body.copyWith(color: kInkSecondary),
            ),
          ] else
            ..._suggestion(context, suggestion, palette),
          const SizedBox(height: 10),
          const Text('General guidance, not medical advice.', style: AppText.caption),
        ],
      ),
    );
  }

  List<Widget> _suggestion(BuildContext context, StepSuggestion s, AccentPalette palette) {
    final copy = stepSuggestionCopy(s, goal: steps.goal);
    final already = s.target == steps.goal;
    return [
      Text(copy.headline, style: AppText.title),
      const SizedBox(height: 6),
      Text(copy.reason, style: AppText.body.copyWith(color: kInkSecondary)),
      if (!s.ageKnown) ...[
        const SizedBox(height: 14),
        Text(
          'Optional: add your birth year and the range fits your age. Height and weight never '
          'come into it.',
          style: AppText.body.copyWith(color: kInkSecondary),
        ),
        const SizedBox(height: 10),
        Semantics(
          container: true,
          child: ChunkyButton.secondary(
            label: 'Add birth year',
            icon: Icons.cake_rounded,
            palette: palette,
            fullWidth: false,
            onPressed: offline || saving ? null : onBirthYear,
          ),
        ),
      ],
      const SizedBox(height: 16),
      if (already)
        Row(
          children: [
            const Icon(Icons.check_circle_rounded, size: 22, color: kSuccessInk),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'This is already your goal.',
                style: AppText.label.copyWith(color: kSuccessInk, fontWeight: FontWeight.w800),
              ),
            ),
          ],
        )
      else ...[
        if (error != null) SaveError(error!),
        Semantics(
          container: true,
          child: ChunkyButton(
            label: error != null ? 'Try again' : 'Use this goal',
            palette: palette,
            busy: saving,
            onPressed: offline ? null : () => onUse(s.target),
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          'The new goal starts tomorrow, so today still counts the old one.',
          style: AppText.caption,
        ),
      ],
    ];
  }
}

const kSuccessInk = Color(0xFF237A4B);

class _Explainer extends StatefulWidget {
  const _Explainer();

  @override
  State<_Explainer> createState() => _ExplainerState();
}

class _ExplainerState extends State<_Explainer> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final reduce = MediaQuery.disableAnimationsOf(context);
    return AppCard(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            container: true,
            button: true,
            expanded: _open,
            label: 'Why not based on height or weight?',
            excludeSemantics: true,
            onTap: () => setState(() => _open = !_open),
            child: Pressable(
              scale: 0.99,
              onTap: () => setState(() => _open = !_open),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 56),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Why not based on height or weight?',
                          style: AppText.body.copyWith(fontWeight: FontWeight.w800),
                        ),
                      ),
                      AnimatedRotation(
                        turns: _open ? 0.5 : 0,
                        duration: reduce ? Duration.zero : kMotionDuration,
                        child: const Icon(Icons.expand_more_rounded, color: kInkSecondary),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          AnimatedSize(
            duration: reduce ? Duration.zero : kMotionDuration,
            curve: Curves.easeOut,
            alignment: Alignment.topCenter,
            child: _open
                ? Semantics(
                    container: true,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          for (final line in _evidence) ...[
                            Text(line, style: AppText.body.copyWith(color: kInkSecondary)),
                            const SizedBox(height: 10),
                          ],
                          const Text(
                            'General guidance, not medical advice.',
                            style: AppText.caption,
                          ),
                        ],
                      ),
                    ),
                  )
                : const SizedBox(width: double.infinity),
          ),
        ],
      ),
    );
  }
}

const _evidence = [
  'Large pooled studies of adults (Paluch et al., The Lancet Public Health, 2022; Ding et al., The Lancet Public Health, 2025) find that the benefit of more steps levels off at roughly 6,000 to 8,000 a day from age 60, and 8,000 to 10,000 for younger adults. Most of the gain is already there around 7,000.',
  'Age moves the target. Height changes your stride, so it changes how far you walk, not how many steps you take, and weight does not set the target either.',
  'So New Me starts from your own last two weeks and your age, and raises the goal about 1,000 steps at a time until you reach the range.',
];
