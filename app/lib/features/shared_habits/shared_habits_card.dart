import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/shared_habit_models.dart';
import '../../state/clock.dart';
import '../../state/session.dart';
import '../../state/shared_habits.dart';
import '../../theme/accent.dart';
import '../../theme/tokens.dart';
import '../../theme/typography.dart';
import '../../util/errors.dart';
import '../../widgets/app_card.dart';
import '../../widgets/pressable.dart';
import '../habits/habit_icons.dart';
import 'shared_habit_sheet.dart';
import 'shared_habit_text.dart';

const _kOverdueDisc = Color(0xFFFFE0B2);
const _kOverdueInk = Color(0xFF8A4B00);

/// Marks a chore done, or takes my own mark back, and says so when the server refuses.
Future<void> toggleSharedHabit(BuildContext context, WidgetRef ref, SharedHabit h) async {
  if (h.doneToday && !h.doneByMe) return;
  HapticFeedback.mediumImpact();
  final notifier = ref.read(sharedHabitsProvider.notifier);
  try {
    await (h.doneByMe ? notifier.undo(h.id) : notifier.markDone(h.id));
  } on Object catch (e) {
    if (!context.mounted) return;
    ScaffoldMessenger.maybeOf(context)
      ?..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(errorCopy(e))));
  }
}

/// The household's chores on Us: what is due first, then what is coming up, with who did each
/// last. One tap marks one done; a tap on the row edits it.
class SharedHabitsCard extends ConsumerWidget {
  const SharedHabitsCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final habits = ref.watch(sharedHabitsProvider).value;
    if (habits == null) return const SizedBox.shrink();
    final myId = ref.watch(sessionProvider.select((s) => s.session?.userId));
    final now = ref.watch(clockProvider)();
    final due = [
      for (final h in habits)
        if (h.isDue && !h.doneToday) h,
    ];
    final rest = [
      for (final h in habits)
        if (!due.contains(h)) h,
    ];
    return Padding(
      padding: const EdgeInsets.only(top: 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(header: true, child: const Text('Home', style: AppText.headline)),
          const SizedBox(height: 2),
          const Text('Chores for both of you.', style: AppText.caption),
          const SizedBox(height: 10),
          AppCard(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Column(
              children: [
                if (due.isNotEmpty) _GroupLabel(rest.isEmpty ? 'Due' : 'Due now'),
                for (final h in due) _ChoreRow(habit: h, myId: myId, now: now),
                if (rest.isNotEmpty && due.isNotEmpty) const _GroupLabel('Coming up'),
                for (final h in rest) _ChoreRow(habit: h, myId: myId, now: now),
                _AddRow(first: habits.isEmpty, onTap: () => showSharedHabitSheet(context)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _GroupLabel extends StatelessWidget {
  const _GroupLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.centerLeft,
    child: Padding(
      padding: const EdgeInsets.only(top: 10, bottom: 2),
      child: Text(text.toUpperCase(), style: AppText.caption.copyWith(letterSpacing: 0.6)),
    ),
  );
}

class _ChoreRow extends ConsumerWidget {
  const _ChoreRow({required this.habit, required this.myId, required this.now});

  final SharedHabit habit;
  final int? myId;
  final DateTime now;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final h = habit;
    final overdue = h.overdue && !h.doneToday;
    final due = sharedDueLabel(h);
    final last = sharedLastLabel(h, myId, now);
    final detail = h.doneToday ? last : '${sharedScheduleLabel(h.schedule)} · $last';
    final palette = context.accentPalette;
    return Column(
      children: [
        Semantics(
          button: true,
          label: '${h.name}, ${h.doneToday ? 'done' : due}, $detail',
          excludeSemantics: true,
          onTap: () => showSharedHabitSheet(context, habit: h),
          child: Pressable(
            scale: 0.99,
            onTap: () => showSharedHabitSheet(context, habit: h),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 64),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: overdue ? _kOverdueDisc : palette.tint,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        habitIcon(h.icon),
                        size: 20,
                        color: overdue ? _kOverdueInk : palette.lip,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            h.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppText.label.copyWith(fontWeight: FontWeight.w800),
                          ),
                          Text(
                            h.doneToday ? 'Done today' : due,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppText.caption.copyWith(
                              color: overdue ? _kOverdueInk : kInkSecondary,
                              fontWeight: overdue ? FontWeight.w800 : FontWeight.w700,
                            ),
                          ),
                          Text(
                            detail,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppText.caption,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    _DoneButton(habit: h),
                  ],
                ),
              ),
            ),
          ),
        ),
        const Divider(height: 2, thickness: 2, color: kBorder),
      ],
    );
  }
}

/// The round check at the end of a row: empty to do it, filled once done. My own mark can be
/// taken back by tapping it again; the partner's stays.
class _DoneButton extends ConsumerWidget {
  const _DoneButton({required this.habit});

  final SharedHabit habit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final h = habit;
    final palette = context.accentPalette;
    final locked = h.doneToday && !h.doneByMe;
    final label = h.doneByMe
        ? 'Undo ${h.name}'
        : locked
        ? '${h.name} done by ${h.last?.name}'
        : 'Mark ${h.name} done';
    return Semantics(
      button: true,
      enabled: !locked,
      checked: h.doneToday,
      label: label,
      excludeSemantics: true,
      onTap: locked ? null : () => toggleSharedHabit(context, ref, h),
      child: Pressable(
        onTap: locked ? null : () => toggleSharedHabit(context, ref, h),
        child: SizedBox(
          width: 48,
          height: 48,
          child: Center(
            child: AnimatedContainer(
              duration: MediaQuery.disableAnimationsOf(context) ? Duration.zero : kMotionDuration,
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: h.doneToday ? palette.fill : kSurface,
                shape: BoxShape.circle,
                border: Border.all(
                  color: h.doneToday ? palette.fill : kBorder,
                  width: kBorderWidth,
                ),
              ),
              child: Icon(
                Icons.check_rounded,
                size: 22,
                color: h.doneToday ? palette.onFill : kInkMuted,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AddRow extends StatelessWidget {
  const _AddRow({required this.first, required this.onTap});

  final bool first;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.accentPalette;
    return Semantics(
      button: true,
      label: first ? 'Add your first chore' : 'Add a chore',
      excludeSemantics: true,
      onTap: onTap,
      child: Pressable(
        scale: 0.99,
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 56),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(color: palette.tint, shape: BoxShape.circle),
                child: Icon(Icons.add_rounded, color: palette.lip),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      first ? 'Add your first chore' : 'Add a chore',
                      style: AppText.label.copyWith(fontWeight: FontWeight.w800),
                    ),
                    if (first)
                      const Text(
                        'Laundry, dishes, vacuum. Either of you marks it done.',
                        style: AppText.caption,
                      ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded, size: 22, color: kInkSecondary),
            ],
          ),
        ),
      ),
    );
  }
}
