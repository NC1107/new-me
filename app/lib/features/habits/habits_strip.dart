import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/models.dart';
import '../../api/shared_habit_models.dart';
import '../../state/clock.dart';
import '../../state/habit_marks.dart';
import '../../state/habits.dart';
import '../../state/shared_habits.dart';
import '../../theme/accent.dart';
import '../../theme/tokens.dart';
import '../../theme/typography.dart';
import '../../widgets/app_card.dart';
import '../../widgets/page_scaffold.dart';
import '../shared_habits/shared_habit_chip.dart';
import '../shared_habits/shared_habits_card.dart';
import 'count_sheet.dart';
import 'day_habits_sheet.dart';
import 'habit_chip.dart';
import 'habit_editor_page.dart';
import 'habit_items.dart';

const _kChipGap = 8.0;

/// Today's due habit slots as chips near the top of Today. One tap marks a slot, with no sheet
/// and no confirmation, because friction is what makes a habit not get done.
class HabitsStrip extends ConsumerStatefulWidget {
  const HabitsStrip({super.key, required this.today});

  final Today today;

  @override
  ConsumerState<HabitsStrip> createState() => _HabitsStripState();
}

class _HabitsStripState extends ConsumerState<HabitsStrip> {
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    // A slot turns overdue as the clock passes it, with no data change to redraw the strip.
    _tick = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  void _failed(String name) {
    ScaffoldMessenger.maybeOf(context)
      ?..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text('Could not save $name. Try again.')));
  }

  void _tap(StripItem item) {
    final marks = ref.read(habitMarksProvider);
    final Future<bool> saved = item.isCount
        ? marks.setCount(item.habit.id, item.habit.count + 1)
        : marks.setSlot(item.habit.id, item.slot!.index, done: !item.done);
    unawaited(
      saved.then((ok) {
        if (!ok && mounted) _failed(item.habit.name);
      }),
    );
  }

  Future<void> _setCount(StripItem item) async {
    final value = await showCountSheet(context, habit: item.habit);
    if (value == null || value == item.habit.count || !mounted) return;
    final ok = await ref.read(habitMarksProvider).setCount(item.habit.id, value);
    if (!ok && mounted) _failed(item.habit.name);
  }

  bool get _yesterdayOpen {
    final until = widget.today.backdateUntil;
    return until != null && ref.read(clockProvider)().toUtc().isBefore(until);
  }

  @override
  Widget build(BuildContext context) {
    final today = widget.today;
    // A shared chore shows while it is due, and stays for the day once done so it can be undone.
    final shared = [
      for (final h in ref.watch(sharedHabitsProvider).value ?? const <SharedHabit>[])
        if (h.isDue || h.doneToday) h,
    ];
    if (today.habits.isEmpty && shared.isEmpty) {
      final all = ref.watch(habitsProvider).value?.data.habits;
      if (all == null || all.isNotEmpty) return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsets.only(top: 16),
        child: _EmptyCard(onTap: () => pushPage(context, const HabitEditorPage())),
      );
    }

    final now = ref.watch(clockProvider)();
    final items = stripItems(today.habits, nowMinutes: now.hour * 60 + now.minute);
    final done = items.where((i) => i.done).length;
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Wrap(
                  spacing: 10,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Semantics(
                      header: true,
                      child: Text('Habits', style: AppText.headline.copyWith(fontSize: 18)),
                    ),
                    if (items.isNotEmpty)
                      Text('$done of ${items.length}', style: AppText.tabular(AppText.caption)),
                  ],
                ),
              ),
              if (_yesterdayOpen)
                TextButton(
                  onPressed: () => showYesterdayHabits(context, today: today),
                  style: TextButton.styleFrom(
                    minimumSize: const Size(44, 44),
                    foregroundColor: context.accentPalette.lip,
                    textStyle: AppText.label.copyWith(fontWeight: FontWeight.w800),
                  ),
                  child: const Text('Yesterday'),
                ),
            ],
          ),
          const SizedBox(height: 8),
          LayoutBuilder(
            builder: (context, box) {
              final columns = MediaQuery.textScalerOf(context).scale(16) > 20 ? 1 : 2;
              final width = (box.maxWidth - (columns - 1) * _kChipGap) / columns;
              return Wrap(
                spacing: _kChipGap,
                runSpacing: _kChipGap,
                children: [
                  for (final item in items)
                    SizedBox(
                      key: ValueKey(item.key),
                      width: width,
                      child: HabitChip(
                        item: item,
                        onTap: () => _tap(item),
                        onLongPress: item.isCount ? () => _setCount(item) : null,
                      ),
                    ),
                  for (final h in shared)
                    SizedBox(
                      key: ValueKey('shared${h.id}'),
                      width: width,
                      child: SharedHabitChip(
                        habit: h,
                        onTap: () => toggleSharedHabit(context, ref, h),
                      ),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _EmptyCard extends StatelessWidget {
  const _EmptyCard({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.accentPalette;
    return AppCard(
      onTap: onTap,
      semanticLabel: 'Add your first habit. Brush teeth, creatine, water. Marked off in one tap.',
      padding: const EdgeInsets.all(14),
      // The label reads this text, so it is not read a second time.
      child: ExcludeSemantics(
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(color: palette.tint, shape: BoxShape.circle),
              child: Icon(Icons.add_rounded, color: palette.lip),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Add your first habit',
                    style: AppText.body.copyWith(fontWeight: FontWeight.w800),
                  ),
                  Text(
                    'Brush teeth, creatine, water. Marked off in one tap.',
                    style: AppText.caption.copyWith(color: kInkSecondary),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: kInkMuted),
          ],
        ),
      ),
    );
  }
}
