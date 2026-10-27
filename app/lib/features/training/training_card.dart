import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/models.dart';
import '../../state/training.dart';
import '../../theme/accent.dart';
import '../../theme/tokens.dart';
import '../../theme/typography.dart';
import '../../util/format.dart';
import '../../widgets/app_card.dart';
import '../../widgets/page_scaffold.dart';
import 'session_page.dart';
import 'training_copy.dart';
import 'training_page.dart';

/// The next plan day after [date] (YYYY-MM-DD), for the rest-day line.
PlanDay? nextPlanDay(TrainingPlan plan, String date) {
  final d = parseLocalDate(date);
  if (plan.days.isEmpty) return null;
  for (var ahead = 1; ahead <= 7; ahead++) {
    final weekday = d.add(Duration(days: ahead)).weekday;
    final day = plan.days.where((p) => p.weekday == weekday).firstOrNull;
    if (day != null) return day;
  }
  return null;
}

/// Today's training on the Today screen: the planned session, a rest day, or the end of a block.
/// Shows nothing for someone without a plan, which the Training page in Me offers.
class TrainingSlot extends ConsumerStatefulWidget {
  const TrainingSlot({super.key, required this.localToday});

  /// Today's date from GET /today; a held training answer for an earlier date is refreshed.
  final String localToday;

  @override
  ConsumerState<TrainingSlot> createState() => _TrainingSlotState();
}

class _TrainingSlotState extends ConsumerState<TrainingSlot> {
  String? _refreshedFor;

  @override
  Widget build(BuildContext context) {
    final value = ref.watch(trainingTodayProvider);
    final training = value.value?.data;
    if (training == null) return const SizedBox.shrink();
    if (training.date != widget.localToday &&
        _refreshedFor != widget.localToday &&
        !value.isLoading) {
      _refreshedFor = widget.localToday;
      Future.microtask(() {
        if (mounted) unawaited(ref.read(trainingTodayProvider.notifier).refresh());
      });
    }
    final plan = training.plan;
    if (plan == null) return const SizedBox.shrink();
    final Widget card;
    if (training.blockEnded) {
      card = _TrainingCard(
        icon: Icons.flag_rounded,
        title: 'Your ${plan.weeks}-week block is done',
        subtitle: 'Design the next block to keep progressing.',
        action: 'Plan',
        onTap: () => pushPage(context, const TrainingPage()),
      );
    } else if (training.session case final session?) {
      card = _TrainingCard(
        icon: session.completed ? Icons.check_circle_rounded : Icons.fitness_center_rounded,
        title: session.label,
        subtitle: session.completed
            ? 'Done today'
            : session.setsLogged == 0
            ? '${session.exercises.length} exercises, ${session.setsPlanned} sets'
            : sessionProgressLabel(session),
        action: session.completed
            ? 'View'
            : session.setsLogged == 0
            ? 'Start'
            : 'Continue',
        onTap: () => pushPage(context, const SessionPage()),
        done: session.completed,
      );
    } else {
      final next = nextPlanDay(plan, training.date);
      card = _TrainingCard(
        icon: Icons.bedtime_rounded,
        title: 'Rest day',
        subtitle: next == null
            ? 'Recovery is part of the plan.'
            : 'Next: ${next.label}, ${weekdayLabel(next.weekday)}',
        onTap: () => pushPage(context, const TrainingPage()),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(top: kCardGap),
      child: card,
    );
  }
}

class _TrainingCard extends StatelessWidget {
  const _TrainingCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.action,
    this.done = false,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final String? action;
  final bool done;

  @override
  Widget build(BuildContext context) {
    final accent = context.accentPalette;
    return AppCard(
      onTap: onTap,
      semanticLabel: ['Training', title, subtitle, ?action].join('. '),
      child: ExcludeSemantics(
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: accent.tint,
                borderRadius: BorderRadius.circular(kRadiusField),
              ),
              child: Icon(icon, color: done ? accent.fill : accent.lip, size: 24),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Training', style: AppText.caption.copyWith(color: kInkMuted)),
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.headline,
                  ),
                  Text(subtitle, style: AppText.caption.copyWith(color: kInkSecondary)),
                ],
              ),
            ),
            if (action case final label?) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: done ? accent.tint : accent.fill,
                  borderRadius: BorderRadius.circular(kRadiusButton),
                ),
                child: Text(
                  label,
                  style: AppText.label.copyWith(
                    color: done ? accent.lip : accent.onFill,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ] else
              const Icon(Icons.chevron_right_rounded, color: kInkMuted),
          ],
        ),
      ),
    );
  }
}
