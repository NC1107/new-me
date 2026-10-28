import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:newme/api/habit_models.dart';
import 'package:newme/features/habits/habit_editor_page.dart';
import 'package:newme/features/habits/habits_page.dart';
import 'package:newme/state/habits.dart';
import 'package:newme/widgets/chunky_button.dart';
import 'package:newme/widgets/time_presets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fixtures.dart';
import 'habit_fixtures.dart';
import 'test_support.dart';

Finder _button(String label) =>
    find.byWidgetPredicate((w) => w is ChunkyButton && w.label == label);

Finder _pill(String label) => find.bySemanticsLabel(label);

void main() {
  setUp(() => FakeStorage().install());

  Future<TestApp> open(
    WidgetTester tester,
    StubAdapter adapter, {
    Widget page = const HabitEditorPage(),
  }) async {
    final app = TestApp(tester, adapter, surfaceHeight: 2400);
    await app.pump(
      Builder(
        builder: (context) => Center(
          child: ElevatedButton(
            onPressed: () =>
                Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page)),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await app.tap(find.text('open'));
    return app;
  }

  group('editor', () {
    testWidgets('a template and Save is the whole job', (tester) async {
      final handle = tester.ensureSemantics();
      final adapter = habitsServer()
        ..on('POST /api/habits', StubResponse(201, {'habit': habitJson(9, 'Brush teeth')}));
      final app = await open(tester, adapter);

      await app.tap(_pill('Brush teeth'));
      await app.tap(_button('Save'));

      final body = app.body('POST /api/habits');
      expect(body['name'], 'Brush teeth');
      expect(body['icon'], 'brush');
      expect(body['kind'], 'check');
      expect(body['weekdays'], [1, 2, 3, 4, 5, 6, 7]);
      expect(body['slots'], [
        {'label': 'Morning', 'time': '07:30'},
        {'label': 'Evening', 'time': '22:00'},
      ]);
      expect(find.text('New habit'), findsNothing, reason: 'the editor closed after saving');
      handle.dispose();
    });

    testWidgets('Huel is weekdays only', (tester) async {
      final handle = tester.ensureSemantics();
      final adapter = habitsServer()
        ..on('POST /api/habits', StubResponse(201, {'habit': habitJson(9, 'Huel')}));
      final app = await open(tester, adapter);
      await app.tap(_pill('Huel'));
      await app.tap(_button('Save'));
      final body = app.body('POST /api/habits');
      expect(body['weekdays'], [1, 2, 3, 4, 5]);
      expect(body['slots'], [
        {'label': 'Lunch', 'time': '12:00'},
      ]);
      handle.dispose();
    });

    testWidgets('Water is a count habit with a target and no slots', (tester) async {
      final handle = tester.ensureSemantics();
      final adapter = habitsServer()
        ..on(
          'POST /api/habits',
          StubResponse(201, {'habit': habitJson(9, 'Water', kind: 'count', target: 8)}),
        );
      final app = await open(tester, adapter);
      await app.tap(_pill('Water'));
      expect(find.text('Daily target'), findsOneWidget);
      await app.tap(_button('Save'));
      final body = app.body('POST /api/habits');
      expect(body['kind'], 'count');
      expect(body['target'], 8);
      expect(body.containsKey('slots'), isFalse);
      handle.dispose();
    });

    testWidgets('Save without a name explains and sends nothing', (tester) async {
      final adapter = habitsServer();
      final app = await open(tester, adapter);
      await app.tap(_button('Save'));
      expect(find.text('Give the habit a name.'), findsOneWidget);
      expect(adapter.to('POST /api/habits'), isEmpty);
    });

    testWidgets('no days, or an unnamed time, is refused before the request', (tester) async {
      final handle = tester.ensureSemantics();
      final adapter = habitsServer();
      final app = await open(tester, adapter);
      await app.tap(_pill('Stretch'));
      for (final day in [
        'Monday',
        'Tuesday',
        'Wednesday',
        'Thursday',
        'Friday',
        'Saturday',
        'Sunday',
      ]) {
        await app.tap(_pill(day));
      }
      await app.tap(_button('Save'));
      expect(find.text('Pick at least one day.'), findsOneWidget);

      await app.tap(_pill('Every day'));
      await app.enter(find.byType(TextField).at(1), '');
      await app.tap(_button('Save'));
      expect(find.text('Give each time a name.'), findsOneWidget);
      expect(adapter.to('POST /api/habits'), isEmpty);
      handle.dispose();
    });

    testWidgets('Weekdays and Every day shortcuts set the day chips', (tester) async {
      final handle = tester.ensureSemantics();
      final adapter = habitsServer()
        ..on('POST /api/habits', StubResponse(201, {'habit': habitJson(9, 'Custom')}));
      final app = await open(tester, adapter);
      await app.tap(_pill('Weekdays'));
      await app.enter(find.byType(TextField).first, 'Read');
      await app.tap(_button('Save'));
      expect(app.body('POST /api/habits')['weekdays'], [1, 2, 3, 4, 5]);
      handle.dispose();
    });

    testWidgets('a custom habit takes a typed name, an icon and an extra time', (tester) async {
      final handle = tester.ensureSemantics();
      final adapter = habitsServer()
        ..on('POST /api/habits', StubResponse(201, {'habit': habitJson(9, 'Read')}));
      final app = await open(tester, adapter);
      await app.tap(_pill('Custom'));
      await app.enter(find.byType(TextField).first, 'Read');
      await app.tap(_pill('Open book'));
      await app.tap(_button('Add a time'));
      await app.enter(find.byType(TextField).last, 'Night');
      await app.tap(_button('Save'));
      final body = app.body('POST /api/habits');
      expect(body['name'], 'Read');
      expect(body['icon'], 'menu_book');
      expect(body['slots'], [
        {'label': 'Daily', 'time': null},
        {'label': 'Night', 'time': null},
      ]);
      handle.dispose();
    });

    testWidgets('a slot time comes from the presets sheet and can carry a reminder choice', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      final adapter = habitsServer()
        ..on('POST /api/habits', StubResponse(201, {'habit': habitJson(9, 'Stretch')}));
      final app = await open(tester, adapter);
      await app.tap(_pill('Stretch'));
      await app.tap(_pill('Set a time'));
      await app.tap(
        find.descendant(of: find.byType(TimePresets).first, matching: find.text('8:00 AM')),
      );
      expect(find.text('Remind me'), findsOneWidget);
      await app.tap(find.byType(Switch));
      await app.tap(_button('Save'));
      expect(app.body('POST /api/habits')['slots'], [
        {'label': 'Daily', 'time': '08:00'},
      ]);
      final muted = (await SharedPreferences.getInstance()).getStringList('mutedHabitSlots');
      expect(muted, ['9:0'], reason: 'the reminder choice is kept on this phone');
      handle.dispose();
    });

    testWidgets('a rejected save shows the server message and keeps the form', (tester) async {
      final handle = tester.ensureSemantics();
      final adapter = habitsServer()
        ..on('POST /api/habits', const StubResponse(422, {'error': 'at most 30 habits'}));
      final app = await open(tester, adapter);
      await app.tap(_pill('Floss'));
      await app.tap(_button('Save'));
      expect(find.text('at most 30 habits'), findsOneWidget);
      expect(find.text('New habit'), findsOneWidget);
      handle.dispose();
    });

    testWidgets('editing patches without a kind and shows the saved values', (tester) async {
      final huel = Habit.fromJson(allHabits()[1]);
      final adapter = habitsServer()
        ..on('PATCH /api/habits/2', StubResponse(200, {'habit': habitJson(2, 'Huel shake')}));
      final app = await open(tester, adapter, page: HabitEditorPage(habit: huel));
      expect(find.text('Edit habit'), findsOneWidget);
      expect(find.text('Marked'), findsNothing, reason: 'the kind cannot change');
      expect(fieldWith('Huel'), findsOneWidget);
      await app.enter(fieldWith('Huel'), 'Huel shake');
      await app.tap(_button('Save'));
      final body = app.body('PATCH /api/habits/2');
      expect(body['name'], 'Huel shake');
      expect(body.containsKey('kind'), isFalse);
      expect(body['weekdays'], [1, 2, 3, 4, 5]);
    });

    testWidgets('the form fits at text scale 2.0 with 44pt targets', (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = 2.0;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final handle = tester.ensureSemantics();
      final app = await open(tester, habitsServer());
      await app.tap(_pill('Brush teeth'));
      expect(tester.takeException(), isNull);
      for (final label in ['Monday', 'Open book', 'Every day', 'Brush teeth']) {
        final size = tester.getSize(_pill(label));
        expect(size.height, greaterThanOrEqualTo(44), reason: label);
        expect(size.width, greaterThanOrEqualTo(44), reason: label);
      }
      handle.dispose();
    });
  });

  group('list', () {
    testWidgets('shows each habit with its schedule and the count in order', (tester) async {
      await open(tester, habitsServer(), page: const HabitsPage());
      expect(find.text('Brush teeth'), findsOneWidget);
      expect(find.text('Every day · 7:30 AM, 10:00 PM · 25 gems'), findsOneWidget);
      expect(find.text('Weekdays · 12:00 PM · 25 gems'), findsOneWidget);
      expect(find.text('Every day · 8 a day · 25 gems'), findsOneWidget);
      expect(find.text('Every day · Once a day · 25 gems'), findsOneWidget);
    });

    testWidgets('an empty list says so', (tester) async {
      await open(tester, habitsServer(all: []), page: const HabitsPage());
      expect(find.text('No habits yet'), findsOneWidget);
    });

    testWidgets('pause sends the flag and dims the row', (tester) async {
      final handle = tester.ensureSemantics();
      final adapter = habitsServer()
        ..on(
          'PATCH /api/habits/2',
          StubResponse(200, {
            'habit': habitJson(2, 'Huel', paused: true, weekdays: [1, 2, 3, 4, 5]),
          }),
        );
      final app = await open(tester, adapter, page: const HabitsPage());
      await app.tap(find.bySemanticsLabel('More for Huel'));
      await app.tap(_button('Pause'));
      expect(app.body('PATCH /api/habits/2'), {'paused': true});
      expect(find.textContaining('Paused'), findsOneWidget);
      handle.dispose();
    });

    testWidgets('delete asks first and then removes the row', (tester) async {
      final handle = tester.ensureSemantics();
      final adapter = habitsServer()..on('DELETE /api/habits/3', const StubResponse(204));
      final app = await open(tester, adapter, page: const HabitsPage());
      await app.tap(find.bySemanticsLabel('More for Floss'));
      await app.tap(_button('Delete'));
      expect(find.text('Delete Floss?'), findsOneWidget);
      expect(adapter.to('DELETE /api/habits/3'), isEmpty, reason: 'not before the confirm');
      await app.tap(find.text('Delete').last);
      expect(adapter.to('DELETE /api/habits/3'), hasLength(1));
      expect(find.text('Floss'), findsNothing);
      handle.dispose();
    });

    testWidgets('cancelling the confirm deletes nothing', (tester) async {
      final handle = tester.ensureSemantics();
      final adapter = habitsServer();
      final app = await open(tester, adapter, page: const HabitsPage());
      await app.tap(find.bySemanticsLabel('More for Floss'));
      await app.tap(_button('Delete'));
      await app.tap(find.text('Cancel'));
      expect(adapter.to('DELETE /api/habits/3'), isEmpty);
      expect(find.text('Floss'), findsOneWidget);
      handle.dispose();
    });

    testWidgets('dragging a handle reorders and sends every id', (tester) async {
      final adapter = habitsServer()
        ..on(
          'PUT /api/habits/order',
          StubResponse(200, {
            'habits': [allHabits()[1], allHabits()[0], allHabits()[2], allHabits()[3]],
          }),
        );
      final app = await open(tester, adapter, page: const HabitsPage());
      final handles = find.byIcon(Icons.drag_handle_rounded);
      final gesture = await tester.startGesture(tester.getCenter(handles.at(1)));
      for (var i = 0; i < 12; i++) {
        await gesture.moveBy(const Offset(0, -10));
        await tester.pump(const Duration(milliseconds: 16));
      }
      await gesture.up();
      await app.settle(20);
      expect(app.body('PUT /api/habits/order')['ids'], [2, 1, 3, 4]);
      final huel = tester.getTopLeft(find.text('Huel')).dy;
      final brush = tester.getTopLeft(find.text('Brush teeth')).dy;
      expect(huel, lessThan(brush));
    });

    testWidgets('the container keeps the order the server answered', (tester) async {
      final adapter = habitsServer();
      final app = await open(tester, adapter, page: const HabitsPage());
      final list = app.container.read(habitsProvider).value!.data.habits;
      expect(list.map((h) => h.id), [1, 2, 3, 4]);
    });

    testWidgets('the add button opens the editor', (tester) async {
      final app = await open(tester, habitsServer(), page: const HabitsPage());
      await app.tap(_button('Add a habit'));
      expect(find.text('New habit'), findsOneWidget);
    });

    testWidgets('rows are at least 44pt wide and tall to tap at text scale 2.0', (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = 2.0;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await open(tester, habitsServer(), page: const HabitsPage());
      expect(tester.takeException(), isNull);
      for (final icon in [Icons.more_horiz_rounded, Icons.drag_handle_rounded]) {
        final size = tester.getSize(
          find.ancestor(of: find.byIcon(icon).first, matching: find.byType(SizedBox)).first,
        );
        expect(size.shortestSide, greaterThanOrEqualTo(44));
      }
    });
  });
}
