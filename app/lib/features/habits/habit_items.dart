import 'package:flutter/foundation.dart';

import '../../api/habit_models.dart';
import '../../reminders/reminder_plan.dart';

/// One tappable thing in the strip: a single slot of a check habit, or a whole count habit.
@immutable
class StripItem {
  const StripItem({
    required this.habit,
    required this.slot,
    required this.minutes,
    required this.done,
    required this.overdue,
    required this.multiSlot,
  });

  final HabitState habit;

  /// Null for a count habit.
  final HabitStateSlot? slot;

  /// Minutes after midnight, or null when there is no time.
  final int? minutes;
  final bool done;

  /// The slot's time has passed and it is not done.
  final bool overdue;
  final bool multiSlot;

  bool get isCount => slot == null;

  String get key => isCount ? 'h${habit.id}' : 'h${habit.id}s${slot!.index}';

  String get title => habit.name;

  /// The slot label (only when the habit has several, since "Daily" says nothing) and the time.
  String? get caption {
    if (isCount) return '${habit.count}/${habit.target ?? 0}';
    final parts = [
      if (multiSlot && slot!.label.isNotEmpty) slot!.label,
      if (minutes != null) formatReminderTime(minutes!),
    ];
    return parts.isEmpty ? null : parts.join(' · ');
  }

  String get semanticLabel {
    final state = done ? 'done' : (overdue ? 'overdue' : 'not done');
    return [title, ?caption, state].join(', ');
  }
}

/// Today's due slots in the order they come up: by time, untimed last, then in the person's own
/// habit order. A done slot keeps its place so the strip never shifts under a thumb.
List<StripItem> stripItems(List<HabitState> habits, {required int nowMinutes}) {
  final items = <StripItem>[];
  for (final habit in habits) {
    if (habit.isCount) {
      items.add(
        StripItem(
          habit: habit,
          slot: null,
          minutes: null,
          done: habit.countDone,
          overdue: false,
          multiSlot: false,
        ),
      );
      continue;
    }
    for (final slot in habit.slots) {
      final minutes = slot.minutes;
      items.add(
        StripItem(
          habit: habit,
          slot: slot,
          minutes: minutes,
          done: slot.done,
          overdue: !slot.done && minutes != null && minutes <= nowMinutes,
          multiSlot: habit.slots.length > 1,
        ),
      );
    }
  }
  final order = {for (final (i, h) in habits.indexed) h.id: i};
  items.sort((a, b) {
    final am = a.minutes, bm = b.minutes;
    if (am != bm) {
      if (am == null) return 1;
      if (bm == null) return -1;
      return am.compareTo(bm);
    }
    final byHabit = order[a.habit.id]!.compareTo(order[b.habit.id]!);
    return byHabit != 0 ? byHabit : (a.slot?.index ?? 0).compareTo(b.slot?.index ?? 0);
  });
  return items;
}
