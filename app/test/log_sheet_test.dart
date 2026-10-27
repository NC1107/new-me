import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:newme/features/log/log_kind.dart';
import 'package:newme/features/log/log_sheet.dart';
import 'package:newme/state/local_prefs.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fixtures.dart';
import 'test_support.dart';

class _Opener extends StatelessWidget {
  const _Opener({this.kind});

  final LogKind? kind;

  @override
  Widget build(BuildContext context) => Center(
    child: ElevatedButton(
      onPressed: () => showLogSheet(context, kind: kind),
      child: const Text('Open'),
    ),
  );
}

StubAdapter _server() => fullServer()
  ..on('POST /api/logs', StubResponse(201, logResultJson()))
  ..on('DELETE /api/logs/77', StubResponse(200, deleteLogJson()));

Future<TestApp> _open(WidgetTester tester, StubAdapter adapter, {LogKind? kind}) async {
  final app = TestApp(tester, adapter);
  await app.pump(_Opener(kind: kind));
  await app.tap(find.text('Open'));
  return app;
}

void main() {
  setUp(FakeStorage().install);

  testWidgets('opens on the kind logged last', (tester) async {
    SharedPreferences.setMockInitialValues({'lastLogKind': 'meal'});
    await _open(tester, _server());
    expect(find.text('Portion'), findsOneWidget);
    expect(find.text('Quick add'), findsNothing);
  });

  testWidgets('an explicit kind beats the last one', (tester) async {
    SharedPreferences.setMockInitialValues({'lastLogKind': 'meal'});
    await _open(tester, _server(), kind: LogKind.reading);
    expect(find.text('Minutes'), findsWidgets);
    expect(find.text('Portion'), findsNothing);
  });

  testWidgets('pushups save stays disabled until the value is valid and caps inline', (
    tester,
  ) async {
    final app = await _open(tester, _server(), kind: LogKind.pushups);
    expect(filledButton(tester, 'Save').onPressed, isNull);

    await app.enter(find.byType(TextField), '0');
    expect(filledButton(tester, 'Save').onPressed, isNull);

    await app.enter(find.byType(TextField), '600');
    expect(find.text('At most 500 pushups'), findsOneWidget);
    expect(filledButton(tester, 'Save').onPressed, isNull);

    await app.enter(find.byType(TextField), '25');
    expect(find.text('At most 500 pushups'), findsNothing);
    expect(filledButton(tester, 'Save').onPressed, isNotNull);
  });

  testWidgets('a value above the sanity limit asks first, and cancel logs nothing', (tester) async {
    final adapter = _server();
    final app = await _open(tester, adapter, kind: LogKind.pushups);

    await app.enter(find.byType(TextField), '250');
    await app.tap(find.widgetWithText(FilledButton, 'Save'));
    expect(find.textContaining('250 pushups in one go'), findsOneWidget);

    await app.tap(find.text('Cancel'));
    expect(adapter.to('POST /api/logs'), isEmpty);
    expect(find.text('Pushups'), findsOneWidget);

    await app.tap(find.widgetWithText(FilledButton, 'Save'));
    await app.tap(find.text('Log it'));
    expect(app.body('POST /api/logs')['quantity'], 250);
  });

  testWidgets('a quick chip logs at once, shows Added 20 with Undo and closes the sheet', (
    tester,
  ) async {
    final adapter = _server();
    final app = await _open(tester, adapter, kind: LogKind.pushups);

    await app.tap(find.text('20'));

    final body = app.body('POST /api/logs');
    expect(body['kind'], 'activity');
    expect(body['type'], 'pushups');
    expect(body['quantity'], 20);
    expect(body['unit'], 'reps');
    expect(body['clientOpId'], isA<String>());
    expect(body.containsKey('date'), isFalse);

    expect(find.text('Quick add'), findsNothing);
    expect(find.text('Added 20'), findsOneWidget);
    expect(find.text('Undo'), findsOneWidget);
    expect((await LocalPrefs.lastLogKind()), 'pushups');

    await app.tap(find.text('Undo'));
    expect(adapter.to('DELETE /api/logs/77').single.queryParameters, isEmpty);
  });

  testWidgets('a failed save keeps the sheet open and the retry reuses the client op id', (
    tester,
  ) async {
    final adapter = _server();
    var attempts = 0;
    adapter.routes['POST /api/logs'] = (_) =>
        ++attempts == 1 ? const StubResponse.unreachable() : StubResponse(201, logResultJson());
    final app = await _open(tester, adapter, kind: LogKind.pushups);

    await app.enter(find.byType(TextField), '25');
    await app.tap(find.widgetWithText(FilledButton, 'Save'));
    expect(find.textContaining('You are offline'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Try again'), findsOneWidget);
    expect(find.text('Quick add'), findsOneWidget);

    await app.tap(find.widgetWithText(FilledButton, 'Try again'));
    final sent = adapter.to('POST /api/logs').map((r) => (r.data as Map)['clientOpId']).toList();
    expect(sent, hasLength(2));
    expect(sent[0], sent[1]);
    expect(find.text('Quick add'), findsNothing);
    expect(find.text('Added 25'), findsOneWidget);
  });

  testWidgets('changing the entry after a failure is a new operation', (tester) async {
    final adapter = _server();
    var attempts = 0;
    adapter.routes['POST /api/logs'] = (_) =>
        ++attempts == 1 ? const StubResponse.unreachable() : StubResponse(201, logResultJson());
    final app = await _open(tester, adapter, kind: LogKind.pushups);

    await app.tap(find.text('20'));
    await app.tap(find.text('10'));
    final sent = adapter.to('POST /api/logs').map((r) => (r.data as Map)['clientOpId']).toList();
    expect(sent[0], isNot(sent[1]));
  });

  testWidgets('reading logs minutes or pages with the matching unit', (tester) async {
    final adapter = _server();
    final app = await _open(tester, adapter, kind: LogKind.reading);

    await app.enter(find.byType(TextField), '15');
    await app.tap(find.widgetWithText(FilledButton, 'Save'));
    expect(app.body('POST /api/logs')['unit'], 'minutes');
    expect(app.body('POST /api/logs')['type'], 'reading');
    expect(find.text('Added 15 min'), findsOneWidget);
  });

  testWidgets('pages above 300 ask before logging', (tester) async {
    final adapter = _server();
    final app = await _open(tester, adapter, kind: LogKind.reading);

    await app.tap(find.text('Pages'));
    await app.enter(find.byType(TextField), '350');
    await app.tap(find.widgetWithText(FilledButton, 'Save'));
    expect(find.textContaining('350 pages in one go'), findsOneWidget);
    await app.tap(find.text('Log it'));
    expect(app.body('POST /api/logs')['unit'], 'pages');
  });

  testWidgets('yoga appears only when its template is enabled', (tester) async {
    await _open(tester, _server(), kind: LogKind.pushups);
    expect(find.text('Yoga'), findsNothing);
    await tester.pumpWidget(const SizedBox());

    final adapter = _server()..on('GET /api/me', StubResponse(200, meJson(yoga: true)));
    final app = TestApp(tester, adapter);
    await app.pump(const _Opener(kind: LogKind.pushups), key: UniqueKey());
    await app.tap(find.text('Open'));
    expect(find.text('Yoga'), findsOneWidget);
  });

  testWidgets('recent meals log in one tap at the chosen portion', (tester) async {
    final adapter = _server()..on('POST /api/logs', StubResponse(201, logResultJson()));
    final app = await _open(tester, adapter, kind: LogKind.meal);

    expect(find.text('Chicken bowl'), findsOneWidget);
    expect(find.text('Oats'), findsOneWidget);

    await app.tap(find.text('1.5'));
    await app.tap(find.text('Chicken bowl'));

    final body = app.body('POST /api/logs');
    expect(body['kind'], 'meal');
    expect(body['name'], 'Chicken bowl');
    expect(body['kcal'], 900);
    expect(body['protein'], 60);
    expect(body['carbs'], 90);
    expect(body['fat'], 30);
    expect(body['fiber'], 7.5);
    expect(find.text('Added Chicken bowl'), findsOneWidget);
  });

  testWidgets('with no recent meals the chip row is hidden', (tester) async {
    final adapter = _server()
      ..on('GET /api/meals/recent', const StubResponse(200, {'meals': <Object>[]}));
    await _open(tester, adapter, kind: LogKind.meal);
    expect(find.textContaining('Recent meals'), findsNothing);
  });

  testWidgets('the meal form needs kcal, scales by the portion and hides fiber under More', (
    tester,
  ) async {
    final adapter = _server();
    final app = await _open(tester, adapter, kind: LogKind.meal);

    expect(filledButton(tester, 'Save').onPressed, isNull);
    expect(find.text('Fiber (g)'), findsNothing);

    final fields = find.byType(TextField);
    await app.enter(fields.at(0), 'Toast');
    await app.enter(fields.at(1), '300');
    await app.enter(fields.at(2), '10.5');
    expect(filledButton(tester, 'Save').onPressed, isNotNull);

    await app.tap(find.text('More'));
    expect(find.text('Fiber (g)'), findsOneWidget);

    await app.tap(find.text('2'));
    expect(find.text('Logs 600 kcal'), findsOneWidget);
    await app.tap(find.widgetWithText(FilledButton, 'Save'));

    final body = app.body('POST /api/logs');
    expect(body['name'], 'Toast');
    expect(body['kcal'], 600);
    expect(body['protein'], 21);
  });

  testWidgets('a meal over 3000 kcal asks first', (tester) async {
    final adapter = _server();
    final app = await _open(tester, adapter, kind: LogKind.meal);

    await app.enter(find.byType(TextField).at(1), '3200');
    await app.tap(find.widgetWithText(FilledButton, 'Save'));
    expect(find.textContaining('3,200 kcal in one meal'), findsOneWidget);
    await app.tap(find.text('Cancel'));
    expect(adapter.to('POST /api/logs'), isEmpty);
  });

  testWidgets('add to yesterday shows before the cutoff and backdates the entry', (tester) async {
    final adapter = _server();
    final app = await _open(tester, adapter, kind: LogKind.pushups);

    expect(find.textContaining('Add to yesterday'), findsOneWidget);
    await app.tap(find.byType(Switch));
    await app.tap(find.text('20'));
    expect(app.body('POST /api/logs')['date'], '2026-10-25');
  });

  testWidgets('add to yesterday is hidden once the window has closed', (tester) async {
    final adapter = _server()
      ..on('GET /api/today', StubResponse(200, richTodayJson(backdateUntil: null)))
      ..on('GET /api/me', StubResponse(200, {...meJson(), 'backdateUntil': null}));
    await _open(tester, adapter, kind: LogKind.pushups);
    expect(find.textContaining('Add to yesterday'), findsNothing);
  });
}
