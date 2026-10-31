import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:newme/api/shared_habit_models.dart';
import 'package:newme/features/board/board_screen.dart';
import 'package:newme/features/shared_habits/shared_habit_text.dart';
import 'package:newme/features/today/today_screen.dart';
import 'package:newme/widgets/chunky_button.dart';
import 'package:newme/widgets/mascot.dart';

import 'fixtures.dart';
import 'habit_fixtures.dart';
import 'test_support.dart';

Map<String, dynamic> _chore(
  int id,
  String name, {
  String state = 'today',
  int days = 0,
  bool doneToday = false,
  bool doneByMe = false,
  Map<String, dynamic>? last,
  Map<String, dynamic> schedule = const {'kind': 'weekly', 'weekdays': [], 'everyDays': null},
}) => {
  'id': id,
  'name': name,
  'icon': 'local_laundry_service',
  'schedule': schedule,
  'last': last,
  'state': state,
  'dueOn': '2026-10-26',
  'daysFromToday': days,
  'doneToday': doneToday,
  'doneByMe': doneByMe,
  'gems': 25,
};

StubAdapter _server(List<Map<String, dynamic>> chores) => habitsServer()
  ..on(
    'GET /api/board',
    StubResponse(200, board([boardUser(1, 'Ana', 'amber'), boardUser(2, 'Sam', 'violet')])),
  )
  ..on('GET /api/shared-habits', StubResponse(200, {'habits': chores}));

Finder _button(String label) =>
    find.byWidgetPredicate((w) => w is ChunkyButton && w.label == label);

Finder _sem(String label) =>
    find.byWidgetPredicate((w) => w is Semantics && w.properties.label == label);

