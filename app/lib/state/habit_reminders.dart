import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../reminders/habit_reminder_plan.dart';
import '../reminders/reminder_plan.dart';
import '../reminders/reminder_scheduler.dart';
import 'clock.dart';
import 'habits.dart';
import 'local_prefs.dart';
import 'reminders.dart';
import 'session.dart';
import 'today.dart';

String _dateKey(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

/// Keeps the pending habit notifications equal to what the habits and today's marks say should
/// be pending. It replans whenever either changes, which is also how marking a slot done
/// withdraws its reminder.
class HabitReminderController extends Notifier<void> {
  Future<void> _queue = Future.value();

  /// What was last handed to the scheduler, so an unchanged reminder is not scheduled again.
  final _scheduled = <int, Reminder>{};

  ReminderScheduler get _scheduler => ref.read(reminderSchedulerProvider);

  @override
  void build() {
    ref.listen(todayProvider, (_, _) => reschedule());
    ref.listen(habitsProvider, (_, _) => reschedule());
    ref.listen(sessionProvider.select((s) => s.session?.userId), (prev, next) {
      if (next != null || prev == null) return;
      unawaited(_enqueue(_cancelAll));
    });
  }

  void reschedule() => unawaited(_enqueue(_apply));

  /// Asks the system for permission the first time a reminder is wanted, then plans. Returns
  /// whether notifications are allowed.
  Future<bool> ensurePermission() async {
    await ref.read(remindersProvider.notifier).ready;
    final allowed = await _scheduler.isAllowed() || await _scheduler.requestPermission();
    reschedule();
    return allowed;
  }

  Future<void> _enqueue(Future<void> Function() job) => _queue = _queue.then((_) async {
    try {
      await job();
    } on Object catch (e) {
      debugPrint('[NEWME] habit reminder scheduling failed: $e');
    }
  });

  Future<void> _cancelAll() async {
    for (final id in await _scheduler.pendingIds()) {
      if (isHabitReminderId(id)) await _scheduler.cancel(id);
    }
    _scheduled.clear();
  }

  Future<void> _apply() async {
    await ref.read(remindersProvider.notifier).ready;
    final habits = ref.read(habitsProvider).value?.data.habits;
    final signedIn = ref.read(sessionProvider).session != null;
    if (habits == null || !signedIn || !await _scheduler.isAllowed()) {
      if (!signedIn || habits != null) await _cancelAll();
      return;
    }
    final now = ref.read(clockProvider)();
    final today = ref.read(todayProvider).value?.data;
    final doneToday = <String>{
      if (today != null && today.localToday == _dateKey(now))
        for (final h in today.habits)
          for (final s in h.slots)
            if (s.done) slotKey(h.id, s.index),
    };
    final plan = planHabitReminders(
      now: now,
      habits: habits,
      muted: await LocalPrefs.mutedHabitSlots(),
      doneToday: doneToday,
    );
    final wanted = {for (final r in plan) r.id: r};
    final doneSnoozes = {
      if (today != null && today.localToday == _dateKey(now))
        for (final h in today.habits)
          for (final s in h.slots)
            if (s.done) habitSnoozeId(h.id, s.index),
    };
    for (final id in await _scheduler.pendingIds()) {
      if (!isHabitReminderId(id)) continue;
      final stale = _isSnooze(id) ? doneSnoozes.contains(id) : !wanted.containsKey(id);
      if (!stale) continue;
      await _scheduler.cancel(id);
      _scheduled.remove(id);
    }
    for (final r in plan) {
      if (_scheduled[r.id] == r) continue;
      await _scheduler.schedule(r);
      _scheduled[r.id] = r;
    }
  }

  /// A snooze belongs to the person's last tap, not to the plan, so a replan leaves it alone
  /// unless the slot has since been done.
  bool _isSnooze(int id) => id >= kHabitSnoozeIdBase;
}

final habitRemindersProvider = NotifierProvider<HabitReminderController, void>(
  HabitReminderController.new,
);
