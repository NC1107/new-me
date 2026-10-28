import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/api_client.dart';
import '../../api/habit_models.dart';
import '../../reminders/reminder_plan.dart';
import '../../state/habits.dart';
import '../../theme/accent.dart';
import '../../theme/tokens.dart';
import '../../theme/typography.dart';
import '../../util/errors.dart';
import '../../widgets/app_card.dart';
import '../../widgets/cached_view.dart';
import '../../widgets/chunky_button.dart';
import '../../widgets/dialogs.dart';
import '../../widgets/page_scaffold.dart';
import '../../widgets/pressable.dart';
import '../../widgets/skeletons.dart';
import 'habit_editor_page.dart';
import 'habit_icons.dart';

const _kDayShort = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

/// "Every day", "Weekdays" or "Mon, Wed, Fri".
String daysSummary(List<int> weekdays) {
  final days = ({...weekdays}.toList()..sort());
  if (days.length == 7) return 'Every day';
  if (days.length == 5 && days.every((d) => d <= 5)) return 'Weekdays';
  if (days.length == 2 && days[0] == 6 && days[1] == 7) return 'Weekends';
  return days.map((d) => _kDayShort[d - 1]).join(', ');
}

String habitSummary(Habit h) {
  final what = h.isCount
      ? '${h.target ?? 0} a day'
      : h.slots.any((s) => s.minutes != null)
      ? (h.slots.map((s) => s.minutes).nonNulls.toList()..sort()).map(formatReminderTime).join(', ')
      : (h.slots.length > 1 ? '${h.slots.length} times a day' : 'Once a day');
  final worth = HabitWorth.of(h.points);
  final counts = worth == HabitWorth.track ? 'just tracked' : '${worth.points} points';
  return '${daysSummary(h.weekdays)} · $what · $counts';
}

/// Every habit, in order: drag to reorder, tap to edit, and a menu to pause or delete.
class HabitsPage extends ConsumerWidget {
  const HabitsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final value = ref.watch(habitsProvider);
    final habits = value.value?.data.habits;
    return PageScaffold(
      title: 'Habits',
      subtitle: 'Marked off from Today in one tap.',
      footer: ChunkyButton(
        label: 'Add a habit',
        icon: Icons.add_rounded,
        onPressed: () => pushPage(context, const HabitEditorPage()),
      ),
      children: [
        if (habits == null && value.hasError)
          ErrorBlock(
            title: 'Could not load habits',
            error: value.error!,
            onRetry: ref.read(habitsProvider.notifier).refresh,
          )
        else if (habits == null)
          const Column(
            children: [
              SkeletonBlock(height: 68, radius: kRadiusCard),
              SizedBox(height: 8),
              SkeletonBlock(height: 68, radius: kRadiusCard),
            ],
          )
        else if (habits.isEmpty)
          const _NoHabits()
        else
          _List(habits: habits),
      ],
    );
  }
}

class _NoHabits extends StatelessWidget {
  const _NoHabits();

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 32),
    child: Column(
      children: [
        const Icon(Icons.checklist_rounded, size: 44, color: kInkMuted),
        const SizedBox(height: 12),
        Text('No habits yet', style: AppText.headline.copyWith(fontSize: 18)),
        const SizedBox(height: 4),
        Text(
          'Brush teeth, creatine, water. Each gets its own times.',
          textAlign: TextAlign.center,
          style: AppText.caption.copyWith(color: kInkSecondary),
        ),
      ],
    ),
  );
}

class _List extends ConsumerWidget {
  const _List({required this.habits});

  final List<Habit> habits;

