import 'package:flutter/material.dart' show Key, Switch;
import 'package:flutter_test/flutter_test.dart';
import 'package:newme/api/models.dart';
import 'package:newme/features/board/board_screen.dart';
import 'package:newme/features/shell/home_shell.dart';
import 'package:newme/features/together/task_sheet.dart';
import 'package:newme/util/task_copy.dart';
import 'package:newme/widgets/chunky_button.dart';
import 'package:newme/widgets/mascot.dart';

import 'fixtures.dart';
import 'hit_targets.dart';
import 'test_support.dart';

// The signed-in user in these tests is Sam (id 2); Ana (id 1) is the partner. The clock reads
// Monday 2026-10-26.
Map<String, dynamic> _task({
  int id = 5,
  String title = 'Call the vet',
  int stake = 40,
  int assignee = 2,
  int creator = 2,
  String status = 'agreed',
  String deadline = '2026-10-28',
  int daysLeft = 2,
  bool loseIfMissed = false,
  int lost = 0,
}) => {
  'id': id,
  'title': title,
  'creatorId': creator,
  'creatorName': creator == 1 ? 'Ana' : 'Sam',
  'assigneeId': assignee,
  'assigneeName': assignee == 1 ? 'Ana' : 'Sam',
  'stake': stake,
  'loseIfMissed': loseIfMissed,
  'lost': lost,
  'deadline': deadline,
  'daysLeft': daysLeft,
  'status': status,
  'createdAt': '2026-10-20T10:00:00Z',
  'agreedAt': null,
  'settledAt': null,
};

Map<String, dynamic> _balance(int id, String name, int balance, {int tasks = 0}) => {
  'userId': id,
  'name': name,
  'earned': 500,
  'paid': 0,
  'tasks': tasks,
  'balance': balance,
};

StubAdapter _server({
  List<Map<String, dynamic>> open = const [],
  List<Map<String, dynamic>> history = const [],
  int mine = 400,
  int mineTasks = 0,
}) => fullServer()
  ..on(
    'GET /api/board',
    StubResponse(200, {
      ...board([
        boardUser(2, 'Sam', 'violet'),
        boardUser(1, 'Ana', 'amber', points: 90, percent: 20),
      ]),
      'challenge': null,
      'reward': null,
    }),
  )
  ..on(
    'GET /api/rewards',
    StubResponse(200, {
      'reward': null,
      'rewards': <Object>[],
      'history': <Object>[],
      'bank': mine + 300,
      'priceHelp': null,
      'treats': <Object>[],
      'treatHistory': <Object>[],
      'balances': [_balance(1, 'Ana', 300), _balance(2, 'Sam', mine, tasks: mineTasks)],
    }),
  )
  ..on(
    'GET /api/tasks',
    StubResponse(200, {
      'tasks': open,
      'history': history,
      'bank': mine + 300,
      'balances': [_balance(1, 'Ana', 300), _balance(2, 'Sam', mine, tasks: mineTasks)],
    }),
  );

ChunkyButton _button(WidgetTester tester, String label) => tester.widget<ChunkyButton>(
  find.byWidgetPredicate((w) => w is ChunkyButton && w.label == label),
);

TestApp _app(WidgetTester tester, StubAdapter server) =>
    TestApp(tester, server, surfaceHeight: 4000);

Future<void> _openUs(TestApp app) => app.pump(const BoardScreen());

