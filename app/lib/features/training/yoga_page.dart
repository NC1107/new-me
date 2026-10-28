import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/models.dart';
import '../../state/training.dart';
import '../../state/yoga.dart';
import '../../theme/accent.dart';
import '../../theme/tokens.dart';
import '../../theme/typography.dart';
import '../../util/errors.dart';
import '../../widgets/app_card.dart';
import '../../widgets/app_widgets.dart';
import '../../widgets/cached_view.dart' show ErrorBlock;
import '../../widgets/chunky_button.dart';
import '../../widgets/page_scaffold.dart';
import '../../widgets/segmented.dart';
import '../../widgets/skeletons.dart';
import 'exercises_page.dart';
import 'guided_page.dart';
import 'guided_session.dart';
import 'training_copy.dart';
import 'yoga_flows.dart';

/// Yoga: this week against the plan, the three guided flows, the plan editor and the pose library.
class YogaPage extends ConsumerStatefulWidget {
  const YogaPage({super.key});

  @override
  ConsumerState<YogaPage> createState() => _YogaPageState();
}

class _YogaPageState extends ConsumerState<YogaPage> {
  int? _days;
  int? _flow;
  bool _saving = false;
  String? _error;

  Future<void> _save(YogaPlanState state, {int? flow, bool restartLevel = false}) async {
    final base = state.plan ?? state.suggested;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref
          .read(yogaPlanProvider.notifier)
          .save(
            daysPerWeek: _days ?? base.daysPerWeek,
            flowMinutes: flow ?? _flow ?? base.flowMinutes,
            restartLevel: restartLevel,
          );
      if (!mounted) return;
      HapticFeedback.mediumImpact();
      setState(() {
        _days = null;
        _flow = null;
      });
    } on Object catch (e) {
      if (mounted) setState(() => _error = errorCopy(e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _open(YogaFlow flow) {
    HapticFeedback.selectionClick();
    unawaited(pushPage(context, GuidedPage(routine: yogaRoutine(flow))));
  }

  @override
  Widget build(BuildContext context) {
    final plan = ref.watch(yogaPlanProvider);
    final catalog = ref.watch(exercisesProvider).value?.data;
    return PageScaffold(
      title: 'Yoga',
      children: [
        switch (plan) {
          AsyncValue(:final value?) => _PlanSection(
            state: value,
            days: _days ?? (value.plan ?? value.suggested).daysPerWeek,
            flow: _flow ?? (value.plan ?? value.suggested).flowMinutes,
            saving: _saving,
            error: _error,
            onDays: (d) => setState(() => _days = d),
            onFlow: (f) => setState(() => _flow = f),
            onSave: () => _save(value),
            onAccept: (minutes) => _save(value, flow: minutes),
            onDecline: () => _save(value, restartLevel: true),
            onStartToday: (f) => _open(f),
          ),
          AsyncValue(:final error?) => ErrorBlock(
            title: 'Could not load your yoga plan',
            error: error,
            onRetry: () async => ref.invalidate(yogaPlanProvider),
          ),
          _ => const SkeletonBlock(height: 160, radius: kRadiusCard),
        },
        const SizedBox(height: 20),
        const FieldLabel('Guided flows'),
        for (final flow in kYogaFlows) ...[
          _FlowCard(flow: flow, catalog: catalog, onTap: () => _open(flow)),
          const SizedBox(height: 10),
        ],
        const SizedBox(height: 4),
        Text(
          '$kYogaOrderNote Finishing a flow adds its minutes to your yoga quest.',
          style: AppText.caption.copyWith(color: kInkMuted),
        ),
        const SizedBox(height: 20),
        const FieldLabel('Poses'),
        AppCard(
          onTap: () {
            HapticFeedback.selectionClick();
            unawaited(pushPage(context, const ExercisesPage(initialFilter: LibraryFilter.yoga)));
          },
          child: const Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Pose library', style: AppText.headline),
                    Text('Photos, steps and cautions for every pose.', style: AppText.caption),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: kInkMuted),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Text(kYogaSafety, style: AppText.caption.copyWith(color: kInkMuted)),
      ],
    );
  }
}

class _PlanSection extends StatelessWidget {
  const _PlanSection({
    required this.state,
    required this.days,
    required this.flow,
    required this.saving,
    required this.error,
    required this.onDays,
    required this.onFlow,
    required this.onSave,
    required this.onAccept,
    required this.onDecline,
    required this.onStartToday,
  });

  final YogaPlanState state;
  final int days;
  final int flow;
  final bool saving;
  final String? error;
  final ValueChanged<int> onDays;
  final ValueChanged<int> onFlow;
  final VoidCallback onSave;
  final ValueChanged<int> onAccept;
  final VoidCallback onDecline;
  final ValueChanged<YogaFlow> onStartToday;

  @override
  Widget build(BuildContext context) {
    final plan = state.plan;
    final week = state.week;
    final changed = plan == null || plan.daysPerWeek != days || plan.flowMinutes != flow;
    final todayFlow = state.todayPlanned && !state.todayDone && plan != null
        ? yogaFlowOf(plan.flowMinutes)
        : null;
    final offer = state.offerMinutes;
    final offered = offer == null ? null : yogaFlowOf(offer);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (plan != null && week != null) ...[
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Yoga this week: ${week.done} of ${week.planned}', style: AppText.headline),
                const SizedBox(height: 4),
                Text(
                  'Planned for ${plan.weekdays.map(weekdayLabel).join(', ')}, '
                  '${plan.flowMinutes} minute flow.',
                  style: AppText.caption.copyWith(color: kInkSecondary),
                ),
                const SizedBox(height: 12),
                _WeekDots(days: week.days),
                if (todayFlow != null) ...[
                  const SizedBox(height: 12),
                  ChunkyButton(
                    label: 'Today: ${todayFlow.name}',
                    icon: Icons.play_arrow_rounded,
                    onPressed: () => onStartToday(todayFlow),
                  ),
                ] else if (state.todayPlanned && state.todayDone) ...[
                  const SizedBox(height: 12),
                  Text(
                    'Today\'s yoga is done.',
                    style: AppText.label.copyWith(color: kInkSecondary),
                  ),
                ],
              ],
            ),
          ),
          if (offered != null) ...[
            const SizedBox(height: 12),
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('Ready for ${offered.name}?', style: AppText.headline),
                  const SizedBox(height: 4),
                  Text(
                    'You did your yoga days two weeks running. A ${offered.minutes} minute flow is '
                    'up to you, and the plan stays as it is if you wait.',
                    style: AppText.body.copyWith(color: kInkSecondary),
                  ),
                  const SizedBox(height: 12),
                  ChunkyButton(
                    label: 'Try ${offered.name}',
                    busy: saving,
                    onPressed: () => onAccept(offered.minutes),
                  ),
                  const SizedBox(height: 4),
                  Align(
                    alignment: Alignment.center,
                    child: TextButton(
                      onPressed: saving ? null : onDecline,
                      style: TextButton.styleFrom(
                        minimumSize: const Size(64, 48),
                        tapTargetSize: MaterialTapTargetSize.padded,
                        foregroundColor: context.accentPalette.lip,
                      ),
                      child: const Text('Not now', style: TextStyle(fontWeight: FontWeight.w700)),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 20),
        ],
        FieldLabel(plan == null ? 'Plan your week' : 'Your plan'),
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('Days a week', style: AppText.label),
              const SizedBox(height: 8),
              Segmented<int>(
                options: [for (var d = 1; d <= 7; d++) (d, '$d')],
                selected: days,
                onChanged: onDays,
                spokenLabel: (d) => '$d ${d == 1 ? 'day' : 'days'} a week',
              ),
              const SizedBox(height: 16),
              const Text('Flow', style: AppText.label),
              const SizedBox(height: 8),
              Segmented<int>(
                options: [for (final f in kYogaFlows) (f.minutes, '${f.minutes} min')],
                selected: flow,
                onChanged: onFlow,
                spokenLabel: (m) => '$m minutes',
              ),
              const SizedBox(height: 12),
              Text(
                state.citation.isEmpty ? kYogaCitation : state.citation,
                style: AppText.caption.copyWith(color: kInkMuted),
              ),
              if (state.avoidedDays.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  'Days are placed around your heavy leg days (${state.avoidedDays.map(weekdayLabel).join(', ')}).',
                  style: AppText.caption.copyWith(color: kInkMuted),
                ),
              ],
              if (error != null) ...[
                const SizedBox(height: 8),
                Text(error!, style: AppText.label.copyWith(color: kDangerText)),
              ],
              const SizedBox(height: 12),
              ChunkyButton(
                label: plan == null ? 'Save plan' : 'Update plan',
                busy: saving,
                onPressed: changed ? onSave : null,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// One dot per weekday: filled when yoga was logged, ringed when planned.
class _WeekDots extends StatelessWidget {
  const _WeekDots({required this.days});

  final List<YogaWeekDay> days;

  @override
  Widget build(BuildContext context) {
    final accent = context.accentPalette;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        for (final d in days)
          Semantics(
            container: true,
            excludeSemantics: true,
            label:
                '${weekdayLabel(d.weekday)}, ${d.done
                    ? 'done'
                    : d.planned
                    ? 'planned'
                    : 'no yoga planned'}',
            child: Column(
              children: [
                Text(
                  weekdayLabel(d.weekday).substring(0, 1),
                  style: AppText.caption.copyWith(color: kInkSecondary),
                ),
                const SizedBox(height: 4),
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: d.done ? accent.fill : Colors.transparent,
                    border: d.done || d.planned
                        ? Border.all(color: accent.fill, width: kBorderWidth)
                        : null,
                  ),
                  child: d.done ? const Icon(Icons.check_rounded, size: 18, color: kSurface) : null,
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _FlowCard extends StatelessWidget {
  const _FlowCard({required this.flow, required this.catalog, required this.onTap});

  final YogaFlow flow;
  final ExerciseCatalog? catalog;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = catalog;
    final holds = c == null ? null : buildYogaHolds(flow, c);
    final detail = holds == null || holds.isEmpty
        ? flow.blurb
        : '${holds.last.stepIndex + 1} poses, about ${(guidedTotalSeconds(holds) / 60).round()} minutes. ${flow.blurb}';
    return AppCard(
      onTap: onTap,
      semanticLabel: flow.name,
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(flow.name, style: AppText.headline),
                const SizedBox(height: 2),
                Text(detail, style: AppText.caption.copyWith(color: kInkSecondary)),
              ],
            ),
          ),
          const Icon(Icons.chevron_right_rounded, color: kInkMuted),
        ],
      ),
    );
  }
}
