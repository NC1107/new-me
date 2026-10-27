import 'package:flutter/foundation.dart';

import '../api/models.dart';

/// Fixed ids, so scheduling again replaces the pending notification instead of stacking.
const kTonightReminderId = 4101;
const kTomorrowReminderId = 4102;

const kDefaultReminderMinutes = 20 * 60;
const kReminderPresetMinutes = [19 * 60, 20 * 60, 21 * 60];

const _kTitle = 'New Me';
const _kGenericBody = 'Your day is waiting';

/// Below this the person is far enough from the line that a walk alone would not close it.
const _kNearLinePercent = 40;

@immutable
class Reminder {
  const Reminder({
    required this.id,
    required this.at,
    required this.body,
    this.title = _kTitle,
    this.payload,
    this.actionable = false,
  });

  final int id;

  /// Wall-clock time on the phone.
  final DateTime at;
  final String body;
  final String title;

  /// Handed back when the person taps the notification or one of its actions.
  final String? payload;

  /// Carries the Done and Snooze actions and breaks through Focus as time sensitive.
  final bool actionable;

  @override
  bool operator ==(Object other) =>
      other is Reminder &&
      other.id == id &&
      other.at == at &&
      other.body == body &&
      other.title == title &&
      other.payload == payload &&
      other.actionable == actionable;

  @override
  int get hashCode => Object.hash(id, at, body, title, payload, actionable);

  @override
  String toString() => 'Reminder($id, $at, $title, $body)';
}

/// The line for an evening when the day has not counted yet.
String reminderCopy({required int questsLeft, required int percent}) {
  final shown = percent.clamp(0, 100);
  if (questsLeft == 1) return '1 quest left to save your streak';
  if (questsLeft == 2) return '2 quests left to save your streak';
  if (shown <= 0) return 'Your day has not started. One quest gets you going.';
  if (shown < _kNearLinePercent) return 'You are at $shown%. One quest gets you moving.';
  return 'You are at $shown%. A short walk gets you there.';
}

String _dateKey(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

/// What should be pending right now, by id. A null entry means nothing for that id.
///
/// Tonight's reminder follows [today] when it describes today; without fresh data it falls back
/// to a generic line so the person is still nudged. Tomorrow's is always generic because the
/// app cannot know tomorrow's score yet.
Map<int, Reminder?> planReminders({required DateTime now, required int minutes, Today? today}) {
  final at = DateTime(now.year, now.month, now.day, minutes ~/ 60, minutes % 60);
  final tomorrow = DateTime(now.year, now.month, now.day + 1, minutes ~/ 60, minutes % 60);
  final fresh = today != null && today.localToday == _dateKey(now);

  Reminder? tonight;
  if (at.isAfter(now) && !(fresh && today.day.counted)) {
    tonight = Reminder(
      id: kTonightReminderId,
      at: at,
      body: fresh
          ? reminderCopy(
              questsLeft: today.quests.where((q) => !q.done).length,
              percent: today.day.percent,
            )
          : _kGenericBody,
    );
  }
  return {
    kTonightReminderId: tonight,
    kTomorrowReminderId: Reminder(id: kTomorrowReminderId, at: tomorrow, body: _kGenericBody),
  };
}

/// "8:00 PM" for minutes since midnight.
String formatReminderTime(int minutes) {
  final h = minutes ~/ 60;
  final m = minutes % 60;
  final hour12 = h % 12 == 0 ? 12 : h % 12;
  return '$hour12:${m.toString().padLeft(2, '0')} ${h < 12 ? 'AM' : 'PM'}';
}
