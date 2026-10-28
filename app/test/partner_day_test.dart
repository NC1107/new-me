import 'package:flutter_test/flutter_test.dart';
import 'package:newme/features/board/board_screen.dart';
import 'package:newme/widgets/mascot.dart';

import 'fixtures.dart';
import 'habit_fixtures.dart';
import 'test_support.dart';

Map<String, dynamic> _partnerToday() => {
  'id': 1,
  'name': 'Ana',
  'date': '2026-10-26',
  'day': dayJson(),
  'streak': {'current': 4, 'restAvailable': true, 'restUsedOn': null},
  'quests': [
    quest('steps', 'Steps', {'unit': 'steps', 'target': 8000, 'actual': 4200}),
    quest('meals_logged', 'Meals', {'unit': 'meals', 'target': 2, 'actual': 2, 'done': true}),
  ],
  'habits': [
    checkState(7, 'Check litter', 'pets', [
      stateSlot(0, 'Morning', '08:00', done: true),
      stateSlot(1, 'Evening', '18:00'),
    ]),
    countState(8, 'Water', target: 8, count: 8),
  ],
};

StubAdapter _server() => fullServer()
  ..on(
    'GET /api/board',
    StubResponse(200, board([boardUser(1, 'Ana', 'amber'), boardUser(2, 'Sam', 'violet')])),
  )
  ..on('GET /api/habits/proposals', const StubResponse(200, {'from': 'Ana', 'proposals': []}))
  ..on('GET /api/partner/today', StubResponse(200, _partnerToday()));

void main() {
  setUp(() {
    FakeStorage().install();
    Mascot.idleMotion = false;
  });

  testWidgets("the partner's sheet shows their quests and habits today", (tester) async {
    final server = _server();
    final app = TestApp(tester, server, surfaceHeight: 2000);
    await app.pump(const BoardScreen());
    await app.tap(find.bySemanticsLabel(RegExp(r'^Ana: ')));

    expect(server.to('GET /api/partner/today'), hasLength(1));
    expect(find.bySemanticsLabel('Walk 8,000 steps, 4,200 of 8,000 steps'), findsOneWidget);
    expect(find.bySemanticsLabel('Log 2 meals, Done'), findsOneWidget);
    expect(find.bySemanticsLabel('Check litter, 1 of 2 done'), findsOneWidget);
    expect(find.bySemanticsLabel('Water, Done'), findsOneWidget);
  });

  testWidgets('my own sheet does not ask for a partner day', (tester) async {
    final server = _server();
    final app = TestApp(tester, server, surfaceHeight: 2000);
    await app.pump(const BoardScreen());
    await app.tap(find.bySemanticsLabel(RegExp(r'^Sam: ')));

    expect(server.to('GET /api/partner/today'), isEmpty);
    expect(find.text('Habits'), findsNothing);
  });
}
