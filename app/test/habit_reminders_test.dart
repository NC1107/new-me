import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:newme/api/habit_models.dart';
import 'package:newme/reminders/habit_notification_actions.dart';
import 'package:newme/reminders/habit_reminder_plan.dart';
import 'package:newme/reminders/reminder_plan.dart';
import 'package:newme/reminders/reminder_scheduler.dart';
import 'package:newme/state/clock.dart';
import 'package:newme/state/habit_marks.dart';
import 'package:newme/state/habit_reminders.dart';
import 'package:newme/state/habits.dart';
import 'package:newme/state/reminders.dart';
import 'package:newme/state/session.dart';
import 'package:newme/state/today.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_reminder_scheduler.dart';
import 'habit_fixtures.dart';
import 'test_support.dart';

// 2026-10-26 is a Monday.
final _monday6am = DateTime(2026, 10, 26, 6, 0);

Habit _habit(
  int id,
  String name, {
  List<int> days = const [1, 2, 3, 4, 5, 6, 7],
  List<HabitSlot> slots = const [HabitSlot(label: 'Daily', time: '08:00')],
  bool paused = false,
  bool count = false,
}) => Habit(
  id: id,
  name: name,
  icon: 'brush',
  kind: count ? HabitKind.count : HabitKind.check,
  weekdays: days,
  slots: count ? const [] : slots,
  target: count ? 8 : null,
  position: id,
  paused: paused,
);

List<Reminder> _plan(
  List<Habit> habits, {
  DateTime? now,
  Set<String> muted = const {},
  Set<String> done = const {},
  int budget = kHabitReminderBudget,
}) => planHabitReminders(
  now: now ?? _monday6am,
  habits: habits,
  muted: muted,
  doneToday: done,
  budget: budget,
);

