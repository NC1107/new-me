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
  int gems = 25,
  int? proposedWorth,
  int? proposedBy,
  String proposedByName = '',
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
  'gems': gems,
  'proposedWorth': proposedWorth,
  'proposedBy': proposedBy,
  'proposedByName': proposedByName,
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

    test('a split gives the odd gem to whoever marked it and always adds up', () {
      for (final worth in [1, 10, 25, 99, 100]) {
        final together = sharedCredit(SharedBy.together, worth);
        expect(together.mine + together.theirs, worth);
        expect(together.mine - together.theirs, worth.isOdd ? 1 : 0);
      }
      expect(sharedCredit(SharedBy.self, 25), (mine: 25, theirs: 0));
      expect(sharedCredit(SharedBy.partner, 25), (mine: 0, theirs: 25));
    });

    test('the worth reads as pending until it is agreed', () {
      final agreed = SharedHabit.fromJson(_chore(1, 'Laundry'));
      final pending = SharedHabit.fromJson(
        _chore(1, 'Laundry', proposedWorth: 40, proposedBy: 2, proposedByName: 'Sam'),
      );
      expect(sharedWorthLabel(agreed), '25 gems');
      expect(sharedWorthLabel(pending), '25 gems');
      expect(sharedPendingLabel(pending, 2, 'Sam'), '40 gems waiting on Sam');
      expect(sharedPendingLabel(pending, 1, 'Sam'), isNull);
      expect(sharedPendingLabel(agreed, 1, 'Sam'), isNull);
      expect(pending.proposalForMe(1), isTrue);
      expect(pending.proposalForMe(2), isFalse);
      expect(agreed.proposalForMe(1), isFalse);
    });

    test('who did it reads from the doers, the viewer first', () {
      final h = SharedHabit.fromJson(
        _chore(
          1,
          'Laundry',
          last: {
            'userId': 2,
            'name': 'Sam',
            'at': '2026-10-26T09:00:00Z',
            'together': true,
            'doers': [
              {'userId': 2, 'name': 'Sam', 'gems': 13},
              {'userId': 1, 'name': 'Ana', 'gems': 12},
            ],
          },
        ),
      );
      final now = DateTime.utc(2026, 10, 26, 12);
      expect(sharedLastLabel(h, 1, now), 'You 12 + Sam 13 gems, 3 h ago');
      expect(sharedLastLabel(h, 2, now), 'You 13 + Ana 12 gems, 3 h ago');
      expect(sharedDoneByLabel(h, 1), 'Done together');
      final alone = SharedHabit.fromJson(
        _chore(
          1,
          'Laundry',
          last: {
            'userId': 2,
            'name': 'Sam',
            'at': '2026-10-26T09:00:00Z',
            'doers': [
              {'userId': 1, 'name': 'Ana', 'gems': 25},
            ],
          },
        ),
      );
      expect(sharedDoneByLabel(alone, 1), 'Done by you');
      expect(sharedDoneByLabel(alone, 2), 'Done by Ana');
      expect(sharedLastLabel(alone, 2, now), 'Ana, 25 gems, 3 h ago');
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
      expect(find.text('Every week · 25 gems'), findsNWidgets(2));
      expect(find.textContaining('Sam, '), findsOneWidget);
      expect(find.text('Due in 2 days'), findsOneWidget);
      expect(find.text('DUE NOW'), findsOneWidget);
      expect(find.text('COMING UP'), findsOneWidget);
    });

    testWidgets('marking it done asks who did it, and Me posts self', (tester) async {
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
      expect(find.text('Who did Do the laundry?'), findsOneWidget);
      expect(adapter.to('POST /api/shared-habits/1/done'), isEmpty);
      await app.tap(_sem('Me, You earn 25 gems'));
      expect(app.body('POST /api/shared-habits/1/done'), {'by': 'self'});
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

  group('who did it', () {
    testWidgets('the sheet offers me, the partner and together with what each earns', (
      tester,
    ) async {
      final adapter = _server([_chore(1, 'Do the laundry', gems: 25)])
        ..on(
          'POST /api/shared-habits/1/done',
          StubResponse(200, {'habit': _chore(1, 'Do the laundry'), 'gemsEarned': 13}),
        );
      final app = TestApp(tester, adapter, surfaceHeight: 2400);
      await app.pump(const BoardScreen());
      await app.tap(_sem('Mark Do the laundry done'));
      expect(_sem('Me, You earn 25 gems'), findsOneWidget);
      expect(_sem('Sam, Sam earns 25 gems'), findsOneWidget);
      expect(_sem('Together, 13 for you, 12 for Sam'), findsOneWidget);
      await app.tap(_sem('Together, 13 for you, 12 for Sam'));
      expect(app.body('POST /api/shared-habits/1/done'), {'by': 'together'});
    });

    testWidgets('marking it for the partner posts partner', (tester) async {
      final adapter = _server([_chore(1, 'Do the laundry')])
        ..on(
          'POST /api/shared-habits/1/done',
          StubResponse(200, {'habit': _chore(1, 'Do the laundry')}),
        );
      final app = TestApp(tester, adapter, surfaceHeight: 2400);
      await app.pump(const BoardScreen());
      await app.tap(_sem('Mark Do the laundry done'));
      await app.tap(_sem('Sam, Sam earns 25 gems'));
      expect(app.body('POST /api/shared-habits/1/done'), {'by': 'partner'});
    });

    testWidgets('dismissing the sheet marks nothing', (tester) async {
      final adapter = _server([_chore(1, 'Do the laundry')]);
      final app = TestApp(tester, adapter, surfaceHeight: 2400);
      await app.pump(const BoardScreen());
      await app.tap(_sem('Mark Do the laundry done'));
      await tester.tapAt(const Offset(20, 20));
      await tester.pumpAndSettle();
      expect(adapter.requests.where((r) => r.method != 'GET'), isEmpty);
    });

    testWidgets('a chore done together shows each person and what they got', (tester) async {
      final app = TestApp(
        tester,
        _server([
          _chore(
            1,
            'Do the laundry',
            state: 'upcoming',
            days: 7,
            doneToday: true,
            doneByMe: true,
            last: {
              'userId': 2,
              'name': 'Sam',
              'at': '2026-10-26T12:00:00Z',
              'together': true,
              'doers': [
                {'userId': 2, 'name': 'Sam', 'gems': 13},
                {'userId': 1, 'name': 'Ana', 'gems': 12},
              ],
            },
          ),
        ]),
        surfaceHeight: 2400,
      );
      await app.pump(const BoardScreen());
      expect(find.text('Done together'), findsOneWidget);
      expect(find.textContaining('You 13 + Ana 12 gems'), findsOneWidget);
    });
  });

  group('worth', () {
    testWidgets('a pending worth is shown beside the agreed one', (tester) async {
      final app = TestApp(
        tester,
        _server([_chore(1, 'Laundry', proposedWorth: 40, proposedBy: 2, proposedByName: 'Sam')]),
        surfaceHeight: 2400,
      );
      await app.pump(const BoardScreen());
      expect(find.text('Every week · 25 gems'), findsOneWidget);
      expect(find.text('40 gems waiting on Sam'), findsOneWidget);
    });

    testWidgets('the partner agrees from the row', (tester) async {
      final adapter =
          _server([_chore(1, 'Laundry', proposedWorth: 40, proposedBy: 1, proposedByName: 'Ana')])
            ..on(
              'POST /api/shared-habits/1/worth/accept',
              StubResponse(200, {'habit': _chore(1, 'Laundry', gems: 40)}),
            );
      final app = TestApp(tester, adapter, surfaceHeight: 2400);
      await app.pump(const BoardScreen());
      expect(find.text('Ana suggests 40 gems'), findsOneWidget);
      expect(find.text('Agree to 40 gems'), findsOneWidget);
      adapter.on(
        'GET /api/shared-habits',
        StubResponse(200, {
          'habits': [_chore(1, 'Laundry', gems: 40)],
        }),
      );
      await app.tap(find.text('Agree to 40 gems'));
      expect(adapter.to('POST /api/shared-habits/1/worth/accept'), hasLength(1));
      expect(find.text('Every week · 40 gems'), findsOneWidget);
    });

    testWidgets('my own suggestion has no agree button', (tester) async {
      final app = TestApp(
        tester,
        _server([_chore(1, 'Laundry', proposedWorth: 40, proposedBy: 2, proposedByName: 'Sam')]),
        surfaceHeight: 2400,
      );
      await app.pump(const BoardScreen());
      expect(find.textContaining('Agree to'), findsNothing);
    });

    testWidgets('a new chore proposes the picked worth', (tester) async {
      final adapter = _server([])
        ..on('POST /api/shared-habits', StubResponse(201, {'habit': _chore(9, 'Vacuum')}));
      final app = TestApp(tester, adapter, surfaceHeight: 2400);
      await app.pump(const BoardScreen());
      await app.tap(_sem('Add your first chore'));
      await app.tap(_sem('Vacuum'));
      await app.tap(_sem('50 gems'));
      expect(find.textContaining('You suggest 50 gems. It pays 25 until Sam agrees.'), findsOne);
      await app.tap(_button('Add chore'));
      expect(app.body('POST /api/shared-habits'), {
        'name': 'Vacuum',
        'icon': 'cleaning_services',
        'schedule': {'kind': 'weekly'},
        'worth': 50,
      });
    });

    testWidgets('an untouched worth is not sent, and a counter is', (tester) async {
      final adapter = _server([
        _chore(1, 'Laundry', proposedWorth: 40, proposedBy: 1, proposedByName: 'Ana'),
      ])..on('PATCH /api/shared-habits/1', StubResponse(200, {'habit': _chore(1, 'Laundry')}));
      final app = TestApp(tester, adapter, surfaceHeight: 2400);
      await app.pump(const BoardScreen());
      await app.tap(find.text('Laundry'));
      expect(_button('Agree to 40 gems'), findsOneWidget);
      await app.tap(_button('Save'));
      expect((app.body('PATCH /api/shared-habits/1') as Map).containsKey('worth'), isFalse);

      await app.tap(find.text('Laundry'));
      await app.tap(_sem('75 gems'));
      await app.tap(_button('Save'));
      expect((app.body('PATCH /api/shared-habits/1') as Map)['worth'], 75);
    });
  });

  group('picking days', () {
    testWidgets('Saturday and Sunday are told apart and today is pre-picked', (tester) async {
      final adapter = _server([])
        ..on('POST /api/shared-habits', StubResponse(201, {'habit': _chore(9, 'Laundry')}));
      final app = TestApp(tester, adapter, surfaceHeight: 2400);
      await app.pump(const BoardScreen());
      await app.tap(_sem('Add your first chore'));
      await app.tap(_sem('Certain days'));
      expect(find.text('Sa'), findsOneWidget);
      expect(find.text('Su'), findsOneWidget);
      expect(find.text('Due Monday.'), findsOneWidget);
      await app.tap(_sem('Monday'));
      await app.tap(_sem('Sunday'));
      expect(find.text('Due Sunday.'), findsOneWidget);
      await app.tap(find.byType(TextField));
      await tester.enterText(find.byType(TextField), 'Laundry');
      await tester.pump();
      await app.tap(_button('Add chore'));
      expect(app.body('POST /api/shared-habits'), {
        'name': 'Laundry',
        'icon': 'home',
        'schedule': {
          'kind': 'weekdays',
          'weekdays': [7],
        },
      });
    });
  });

  group('Us order', () {
    testWidgets('Home sits above the recap links, so a first chore is on the first screen', (
      tester,
    ) async {
      final app = TestApp(tester, _server([]), surfaceHeight: 2400);
      await app.pump(const BoardScreen());
      final home = tester.getTopLeft(find.text('Home')).dy;
      final recap = tester.getTopLeft(find.text('Weekly recap')).dy;
      expect(home, lessThan(recap));
      expect(find.text('Add your first chore'), findsOneWidget);
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
      await app.tap(_sem('Me, You earn 25 gems'));
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
