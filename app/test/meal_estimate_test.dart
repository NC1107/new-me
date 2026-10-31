import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:newme/features/log/log_sheet.dart';
import 'package:newme/features/log/log_kind.dart';
import 'package:newme/widgets/mascot.dart';

import 'fixtures.dart';
import 'test_support.dart';

const _estimate = {
  'name': 'Chicken burrito bowl',
  'kcal': 640,
  'protein': 42,
  'carbs': 58,
  'fat': 24,
  'fiber': 9,
  'confidence': 'medium',
  'notes': 'Portion looked like about 350 g.',
};

StubAdapter _server({bool enabled = true}) => fullServer()
  ..on(
    'GET /api/me',
    StubResponse(200, {
      ...meJson(),
      'features': {'mealEstimate': enabled, 'planPolish': false},
    }),
  )
  ..on('POST /api/logs', StubResponse(201, logResultJson()));

Future<TestApp> _open(WidgetTester tester, StubAdapter server) async {
  final app = TestApp(tester, server, surfaceHeight: 2000);
  await app.pump(const Scaffold(body: LogSheet(kind: LogKind.meal)));
  return app;
}

final _searchField = find.byWidgetPredicate(
  (w) => w is TextField && (w.decoration?.hintText ?? '').startsWith('Search'),
);

void main() {
  setUp(() {
    FakeStorage().install();
    Mascot.idleMotion = false;
  });

  testWidgets('one field searches and describes, and there is no separate describe box', (
    tester,
  ) async {
    await _open(tester, _server());
    expect(find.text('DESCRIBE IT'), findsNothing);
    expect(find.text('What did you eat?'), findsOneWidget);
    expect(_searchField, findsOneWidget);
    expect(find.bySemanticsLabel('Search, or describe it: 2 eggs and toast'), findsOneWidget);
    expect(find.textContaining('SNAP'), findsNothing);
  });

  testWidgets('without the feature the field only searches and offers no Work it out row', (
    tester,
  ) async {
    final server = _server(enabled: false);
    final app = await _open(tester, server);
    expect(find.bySemanticsLabel('Search foods'), findsOneWidget);
    await app.enter(_searchField, 'oats');
    expect(find.textContaining('Work it out'), findsNothing);
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await app.settle();
    expect(server.to('POST /api/meals/estimate'), isEmpty);
  });

  testWidgets('typing offers Work it out, which pre-fills the form and logs nothing until Save', (
    tester,
  ) async {
    final reply = Completer<StubResponse>();
    final server = _server()..routes['POST /api/meals/estimate'] = (_) => reply.future;
    final app = await _open(tester, server);

    expect(find.textContaining('Work it out'), findsNothing);
    await app.enter(_searchField, 'chicken burrito bowl, no rice');
    expect(find.text('Work it out: \u201cchicken burrito bowl, no rice\u201d'), findsOneWidget);
    await app.tap(find.textContaining('Work it out'));

    expect(find.text('Estimating...'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.textContaining('Work it out'), findsNothing);
    expect(app.body('POST /api/meals/estimate'), {'text': 'chicken burrito bowl, no rice'});

    reply.complete(const StubResponse(200, _estimate));
    await app.settle();
    expect(find.text('Estimating...'), findsNothing);
    expect(find.text('Estimate, medium confidence'), findsOneWidget);
    expect(find.text('Portion looked like about 350 g.'), findsOneWidget);
    expect(fieldWith('Chicken burrito bowl'), findsOneWidget);
    expect(fieldWith('640'), findsOneWidget);
    expect(fieldWith('42'), findsOneWidget);
    expect(fieldWith('9'), findsOneWidget);
    expect(server.to('POST /api/logs'), isEmpty);

    await app.tap(find.text('SAVE'));
    final saved = app.body('POST /api/logs');
    expect((saved['name'], saved['kcal'], saved['protein']), ('Chicken burrito bowl', 640, 42));
  });

  testWidgets('the keyboard return key works the meal out too', (tester) async {
    final server = _server()..on('POST /api/meals/estimate', const StubResponse(200, _estimate));
    final app = await _open(tester, server);
    await app.enter(_searchField, 'burrito bowl');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await app.settle();
    expect(app.body('POST /api/meals/estimate'), {'text': 'burrito bowl'});
    expect(find.text('Estimate, medium confidence'), findsOneWidget);
  });

  testWidgets('a rate limit and an upstream failure show inline and keep the text', (tester) async {
    final server = _server()
      ..on(
        'POST /api/meals/estimate',
        const StubResponse(429, {'code': 'rate_limited', 'error': 'slow down'}),
      );
    final app = await _open(tester, server);
    await app.enter(_searchField, 'oats');
    await app.tap(find.textContaining('Work it out'));
    expect(find.textContaining('Enter this one by hand'), findsOneWidget);
    expect(find.text('Estimate, medium confidence'), findsNothing);

    server.on(
      'POST /api/meals/estimate',
      const StubResponse(502, {'code': 'estimate_unavailable', 'error': 'x'}),
    );
    await app.tap(find.textContaining('Work it out'));
    expect(find.textContaining('Claude could not estimate that'), findsOneWidget);
  });
}
