import 'package:flutter_test/flutter_test.dart';
import 'package:newme/api/models.dart';
import 'package:newme/features/board/board_screen.dart';
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
}) => {
  'id': id,
  'title': title,
  'creatorId': creator,
  'creatorName': creator == 1 ? 'Ana' : 'Sam',
  'assigneeId': assignee,
  'assigneeName': assignee == 1 ? 'Ana' : 'Sam',
  'stake': stake,
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

    testWidgets('a proposal from my partner waits for Agree or Decline', (tester) async {
      final server = _server(open: [_task(creator: 1, status: 'proposed')])
        ..on('POST /api/tasks/5/agree', StubResponse(200, {'task': _task(creator: 1)}));
      final app = _app(tester, server);
      await _openUs(app);

      expect(find.text('Ana asks you to Call the vet: 40 gems, due Wed'), findsOneWidget);
      expect(find.text('DONE'), findsNothing);
      await app.tap(find.text('AGREE'));
      expect(app.adapter.to('POST /api/tasks/5/agree'), hasLength(1));
    });

    testWidgets('declining sends the decline', (tester) async {
      final server = _server(open: [_task(creator: 1, assignee: 1, status: 'proposed')])
        ..on('POST /api/tasks/5/decline', StubResponse(200, {'task': _task(status: 'declined')}));
      final app = _app(tester, server);
      await _openUs(app);

      expect(find.text('Ana takes on Call the vet: 40 gems, due Wed'), findsOneWidget);
      await app.tap(find.text('DECLINE'));
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

    testWidgets('the history lists what was won and lost', (tester) async {
      final app = _app(
        tester,
        _server(
          history: [
            _task(id: 7, title: 'Pay the bill', status: 'done'),
            _task(id: 8, title: 'Fix the fence', assignee: 1, stake: 100, status: 'missed'),
          ],
        ),
      );
      await _openUs(app);

      expect(find.text('Tasks settled'), findsOneWidget);
      expect(find.text('You finished · +40 gems'), findsOneWidget);
      expect(find.text('Ana missed · -100 gems'), findsOneWidget);
    });

    testWidgets('a balance below zero reads as a debt', (tester) async {
      final app = _app(tester, _server(mine: -70, mineTasks: -100));
      await _openUs(app);

      expect(find.text('-70'), findsOneWidget);
      expect(find.text('In debt'), findsOneWidget);
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

      await app.tap(find.text('Add a task'));
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

    testWidgets('what it is worth is held to 1 to 100,000 gems', (tester) async {
      final app = _app(tester, _server());
      await _openUs(app);

      await app.tap(find.text('Add a task'));
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
