import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:newme/api/models.dart';
import 'package:newme/features/shell/home_tab.dart';
import 'package:newme/reminders/reminder_plan.dart';
import 'package:newme/reminders/reminder_scheduler.dart';
import 'package:newme/state/clock.dart';
import 'package:newme/state/reminders.dart';
import 'package:newme/state/session.dart';
import 'package:newme/state/today.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_reminder_scheduler.dart';
import 'fixtures.dart';
import 'test_support.dart';

class _Setup {
  _Setup({DateTime? now, bool allowed = true, bool grants = true, Map<String, Object>? prefs}) {
    FakeStorage().install();
    SharedPreferences.setMockInitialValues(prefs ?? {});
    scheduler = FakeReminderScheduler(allowed: allowed, grantsOnRequest: grants);
    this.now = now ?? DateTime(2026, 10, 26, 18, 0);
    container = testContainer(
      overrides: <Override>[
        sessionProvider.overrideWith(() => SessionController.seeded(testSession)),
        apiClientFactoryProvider.overrideWithValue(stubFactory(fullServer())),
        clockProvider.overrideWithValue(() => this.now),
        reminderSchedulerProvider.overrideWithValue(scheduler),
      ],
    );
  }

  late final FakeReminderScheduler scheduler;
  late DateTime now;
  late final ProviderContainer container;

  ReminderController get reminders => container.read(remindersProvider.notifier);

  Future<void> flush() async {
    for (var i = 0; i < 20; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  Future<void> start() async {
    container.read(remindersProvider);
    await container.read(todayProvider.future);
    await flush();
  }
}

void main() {
  test('nothing is scheduled until reminders are on', () async {
    final t = _Setup();
    await t.start();
    expect(t.scheduler.pending, isEmpty);
    expect(t.container.read(remindersProvider).active, isFalse);
  });

  test('turning on asks once, schedules tonight with Today copy and a generic tomorrow', () async {
    final t = _Setup();
    await t.start();

    expect(await t.reminders.enable(), isTrue);
    await t.flush();

    expect(t.scheduler.permissionRequests, 1);
    final tonight = t.scheduler.pending[kTonightReminderId]!;
    expect(tonight.at, DateTime(2026, 10, 26, 20));
    final left = t.container.read(todayProvider).value!.data.quests.where((q) => !q.done).length;
    expect(tonight.body, reminderCopy(questsLeft: left, percent: 62));
    expect(t.scheduler.pending[kTomorrowReminderId]!.at, DateTime(2026, 10, 27, 20));
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('remindersEnabled'), isTrue);
  });

  test('turning on right away is not undone by loading saved preferences', () async {
    final t = _Setup();
    await t.reminders.enable(minutes: 21 * 60);
    await t.flush();

    final settings = t.container.read(remindersProvider);
    expect(settings.active, isTrue);
    expect(settings.minutes, 21 * 60);
  });

  test('a day that counts cancels tonight and keeps tomorrow', () async {
    final t = _Setup();
    await t.start();
    await t.reminders.enable();
    await t.flush();
    expect(t.scheduler.pending, contains(kTonightReminderId));

    final today = t.container.read(todayProvider).value!.data;
    await t.container
        .read(todayProvider.notifier)
        .replace(today.copyWith(day: DayScore.fromJson(dayJson(counted: true))));
    await t.flush();

    expect(t.scheduler.pending, isNot(contains(kTonightReminderId)));
    expect(t.scheduler.pending, contains(kTomorrowReminderId));
  });

  test('new numbers on Today reword tonight without adding a second reminder', () async {
    final t = _Setup();
    await t.start();
    await t.reminders.enable();
    await t.flush();
    final before = t.scheduler.pending[kTonightReminderId]!.body;

    final today = t.container.read(todayProvider).value!.data;
    await t.container
        .read(todayProvider.notifier)
        .replace(today.copyWith(day: DayScore.fromJson(dayJson(percent: 5))));
    await t.flush();

    expect(t.scheduler.pending[kTonightReminderId]!.body, isNot(before));
    expect(t.scheduler.pending, hasLength(2));
  });

  test('after the reminder time only tomorrow is scheduled', () async {
    final t = _Setup(now: DateTime(2026, 10, 26, 21, 15));
    await t.start();
    await t.reminders.enable();
    await t.flush();

    expect(t.scheduler.pending.keys, [kTomorrowReminderId]);
  });

  test('stale cached data from another day gives the generic line, not old numbers', () async {
    final t = _Setup(now: DateTime(2026, 10, 27, 9, 0));
    await t.start();
    await t.reminders.enable();
    await t.flush();

    expect(t.scheduler.pending[kTonightReminderId]!.body, 'Your day is waiting');
  });

  test('changing the time moves both reminders', () async {
    final t = _Setup();
    await t.start();
    await t.reminders.enable();
    await t.reminders.setMinutes(21 * 60);
    await t.flush();

    expect(t.scheduler.pending[kTonightReminderId]!.at, DateTime(2026, 10, 26, 21));
    expect(t.scheduler.pending[kTomorrowReminderId]!.at, DateTime(2026, 10, 27, 21));
    expect((await SharedPreferences.getInstance()).getInt('reminderMinutes'), 21 * 60);
  });

  test('turning off cancels everything', () async {
    final t = _Setup();
    await t.start();
    await t.reminders.enable();
    await t.reminders.disable();
    await t.flush();

    expect(t.scheduler.pending, isEmpty);
    expect(t.container.read(remindersProvider).active, isFalse);
  });

  test('a denied permission schedules nothing and reports blocked', () async {
    final t = _Setup(grants: false);
    await t.start();

    expect(await t.reminders.enable(), isFalse);
    await t.flush();

    expect(t.scheduler.pending, isEmpty);
    expect(t.container.read(remindersProvider).blocked, isTrue);
  });

  test('allowing notifications in iOS Settings later brings the reminder back', () async {
    final t = _Setup(grants: false);
    await t.start();
    await t.reminders.enable();
    t.scheduler.allowed = true;

    await t.reminders.refreshPermission();
    await t.flush();

    expect(t.container.read(remindersProvider).active, isTrue);
    expect(t.scheduler.pending, contains(kTonightReminderId));
  });

  test('saved preferences are restored on the next launch', () async {
    final t = _Setup(prefs: {'remindersEnabled': true, 'reminderMinutes': 19 * 60});
    await t.start();

    expect(t.container.read(remindersProvider).minutes, 19 * 60);
    expect(t.scheduler.pending[kTonightReminderId]!.at, DateTime(2026, 10, 26, 19));
  });

  test('tapping the notification selects the Today tab', () async {
    final t = _Setup();
    await t.start();
    t.container.read(homeTabProvider.notifier).select(HomeTab.me);

    t.scheduler.onTap!();

    expect(t.container.read(homeTabProvider), HomeTab.today);
  });
}
