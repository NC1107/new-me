import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:newme/features/shell/home_shell.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fixtures.dart';
import 'test_support.dart';

StubAdapter _server() => fullServer()
  ..on('POST /api/logs', StubResponse(201, logResultJson()))
  ..on('DELETE /api/logs/77', StubResponse(200, deleteLogJson()))
  ..on('DELETE /api/logs/78', StubResponse(200, deleteLogJson()))
  ..on('PATCH /api/me', StubResponse(200, meJson()));

void main() {
  setUp(FakeStorage().install);

  testWidgets('a quick add moves the ring and the board, and reloads Today only for the streak', (
    tester,
  ) async {
    final adapter = _server();
    var logged = false;
    adapter.routes['POST /api/logs'] = (_) {
      logged = true;
      return StubResponse(201, logResultJson());
    };
    adapter.routes['GET /api/today'] = (_) => StubResponse(
      200,
      logged ? richTodayJson(points: 170, percent: 70, counted: true, streak: 4) : richTodayJson(),
    );
    final app = TestApp(tester, adapter);
    await app.pump(const HomeShell());
    final loads = adapter.to('GET /api/today').length;
    final boardLoads = adapter.to('GET /api/board').length;

    await app.tap(find.byIcon(Icons.add));
    await app.tap(find.text('20'));

    expect(find.text('170'), findsOneWidget);
    expect(find.text('70%'), findsOneWidget);
    expect(find.text('Streak day counted'), findsOneWidget);
    expect(find.text('Day 4'), findsOneWidget, reason: 'the pill follows the counted day');
    expect(adapter.to('GET /api/today'), hasLength(loads + 1));
    expect(adapter.to('GET /api/board').length, greaterThan(boardLoads));
  });

  testWidgets('a quick add that does not change whether the day counts needs no second GET', (
    tester,
  ) async {
    final adapter = _server();
    adapter.on(
      'POST /api/logs',
      StubResponse(201, {
        ...logResultJson(),
        'day': {
          'date': '2026-10-26',
          ...dayJson(points: 160, percent: 66),
          'quests': richTodayJson()['quests'],
        },
      }),
    );
    final app = TestApp(tester, adapter);
    await app.pump(const HomeShell());
    final loads = adapter.to('GET /api/today').length;

    await app.tap(find.byIcon(Icons.add));
    await app.tap(find.text('20'));

    expect(find.text('160'), findsOneWidget);
    expect(find.text('66%'), findsOneWidget);
    expect(adapter.to('GET /api/today'), hasLength(loads));
  });

  testWidgets('a logged meal adds to the food card', (tester) async {
    final adapter = _server()
      ..on(
        'POST /api/logs',
        StubResponse(201, {
          'log': mealLogJson(),
          'day': {'date': '2026-10-26', ...dayJson(), 'quests': richTodayJson()['quests']},
        }),
      );
    final app = TestApp(tester, adapter);
    await app.pump(const HomeShell());
    expect(find.text('1,850 / 2,200 kcal'), findsOneWidget);

    await app.tap(find.byIcon(Icons.add));
    await app.tap(find.text('Meal'));
    await app.tap(find.text('Chicken bowl'));

    expect(find.text('2,450 / 2,200 kcal'), findsOneWidget);
    expect(find.text('122 / 150 g'), findsOneWidget);
  });

  testWidgets('the day detail sheet lists entries and a swipe deletes with an undo', (
    tester,
  ) async {
    final adapter = _server();
    final app = TestApp(tester, adapter);
    await app.pump(const HomeShell());

    await app.tap(find.text('Food'));
    expect(find.text("Today's entries"), findsOneWidget);
    expect(find.text('20 reps'), findsOneWidget);
    expect(find.text('600 kcal'), findsOneWidget);
    expect(find.text('Chicken bowl'), findsOneWidget);
    expect(find.textContaining('P 40 C 60 F 20'), findsOneWidget);

    await tester.drag(find.text('20 reps'), const Offset(-500, 0));
    await app.settle(20);
    expect(adapter.to('DELETE /api/logs/77').single.queryParameters, isEmpty);
    expect(find.text('20 reps'), findsNothing);
    expect(find.text('Deleted'), findsOneWidget);

    final reloads = adapter.to('GET /api/today').length;
    await app.tap(find.text('Undo'));
    final repost = app.body('POST /api/logs');
    expect(repost['quantity'], 20);
    expect(repost['type'], 'pushups');
    expect(repost['clientOpId'], isNot(isEmpty));
    expect(
      adapter.to('GET /api/today').length,
      reloads + 1,
      reason: 'the restored entry makes the day count again, so the streak is fetched',
    );
  });

  testWidgets('an entry can be deleted without a swipe through its Delete action', (tester) async {
    final handle = tester.ensureSemantics();
    final adapter = _server();
    final app = TestApp(tester, adapter);
    await app.pump(const HomeShell());
    await app.tap(find.text('Food'));

    final row = find.ancestor(of: find.text('20 reps'), matching: find.byType(Semantics)).first;
    final node = tester.getSemantics(row);
    final deleteId = node.getSemanticsData().customSemanticsActionIds!.single;
    tester.semantics.performAction(
      find.semantics.byLabel(RegExp(r'^Pushups')),
      SemanticsAction.customAction,
      args: deleteId,
    );
    await app.settle(20);

    expect(adapter.to('DELETE /api/logs/77'), hasLength(1));
    expect(find.text('20 reps'), findsNothing);
    handle.dispose();
  });

  testWidgets('a failed delete puts the entry back', (tester) async {
    final adapter = _server()..on('DELETE /api/logs/77', const StubResponse.unreachable());
    final app = TestApp(tester, adapter);
    await app.pump(const HomeShell());

    await app.tap(find.text('Food'));
    await tester.drag(find.text('20 reps'), const Offset(-500, 0));
    await app.settle(20);
    expect(find.text('20 reps'), findsOneWidget);
    expect(find.textContaining('You are offline'), findsOneWidget);
  });

  testWidgets('Set your targets sends you to Me', (tester) async {
    final app = TestApp(tester, _server());
    await app.pump(const HomeShell());

    await app.tap(find.text('Set your targets'));
    expect(find.text('Takes effect tomorrow'), findsOneWidget);
  });

  testWidgets('a phone that moved time zones tells the server, a first run does not', (
    tester,
  ) async {
    final adapter = _server();
    final app = TestApp(tester, adapter);
    await app.pump(const HomeShell());
    expect(adapter.to('PATCH /api/me'), isEmpty);
    expect((await SharedPreferences.getInstance()).getString('deviceTimezone'), 'America/New_York');
  });

  testWidgets('moving the phone to a new zone patches it once', (tester) async {
    SharedPreferences.setMockInitialValues({'deviceTimezone': 'Europe/London'});
    final adapter = _server()
      ..on('GET /api/me', StubResponse(200, meJson(timezone: 'Europe/London')));
    final app = TestApp(tester, adapter);
    await app.pump(const HomeShell());
    expect(app.body('PATCH /api/me'), {'timezone': 'America/New_York'});
  });

  testWidgets('a zone picked by hand is not overwritten by the device zone', (tester) async {
    SharedPreferences.setMockInitialValues({'deviceTimezone': 'America/New_York'});
    final adapter = _server()..on('GET /api/me', StubResponse(200, meJson(timezone: 'Asia/Tokyo')));
    final app = TestApp(tester, adapter);
    await app.pump(const HomeShell());
    expect(adapter.to('PATCH /api/me'), isEmpty);
  });
}
