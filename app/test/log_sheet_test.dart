import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:newme/features/log/log_kind.dart';
import 'package:newme/features/log/log_sheet.dart';
import 'package:newme/widgets/chunky_button.dart';
import 'package:newme/widgets/mascot.dart';

import 'fixtures.dart';
import 'test_support.dart';

class _Opener extends StatelessWidget {
  const _Opener({required this.kind});

  final LogKind kind;

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

Future<TestApp> _open(WidgetTester tester, StubAdapter adapter, LogKind kind) async {
  final app = TestApp(tester, adapter);
  await app.pump(_Opener(kind: kind));
  await app.tap(find.text('Open'));
  return app;
}

Finder _save([String label = 'Save']) =>
    find.byWidgetPredicate((w) => w is ChunkyButton && w.label == label);

bool _saveEnabled(WidgetTester tester, [String label = 'Save']) =>
    tester.widget<ChunkyButton>(_save(label)).onPressed != null;

String _number(WidgetTester tester) =>
    tester.widget<TextField>(find.byType(TextField).first).controller!.text;

void main() {
  setUp(() {
    FakeStorage().install();
    Mascot.idleMotion = false;
  });

  testWidgets('each kind opens its own form with its title', (tester) async {
    await _open(tester, _server(), LogKind.pushups);
    expect(find.text('Log push-ups'), findsOneWidget);
    expect(find.text('Portion'), findsNothing);
    await tester.pumpWidget(const SizedBox());

    final meal = TestApp(tester, _server());
    await meal.pump(const _Opener(kind: LogKind.meal), key: UniqueKey());
    await meal.tap(find.text('Open'));
    expect(find.text('Log a meal'), findsOneWidget);
    expect(find.text('Portion'), findsOneWidget);
  });

  testWidgets('pushups start at 10, step with - and +, and chips add to the number', (
    tester,
  ) async {
    final app = await _open(tester, _server(), LogKind.pushups);
    expect(_number(tester), '10');

    await app.tap(find.bySemanticsLabel('More'));
    expect(_number(tester), '11');
    await app.tap(find.bySemanticsLabel('Less'));
    await app.tap(find.bySemanticsLabel('Less'));
    expect(_number(tester), '9');

    await app.tap(find.text('+5'));
    await app.tap(find.text('+20'));
    expect(_number(tester), '34');
  });

  testWidgets('the stepper buttons are 44pt targets and - stops at zero', (tester) async {
    final app = await _open(tester, _server(), LogKind.pushups);
    for (final label in ['Less', 'More']) {
      final size = tester.getSize(find.bySemanticsLabel(label));
      expect(size.width, greaterThanOrEqualTo(44));
      expect(size.height, greaterThanOrEqualTo(44));
    }
    await app.enter(find.byType(TextField), '1');
    await app.tap(find.bySemanticsLabel('Less'));
    expect(_number(tester), '0');
    expect(_saveEnabled(tester), isFalse);
    await app.tap(find.bySemanticsLabel('Less'));
    expect(_number(tester), '0');
  });

  testWidgets('save stays disabled until the value is valid and the cap shows inline', (
    tester,
  ) async {
    final app = await _open(tester, _server(), LogKind.pushups);
    expect(_saveEnabled(tester), isTrue);

    await app.enter(find.byType(TextField), '0');
    expect(_saveEnabled(tester), isFalse);

    await app.enter(find.byType(TextField), '600');
    expect(find.text('At most 500 push-ups'), findsOneWidget);
    expect(_saveEnabled(tester), isFalse);

    await app.enter(find.byType(TextField), '25');
    expect(find.text('At most 500 push-ups'), findsNothing);
    expect(_saveEnabled(tester), isTrue);
  });

  testWidgets('a chip never pushes the number past the cap', (tester) async {
    final app = await _open(tester, _server(), LogKind.pushups);
    await app.enter(find.byType(TextField), '495');
    await app.tap(find.text('+20'));
    expect(_number(tester), '500');
    expect(find.text('At most 500 push-ups'), findsNothing);
  });

  testWidgets('a value above the sanity limit asks first, and cancel logs nothing', (tester) async {
    final adapter = _server();
    final app = await _open(tester, adapter, LogKind.pushups);

    await app.enter(find.byType(TextField), '250');
    await app.tap(_save());
    expect(find.textContaining('250 push-ups in one go'), findsOneWidget);

    await app.tap(find.text('Cancel'));
    expect(adapter.to('POST /api/logs'), isEmpty);
    expect(find.text('Log push-ups'), findsOneWidget);

    await app.tap(_save());
    await app.tap(find.text('Log it'));
    expect(app.body('POST /api/logs')['quantity'], 250);
  });

  testWidgets('saving posts the number, shows Added with Undo and closes the sheet', (
    tester,
  ) async {
    final adapter = _server();
    final app = await _open(tester, adapter, LogKind.pushups);

    await app.tap(find.text('+10'));
    await app.tap(_save());

    final body = app.body('POST /api/logs');
    expect(body['kind'], 'activity');
    expect(body['type'], 'pushups');
    expect(body['quantity'], 20);
    expect(body['unit'], 'reps');
    expect(body['clientOpId'], isA<String>());
    expect(body.containsKey('date'), isFalse);

    expect(find.text('Log push-ups'), findsNothing);
    expect(find.text('Added 20 push-ups'), findsOneWidget);
    expect(find.text('Undo'), findsOneWidget);

    await app.tap(find.text('Undo'));
    expect(adapter.to('DELETE /api/logs/77').single.queryParameters, isEmpty);
  });

  testWidgets('the Added snack bar goes away on its own after the undo window', (tester) async {
    final app = await _open(tester, _server(), LogKind.pushups);
    await app.tap(find.text('+10'));
    await app.tap(_save());
    expect(find.text('Undo'), findsOneWidget);
    await tester.pump(const Duration(seconds: 7));
    await tester.pumpAndSettle();
    expect(find.text('Added 20 push-ups'), findsNothing);
  });

  testWidgets('a failed save keeps the sheet open and the retry reuses the client op id', (
    tester,
  ) async {
    final adapter = _server();
    var attempts = 0;
    adapter.routes['POST /api/logs'] = (_) =>
        ++attempts == 1 ? const StubResponse.unreachable() : StubResponse(201, logResultJson());
    final app = await _open(tester, adapter, LogKind.pushups);

    await app.enter(find.byType(TextField), '25');
    await app.tap(_save());
    expect(find.textContaining('You are offline'), findsOneWidget);
    expect(_save('Try again'), findsOneWidget);
    expect(find.text('Log push-ups'), findsOneWidget);

    await app.tap(_save('Try again'));
    final sent = adapter.to('POST /api/logs').map((r) => (r.data as Map)['clientOpId']).toList();
    expect(sent, hasLength(2));
    expect(sent[0], sent[1]);
    expect(find.text('Log push-ups'), findsNothing);
    expect(find.text('Added 25 push-ups'), findsOneWidget);
  });

  testWidgets('changing the entry after a failure is a new operation', (tester) async {
    final adapter = _server();
    var attempts = 0;
    adapter.routes['POST /api/logs'] = (_) =>
        ++attempts == 1 ? const StubResponse.unreachable() : StubResponse(201, logResultJson());
    final app = await _open(tester, adapter, LogKind.pushups);

    await app.tap(_save());
    await app.tap(find.text('+5'));
    await app.tap(_save('Try again'));
    final sent = adapter.to('POST /api/logs').map((r) => (r.data as Map)['clientOpId']).toList();
    expect(sent, hasLength(2));
    expect(sent[0], isNot(sent[1]));
  });

  testWidgets('reading logs minutes or pages with the matching unit', (tester) async {
    final adapter = _server();
    final app = await _open(tester, adapter, LogKind.reading);
    expect(_number(tester), '15');

    await app.tap(_save());
    expect(app.body('POST /api/logs')['unit'], 'minutes');
    expect(app.body('POST /api/logs')['type'], 'reading');
    expect(find.text('Added 15 min'), findsOneWidget);
  });

  testWidgets('switching to pages resets the number and above 300 pages asks first', (
    tester,
  ) async {
    final adapter = _server();
    final app = await _open(tester, adapter, LogKind.reading);

    await app.tap(find.text('Pages'));
    expect(_number(tester), '10');
    await app.enter(find.byType(TextField), '350');
    await app.tap(_save());
    expect(find.textContaining('350 pages in one go'), findsOneWidget);
    await app.tap(find.text('Log it'));
    expect(app.body('POST /api/logs')['unit'], 'pages');
  });

  testWidgets('yoga logs minutes against the yoga type', (tester) async {
    final adapter = _server();
    final app = await _open(tester, adapter, LogKind.yoga);
    expect(find.text('Log yoga'), findsOneWidget);

    for (final minutes in ['15', '30', '45', '60', '75', '90']) {
      expect(find.text(minutes), findsWidgets, reason: 'a $minutes minute choice');
    }
    await app.tap(find.text('90'));
    await app.tap(_save());
    expect(app.body('POST /api/logs')['type'], 'yoga');
    expect(app.body('POST /api/logs')['quantity'], 90);
    expect(app.body('POST /api/logs')['unit'], 'minutes');
  });

  testWidgets('recent meals log in one tap at the chosen portion', (tester) async {
    final adapter = _server()..on('POST /api/logs', StubResponse(201, logResultJson()));
    final app = await _open(tester, adapter, LogKind.meal);

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
    await _open(tester, adapter, LogKind.meal);
    expect(find.textContaining('Recent meals'), findsNothing);
  });

  testWidgets('the meal form needs kcal, scales by the portion and hides fiber under More', (
    tester,
  ) async {
    final adapter = _server();
    final app = await _open(tester, adapter, LogKind.meal);

    expect(_saveEnabled(tester), isFalse);
    expect(find.text('Fiber (g)'), findsNothing);

    // The food search field comes first and is always there.
    final fields = find.byType(TextField);
    await app.enter(fields.at(1), 'Toast');
    await app.enter(fields.at(2), '300');
    await app.enter(fields.at(3), '10.5');
    expect(_saveEnabled(tester), isTrue);

    await app.tap(find.text('More'));
    expect(find.text('Fiber (g)'), findsOneWidget);

    await app.tap(find.text('2'));
    expect(find.text('Logs 600 kcal'), findsOneWidget);
    await app.tap(_save());

    final body = app.body('POST /api/logs');
    expect(body['name'], 'Toast');
    expect(body['kcal'], 600);
    expect(body['protein'], 21);
  });

  testWidgets('a meal over 3000 kcal asks first', (tester) async {
    final adapter = _server();
    final app = await _open(tester, adapter, LogKind.meal);

    await app.enter(find.byType(TextField).at(2), '3200');
    await app.tap(_save());
    expect(find.textContaining('3,200 kcal in one meal'), findsOneWidget);
    await app.tap(find.text('Cancel'));
    expect(adapter.to('POST /api/logs'), isEmpty);
  });

  testWidgets('add to yesterday shows before the cutoff and backdates the entry', (tester) async {
    final adapter = _server();
    final app = await _open(tester, adapter, LogKind.pushups);

    expect(find.textContaining('Add to yesterday'), findsOneWidget);
    await app.tap(find.byType(Switch));
    await app.tap(_save());
    expect(app.body('POST /api/logs')['date'], '2026-10-25');
  });

  testWidgets('add to yesterday is hidden once the window has closed', (tester) async {
    final adapter = _server()
      ..on('GET /api/today', StubResponse(200, richTodayJson(backdateUntil: null)))
      ..on('GET /api/me', StubResponse(200, {...meJson(), 'backdateUntil': null}));
    await _open(tester, adapter, LogKind.pushups);
    expect(find.textContaining('Add to yesterday'), findsNothing);
  });
}