void main() {
  setUp(() {
    FakeStorage().install();
    Mascot.idleMotion = false;
  });

  group('due labels', () {
    test('say overdue, today, tomorrow, the weekday, then the date', () {
      expect(dueLabel(-1, '2026-10-25'), 'overdue');
      expect(dueLabel(0, '2026-10-26'), 'due today');
      expect(dueLabel(1, '2026-10-27'), 'due tomorrow');
      expect(dueLabel(2, '2026-10-28'), 'due Wed');
      expect(dueLabel(6, '2026-11-01'), 'due Sun');
      expect(dueLabel(7, '2026-11-02'), 'due Nov 2');
    });

    test('the wire date has no time zone in it', () {
      expect(isoDate(DateTime(2026, 3, 5)), '2026-03-05');
    });
  });

  group('GemTask', () {
    test('drops a row without an id, a stake or a real date', () {
      expect(GemTask.tryParse(_task(id: 0)), isNull);
      expect(GemTask.tryParse(_task(stake: 0)), isNull);
      expect(GemTask.tryParse(_task(deadline: 'soon')), isNull);
      expect(GemTask.tryParse(_task())!.agreed, isTrue);
    });

    test('sorts open tasks into live, waiting for me and mine still open', () {
      final list = TaskList.fromJson({
        'tasks': [
          _task(id: 1),
          _task(id: 2, creator: 1, assignee: 2, status: 'proposed'),
          _task(id: 3, status: 'proposed', assignee: 1),
          _task(id: 4, status: 'declined', assignee: 1),
        ],
      });
      expect([for (final t in list.live) t.id], [1]);
      expect([for (final t in list.proposalsFor(2)) t.id], [2]);
      expect([for (final t in list.mineOpen(2)) t.id], [3, 4]);
    });
  });

  group('tasks on Us', () {
    testWidgets('lists agreed tasks with who, the stake and when, and Done only on mine', (
      tester,
    ) async {
      final app = _app(
        tester,
        _server(
          open: [
            _task(),
            _task(
              id: 6,
              title: 'Renew the car tag',
              assignee: 1,
              deadline: '2026-10-26',
              daysLeft: 0,
            ),
          ],
        ),
      );
      await _openUs(app);

      expect(find.text('Tasks'), findsOneWidget);
      expect(find.text('Call the vet'), findsOneWidget);
      expect(find.text('You · 40 gems · due Wed'), findsOneWidget);
      expect(find.text('Ana · 40 gems · due today'), findsOneWidget);
      expect(find.text('DONE'), findsOneWidget);
      expect(find.bySemanticsLabel('Mark Call the vet done'), findsOneWidget);
    });

    testWidgets('Done marks my task finished and reloads the balances', (tester) async {
      final server = _server(open: [_task()])
        ..on('POST /api/tasks/5/done', StubResponse(200, {'task': _task(status: 'done')}));
      final app = _app(tester, server);
      await _openUs(app);

      await app.tap(find.text('DONE'));

      expect(app.adapter.to('POST /api/tasks/5/done'), hasLength(1));
      expect(app.adapter.to('GET /api/tasks').length, greaterThan(1));
      expect(app.adapter.to('GET /api/rewards').length, greaterThan(1));
    });

    testWidgets('a refused Done says why and keeps the button', (tester) async {
      final server = _server(open: [_task()])
        ..on(
          'POST /api/tasks/5/done',
          const StubResponse(409, {
            'error': 'the deadline passed, so the gems are lost',
            'code': 'task_state',
          }),
        );
      final app = _app(tester, server);
      await _openUs(app);

      await app.tap(find.text('DONE'));
      expect(find.textContaining('the gems are lost'), findsOneWidget);
    });

    testWidgets('an overdue task is flagged and cannot be marked done', (tester) async {
      final app = _app(tester, _server(open: [_task(deadline: '2026-10-25', daysLeft: -1)]));
      await _openUs(app);

      expect(find.text('You · 40 gems · overdue'), findsOneWidget);
      expect(find.text('DONE'), findsNothing);
    });

    testWidgets('a proposal from my partner waits for Agree, a new amount or Not now', (
      tester,
    ) async {
      final server = _server(open: [_task(creator: 1, status: 'proposed')])
        ..on('POST /api/tasks/5/agree', StubResponse(200, {'task': _task(creator: 1)}));
      final app = _app(tester, server);
      await _openUs(app);

      expect(find.text('Action needed'), findsOneWidget);
      expect(find.text('Ana asks you to Call the vet: 40 gems, due Wed'), findsOneWidget);
      expect(find.text('Change the amount'), findsOneWidget);
      expect(find.text('DONE'), findsNothing);
      await app.tap(find.text('AGREE'));
      expect(app.adapter.to('POST /api/tasks/5/agree'), hasLength(1));
    });

    testWidgets('Change the amount sends a counter-offer', (tester) async {
      final server = _server(open: [_task(creator: 1, status: 'proposed')])
        ..on(
          'POST /api/tasks/5/counter',
          StubResponse(200, {'task': _task(status: 'proposed', stake: 25)}),
        );
      final app = _app(tester, server);
      await _openUs(app);

      await app.tap(find.text('Change the amount'));
      await tester.enterText(fieldWith('40'), '25');
      await app.settle();
      await app.tap(find.text('SEND'));

      expect(app.body('POST /api/tasks/5/counter'), {'stake': 25});
    });

    testWidgets('the Action needed card is first and the Us tab counts it', (tester) async {
      final server = _server(
        open: [
          _task(creator: 1, status: 'proposed'),
          _task(id: 6, title: 'Book the dentist', creator: 1, status: 'proposed'),
        ],
      );
      final app = _app(tester, server);
      await _openUs(app);

      expect(find.text('Action needed'), findsOneWidget);
      final actionTop = tester.getTopLeft(find.text('Action needed')).dy;
      expect(actionTop, lessThan(tester.getTopLeft(find.text('Tasks')).dy));
      expect(
        tester.getTopLeft(find.text('Action needed')).dy,
        lessThan(tester.getTopLeft(find.text('Your gems')).dy),
      );
    });

    testWidgets('the Us tab shows how many answers wait on me', (tester) async {
      final server = _server(
        open: [
          _task(creator: 1, status: 'proposed'),
          _task(id: 6, title: 'Book the dentist', creator: 1, status: 'proposed'),
        ],
      );
      await _app(tester, server).pump(const HomeShell());

      expect(
        find.descendant(of: find.byKey(const Key('nav-badge')), matching: find.text('2')),
        findsOneWidget,
      );
    });

    testWidgets('nothing waiting on me means no Action needed card', (tester) async {
      final app = _app(tester, _server(open: [_task()]));
      await _openUs(app);

      expect(find.text('Action needed'), findsNothing);
    });

    testWidgets('Not now sends the decline', (tester) async {
      final server = _server(open: [_task(creator: 1, assignee: 1, status: 'proposed')])
        ..on('POST /api/tasks/5/decline', StubResponse(200, {'task': _task(status: 'declined')}));
      final app = _app(tester, server);
      await _openUs(app);

      expect(find.text('Ana takes on Call the vet: 40 gems, due Wed'), findsOneWidget);
      await app.tap(find.text('NOT NOW'));
      expect(app.adapter.to('POST /api/tasks/5/decline'), hasLength(1));
    });

    testWidgets('my proposal shows who it waits on and opens to edit', (tester) async {
      final app = _app(tester, _server(open: [_task(status: 'proposed', assignee: 1)]));
      await _openUs(app);

      expect(find.text('40 gems · due Wed · waiting for Ana'), findsOneWidget);
      await app.tap(find.text('Call the vet'));
      expect(find.byType(TaskSheet), findsOneWidget);
      expect(find.text('Edit task'), findsOneWidget);
      expect(find.text('WITHDRAW'), findsOneWidget);
    });

    testWidgets('the history lists what was earned, and a loss only when one was taken', (
      tester,
    ) async {
      final app = _app(
        tester,
        _server(
          history: [
            _task(id: 7, title: 'Pay the bill', status: 'done'),
            _task(id: 8, title: 'Fix the fence', assignee: 1, stake: 100, status: 'missed'),
            _task(
              id: 9,
              title: 'Mow the lawn',
              assignee: 1,
              stake: 100,
              status: 'missed',
              loseIfMissed: true,
              lost: 30,
            ),
          ],
        ),
      );
      await _openUs(app);

      expect(find.text('Tasks settled'), findsOneWidget);
      expect(find.text('You finished · +40 gems'), findsOneWidget);
      expect(find.text('Ana missed'), findsOneWidget);
      expect(find.text('Ana missed · -30 gems'), findsOneWidget);
    });

    testWidgets('there is no debt state on the balances', (tester) async {
      final app = _app(tester, _server(mine: 0));
      await _openUs(app);

      expect(find.text('In debt'), findsNothing);
    });

    testWidgets('a task I put gems on the line for says so', (tester) async {
      final app = _app(tester, _server(open: [_task(loseIfMissed: true)]));
      await _openUs(app);

      expect(find.text('You · 40 gems · due Wed · lost if missed'), findsOneWidget);
    });

    testWidgets('with no tasks it shows an empty state with one way in', (tester) async {
      final app = _app(tester, _server());
      await _openUs(app);

      expect(find.text('No tasks yet'), findsOneWidget);
      expect(find.text('ADD A TASK'), findsOneWidget);
    });

    testWidgets('the touch targets are 44pt', (tester) async {
      final app = _app(
        tester,
        _server(
          open: [
            _task(),
            _task(id: 9, status: 'proposed', assignee: 1),
          ],
        ),
      );
      await _openUs(app);

      expect(smallTargets(tester), isEmpty);
    });
  });

  group('add a task', () {
    testWidgets('proposes title, who, worth and deadline', (tester) async {
      final server = _server()
        ..on(
          'POST /api/tasks',
          StubResponse(201, {'task': _task(status: 'proposed', assignee: 1)}),
        );
      final app = _app(tester, server);
      await _openUs(app);

      await app.tap(find.text('ADD A TASK'));
      expect(find.byType(TaskSheet), findsOneWidget);
      expect(_button(tester, 'Propose task').onPressed, isNull);

      await app.tap(find.text('Call the vet').last);
      await app.tap(find.descendant(of: find.byType(TaskSheet), matching: find.text('Ana')));
      await tester.enterText(fieldWith(''), '50');
      await app.settle();
      await app.tap(find.text('Tomorrow'));
      await app.tap(find.text('PROPOSE TASK'));

      expect(app.body('POST /api/tasks'), {
        'title': 'Call the vet',
        'assigneeId': 1,
        'stake': 50,
        'deadline': '2026-10-27',
      });
    });

    testWidgets('losing gems is an opt-in offered only on a task for myself', (tester) async {
      final server = _server()
        ..on('POST /api/tasks', StubResponse(201, {'task': _task(loseIfMissed: true)}));
      final app = _app(tester, server);
      await _openUs(app);

      await app.tap(find.text('ADD A TASK'));
      expect(find.text('Lose them if missed'), findsOneWidget);
      await app.tap(find.descendant(of: find.byType(TaskSheet), matching: find.text('Ana')));
      expect(find.text('Lose them if missed'), findsNothing);
      await app.tap(find.descendant(of: find.byType(TaskSheet), matching: find.text('Me')));
      await app.tap(find.byType(Switch));
      await app.tap(find.text('Call the vet').last);
      await tester.enterText(fieldWith(''), '50');
      await app.settle();
      await app.tap(find.text('Tomorrow'));
      await app.tap(find.text('PROPOSE TASK'));

      expect(app.body('POST /api/tasks'), {
        'title': 'Call the vet',
        'assigneeId': 2,
        'stake': 50,
        'deadline': '2026-10-27',
        'loseIfMissed': true,
      });
    });

    testWidgets('what it is worth is held to 1 to 100,000 gems', (tester) async {
      final app = _app(tester, _server());
      await _openUs(app);

      await app.tap(find.text('ADD A TASK'));
      await app.tap(find.text('Call the vet').last);
      await app.tap(find.text('Today'));
      await tester.enterText(fieldWith(''), '0');
      await app.settle();
      expect(find.text('Between 1 and 100,000'), findsOneWidget);
      expect(_button(tester, 'Propose task').onPressed, isNull);
    });

    testWidgets('editing a proposal sends only what changed', (tester) async {
      final server = _server(open: [_task(status: 'proposed', assignee: 1)])
        ..on(
          'PATCH /api/tasks/5',
          StubResponse(200, {'task': _task(status: 'proposed', stake: 25)}),
        );
      final app = _app(tester, server);
      await _openUs(app);

      await app.tap(find.text('Call the vet'));
      await tester.enterText(fieldWith('40'), '25');
      await app.settle();
      await app.tap(find.text('SAVE'));

      expect(app.body('PATCH /api/tasks/5'), {'stake': 25});
    });
  });
}
