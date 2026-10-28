import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../api/models.dart';
import '../../state/insights.dart';
import '../../state/me.dart';
import '../../theme/quest_style.dart';
import '../../theme/tokens.dart';
import '../../theme/typography.dart';
import '../../util/format.dart';
import '../../widgets/app_card.dart';
import '../../widgets/chunky_button.dart';
import '../../widgets/mascot.dart';
import '../../widgets/pressable.dart';
import '../../widgets/quest_copy.dart';
import '../log/log_kind.dart';
import '../log/log_sheet.dart';
import 'insight_charts.dart';
import 'insights_logic.dart';
import 'insights_widgets.dart';
import 'workout_sheet.dart';
import 'workout_types.dart';
import '../../widgets/units_scope.dart';

class WorkoutsScreen extends ConsumerWidget {
  const WorkoutsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final insights = ref.watch(insightsProvider);
    final list = ref.watch(workoutsProvider(30));
    final zone = ref.watch(meProvider.select((v) => v.value?.data.user.timezone));
    return InsightsFrame(
      title: 'Workouts',
      sources: [insights, list],
      onRetry: () async {
        await ref.read(insightsProvider.notifier).refresh();
        await ref.read(workoutsProvider(30).notifier).refresh();
      },
      builder: (context) {
        final data = insights.value!.data.workouts;
        final workouts = list.value!.data.workouts;
        if (workouts.isEmpty && data.last30.count == 0 && data.week.count == 0) {
          return [const _NoWorkouts(), const SizedBox(height: kCardGap), _LogActivityButton()];
        }
        return [
          _WeekCard(week: data.week),
          const SizedBox(height: kCardGap),
          _LogActivityButton(),
          const SizedBox(height: 20),
          if (data.byType.isNotEmpty) ...[_ByType(workouts: data), const SizedBox(height: 20)],
          if (workouts.isNotEmpty) ...[
            const Text('Recent workouts', style: AppText.headline),
            const SizedBox(height: 8),
            AppCard(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  for (final (i, w) in workouts.indexed) ...[
                    if (i > 0) const Divider(height: 2, thickness: 2, color: kBorder),
                    WorkoutRow(
                      workout: w,
                      onTap: () => showWorkoutSheet(context, workout: w, zone: zone),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ];
      },
    );
  }
}

/// Anything Health does not see: it counts toward the day's exercise minutes.
class _LogActivityButton extends StatelessWidget {
  @override
  Widget build(BuildContext context) => ChunkyButton.secondary(
    label: 'Log an activity',
    icon: Icons.add_rounded,
    onPressed: () => showLogSheet(context, kind: LogKind.activity),
  );
}

class _NoWorkouts extends StatelessWidget {
  const _NoWorkouts();

  @override
  Widget build(BuildContext context) => AppCard(
    padding: const EdgeInsets.all(24),
    child: Column(
      children: [
        const Mascot(size: 88, state: MascotState.thinking),
        const SizedBox(height: 12),
        const Text('No workouts yet', textAlign: TextAlign.center, style: AppText.headline),
        const SizedBox(height: 6),
        Text(
          'Start a workout on your Apple Watch or in the Fitness app. It shows up here after '
          'the next Health sync.',
          textAlign: TextAlign.center,
          style: AppText.body.copyWith(color: kInkSecondary),
        ),
      ],
    ),
  );
}

class _WeekCard extends StatelessWidget {
  const _WeekCard({required this.week});

  final WorkoutTotals week;

  @override
  Widget build(BuildContext context) {
    final palette = questPalette('exercise');
    final none = week.count == 0;
    return Semantics(
      container: true,
      label: none
          ? 'No workouts yet this week'
          : 'This week, ${workoutCountLabel(week.count)}, ${durationLabel(week.minutes)}',
      excludeSemantics: true,
      child: AppCard(
        padding: const EdgeInsets.all(18),
        child: Row(
          children: [
            IconDisc(icon: Icons.local_fire_department_rounded, palette: palette, size: 56),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('This week', style: AppText.caption.copyWith(color: kInkSecondary)),
                  Text(
                    none ? 'No workouts yet' : workoutCountLabel(week.count),
                    style: AppText.tabular(AppText.title.copyWith(fontWeight: FontWeight.w900)),
                  ),
                  Text(
                    none ? 'Your week starts on Monday.' : '${durationLabel(week.minutes)} moving',
                    style: AppText.caption,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ByType extends StatelessWidget {
  const _ByType({required this.workouts});

  final WorkoutInsights workouts;

  @override
  Widget build(BuildContext context) {
    final palette = questPalette('exercise');
    final top = workouts.byType.fold<int>(1, (m, t) => t.minutes > m ? t.minutes : m);
    return AppCard(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('Last 30 days', style: AppText.headline),
          const SizedBox(height: 2),
          Text(
            '${workoutCountLabel(workouts.last30.count)}, ${durationLabel(workouts.last30.minutes)}',
            style: AppText.caption,
          ),
          const SizedBox(height: 14),
          for (final (i, t) in workouts.byType.indexed) ...[
            if (i > 0) const SizedBox(height: 14),
            Semantics(
              container: true,
              label:
                  '${workoutTypeName(t.type)}, ${workoutCountLabel(t.count)}, ${durationLabel(t.minutes)}',
              excludeSemantics: true,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      IconDisc(icon: workoutTypeIcon(t.type), palette: palette, size: 32),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          workoutTypeName(t.type),
                          style: AppText.body.copyWith(fontWeight: FontWeight.w800),
                        ),
                      ),
                      Flexible(
                        child: Text(
                          '${t.count}x - ${durationLabel(t.minutes)}',
                          textAlign: TextAlign.end,
                          style: AppText.tabular(AppText.label.copyWith(color: kInkSecondary)),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  RankedBar(fraction: t.minutes / top, color: palette.fill),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// One workout of the recent list: icon, name and day, then its numbers.
class WorkoutRow extends StatelessWidget {
  const WorkoutRow({super.key, required this.workout, required this.onTap});

  final Workout workout;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = questPalette('exercise');
    final w = workout;
    final day = DateFormat.MMMEd().format(parseLocalDate(w.date));
    final facts = [
      durationLabel(w.durationMin),
      if (w.kcal != null) '${w.kcal!.formatted} kcal',
      if (w.distanceM != null && w.distanceM! > 0) distanceLabel(w.distanceM!, context.units),
      if (w.avgHr != null) '${w.avgHr} bpm',
    ];
    return Semantics(
      container: true,
      button: true,
      excludeSemantics: true,
      label: '${workoutTypeName(w.type)}, $day, ${facts.join(', ')}',
      onTap: onTap,
      child: Pressable(
        scale: 0.99,
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 68),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Row(
              children: [
                IconDisc(icon: workoutTypeIcon(w.type), palette: palette),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: 8,
                        crossAxisAlignment: WrapCrossAlignment.end,
                        children: [
                          Text(
                            workoutTypeName(w.type),
                            style: AppText.body.copyWith(fontWeight: FontWeight.w800),
                          ),
                          Text(day, style: AppText.caption.copyWith(color: kInkSecondary)),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Wrap(
                        spacing: 10,
                        runSpacing: 2,
                        children: [
                          for (final f in facts)
                            Text(
                              f,
                              style: AppText.tabular(
                                AppText.caption.copyWith(color: kInkSecondary),
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right_rounded, color: kInkMuted),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
