import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../api/habit_models.dart';
import 'reminder_plan.dart';

/// Habit reminders own ids from here up, below the cap, so they never meet the evening ones.
const kHabitReminderIdBase = 1000000;
const kHabitSnoozeIdBase = 2000000;
const _kIdSpan = 10000;

/// iOS keeps at most 64 pending notifications; the evening reminders take two of them.
const kHabitReminderBudget = 50;
const kHabitReminderDays = 7;
const kSnoozeMinutes = 30;

bool isHabitReminderId(int id) =>
    id >= kHabitReminderIdBase && id < kHabitSnoozeIdBase + _kIdSpan * 10;

int habitReminderId(int habitId, int slot, int dayOffset) =>
    kHabitReminderIdBase + (habitId % _kIdSpan) * 100 + slot * 10 + dayOffset;

int habitSnoozeId(int habitId, int slot) => kHabitSnoozeIdBase + (habitId % _kIdSpan) * 10 + slot;

String slotKey(int habitId, int slot) => '$habitId:$slot';

String _dateKey(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

/// What a notification tap carries: which slot, and the day it was for, so Done lands on the
/// right day even when it is pressed after midnight.
@immutable
class HabitReminderPayload {
  const HabitReminderPayload({
    required this.habitId,
    required this.slot,
    required this.date,
    this.title = 'New Me',
    this.body = '',
  });

  static HabitReminderPayload? tryParse(String? raw) {
    if (raw == null) return null;
    try {
      final j = jsonDecode(raw);
      if (j is! Map<String, dynamic>) return null;
      final habit = j['h'], slot = j['s'], date = j['d'];
      if (habit is! int || slot is! int || date is! String) return null;
      return HabitReminderPayload(
        habitId: habit,
        slot: slot,
        date: date,
        title: j['t'] as String? ?? 'New Me',
        body: j['b'] as String? ?? '',
      );
    } on FormatException {
      return null;
    }
  }

  final int habitId;
  final int slot;
  final String date;

  /// Kept so a snoozed copy can be shown again without looking the habit up.
  final String title;
  final String body;

  String encode() => jsonEncode({'h': habitId, 's': slot, 'd': date, 't': title, 'b': body});
}

/// The notification text: the habit is the title, and the slot says which one of the day.
({String title, String body}) habitReminderCopy(String name, String slotLabel, int slotCount) =>
    (title: name, body: slotCount > 1 ? slotLabel : 'Time to check it off');

/// The reminders that should be pending now: each timed, unpaused, unmuted slot at its time on
/// its weekdays for the next [kHabitReminderDays] days, minus slots already done today.
///
/// One-off notifications for specific dates, not repeating ones, because a repeating one cannot
/// skip a single day when the slot has been done. The earliest [budget] are kept so the near
/// future is always covered.
List<Reminder> planHabitReminders({
  required DateTime now,
  required List<Habit> habits,
  required Set<String> muted,
  required Set<String> doneToday,
  int budget = kHabitReminderBudget,
}) {
  final out = <Reminder>[];
  final today = DateTime(now.year, now.month, now.day);
  for (final habit in habits) {
    if (habit.paused || habit.isCount) continue;
    for (final (slot, spec) in habit.slots.indexed) {
      final minutes = spec.minutes;
      if (minutes == null || muted.contains(slotKey(habit.id, slot))) continue;
      for (var offset = 0; offset < kHabitReminderDays; offset++) {
        final day = DateTime(today.year, today.month, today.day + offset);
        if (!habit.dueOn(day.weekday)) continue;
        final at = DateTime(day.year, day.month, day.day, minutes ~/ 60, minutes % 60);
        if (!at.isAfter(now)) continue;
        if (offset == 0 && doneToday.contains(slotKey(habit.id, slot))) continue;
        final copy = habitReminderCopy(habit.name, spec.label, habit.slots.length);
        out.add(
          Reminder(
            id: habitReminderId(habit.id, slot, offset),
            at: at,
            title: copy.title,
            body: copy.body,
            actionable: true,
            payload: HabitReminderPayload(
              habitId: habit.id,
              slot: slot,
              date: _dateKey(day),
              title: copy.title,
              body: copy.body,
            ).encode(),
          ),
        );
      }
    }
  }
  out.sort((a, b) => a.at != b.at ? a.at.compareTo(b.at) : a.id.compareTo(b.id));
  return out.take(budget).toList();
}

/// A snoozed copy of a delivered reminder, for [kSnoozeMinutes] later.
Reminder snoozedReminder({required HabitReminderPayload payload, required DateTime now}) =>
    Reminder(
      id: habitSnoozeId(payload.habitId, payload.slot),
      at: now.add(const Duration(minutes: kSnoozeMinutes)),
      title: payload.title,
      body: payload.body,
      actionable: true,
      payload: payload.encode(),
    );
