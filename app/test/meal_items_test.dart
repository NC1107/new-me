import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:newme/features/log/log_kind.dart';
import 'package:newme/features/log/log_sheet.dart';
import 'package:newme/widgets/mascot.dart';

import 'fixtures.dart';
import 'test_support.dart';

Map<String, dynamic> _item(
  String text,
  String name,
  String unit,
  num kcal,
  num protein,
  num carbs,
  num fat,
  String source, {
  String brand = '',
  String sourceId = '',
  num grams = 0,
  num quantity = 1,
}) => {
  'text': text,
  'name': name,
  'brand': brand,
  'quantity': quantity,
  'unit': unit,
  'grams': grams,
  'kcal': kcal,
  'protein': protein,
  'carbs': carbs,
  'fat': fat,
  'fiber': 0,
  'source': source,
  'sourceId': sourceId,
  'matchedName': source == 'estimated' ? '' : name,
  'confidence': 'high',
  'origin': '',
};

final _breakdown = {
  'name': 'Apple, Chomps stick, Hot Pocket',
  'kcal': 485,
  'protein': 15.5,
  'carbs': 55,
  'fat': 14,
  'fiber': 4,
  'confidence': 'low',
  'notes': '2 of 3 items matched a nutrition database; the rest are estimated.',
  'items': [
    _item('an apple', 'Apple', 'medium', 95, 0.5, 25, 0.3, 'usda', sourceId: '171688', grams: 182),
    _item(
      'a chomp meat stick',
      'Chomps stick',
      'stick',
      90,
      10,
      0,
      6,
      'openfoodfacts',
      brand: 'Chomps',
      sourceId: '850',
      grams: 32,
    ),
    _item('a hotpocket', 'Hot Pocket', 'piece', 300, 5, 30, 8, 'estimated', brand: 'Hot Pockets'),
  ],
  'total': {'kcal': 485},
  'databaseShare': 38,
};

StubAdapter _server() => fullServer()
  ..on(
    'GET /api/me',
    StubResponse(200, {
      ...meJson(),
      'features': {'mealEstimate': true, 'planPolish': false},
    }),
  )
  ..on('POST /api/logs', StubResponse(201, logResultJson()))
  ..on('POST /api/meals/estimate', StubResponse(200, _breakdown))
  ..on(
    'POST /api/foods',
    const StubResponse(201, {
      'id': 11,
      'name': 'x',
      'servingText': '1',
      'kcal': 1,
      'source': 'usda',
    }),
  )
  ..on(
    'POST /api/foods/11/use',
    const StubResponse(200, {'id': 11, 'name': 'x', 'servingText': '1', 'kcal': 1}),
  )
  ..on('GET /api/foods', const StubResponse(200, {'foods': [], 'candidates': []}));

Future<TestApp> _described(WidgetTester tester, StubAdapter server) async {
  final app = TestApp(tester, server, surfaceHeight: 2400);
  await app.pump(const Scaffold(body: LogSheet(kind: LogKind.meal)));
  await app.tap(find.text('DESCRIBE IT'));
  await app.enter(
    find.widgetWithText(TextField, '').first,
    'an apple, a chomp meat stick, and a hotpocket',
  );
  await app.tap(find.text('ESTIMATE'));
  return app;
}