void main() {
  setUp(() {
    FakeStorage().install();
    Mascot.idleMotion = false;
  });

  group('models and words', () {
    test('a chore reads its schedule, who did it last and how late it is', () {
      final h = SharedHabit.fromJson(
        _chore(
          3,
          'Vacuum',
          state: 'overdue',
          days: -2,
          last: {'userId': 2, 'name': 'Sam', 'at': '2026-10-24T12:00:00Z'},
        ),
      );
      expect(h.overdue, isTrue);
      expect(h.last?.name, 'Sam');
      expect(sharedDueLabel(h), 'Overdue by 2 days');
      expect(sharedScheduleLabel(h.schedule), 'Every week');
      expect(sharedLastLabel(h, 1, DateTime.utc(2026, 10, 26, 12)), 'Sam, 2 d ago');
      expect(sharedLastLabel(h, 2, DateTime.utc(2026, 10, 26, 12)), 'You, 2 d ago');
    });

    test('the schedule words and validation follow the kind', () {
      const days = SharedSchedule(kind: SharedKind.weekdays, weekdays: [1, 3, 5]);
      expect(sharedScheduleLabel(days), 'Mon, Wed, Fri');
      expect(days.valid, isTrue);
      expect(const SharedSchedule(kind: SharedKind.weekdays).valid, isFalse);
      const every = SharedSchedule(kind: SharedKind.everyN, everyDays: 3);
      expect(sharedScheduleLabel(every), 'Every 3 days');
      expect(every.toJson(), {'kind': 'every_n', 'everyDays': 3});
      expect(const SharedSchedule(kind: SharedKind.everyN, everyDays: 1).valid, isFalse);
    });
  });

  group('Us section', () {
    testWidgets('lists what is due first and says who did each last', (tester) async {
      final app = TestApp(
        tester,
        _server([
          _chore(
            1,
            'Do the laundry',
            state: 'overdue',
            days: -2,
            last: {'userId': 99, 'name': 'Sam', 'at': '2026-10-25T00:00:00Z'},
          ),
          _chore(2, 'Water the plants', state: 'upcoming', days: 2),
        ]),
        surfaceHeight: 2400,
      );
      await app.pump(const BoardScreen());
      expect(find.text('Home'), findsOneWidget);
      expect(find.text('Do the laundry'), findsOneWidget);
      expect(find.text('Overdue by 2 days'), findsOneWidget);
      expect(find.textContaining('Every week · Sam, '), findsOneWidget);
      expect(find.text('Due in 2 days'), findsOneWidget);
      expect(find.text('DUE NOW'), findsOneWidget);
      expect(find.text('COMING UP'), findsOneWidget);
    });

    testWidgets('one tap marks it done and posts', (tester) async {
      final adapter = _server([_chore(1, 'Do the laundry')])
        ..on(
          'POST /api/shared-habits/1/done',
          StubResponse(200, {'habit': _chore(1, 'Do the laundry'), 'gemsEarned': 25}),
        );
      final app = TestApp(tester, adapter, surfaceHeight: 2400);
      await app.pump(const BoardScreen());
      adapter.on(
        'GET /api/shared-habits',
        StubResponse(200, {
          'habits': [
            _chore(
              1,
              'Do the laundry',
              state: 'upcoming',
              days: 7,
              doneToday: true,
              doneByMe: true,
              last: {'userId': 1, 'name': 'Ana', 'at': '2026-10-26T12:00:00Z'},
            ),
          ],
        }),
      );
      await app.tap(_sem('Mark Do the laundry done'));
      expect(adapter.to('POST /api/shared-habits/1/done'), hasLength(1));
      expect(find.text('Done today'), findsOneWidget);
      expect(_sem('Undo Do the laundry'), findsOneWidget);
    });

    testWidgets('a chore the partner did today cannot be marked again', (tester) async {
      final adapter = _server([
        _chore(
          1,
          'Do the laundry',
          state: 'upcoming',
          days: 7,
          doneToday: true,
          last: {'userId': 99, 'name': 'Sam', 'at': '2026-10-26T12:00:00Z'},
        ),
      ]);
      final app = TestApp(tester, adapter, surfaceHeight: 2400);
      await app.pump(const BoardScreen());
      await app.tap(_sem('Do the laundry done by Sam'));
      expect(adapter.requests.where((r) => r.method != 'GET'), isEmpty);
    });

    testWidgets('a template fills the sheet and saves the chore', (tester) async {
      final adapter = _server([])
        ..on('POST /api/shared-habits', StubResponse(201, {'habit': _chore(9, 'Vacuum')}));
      final app = TestApp(tester, adapter, surfaceHeight: 2400);
      await app.pump(const BoardScreen());
      await app.tap(_sem('Add your first chore'));
      expect(find.text('Quick add'), findsOneWidget);
      await app.tap(_sem('Vacuum'));
      await app.tap(_button('Add chore'));
      expect(app.body('POST /api/shared-habits'), {
        'name': 'Vacuum',
        'icon': 'cleaning_services',
        'schedule': {'kind': 'weekly'},
      });
    });

    testWidgets('deleting asks first and then removes it for both', (tester) async {
      final adapter = _server([_chore(1, 'Do the laundry')])
        ..on('DELETE /api/shared-habits/1', const StubResponse(204, ''));
      final app = TestApp(tester, adapter, surfaceHeight: 2400);
      await app.pump(const BoardScreen());
      await app.tap(find.text('Do the laundry'));
      await app.tap(_button('Delete chore'));
      expect(find.text('Delete Do the laundry?'), findsOneWidget);
      expect(adapter.to('DELETE /api/shared-habits/1'), isEmpty);
      await app.tap(find.text('Delete'));
      expect(adapter.to('DELETE /api/shared-habits/1'), hasLength(1));
    });
  });

  group('Today strip', () {
    testWidgets('shows a due chore with the shared marker and marks it', (tester) async {
      final adapter = _server([
        _chore(1, 'Do the laundry'),
        _chore(2, 'Water the plants', state: 'upcoming', days: 2),
      ])..on('POST /api/shared-habits/1/done', StubResponse(200, {'habit': _chore(1, 'x')}));
      final app = TestApp(tester, adapter, surfaceHeight: 2800);
      await app.pump(const TodayScreen());
      expect(find.byKey(const ValueKey('shared1')), findsOneWidget);
      expect(find.byKey(const ValueKey('shared2')), findsNothing);
      expect(find.byIcon(Icons.people_alt_rounded), findsOneWidget);
      await app.tap(find.byKey(const ValueKey('shared1')));
      expect(adapter.to('POST /api/shared-habits/1/done'), hasLength(1));
    });

    testWidgets('a chore alone fills the strip when there are no personal habits', (tester) async {
      final adapter = habitsServer(due: [])
        ..on(
          'GET /api/shared-habits',
          StubResponse(200, {
            'habits': [_chore(1, 'Dishes')],
          }),
        );
      final app = TestApp(tester, adapter, surfaceHeight: 2800);
      await app.pump(const TodayScreen());
      expect(find.byKey(const ValueKey('shared1')), findsOneWidget);
      expect(find.text('Add your first habit'), findsNothing);
    });
  });
}
