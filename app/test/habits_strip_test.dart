import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:newme/features/habits/habit_chip.dart';
import 'package:newme/features/today/today_screen.dart';
import 'package:newme/state/today.dart';
import 'package:newme/widgets/chunky_button.dart';
import 'package:newme/widgets/mascot.dart';

import 'fixtures.dart';
import 'habit_fixtures.dart';
import 'test_support.dart';

const _markBrushMorning = 'PUT /api/habits/1/marks/2026-10-26';

List<Map<String, dynamic>> _afterBrushMorning() => [
  checkState(1, 'Brush teeth', 'brush', [
    stateSlot(0, 'Morning', '07:30', done: true),
    stateSlot(1, 'Evening', '22:00'),
  ]),
  ...dueHabits().skip(1),
];

Finder _button(String label) =>
    find.byWidgetPredicate((w) => w is ChunkyButton && w.label == label);

Finder _chip(String key) => find.byKey(ValueKey(key));

/// The chip's own rendering, which is what the person sees and taps.
Finder _chipBox(String key) => find.descendant(of: _chip(key), matching: find.byType(HabitChip));

Finder _check(String key) =>
    find.descendant(of: _chip(key), matching: find.byIcon(Icons.check_rounded));

void main() {
  setUp(() {
    FakeStorage().install();
    Mascot.idleMotion = false;
  });

  Future<TestApp> open(WidgetTester tester, StubAdapter adapter) async {
    final app = TestApp(tester, adapter, surfaceHeight: 2800);
    await app.pump(const TodayScreen());
    return app;
  }

  testWidgets('shows only today due slots, by time, untimed last', (tester) async {
    await open(tester, habitsServer());
    final keys = ['h1s0', 'h2s0', 'h1s1', 'h3s0', 'h4'];
    final order = [...keys]
      ..sort((a, b) {
        final pa = tester.getTopLeft(_chip(a)), pb = tester.getTopLeft(_chip(b));
        return pa.dy != pb.dy ? pa.dy.compareTo(pb.dy) : pa.dx.compareTo(pb.dx);
      });
    expect(order, keys, reason: '07:30, 12:00, 22:00, then the untimed floss and water');
    expect(find.text('Habits'), findsOneWidget);
    expect(find.text('0 of 5'), findsOneWidget);
    expect(find.text('Morning · 7:30 AM'), findsOneWidget);
    expect(find.text('0/8'), findsOneWidget);
  });

  testWidgets('a slot past its time and not done is marked overdue, a later one is not', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await open(tester, habitsServer());
    expect(
      find.bySemanticsLabel(RegExp(r'^Brush teeth, Morning · 7:30 AM, overdue$')),
      findsOneWidget,
    );
    expect(find.bySemanticsLabel(RegExp(r'^Huel, 12:00 PM, overdue$')), findsOneWidget);
    expect(
      find.bySemanticsLabel(RegExp(r'^Brush teeth, Evening · 10:00 PM, not done$')),
      findsOneWidget,
    );
    expect(find.bySemanticsLabel(RegExp(r'^Floss, not done$')), findsOneWidget);
    handle.dispose();
  });

  testWidgets('one tap checks the slot before the server answers and applies the points', (
    tester,
  ) async {
    final answer = Completer<StubResponse>();
    final adapter = habitsServer()..routes[_markBrushMorning] = (_) => answer.future;
    final app = await open(tester, adapter);
    expect(_check('h1s0'), findsNothing);
    expect(find.text('150'), findsOneWidget);

    await tester.tap(_chipBox('h1s0'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(_check('h1s0'), findsOneWidget, reason: 'checked while the request is still out');
    expect(find.text('1 of 5'), findsOneWidget);
    expect(adapter.to(_markBrushMorning).single.data, {'slot': 0, 'done': true});

    answer.complete(StubResponse(200, markResponse(_afterBrushMorning(), points: 155)));
    await app.settle();
    expect(_check('h1s0'), findsOneWidget);
    expect(find.text('155'), findsOneWidget, reason: 'the day points come from the answer');
    expect(app.container.read(todayProvider).value!.data.day.points, 155);
  });

  testWidgets('tapping a done slot undoes it', (tester) async {
    final due = _afterBrushMorning();
    final adapter = habitsServer(due: due)
      ..on(_markBrushMorning, StubResponse(200, markResponse(dueHabits(), points: 150)));
    final app = await open(tester, adapter);
    expect(_check('h1s0'), findsOneWidget);
    await tester.tap(_chipBox('h1s0'));
    await app.settle();
    expect(adapter.to(_markBrushMorning).single.data, {'slot': 0, 'done': false});
    expect(_check('h1s0'), findsNothing);
  });

  testWidgets('a refused mark puts the chip back and says so', (tester) async {
    final adapter = habitsServer()
      ..on(_markBrushMorning, const StubResponse(422, {'error': 'that habit is paused'}));
    final app = await open(tester, adapter);
    await tester.tap(_chipBox('h1s0'));
    await app.settle();
    expect(_check('h1s0'), findsNothing);
    expect(find.text('Could not save Brush teeth. Try again.'), findsOneWidget);
    expect(find.text('0 of 5'), findsOneWidget);
  });

  testWidgets('an unreachable server reverts the same way', (tester) async {
    final adapter = habitsServer()..on(_markBrushMorning, const StubResponse.unreachable());
    final app = await open(tester, adapter);
    await tester.tap(_chipBox('h1s0'));
    await app.settle();
    expect(_check('h1s0'), findsNothing);
    expect(find.textContaining('Could not save'), findsOneWidget);
  });

  testWidgets('a count habit adds one per tap and shows the number', (tester) async {
    final adapter = habitsServer()
      ..on(
        'PUT /api/habits/4/marks/2026-10-26',
        StubResponse(200, markResponse([...dueHabits().take(3), countState(4, 'Water', count: 1)])),
      );
    final app = await open(tester, adapter);
    expect(find.text('0/8'), findsOneWidget);
    await tester.tap(_chipBox('h4'));
    await app.settle();
    expect(adapter.to('PUT /api/habits/4/marks/2026-10-26').single.data, {'count': 1});
    expect(find.text('1/8'), findsOneWidget);
  });

  testWidgets('reaching the target turns the count chip into a check', (tester) async {
    final due = [...dueHabits().take(3), countState(4, 'Water', count: 7)];
    final adapter = habitsServer(due: due)
      ..on(
        'PUT /api/habits/4/marks/2026-10-26',
        StubResponse(200, markResponse([...dueHabits().take(3), countState(4, 'Water', count: 8)])),
      );
    final app = await open(tester, adapter);
    expect(_check('h4'), findsNothing);
    await tester.tap(_chipBox('h4'));
    await app.settle();
    expect(_check('h4'), findsOneWidget);
    expect(find.text('8/8'), findsOneWidget);
  });

  testWidgets('long press on a count chip sets the number from a tiny sheet', (tester) async {
    final adapter = habitsServer()
      ..on(
        'PUT /api/habits/4/marks/2026-10-26',
        StubResponse(200, markResponse([...dueHabits().take(3), countState(4, 'Water', count: 2)])),
      );
    final app = await open(tester, adapter);
    await tester.longPress(_chipBox('h4'));
    await app.settle();
    expect(find.text('0 / 8'), findsOneWidget);
    final plus = find.descendant(
      of: find.byType(BottomSheet),
      matching: find.byIcon(Icons.add_rounded),
    );
    await app.tap(plus);
    await app.tap(plus);
    expect(find.text('2 / 8'), findsOneWidget);
    await app.tap(_button('Save'));
    expect(adapter.to('PUT /api/habits/4/marks/2026-10-26').single.data, {'count': 2});
    expect(find.text('2/8'), findsOneWidget);
  });

  testWidgets('no habits at all offers the first one', (tester) async {
    await open(tester, habitsServer(due: [], all: []));
    expect(find.text('Add your first habit'), findsOneWidget);
    expect(find.text('Habits'), findsNothing);
  });

  testWidgets('habits that are simply not due today show nothing, not the empty card', (
    tester,
  ) async {
    await open(tester, habitsServer(due: []));
    expect(find.text('Add your first habit'), findsNothing);
    expect(find.text('Habits'), findsNothing);
  });

  testWidgets('Yesterday opens while the grace window is open and marks that day', (tester) async {
    final yesterday = richTodayJson(stepsEverSynced: true)
      ..['date'] = '2026-10-25'
      ..['habits'] = dueHabits();
    final adapter = habitsServer()
      ..on(
        'GET /api/today',
        StubResponse(
          200,
          (richTodayJson(stepsEverSynced: true)..['habits'] = dueHabits())
            ..['backdateUntil'] = '2026-10-26T15:00:00Z',
        ),
      )
      ..on(
        'PUT /api/habits/1/marks/2026-10-25',
        StubResponse(200, markResponse(_afterBrushMorning(), points: 155)),
      );
    adapter.routes['GET /api/today'] = (options) => options.queryParameters['date'] == '2026-10-25'
        ? StubResponse(200, yesterday)
        : StubResponse(
            200,
            (richTodayJson(stepsEverSynced: true)..['habits'] = dueHabits())
              ..['backdateUntil'] = '2026-10-26T15:00:00Z',
          );
    final app = await open(tester, adapter);
    await app.tap(find.text('Yesterday'));
    expect(find.text('Nothing was due.'), findsNothing);
    final sheetChip = find.descendant(
      of: find.byKey(const ValueKey('h1s0')).last,
      matching: find.byType(HabitChip),
    );
    await tester.tap(sheetChip);
    await app.settle();
    expect(adapter.to('PUT /api/habits/1/marks/2026-10-25').single.data, {'slot': 0, 'done': true});
  });

  testWidgets('no Yesterday once the grace window has closed', (tester) async {
    final today = richTodayJson(stepsEverSynced: true)
      ..['habits'] = dueHabits()
      ..['backdateUntil'] = null;
    await open(tester, habitsServer()..on('GET /api/today', StubResponse(200, today)));
    expect(find.text('Yesterday'), findsNothing);
  });

  testWidgets('chips are at least 44 tall and the strip fits at text scale 2.0', (tester) async {
    tester.platformDispatcher.textScaleFactorTestValue = 2.0;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await open(tester, habitsServer());
    for (final key in ['h1s0', 'h2s0', 'h1s1', 'h3s0', 'h4']) {
      final size = tester.getSize(_chipBox(key));
      expect(size.height, greaterThanOrEqualTo(44), reason: key);
      expect(size.width, lessThanOrEqualTo(390 - 40), reason: key);
    }
    expect(tester.takeException(), isNull);
  });
}