void main() {
  setUp(() {
    FakeStorage().install();
    Mascot.idleMotion = false;
  });

  testWidgets('a described meal shows one editable row per food, a total and the database share', (
    tester,
  ) async {
    final server = _server();
    await _described(tester, server);

    expect(fieldWith('Apple'), findsOneWidget);
    expect(fieldWith('Chomps stick'), findsOneWidget);
    expect(fieldWith('Hot Pocket'), findsOneWidget);
    expect(find.text('USDA'), findsOneWidget);
    expect(find.text('Label'), findsOneWidget);
    expect(find.text('Estimated'), findsOneWidget);
    expect(find.text('485 kcal'), findsOneWidget);
    expect(find.text('38% from nutrition databases'), findsOneWidget);
    expect(find.text('LOG AS ONE MEAL'), findsOneWidget);
    expect(find.text('LOG SEPARATELY'), findsOneWidget);
    expect(server.to('POST /api/logs'), isEmpty);
  });

  testWidgets(
    'changing an amount rescales its numbers, the total and the share; delete removes a row',
    (tester) async {
      final app = await _described(tester, _server());

      await app.tap(find.bySemanticsLabel('More Apple'));
      expect(fieldWith('1.5'), findsOneWidget);
      expect(find.text('533 kcal'), findsOneWidget);
      expect(find.text('143 kcal   protein 0.8 g   carbs 37.5 g   fat 0.5 g'), findsOneWidget);
      expect(find.text('44% from nutrition databases'), findsOneWidget);

      await app.tap(find.bySemanticsLabel('Less Apple'));
      expect(find.text('485 kcal'), findsOneWidget);

      await app.enter(fieldWith('1').first, '2');
      expect(find.text('580 kcal'), findsOneWidget);

      await app.tap(find.bySemanticsLabel('Remove Hot Pocket'));
      expect(fieldWith('Hot Pocket'), findsNothing);
      expect(find.text('280 kcal'), findsOneWidget);
      expect(find.text('100% from nutrition databases'), findsOneWidget);
    },
  );

  testWidgets(
    'Log as one meal sums the items, joins the names and saves database foods for next time',
    (tester) async {
      final server = _server();
      final app = await _described(tester, server);

      await app.tap(find.text('LOG AS ONE MEAL'));
      final saved = app.body('POST /api/logs');
      expect(saved['name'], 'Apple, Chomps stick, Hot Pocket');
      expect(
        (saved['kcal'], saved['protein'], saved['carbs'], saved['fat']),
        (485, 15.5, 55, 14.3),
      );
      expect(server.to('POST /api/logs'), hasLength(1));

      // The database foods are saved with their serving; the estimate is not unless kept.
      final creates = server.to('POST /api/foods').toList();
      expect(creates, hasLength(2));
      expect((creates.first.data as Map)['sourceId'], '171688');
      expect((creates.first.data as Map)['servingText'], '1 medium (182 g)');
      expect(server.to('POST /api/foods/11/use'), hasLength(2));
    },
  );

  testWidgets('keeping an estimate saves it with the rest', (tester) async {
    final server = _server();
    final app = await _described(tester, server);
    await app.tap(find.bySemanticsLabel('Keep Hot Pocket in My foods'));
    expect(find.text('Will keep in My foods'), findsOneWidget);
    await app.tap(find.text('LOG AS ONE MEAL'));
    final sources = [for (final r in server.to('POST /api/foods')) (r.data as Map)['source']];
    expect(sources, ['usda', 'openfoodfacts', 'estimated']);
  });

  testWidgets('Log separately makes one meal per item, each with its own clientOpId', (
    tester,
  ) async {
    final server = _server();
    final app = await _described(tester, server);
    await app.tap(find.text('LOG SEPARATELY'));

    final bodies = [
      for (final r in server.to('POST /api/logs')) (r.data as Map).cast<String, dynamic>(),
    ];
    expect([for (final b in bodies) b['name']], ['Apple', 'Chomps stick', 'Hot Pocket']);
    expect([for (final b in bodies) b['kcal']], [95, 90, 300]);
    expect({for (final b in bodies) b['clientOpId']}, hasLength(3));
  });

  testWidgets(
    'a failure halfway says how far it got and a retry logs only the rest, with the same key',
    (tester) async {
      final server = _server();
      var calls = 0;
      server.routes['POST /api/logs'] = (_) {
        calls++;
        return calls == 2
            ? const StubResponse(500, {'error': 'boom', 'code': 'internal'})
            : StubResponse(201, logResultJson());
      };
      final app = await _described(tester, server);

      await app.tap(find.text('LOG SEPARATELY'));
      expect(find.textContaining('Logged 1 of 3'), findsOneWidget);
      expect(find.text('LOG SEPARATELY'), findsOneWidget);

      await app.tap(find.text('LOG SEPARATELY'));
      final ids = [for (final r in server.to('POST /api/logs')) (r.data as Map)['clientOpId']];
      expect(ids, hasLength(4));
      expect(ids[1], ids[2], reason: 'the failed entry retries under the same key');
      expect({ids[0], ids[1], ids[3]}, hasLength(3));
      expect(
        [for (final r in server.to('POST /api/logs')) (r.data as Map)['name']],
        ['Apple', 'Chomps stick', 'Chomps stick', 'Hot Pocket'],
      );
    },
  );

  testWidgets('search lists saved foods first and adds one with a serving', (tester) async {
    final server = _server()
      ..on(
        'GET /api/foods',
        const StubResponse(200, {
          'foods': [
            {
              'id': 4,
              'name': 'Apple',
              'servingText': '1 medium (182 g)',
              'servingGrams': 182,
              'kcal': 95,
              'protein': 0.5,
              'source': 'usda',
              'servings': [],
              'useCount': 6,
            },
          ],
          'candidates': [],
        }),
      );
    final app = TestApp(tester, server, surfaceHeight: 2400);
    await app.pump(const Scaffold(body: LogSheet(kind: LogKind.meal)));

    await app.enter(_searchField, 'app');
    await app.settle(10);
    expect(server.to('GET /api/foods').last.queryParameters, {'q': 'app'});
    await app.tap(find.textContaining('1 medium (182 g)  -  95 kcal'));

    expect(fieldWith('Apple'), findsOneWidget);
    expect(find.text('Saved'), findsOneWidget);
    expect(find.text('medium (182 g)'), findsOneWidget);
    await app.tap(find.text('LOG AS ONE MEAL'));
    expect(app.body('POST /api/logs')['kcal'], 95);
    expect(server.to('POST /api/foods'), isEmpty);
    expect(server.to('POST /api/foods/4/use'), hasLength(1));
  });

  testWidgets('database results come only when asked for, and are added as unsaved candidates', (
    tester,
  ) async {
    final server = _server()
      ..routes['GET /api/foods'] = (o) => StubResponse(200, {
        'foods': <Object>[],
        'candidates': o.queryParameters['remote'] == 1
            ? [
                {
                  'id': null,
                  'name': 'Apple sauce',
                  'brand': "Mott's",
                  'servingText': '1 cup (240 g)',
                  'servingGrams': 240,
                  'kcal': 100,
                  'source': 'openfoodfacts',
                  'sourceId': '9',
                  'servings': [],
                },
              ]
            : <Object>[],
      });
    server.routes['POST /api/foods/11/use'] = (_) =>
        const StubResponse(200, {'id': 11, 'name': 'x', 'servingText': '1', 'kcal': 1});
    final app = TestApp(tester, server, surfaceHeight: 2400);
    await app.pump(const Scaffold(body: LogSheet(kind: LogKind.meal)));

    await app.enter(_searchField, 'sauce');
    await app.settle(10);
    expect(find.text('Nothing saved matches.'), findsOneWidget);
    expect(server.to('GET /api/foods').every((r) => r.queryParameters['remote'] == null), isTrue);

    await app.tap(find.text('SEARCH USDA AND OPEN FOOD FACTS'));
    expect(find.text('From the databases'), findsOneWidget);
    await app.tap(find.textContaining('1 cup (240 g)'));
    expect(find.text('Label'), findsOneWidget);

    await app.tap(find.text('LOG AS ONE MEAL'));
    expect((app.body('POST /api/foods'))['sourceId'], '9');
  });

  testWidgets('an older server still pre-fills the form from the single meal', (tester) async {
    final server = _server()
      ..on(
        'POST /api/meals/estimate',
        const StubResponse(200, {
          'name': 'Chicken burrito bowl',
          'kcal': 640,
          'protein': 42,
          'carbs': 58,
          'fat': 24,
          'fiber': 9,
          'confidence': 'medium',
          'notes': 'x',
        }),
      );
    await _described(tester, server);
    expect(fieldWith('Chicken burrito bowl'), findsOneWidget);
    expect(find.text('LOG AS ONE MEAL'), findsNothing);
  });

  for (final scale in [1.0, 2.0]) {
    testWidgets('the itemized meal fits at text scale $scale with 44pt targets', (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = scale;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final server = _server();
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final app = TestApp(tester, server, surfaceHeight: 844);
      await app.pump(const Scaffold(body: LogSheet(kind: LogKind.meal)), tall: false);
      expect(tester.takeException(), isNull);
      await app.enter(_searchField, 'app');
      await app.settle(10);
      expect(tester.takeException(), isNull);
      await app.tap(find.text('SEARCH USDA AND OPEN FOOD FACTS'));
      expect(tester.takeException(), isNull);
      await app.enter(_searchField, '');
      await app.tap(find.text('DESCRIBE IT'));
      await app.enter(find.widgetWithText(TextField, '').first, 'x');
      await app.tap(find.text('ESTIMATE'));

      expect(tester.takeException(), isNull);
      for (final label in [
        'Less Apple',
        'More Apple',
        'Remove Apple',
        'Keep Hot Pocket in My foods',
      ]) {
        final finder = find.bySemanticsLabel(label);
        await tester.ensureVisible(finder);
        final size = tester.getSize(finder);
        expect(size.height, greaterThanOrEqualTo(44), reason: label);
        expect(size.width, greaterThanOrEqualTo(44), reason: label);
      }
      await tester.drag(find.byType(SingleChildScrollView).first, const Offset(0, -3000));
      await app.settle();
      expect(tester.takeException(), isNull);
    });
  }
}

final _searchField = find.ancestor(
  of: find.text('Search your foods'),
  matching: find.byType(TextField),
);
