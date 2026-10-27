import 'package:flutter_test/flutter_test.dart';
import 'package:newme/api/models.dart';
import 'package:newme/reminders/reminder_plan.dart';

import 'fixtures.dart';

Today _today({bool counted = false, int percent = 62, String localToday = '2026-10-26'}) =>
    Today.fromJson({
      ...richTodayJson(counted: counted, percent: percent),
      'localToday': localToday,
    });

void main() {
  group('reminderCopy', () {
    test('names the quests left when one or two remain', () {
      expect(reminderCopy(questsLeft: 1, percent: 90), '1 quest left to save your streak');
      expect(reminderCopy(questsLeft: 2, percent: 30), '2 quests left to save your streak');
    });

    test('talks about the percent when many quests remain', () {
      expect(
        reminderCopy(questsLeft: 4, percent: 54),
        'You are at 54%. A short walk gets you there.',
      );
      expect(
        reminderCopy(questsLeft: 5, percent: 12),
        'You are at 12%. One quest gets you moving.',
      );
    });

    test('has a line for a day that has not started', () {
      expect(
        reminderCopy(questsLeft: 5, percent: 0),
        'Your day has not started. One quest gets you going.',
      );
    });

    test('has a line when everything is done but the day has not counted', () {
      expect(
        reminderCopy(questsLeft: 0, percent: 66),
        'You are at 66%. A short walk gets you there.',
      );
    });

    test('is deterministic and clamps nonsense percents', () {
      expect(reminderCopy(questsLeft: 3, percent: 54), reminderCopy(questsLeft: 3, percent: 54));
      expect(reminderCopy(questsLeft: 3, percent: 140), contains('100%'));
      expect(reminderCopy(questsLeft: 3, percent: -5), contains('has not started'));
    });
  });

  group('planReminders', () {
    final evening = DateTime(2026, 10, 26, 18, 30);

    test('schedules tonight from Today and a generic tomorrow', () {
      final plan = planReminders(now: evening, minutes: 20 * 60, today: _today());
      final left = _today().quests.where((q) => !q.done).length;
      expect(plan[kTonightReminderId]?.at, DateTime(2026, 10, 26, 20));
      expect(plan[kTonightReminderId]?.body, reminderCopy(questsLeft: left, percent: 62));
      expect(plan[kTomorrowReminderId]?.at, DateTime(2026, 10, 27, 20));
      expect(plan[kTomorrowReminderId]?.body, 'Your day is waiting');
    });

    test('keeps no reminder for tonight once the day has counted', () {
      final plan = planReminders(now: evening, minutes: 20 * 60, today: _today(counted: true));
      expect(plan[kTonightReminderId], isNull);
      expect(plan[kTomorrowReminderId], isNotNull);
    });

    test('skips tonight when the time has passed', () {
      final plan = planReminders(
        now: DateTime(2026, 10, 26, 20, 0),
        minutes: 20 * 60,
        today: _today(),
      );
      expect(plan[kTonightReminderId], isNull);
      expect(plan[kTomorrowReminderId]?.at, DateTime(2026, 10, 27, 20));
    });

    test('falls back to the generic line without data or with data from another day', () {
      final none = planReminders(now: evening, minutes: 20 * 60);
      expect(none[kTonightReminderId]?.body, 'Your day is waiting');
      final stale = planReminders(
        now: evening,
        minutes: 20 * 60,
        today: _today(localToday: '2026-10-25'),
      );
      expect(stale[kTonightReminderId]?.body, 'Your day is waiting');
    });

    test('rolls tomorrow over a month end', () {
      final plan = planReminders(now: DateTime(2026, 10, 31, 9), minutes: 19 * 60 + 30);
      expect(plan[kTomorrowReminderId]?.at, DateTime(2026, 11, 1, 19, 30));
    });
  });

  test('formatReminderTime writes a 12 hour clock', () {
    expect(formatReminderTime(20 * 60), '8:00 PM');
    expect(formatReminderTime(0), '12:00 AM');
    expect(formatReminderTime(12 * 60 + 5), '12:05 PM');
    expect(formatReminderTime(9 * 60 + 30), '9:30 AM');
  });
}