void main() {
  group('planHabitReminders', () {
    test('each timed slot is planned at its time for the next week', () {
      final plan = _plan([
        _habit(
          1,
          'Brush teeth',
          slots: const [
            HabitSlot(label: 'Morning', time: '07:30'),
            HabitSlot(label: 'Evening', time: '22:00'),
          ],
        ),
      ]);
      expect(plan, hasLength(14));
      expect(plan.first.at, DateTime(2026, 10, 26, 7, 30));
      expect(plan.first.title, 'Brush teeth');
      expect(plan.first.body, 'Morning');
      expect(plan.first.actionable, isTrue);
      expect(plan.map((r) => r.id).toSet(), hasLength(14), reason: 'ids never collide');
      expect(plan.every((r) => isHabitReminderId(r.id)), isTrue);
    });

    test('only the scheduled weekdays get a reminder', () {
      final plan = _plan([_habit(2, 'Huel', days: kWeekdaysForTest)]);
      final weekdays = plan.map((r) => r.at.weekday).toSet();
      expect(weekdays, {1, 2, 3, 4, 5});
      expect(plan, hasLength(5));
    });

    test('a slot whose time has passed today waits for tomorrow', () {
      final plan = _plan([_habit(1, 'Creatine')], now: DateTime(2026, 10, 26, 9, 0));
      expect(plan.first.at, DateTime(2026, 10, 27, 8, 0));
    });

    test('a slot already done today is not reminded today but is tomorrow', () {
      final plan = _plan([_habit(1, 'Creatine')], done: {slotKey(1, 0)});
      expect(plan.first.at, DateTime(2026, 10, 27, 8, 0));
      expect(plan, hasLength(6));
    });

    test('muted, untimed, paused and count habits are never reminded', () {
      expect(_plan([_habit(1, 'A')], muted: {slotKey(1, 0)}), isEmpty);
      expect(
        _plan([
          _habit(1, 'A', slots: const [HabitSlot(label: 'Daily')]),
        ]),
        isEmpty,
      );
      expect(_plan([_habit(1, 'A', paused: true)]), isEmpty);
      expect(_plan([_habit(1, 'A', count: true)]), isEmpty);
    });

    test('one slot of two can be muted without the other', () {
      final plan = _plan(
        [
          _habit(
            1,
            'Brush teeth',
            slots: const [
              HabitSlot(label: 'Morning', time: '07:30'),
              HabitSlot(label: 'Evening', time: '22:00'),
            ],
          ),
        ],
        muted: {slotKey(1, 1)},
      );
      expect(plan.map((r) => r.body).toSet(), {'Morning'});
    });

    test('the plan stays under the budget and keeps the earliest', () {
      final many = [for (var i = 1; i <= 20; i++) _habit(i, 'Habit $i')];
      final plan = _plan(many, budget: 50);
      expect(plan, hasLength(50));
      expect(plan.last.at.isBefore(DateTime(2026, 10, 29)), isTrue);
    });

    test('the payload names the habit, the slot and the day it was for', () {
      final plan = _plan([_habit(7, 'Floss')], now: DateTime(2026, 10, 26, 23, 0));
      final payload = HabitReminderPayload.tryParse(plan.first.payload)!;
      expect(payload.habitId, 7);
      expect(payload.slot, 0);
      expect(payload.date, '2026-10-27');
      expect(HabitReminderPayload.tryParse('not json'), isNull);
      expect(HabitReminderPayload.tryParse(null), isNull);
    });

    test('habit ids stay clear of the evening reminders', () {
      expect(isHabitReminderId(kTonightReminderId), isFalse);
      expect(isHabitReminderId(kTomorrowReminderId), isFalse);
    });
  });

  group('notification actions', () {
    final payload = const HabitReminderPayload(
      habitId: 1,
      slot: 0,
      date: '2026-10-26',
      title: 'Brush teeth',
      body: 'Morning',
    ).encode();

    const session = Session(
      baseUrl: 'https://x.invalid',
      token: 'tok',
      userId: 2,
      userName: 'Sam',
      color: 'violet',
    );

    Future<List<Reminder>> run(
      String? actionId,
      StubAdapter adapter, {
      Session? s = session,
    }) async {
      final scheduled = <Reminder>[];
      await handleHabitAction(
        actionId: actionId,
        payload: payload,
        loadSession: () async => s,
        clientFor: (session) =>
            stubFactory(adapter)(baseUrl: session.baseUrl, token: session.token),
        schedule: (r) async => scheduled.add(r),
        now: () => _monday6am,
      );
      return scheduled;
    }

    test('Done marks the slot on the day the reminder was for', () async {
      final adapter = StubAdapter()
        ..on('PUT /api/habits/1/marks/2026-10-26', StubResponse(200, markResponse(dueHabits())));
      final scheduled = await run(kActionDone, adapter);
      expect(adapter.last!.data, {'slot': 0, 'done': true});
      expect(adapter.last!.headers['Authorization'], 'Bearer tok');
      expect(scheduled, isEmpty);
    });

    test('Snooze schedules the same reminder half an hour later and calls nothing', () async {
      final adapter = StubAdapter();
      final scheduled = await run(kActionSnooze, adapter);
      expect(adapter.requests, isEmpty);
      expect(scheduled.single.at, _monday6am.add(const Duration(minutes: 30)));
      expect(scheduled.single.title, 'Brush teeth');
      expect(scheduled.single.actionable, isTrue);
      expect(scheduled.single.id, habitSnoozeId(1, 0));
    });

    test('Done while signed out or for a tap on the note does nothing', () async {
      final adapter = StubAdapter();
      expect(await run(kActionDone, adapter, s: null), isEmpty);
      expect(await run(null, adapter), isEmpty);
      expect(adapter.requests, isEmpty);
    });

    test('Done that cannot reach the server asks again in a minute, a refusal does not', () async {
      final offline = StubAdapter()
        ..on('PUT /api/habits/1/marks/2026-10-26', const StubResponse.unreachable());
      final retry = await run(kActionDone, offline);
      expect(retry.single.at, _monday6am.add(const Duration(minutes: 1)));
      expect(retry.single.body, contains('try again'));

      final refused = StubAdapter()
        ..on('PUT /api/habits/1/marks/2026-10-26', const StubResponse(422, {'error': 'paused'}));
      expect(await run(kActionDone, refused), isEmpty);
    });
  });

  group('HabitReminderController', () {
    late FakeReminderScheduler scheduler;
    late DateTime now;
    late ProviderContainer container;
    late StubAdapter adapter;

    Future<void> flush() async {
      for (var i = 0; i < 30; i++) {
        await Future<void>.delayed(Duration.zero);
      }
    }

    Future<void> start({
      bool allowed = true,
      List<Map<String, dynamic>>? due,
      List<Map<String, dynamic>>? all,
      Map<String, Object>? prefs,
    }) async {
      FakeStorage().install();
      SharedPreferences.setMockInitialValues(prefs ?? {});
      scheduler = FakeReminderScheduler(allowed: allowed);
      now = _monday6am;
      adapter = habitsServer(due: due, all: all)
        ..on(
          'PUT /api/habits/1/marks/2026-10-26',
          StubResponse(
            200,
            markResponse([
              checkState(1, 'Brush teeth', 'brush', [
                stateSlot(0, 'Morning', '07:30', done: true),
                stateSlot(1, 'Evening', '22:00'),
              ]),
              ...dueHabits().skip(1),
            ]),
          ),
        );
      container = testContainer(
        overrides: <Override>[
          sessionProvider.overrideWith(() => SessionController.seeded(testSession)),
          apiClientFactoryProvider.overrideWithValue(stubFactory(adapter)),
          clockProvider.overrideWithValue(() => now),
          reminderSchedulerProvider.overrideWithValue(scheduler),
        ],
      );
      container.read(remindersProvider);
      container.read(habitRemindersProvider);
      await container.read(todayProvider.future);
      await container.read(habitsProvider.future);
      await flush();
    }

    List<int> habitIds() => scheduler.pending.keys.where(isHabitReminderId).toList();

    test('timed slots are scheduled once the habits load, with the actions attached', () async {
      await start();
      expect(scheduler.pending[habitReminderId(1, 0, 0)]!.at, DateTime(2026, 10, 26, 7, 30));
      expect(scheduler.pending[habitReminderId(1, 1, 0)]!.at, DateTime(2026, 10, 26, 22, 0));
      expect(scheduler.pending[habitReminderId(2, 0, 0)]!.at, DateTime(2026, 10, 26, 12, 0));
      expect(scheduler.pending.values.every((r) => r.actionable), isTrue);
      expect(habitIds().any((id) => id == habitReminderId(3, 0, 0)), isFalse, reason: 'no time');
      expect(habitIds().any((id) => id == habitReminderId(4, 0, 0)), isFalse, reason: 'count');
    });

    test('marking a slot done withdraws today but keeps the following days', () async {
      await start();
      expect(scheduler.pending.containsKey(habitReminderId(1, 0, 0)), isTrue);
      await container.read(habitMarksProvider).setSlot(1, 0, done: true);
      await flush();
      expect(scheduler.pending.containsKey(habitReminderId(1, 0, 0)), isFalse);
      expect(scheduler.pending.containsKey(habitReminderId(1, 0, 1)), isTrue);
      expect(scheduler.pending.containsKey(habitReminderId(1, 1, 0)), isTrue);
    });

    test('a muted slot is not scheduled', () async {
      await start(
        prefs: {
          'mutedHabitSlots': [slotKey(1, 1)],
        },
      );
      expect(scheduler.pending.containsKey(habitReminderId(1, 1, 0)), isFalse);
      expect(scheduler.pending.containsKey(habitReminderId(1, 0, 0)), isTrue);
    });

    test('a paused or deleted habit loses its reminders when the list changes', () async {
      await start();
      adapter.on(
        'PATCH /api/habits/2',
        StubResponse(200, {'habit': habitJson(2, 'Huel', paused: true)}),
      );
      await container.read(habitsProvider.notifier).setPaused(2, true);
      await flush();
      expect(
        scheduler.pending.keys.where((id) => id ~/ 100 % 10000 == 2 && isHabitReminderId(id)),
        isEmpty,
      );
      expect(scheduler.pending.containsKey(habitReminderId(1, 0, 0)), isTrue);
    });

    test('nothing is scheduled while notifications are not allowed', () async {
      await start(allowed: false);
      expect(habitIds(), isEmpty);
    });

    test('asking for permission schedules afterwards', () async {
      await start(allowed: false);
      scheduler.allowed = false;
      final ok = await container.read(habitRemindersProvider.notifier).ensurePermission();
      await flush();
      expect(ok, isTrue);
      expect(scheduler.permissionRequests, 1);
      expect(habitIds(), isNotEmpty);
    });

    test('the evening reminder ids are left alone', () async {
      await start();
      await container.read(remindersProvider.notifier).enable(minutes: 20 * 60);
      await flush();
      expect(scheduler.pending.containsKey(kTonightReminderId), isTrue);
      await container.read(habitMarksProvider).setSlot(1, 0, done: true);
      await flush();
      expect(scheduler.pending.containsKey(kTonightReminderId), isTrue);
    });

    test('a snooze survives a replan until its slot is done', () async {
      await start();
      scheduler.pending[habitSnoozeId(1, 0)] = Reminder(
        id: habitSnoozeId(1, 0),
        at: DateTime(2026, 10, 26, 8),
        body: 'x',
        actionable: true,
      );
      container.read(habitRemindersProvider.notifier).reschedule();
      await flush();
      expect(scheduler.pending.containsKey(habitSnoozeId(1, 0)), isTrue);
      await container.read(habitMarksProvider).setSlot(1, 0, done: true);
      await flush();
      expect(scheduler.pending.containsKey(habitSnoozeId(1, 0)), isFalse);
    });
  });
}

const kWeekdaysForTest = [1, 2, 3, 4, 5];
