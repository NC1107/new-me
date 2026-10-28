import 'package:flutter_test/flutter_test.dart';
import 'package:newme/api/habit_models.dart';
import 'package:newme/api/models.dart';

import 'fixtures.dart';
import 'habit_fixtures.dart';
import 'test_support.dart';

void main() {
  group('parsing', () {
    test('Today reads the habits due today with their slots and counts', () {
      final today = Today.fromJson(richTodayJson()..['habits'] = dueHabits());
      expect(today.habits.map((h) => h.name), ['Brush teeth', 'Huel', 'Floss', 'Water']);
      final brush = today.habits.first;
      expect(brush.slots.map((s) => s.minutes), [7 * 60 + 30, 22 * 60]);
      expect(brush.slots.every((s) => !s.done), isTrue);
      final water = today.habits.last;
      expect(water.isCount, isTrue);
      expect(water.target, 8);
      expect(water.countDone, isFalse);
      expect(today.habits.first.slots.first.label, 'Morning');
    });

    test('a server without habits, or with odd entries, still parses', () {
      expect(Today.fromJson(richTodayJson()).habits, isEmpty);
      final odd = Today.fromJson(
        richTodayJson()
          ..['habits'] = [
            'nope',
            {
              'id': 9,
              'name': 'Odd',
              'icon': 'a_new_icon',
              'kind': 'check',
              'slots': [
                1,
                {'index': 0, 'label': 'Now', 'time': 'later'},
              ],
            },
          ],
      );
      expect(odd.habits, hasLength(1));
      expect(odd.habits.single.slots.single.minutes, isNull);
    });

    test('Today keeps habits through a JSON round trip for the offline cache', () {
      final json = richTodayJson()..['habits'] = dueHabits();
      final again = Today.fromJson(Today.fromJson(json).toJson());
      expect(canonicalInstants(again.toJson()), canonicalInstants(Today.fromJson(json).toJson()));
      expect(again.habits.last.count, 0);
    });

    test('copyWith swaps habits and leaves the rest', () {
      final today = Today.fromJson(richTodayJson()..['habits'] = dueHabits());
      final next = today.copyWith(habits: [today.habits.first.withSlotDone(0, true)]);
      expect(next.habits.single.slots.first.done, isTrue);
      expect(next.quests, hasLength(today.quests.length));
    });

    test('a habit reads weekdays, paused and target', () {
      final h = Habit.fromJson(
        habitJson(
          2,
          'Huel',
          weekdays: [1, 2, 3, 4, 5],
          slots: [
            {'label': 'Lunch', 'time': '12:00'},
          ],
        ),
      );
      expect(h.dueOn(1), isTrue);
      expect(h.dueOn(6), isFalse);
      expect(h.everyDay, isFalse);
      expect(h.paused, isFalse);
      expect(Habit.fromJson(habitJson(4, 'Water', kind: 'count', target: 8)).target, 8);
    });

    test('slot times parse only as HH:MM', () {
      expect(parseSlotTime('07:30'), 450);
      expect(parseSlotTime('24:00'), isNull);
      expect(parseSlotTime('7'), isNull);
      expect(parseSlotTime(null), isNull);
      expect(slotTimeString(450), '07:30');
    });

    test('a draft sends slots for a check habit and a target for a count habit', () {
      const check = HabitDraft(
        name: 'Floss',
        icon: 'clean_hands',
        kind: HabitKind.check,
        weekdays: [1, 2],
        slots: [HabitSlot(label: 'Evening', time: '22:00')],
      );
      expect(check.toJson(), {
        'name': 'Floss',
        'icon': 'clean_hands',
        'kind': 'check',
        'weekdays': [1, 2],
        'slots': [
          {'label': 'Evening', 'time': '22:00'},
        ],
        'points': 25,
      });
      expect(check.toPatchJson().containsKey('kind'), isFalse);
      const count = HabitDraft(
        name: 'Water',
        icon: 'water_drop',
        kind: HabitKind.count,
        weekdays: kEveryDayForTest,
        target: 8,
      );
      expect(count.toJson().containsKey('slots'), isFalse);
      expect(count.toJson()['target'], 8);
      expect(HabitWorth.of(0), HabitWorth.track);
      expect(HabitWorth.of(7), HabitWorth.medium);
    });
  });

  group('ApiClient', () {
    test('habits lists, creates, patches, deletes and orders', () async {
      final adapter = StubAdapter()
        ..on('GET /api/habits', StubResponse(200, {'habits': allHabits()}))
        ..on('POST /api/habits', StubResponse(201, {'habit': habitJson(5, 'Stretch')}))
        ..on(
          'PATCH /api/habits/5',
          StubResponse(200, {'habit': habitJson(5, 'Stretch', paused: true)}),
        )
        ..on('DELETE /api/habits/5', const StubResponse(204))
        ..on('PUT /api/habits/order', StubResponse(200, {'habits': allHabits().reversed.toList()}));
      final client = stubFactory(adapter)(baseUrl: 'https://x.invalid', token: 't');

      expect((await client.habits()).map((h) => h.id), [1, 2, 3, 4]);
      final created = await client.createHabit(
        const HabitDraft(
          name: 'Stretch',
          icon: 'self_improvement',
          kind: HabitKind.check,
          weekdays: kEveryDayForTest,
          slots: [HabitSlot(label: 'Daily')],
        ),
      );
      expect(created.id, 5);
      expect((adapter.last!.data as Map)['slots'], [
        {'label': 'Daily', 'time': null},
      ]);
      expect((await client.patchHabit(5, {'paused': true})).paused, isTrue);
      await client.deleteHabit(5);
      expect((await client.orderHabits([4, 3, 2, 1])).first.id, 4);
      expect((adapter.last!.data as Map)['ids'], [4, 3, 2, 1]);
    });

    test('marks send slot and done, or a count, and read the day back', () async {
      final adapter = StubAdapter()
        ..on(
          'PUT /api/habits/1/marks/2026-10-26',
          StubResponse(200, markResponse(dueHabits(), points: 155)),
        );
      final client = stubFactory(adapter)(baseUrl: 'https://x.invalid', token: 't');

      final slot = await client.markHabitSlot(1, '2026-10-26', slot: 0, done: true);
      expect(adapter.last!.data, {'slot': 0, 'done': true});
      expect(slot.day.score.points, 155);
      expect(slot.habits, hasLength(4));

      await client.markHabitCount(1, '2026-10-26', 3);
      expect(adapter.last!.data, {'count': 3});
    });
  });
}

const kEveryDayForTest = [1, 2, 3, 4, 5, 6, 7];
