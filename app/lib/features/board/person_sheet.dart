import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/habit_models.dart';
import '../../api/models.dart';
import '../../state/partner_today.dart';
import '../../theme/quest_style.dart';
import '../../theme/accent.dart';
import '../../theme/tokens.dart';
import '../../theme/typography.dart';
import '../../util/format.dart';
import '../../widgets/app_widgets.dart';
import '../../widgets/avatar.dart';
import '../../widgets/chunky_button.dart';
import '../../widgets/dialogs.dart';
import '../../widgets/quest_copy.dart';
import '../../widgets/skeletons.dart';
import '../habits/habit_icons.dart';
import '../insights/insights_logic.dart';
import '../streaks/streak_visuals.dart';

Future<void> showPersonSheet(
  BuildContext context, {
  required BoardUser user,
  required DateTime now,
  bool isPartner = false,
}) => showAppSheet<void>(
  context,
  builder: (_) => PersonSheet(user: user, now: now, isPartner: isPartner),
);

/// The detail behind a person card: for the partner, what they have done today; then week,
/// workouts, season, freezes and when health last synced.
class PersonSheet extends StatelessWidget {
  const PersonSheet({super.key, required this.user, required this.now, this.isPartner = false});

  final BoardUser user;
  final DateTime now;
  final bool isPartner;

  @override
  Widget build(BuildContext context) {
    final held = user.freezes.held;
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        kGutter,
        4,
        kGutter,
        kGutter + MediaQuery.paddingOf(context).bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Avatar(name: user.name, palette: accentById(user.color), size: 44),
              const SizedBox(width: 12),
              Expanded(
                child: Semantics(header: true, child: Text(user.name, style: AppText.title)),
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (isPartner) ...[
            PartnerDay(palette: accentById(user.color)),
            const SizedBox(height: 18),
          ],
          _Row(label: 'Week', value: '${user.week.formatted} points'),
          if (user.workoutsThisWeek case final n?)
            _Row(
              label: 'Workouts',
              value: workoutCountLabel(n),
              semantics: '${workoutCountLabel(n)} this week',
            ),
          _Row(label: 'Season', value: '${user.season.formatted} points'),
          _Row(
            label: 'Freezes',
            value: '$held',
            leading: FreezeFlakes(held: held, size: 18),
            semantics: freezesLabel(held),
          ),
          _Row(
            label: 'Health',
            value: user.syncedAt == null
                ? 'Not synced'
                : 'Synced ${relativeTime(user.syncedAt!, now)}',
          ),
          const SizedBox(height: 18),
          ChunkyButton.secondary(label: 'Done', onPressed: () => Navigator.of(context).pop()),
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.label, required this.value, this.leading, this.semantics});

  final String label;
  final String value;
  final Widget? leading;
  final String? semantics;

  @override
  Widget build(BuildContext context) => Semantics(
    container: true,
    label: semantics ?? '$label, $value',
    excludeSemantics: true,
    child: Container(
      constraints: const BoxConstraints(minHeight: 44),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: kBorder, width: 2)),
      ),
      child: Row(
        children: [
          Text(label, style: AppText.label.copyWith(color: kInkSecondary)),
          const SizedBox(width: 12),
          Expanded(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (leading != null) ...[leading!, const SizedBox(width: 8)],
                Flexible(
                  child: Text(
                    value,
                    textAlign: TextAlign.end,
                    style: AppText.tabular(AppText.label.copyWith(fontWeight: FontWeight.w800)),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

/// The partner's quests and habits today, each with how far along it is.
class PartnerDay extends ConsumerWidget {
  const PartnerDay({super.key, required this.palette});

  /// The partner's own colour, for their habits, which have no colour of their own.
  final AccentPalette palette;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final value = ref.watch(partnerTodayProvider);
    final day = value.value;
    if (day == null) {
      if (value.hasError) {
        return Text(
          'Could not load their day. Pull Us down to try again.',
          style: AppText.label.copyWith(color: kInkSecondary),
        );
      }
      return const Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SkeletonBlock(width: 64, height: 14),
          SizedBox(height: 12),
          SkeletonBlock(height: 44, radius: 12),
          SizedBox(height: 8),
          SkeletonBlock(height: 44, radius: 12),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const FieldLabel('Today'),
        for (final q in day.quests)
          _DayRow(
            icon: questIcon(q.key),
            palette: questPalette(q.key),
            title: questTitle(q),
            detail: q.done ? 'Done' : questProgress(q),
            done: q.done,
          ),
        if (day.habits.isNotEmpty) ...[
          const SizedBox(height: 18),
          const FieldLabel('Habits'),
          for (final h in day.habits)
            _DayRow(
              icon: habitIcon(h.icon),
              palette: palette,
              title: h.name,
              detail: _habitProgress(h),
              done: _habitDone(h),
            ),
        ],
      ],
    );
  }

  static bool _habitDone(HabitState h) =>
      h.isCount ? h.countDone : h.slots.isNotEmpty && h.slots.every((s) => s.done);

  /// "Done", "1 of 2 done" or "Not yet"; a count habit says "2 of 3".
  static String _habitProgress(HabitState h) {
    if (_habitDone(h)) return 'Done';
    if (h.isCount) return '${h.count} of ${h.target ?? 0}';
    final done = h.slots.where((s) => s.done).length;
    return done == 0 ? 'Not yet' : '$done of ${h.slots.length} done';
  }
}

class _DayRow extends StatelessWidget {
  const _DayRow({
    required this.icon,
    required this.palette,
    required this.title,
    required this.detail,
    required this.done,
  });

  final IconData icon;
  final AccentPalette palette;
  final String title;
  final String detail;
  final bool done;

  @override
  Widget build(BuildContext context) => Semantics(
    container: true,
    label: '$title, $detail',
    excludeSemantics: true,
    child: Container(
      constraints: const BoxConstraints(minHeight: 56),
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: kBorder, width: 2)),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(color: palette.tint, shape: BoxShape.circle),
            child: Icon(icon, size: 18, color: palette.lip),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: AppText.label.copyWith(fontWeight: FontWeight.w800)),
                Text(detail, style: AppText.caption.copyWith(color: kInkSecondary)),
              ],
            ),
          ),
          if (done) ...[
            const SizedBox(width: 8),
            Icon(Icons.check_circle_rounded, size: 22, color: palette.lip),
          ],
        ],
      ),
    ),
  );
}