  Future<void> _reorder(WidgetRef ref, BuildContext context, int from, int to) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    final ids = [for (final h in habits) h.id];
    ids.insert(to, ids.removeAt(from));
    HapticFeedback.selectionClick();
    try {
      await ref.read(habitsProvider.notifier).reorder(ids);
    } on ApiException catch (e) {
      messenger?.showSnackBar(SnackBar(content: Text(errorCopy(e))));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ReorderableListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      buildDefaultDragHandles: false,
      itemCount: habits.length,
      proxyDecorator: (child, _, _) => Material(color: Colors.transparent, child: child),
      onReorderItem: (from, to) => _reorder(ref, context, from, to),
      itemBuilder: (context, i) {
        final habit = habits[i];
        return Padding(
          key: ValueKey(habit.id),
          padding: const EdgeInsets.only(bottom: 8),
          child: _HabitRow(habit: habit, index: i),
        );
      },
    );
  }
}

final _danger = AccentPalette.of('danger', 'Danger', 0xFFD9534F, 0xFFB23C38, 0xFFFCE9E7);

class _HabitRow extends ConsumerWidget {
  const _HabitRow({required this.habit, required this.index});

  final Habit habit;
  final int index;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.accentPalette;
    final paused = habit.paused;
    return AppCard(
      padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
      onTap: () => pushPage(context, HabitEditorPage(habit: habit)),
      semanticLabel: '${habit.name}, ${paused ? 'paused, ' : ''}${habitSummary(habit)}',
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: paused ? kSunken : palette.tint,
              shape: BoxShape.circle,
            ),
            child: Icon(habitIcon(habit.icon), size: 22, color: paused ? kInkMuted : palette.lip),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  habit.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.body.copyWith(fontWeight: FontWeight.w800),
                ),
                Text(
                  paused ? 'Paused · ${habitSummary(habit)}' : habitSummary(habit),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.caption.copyWith(color: kInkSecondary),
                ),
              ],
            ),
          ),
          _IconTap(
            icon: Icons.more_horiz_rounded,
            label: 'More for ${habit.name}',
            onTap: () => _showMenu(context, ref),
          ),
          ReorderableDragStartListener(
            index: index,
            child: Semantics(
              label: 'Reorder ${habit.name}',
              child: const SizedBox(
                width: 44,
                height: 44,
                child: Icon(Icons.drag_handle_rounded, color: kInkMuted),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showMenu(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    final notifier = ref.read(habitsProvider.notifier);
    final action = await showAppSheet<String>(
      context,
      builder: (sheet) => Padding(
        padding: EdgeInsets.fromLTRB(
          kGutter,
          0,
          kGutter,
          kGutter + MediaQuery.paddingOf(sheet).bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Semantics(header: true, child: Text(habit.name, style: AppText.title)),
            const SizedBox(height: 16),
            ChunkyButton.secondary(
              label: habit.paused ? 'Resume' : 'Pause',
              icon: habit.paused ? Icons.play_arrow_rounded : Icons.pause_rounded,
              onPressed: () => Navigator.of(sheet).pop('pause'),
            ),
            const SizedBox(height: kCardGap),
            ChunkyButton.secondary(
              label: 'Delete',
              palette: _danger,
              icon: Icons.delete_outline_rounded,
              onPressed: () => Navigator.of(sheet).pop('delete'),
            ),
          ],
        ),
      ),
    );
    if (action == null || !context.mounted) return;
    try {
      if (action == 'pause') {
        await notifier.setPaused(habit.id, !habit.paused);
      } else if (await confirmDialog(
        context,
        title: 'Delete ${habit.name}?',
        message: 'It leaves Today and its reminders stop. Past days keep their points.',
        confirmLabel: 'Delete',
        destructive: true,
      )) {
        await notifier.delete(habit.id);
      }
    } on ApiException catch (e) {
      messenger?.showSnackBar(SnackBar(content: Text(errorCopy(e))));
    }
  }
}

class _IconTap extends StatelessWidget {
  const _IconTap({required this.icon, required this.label, required this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: label,
    excludeSemantics: true,
    onTap: onTap,
    child: Pressable(
      onTap: onTap,
      child: SizedBox(width: 44, height: 44, child: Icon(icon, color: kInkSecondary)),
    ),
  );
}
