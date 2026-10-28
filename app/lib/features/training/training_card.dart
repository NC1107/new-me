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
import 'eased_note.dart';
import 'session_page.dart';
import 'training_copy.dart';
import '../shell/home_tab.dart';

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

/// Today's training: the planned session, a rest day, or the end of a block. Shows nothing without
/// a plan. On Today only something to do is shown; the Train tab shows every state.
class TrainingSlot extends ConsumerStatefulWidget {
  const TrainingSlot({super.key, required this.localToday, this.onTrainTab = false});

  /// Today's date from GET /today; a held training answer for an earlier date is refreshed.
  final String localToday;
  final bool onTrainTab;

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
    final tab = widget.onTrainTab;
    final session = training.session;
    if (!tab && !training.blockEnded && (session == null || session.completed)) {
      return const SizedBox.shrink();
    }
    // The plan sits right under the card on the Train tab, so there the card only opens a session.
    final VoidCallback? openPlan = tab
        ? null
        : () => ref.read(homeTabProvider.notifier).select(HomeTab.train);
    final Widget card;
    if (training.blockEnded) {
      card = _TrainingCard(
        icon: Icons.flag_rounded,
        title: 'Your ${plan.weeks}-week block is done',
        subtitle: 'Design the next block to keep progressing.',
        action: tab ? null : 'Plan',
        onTap: openPlan,
      );
    } else if (session != null) {
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
        footer: session.eased && !session.completed ? EasedNote(session: session) : null,
      );
    } else {
      final next = nextPlanDay(plan, training.date);
      card = _TrainingCard(
        icon: Icons.bedtime_rounded,
        title: 'Rest day',
        subtitle: next == null
            ? 'Recovery is part of the plan.'
            : 'Next: ${next.label}, ${weekdayLabel(next.weekday)}',
        onTap: openPlan,
      );
    }
    return Padding(
      padding: EdgeInsets.only(top: tab ? 0 : kCardGap, bottom: tab ? 20 : 0),
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
    this.footer,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;
  final String? action;
  final bool done;

  /// A line under the row, such as why the session is eased.
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    final accent = context.accentPalette;
    final row = ExcludeSemantics(
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
                Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.headline),
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
          ] else if (onTap != null)
            const Icon(Icons.chevron_right_rounded, color: kInkMuted),
        ],
      ),
    );
    return AppCard(
      onTap: onTap,
      semanticLabel: ['Training', title, subtitle, ?action].join('. '),
      child: footer == null
          ? row
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [row, const SizedBox(height: 10), footer!],
            ),
    );
  }
}
