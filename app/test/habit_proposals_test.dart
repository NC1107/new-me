import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:newme/features/board/board_screen.dart';
import 'package:newme/features/habits/habit_editor_page.dart';
import 'package:newme/features/habits/habits_page.dart';
import 'package:newme/api/habit_models.dart';
import 'package:newme/widgets/chunky_button.dart';
import 'package:newme/widgets/mascot.dart';

import 'fixtures.dart';
import 'habit_fixtures.dart';
import 'test_support.dart';

Finder _button(String label) =>
    find.byWidgetPredicate((w) => w is ChunkyButton && w.label == label);

Map<String, dynamic> _proposal({int id = 7, int points = 6, int? minutes = 2}) => {
  'habitId': id,
  'name': 'Brush teeth',
  'icon': 'brush',
  'points': points,
  'minutes': minutes,
  'currentPoints': 0,
  'at': '2026-11-02T12:00:00Z',
};

StubAdapter _usServer(List<Map<String, dynamic>> proposals) => fullServer()
  ..on(
    'GET /api/board',
    StubResponse(200, board([boardUser(1, 'Ana', 'amber'), boardUser(2, 'Sam', 'violet')])),
  )
  ..on('GET /api/habits/proposals', StubResponse(200, {'from': 'Sam', 'proposals': proposals}))
  ..on('POST /api/habits/7/approve', StubResponse(200, {'habit': habitJson(7, 'Brush teeth')}))
  ..on('POST /api/habits/7/decline', StubResponse(200, {'habit': habitJson(7, 'Brush teeth')}));

void main() {
  setUp(() {
    FakeStorage().install();
    Mascot.idleMotion = false;
  });

  group('models', () {
    test('minutes pay 3 gems each, capped at 100', () {
      expect([for (final m in kHabitMinuteChoices) habitGems(m)], [0, 3, 6, 15, 30, 45, 60, 90]);
      expect(habitGems(40), 100);
    });

    test('a habit reads its minutes and pending proposal', () {
      final h = Habit.fromJson(
        habitJson(1, 'Brush', points: 0, proposedPoints: 6, proposedMinutes: 2),
      );
      expect(h.pending, isTrue);
      expect(h.proposedPoints, 6);
      expect(h.minutes, isNull);
      expect(Habit.fromJson(habitJson(2, 'Floss', points: 25)).pending, isFalse);
    });
  });

  group('Us card', () {
    testWidgets('names the partner, the habit, its gems and minutes', (tester) async {
      final app = TestApp(tester, _usServer([_proposal()]));
      await app.pump(const BoardScreen());
      expect(find.text('Sam wants Brush teeth worth 6 gems (2 min)'), findsOneWidget);
      expect(_button('Approve'), findsOneWidget);
      expect(_button('Decline'), findsOneWidget);
      for (final label in ['Approve', 'Decline']) {
        expect(tester.getSize(_button(label)).height, greaterThanOrEqualTo(44));
      }
    });

    testWidgets('approve posts the answer and the row goes away', (tester) async {
      final adapter = _usServer([_proposal()]);
      final app = TestApp(tester, adapter);
      await app.pump(const BoardScreen());
      adapter.on(
        'GET /api/habits/proposals',
        const StubResponse(200, {'from': 'Sam', 'proposals': []}),
      );
      await app.tap(_button('Approve'));
      expect(adapter.to('POST /api/habits/7/approve'), hasLength(1));
      expect(find.textContaining('wants Brush teeth'), findsNothing);
    });

    testWidgets('decline posts the other answer', (tester) async {
      final adapter = _usServer([_proposal(minutes: null, points: 0)]);
      final app = TestApp(tester, adapter);
      await app.pump(const BoardScreen());
      expect(find.text('Sam wants Brush teeth worth 0 gems'), findsOneWidget);
      await app.tap(_button('Decline'));
      expect(adapter.to('POST /api/habits/7/decline'), hasLength(1));
      expect(adapter.to('POST /api/habits/7/approve'), isEmpty);
      expect(find.textContaining('wants Brush teeth'), findsNothing);
    });

    testWidgets('nothing pending shows no card', (tester) async {
      final app = TestApp(tester, _usServer([]));
      await app.pump(const BoardScreen());
      expect(find.textContaining('wants'), findsNothing);
      expect(_button('Approve'), findsNothing);
    });
  });

  group('editor and list', () {
    Future<TestApp> open(WidgetTester tester, StubAdapter adapter, Widget page) async {
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

    testWidgets('picking minutes shows the gems and saves minutes, not points', (tester) async {
      final handle = tester.ensureSemantics();
      final adapter = habitsServer()
        ..on('POST /api/habits', StubResponse(201, {'habit': habitJson(9, 'Brush teeth')}));
      final app = await open(tester, adapter, const HabitEditorPage());
      await app.tap(find.bySemanticsLabel('Brush teeth'));
      expect(find.text('How long it takes'), findsOneWidget);
      await app.tap(find.bySemanticsLabel('5 min'));
      expect(find.text('15 gems'), findsOneWidget);
      await app.tap(_button('Save'));
      final body = app.body('POST /api/habits');
      expect(body['minutes'], 5);
      expect(body.containsKey('points'), isFalse);
      handle.dispose();
    });

    testWidgets('Only track sends null minutes', (tester) async {
      final handle = tester.ensureSemantics();
      final adapter = habitsServer()
        ..on('POST /api/habits', StubResponse(201, {'habit': habitJson(9, 'Brush teeth')}));
      final app = await open(tester, adapter, const HabitEditorPage());
      await app.tap(find.bySemanticsLabel('Brush teeth'));
      await app.tap(find.bySemanticsLabel('Only track'));
      expect(find.text('0 gems'), findsOneWidget);
      await app.tap(_button('Save'));
      final body = app.body('POST /api/habits');
      expect(body.containsKey('minutes'), isTrue);
      expect(body['minutes'], isNull);
      handle.dispose();
    });

    testWidgets('a pending habit says who it waits for', (tester) async {
      final adapter = habitsServer()
        ..on(
          'GET /api/board',
          StubResponse(200, board([boardUser(1, 'Ana', 'amber'), boardUser(2, 'Sam', 'violet')])),
        );
      final app = await open(
        tester,
        adapter,
        HabitEditorPage(
          habit: Habit.fromJson(
            habitJson(1, 'Brush teeth', points: 0, proposedPoints: 90, proposedMinutes: 30),
          ),
        ),
      );
      await app.settle();
      expect(find.text('Waiting for Sam to approve 90 gems'), findsOneWidget);
    });

    testWidgets('the list shows gems and a pending marker', (tester) async {
      final adapter = habitsServer(
        all: [
          habitJson(1, 'Brush teeth', points: 0, proposedPoints: 6, proposedMinutes: 2),
          habitJson(2, 'Floss', points: 30, minutes: 10),
        ],
      );
      await open(tester, adapter, const HabitsPage());
      expect(find.text('Every day · Once a day · 0 gems (6 pending)'), findsOneWidget);
      expect(find.text('Every day · Once a day · 30 gems'), findsOneWidget);
    });
  });
}
