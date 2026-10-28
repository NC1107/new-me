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

void main() {
  setUp(() {
    FakeStorage().install();
    Mascot.idleMotion = false;
  });

  testWidgets('Describe it shows only when the server can estimate, and there is no photo option', (
    tester,
  ) async {
    await _open(tester, _server());
    expect(find.text('DESCRIBE IT'), findsOneWidget);
    expect(find.bySemanticsLabel('Search foods'), findsOneWidget);
    expect(find.textContaining('SNAP'), findsNothing);
  });

  testWidgets('without the feature the form is just the form', (tester) async {
    await _open(tester, _server(enabled: false));
    expect(find.text('DESCRIBE IT'), findsNothing);
    // Searching the library needs no Claude key.
    expect(find.bySemanticsLabel('Search foods'), findsOneWidget);
  });

  testWidgets('a sentence pre-fills the form with the estimate and logs nothing until Save', (
    tester,
  ) async {
    final reply = Completer<StubResponse>();
    final server = _server()..routes['POST /api/meals/estimate'] = (_) => reply.future;
    final app = await _open(tester, server);

    await app.tap(find.text('DESCRIBE IT'));
    expect(find.byType(TextField), findsWidgets);
    expect(find.text('ESTIMATE'), findsOneWidget);
    await app.enter(find.widgetWithText(TextField, '').first, 'chicken burrito bowl, no rice');
    await app.tap(find.text('ESTIMATE'));

    expect(find.text('Estimating...'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
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

  testWidgets('a rate limit and an upstream failure leave the form to fill by hand', (
    tester,
  ) async {
    final server = _server()
      ..on(
        'POST /api/meals/estimate',
        const StubResponse(429, {'code': 'rate_limited', 'error': 'slow down'}),
      );
    final app = await _open(tester, server);
    await app.tap(find.text('DESCRIBE IT'));
    await app.enter(find.widgetWithText(TextField, '').first, 'oats');
    await app.tap(find.text('ESTIMATE'));
    expect(find.textContaining('Enter this one by hand'), findsOneWidget);
    expect(find.text('Estimate, medium confidence'), findsNothing);

    server.on(
      'POST /api/meals/estimate',
      const StubResponse(502, {'code': 'estimate_unavailable', 'error': 'x'}),
    );
    await app.tap(find.text('ESTIMATE'));
    expect(find.textContaining('Claude could not estimate that'), findsOneWidget);
  });
}
