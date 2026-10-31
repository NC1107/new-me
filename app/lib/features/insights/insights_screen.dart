import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../state/insights.dart';
import '../../state/me.dart';
import '../../state/today.dart';
import '../../theme/accent.dart';
import '../../theme/quest_style.dart';
import '../../theme/tokens.dart';
import '../../theme/typography.dart';
import '../../util/format.dart';
import '../../widgets/app_card.dart';
import '../../widgets/page_scaffold.dart';
import '../../widgets/quest_copy.dart';
import '../coach/coach_chat_page.dart';
import '../coach/coach_entry_card.dart';
import '../progress/progress_entry_card.dart';
import '../progress/progress_screen.dart';
import 'body_insights.dart';
import 'insights_logic.dart';
import 'insights_widgets.dart';
import 'sleep_insight_screen.dart';
import 'steps_insight_screen.dart';
import 'workouts_screen.dart';

/// Opens the Insights hub from Today or Me.
Future<void> openInsights(BuildContext context) => pushPage(context, const InsightsScreen());

/// Three big cards, one for each insight, each with its headline number.
class InsightsScreen extends ConsumerWidget {
  const InsightsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final insights = ref.watch(insightsProvider);
    return InsightsFrame(
      title: 'Insights',
      subtitle: 'What your steps, sleep and workouts add up to',
      sources: [insights],
      onRetry: ref.read(insightsProvider.notifier).refresh,
      builder: (context) {
        final data = insights.value!.data;
        final today = ref.watch(todayProvider.select((v) => v.value?.data.localToday));
        return [
          if (ref.watch(meProvider.select((m) => m.value?.data.features.coachChat ?? false))) ...[
            CoachEntryCard(onTap: () => openCoachChat(context)),
            const SizedBox(height: kCardGap),
          ],
          ProgressEntryCard(onTap: () => openProgress(context)),
          const SizedBox(height: kCardGap),
          _HubCard(
            icon: Icons.directions_walk_rounded,
            palette: questPalette('steps'),
            title: 'Steps',
            headline: data.steps.avg7?.round().formatted,
            unit: 'a day this week',
            detail: data.steps.avg7 == null ? null : trendLabel(data.steps.trend),
            onTap: () => pushPage(context, const StepsInsightScreen()),
          ),
          const SizedBox(height: kCardGap),
          _HubCard(
            icon: Icons.bedtime_rounded,
            palette: questPalette('sleep'),
            title: 'Sleep',
            headline: data.sleep.avg7Min == null ? null : durationLabel(data.sleep.avg7Min!),
            unit: 'a night this week',
            detail: data.sleep.lastNight == null
                ? null
                : '${lastNightTitle(data.sleep.lastNight!.date, today)} '
                      '${durationLabel(data.sleep.lastNight!.asleepMin)}',
            onTap: () => pushPage(context, const SleepInsightScreen()),
          ),
          const SizedBox(height: kCardGap),
          _HubCard(
            icon: Icons.fitness_center_rounded,
            palette: questPalette('exercise'),
            title: 'Workouts',
            headline: data.workouts.week.count == 0 && data.workouts.last30.count == 0
                ? null
                : '${data.workouts.week.count}',
            unit: data.workouts.week.count == 1 ? 'workout this week' : 'workouts this week',
            detail: data.workouts.week.count == 0
                ? null
                : durationLabel(data.workouts.week.minutes),
            onTap: () => pushPage(context, const WorkoutsScreen()),
          ),
          if (data.activity.available) ...[
            const SizedBox(height: kCardGap),
            ActivitySummaryCard(activity: data.activity),
          ],
          const SizedBox(height: kCardGap),
          WeightInsightCard(weight: data.weight),
          if (data.protein.available) ...[
            const SizedBox(height: kCardGap),
            ProteinHitCard(protein: data.protein),
          ],
        ];
      },
    );
  }
}

class _HubCard extends StatelessWidget {
  const _HubCard({
    required this.icon,
    required this.palette,
    required this.title,
    required this.headline,
    required this.unit,
    required this.detail,
    required this.onTap,
  });

  final IconData icon;
  final AccentPalette palette;
  final String title;

  /// Null when there is nothing to show yet.
  final String? headline;
  final String unit;
  final String? detail;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      onTap: onTap,
      semanticLabel: headline == null
          ? '$title, no data yet'
          : '$title, $headline $unit${detail == null ? '' : ', $detail'}',
      padding: const EdgeInsets.all(18),
      child: ExcludeSemantics(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                IconDisc(icon: icon, palette: palette, size: 40),
                const SizedBox(width: 12),
                Expanded(child: Text(title, style: AppText.headline)),
                const Icon(Icons.chevron_right_rounded, color: kInkMuted),
              ],
            ),
            const SizedBox(height: 14),
            if (headline == null)
              Text('No data yet', style: AppText.title.copyWith(color: kInkMuted))
            else ...[
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  headline!,
                  style: AppText.tabular(AppText.display.copyWith(color: palette.lip)),
                ),
              ),
              Text(unit, style: AppText.caption),
              if (detail != null) ...[
                const SizedBox(height: 6),
                Text(detail!, style: AppText.label.copyWith(color: kInkSecondary)),
              ],
            ],
          ],
        ),
      ),
    );
  }
}
