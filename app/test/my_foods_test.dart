import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:newme/features/me/my_foods_page.dart';
import 'package:newme/widgets/chunky_button.dart';
import 'package:newme/widgets/mascot.dart';

import 'fixtures.dart';
import 'test_support.dart';

const _apple = {
  'id': 4,
  'saved': true,
  'name': 'Apple',
  'brand': '',
  'servingText': '1 medium (182 g)',
  'servingGrams': 182,
  'kcal': 95,
  'protein': 0.5,
  'carbs': 25,
  'fat': 0.3,
  'fiber': 4.4,
  'source': 'usda',
  'sourceId': '171688',
  'servings': [
    {'text': '1 cup slices', 'grams': 109},
  ],
  'useCount': 6,
};

final _oat = {..._apple, 'id': 9, 'name': 'Oat bar', 'source': 'manual'};

StubAdapter _server() => fullServer()
  ..on(
    'GET /api/foods',
    const StubResponse(200, {
      'foods': [
        _apple,
        {
          'id': 5,
          'name': 'Beef stick',
          'brand': 'Chomps',
          'servingText': '1 stick (32 g)',
          'servingGrams': 32,
          'kcal': 90,
          'source': 'manual',
          'servings': [],
          'useCount': 1,
        },
      ],
      'candidates': <Object>[],
    }),
  );

Future<TestApp> _open(WidgetTester tester, StubAdapter server) async {
  final app = TestApp(tester, server, surfaceHeight: 3200);
  await app.pump(const MyFoodsPage());
  return app;
}

void main() {
  setUp(() {
    FakeStorage().install();
    Mascot.idleMotion = false;
  });

  testWidgets('lists saved foods with their serving, kcal and use', (tester) async {
    await _open(tester, _server());
    expect(find.text('Apple'), findsOneWidget);
    expect(find.text('1 medium (182 g) · 95 kcal · used 6 times'), findsOneWidget);
    expect(find.text('Chomps Beef stick'), findsOneWidget);
    expect(find.textContaining('used 1 time'), findsOneWidget);
  });

  testWidgets('a database result opens the edit page prefilled and saves without logging', (
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
    server.on(
      'POST /api/foods',
      const StubResponse(201, {
        'id': 12,
        'name': 'Apple sauce',
        'servingText': '1 cup',
        'kcal': 100,
      }),
    );
    final app = await _open(tester, server);

    await app.enter(_searchBox(), 'sauce');
    await app.settle(14);
    expect(find.text('From the databases'), findsOneWidget);
    await app.tap(find.textContaining('1 cup (240 g)'));

    expect(find.text('Save food'), findsOneWidget);
    expect(find.text('DELETE FOOD'), findsNothing);
    expect(find.text('Apple sauce'), findsOneWidget);
    await app.tap(find.text('SAVE'));
    final body = app.body('POST /api/foods');
    expect((body['sourceId'], body['source']), ('9', 'openfoodfacts'));
    expect(server.to('POST /api/logs'), isEmpty);
  });

  testWidgets('New food saves a manual food from a label', (tester) async {
    final server = _server()..on('POST /api/foods', StubResponse(201, _oat));
    final app = await _open(tester, server);

    await app.tap(find.text('NEW FOOD'));
    expect(find.text('SAVE'), findsOneWidget);
    expect(
      tester
          .widget<ChunkyButton>(
            find.byWidgetPredicate((w) => w is ChunkyButton && w.label == 'Save'),
          )
          .onPressed,
      isNull,
    );

    await app.enter(_hinted('Apple'), 'Oat bar');
    await app.enter(_hinted('1 medium (182 g)'), '1 bar (45 g)');
    await app.enter(_hinted('kcal'), '190');
    await app.enter(_hinted('0').first, '4.5');
    await app.tap(find.text('ADD A SERVING'));
    await app.enter(_hinted('1 cup sliced'), '1/2 bar');
    await app.enter(_hinted('g'), '22.5');
    await app.tap(find.text('SAVE'));

    final body = app.body('POST /api/foods');
    expect(body['name'], 'Oat bar');
    expect(
      (body['servingText'], body['kcal'], body['protein'], body['source']),
      ('1 bar (45 g)', 190, 4.5, 'manual'),
    );
    expect(body['servings'], [
      {'text': '1/2 bar', 'grams': 22.5},
    ]);
  });

  testWidgets('editing changes the serving and nutrients but never the source', (tester) async {
    final server = _server()..on('PATCH /api/foods/4', const StubResponse(200, _apple));
    final app = await _open(tester, server);

    await app.tap(find.text('Apple'));
    expect(fieldWith('1 medium (182 g)'), findsOneWidget);
    expect(fieldWith('1 cup slices'), findsOneWidget);
    await app.enter(fieldWith('95'), '100');
    await app.tap(find.text('SAVE'));

    final body = app.body('PATCH /api/foods/4');
    expect(body['kcal'], 100);
    expect(body.containsKey('source'), isFalse);
    expect(body.containsKey('sourceId'), isFalse);
    expect(body['servings'], [
      {'text': '1 cup slices', 'grams': 109},
    ]);
  });

  testWidgets('deleting asks first, then removes the food', (tester) async {
    final server = _server()..on('DELETE /api/foods/4', const StubResponse(204));
    final app = await _open(tester, server);

    await app.tap(find.text('Apple'));
    await app.tap(find.text('DELETE FOOD'));
    expect(find.text('Delete this food?'), findsOneWidget);
    await app.tap(find.text('Cancel'));
    expect(server.to('DELETE /api/foods/4'), isEmpty);

    await app.tap(find.text('DELETE FOOD'));
    await app.tap(find.text('Delete'));
    expect(server.to('DELETE /api/foods/4'), hasLength(1));
  });

  testWidgets('the page and the edit form fit at text scale 2.0', (tester) async {
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final app = TestApp(tester, _server());
    await app.pump(const MyFoodsPage(), tall: false);
    expect(tester.takeException(), isNull);
    await app.tap(find.text('Apple'));
    expect(tester.takeException(), isNull);
    final remove = find.ancestor(
      of: find.byIcon(Icons.close_rounded),
      matching: find.byType(IconButton),
    );
    await tester.dragUntilVisible(remove, find.byType(ListView).last, const Offset(0, -150));
    expect(tester.takeException(), isNull);
    final size = tester.getSize(remove.first);
    expect(size.height, greaterThanOrEqualTo(44));
  });
}

Finder _searchBox() => _hinted('Search foods');

Finder _hinted(String hint) =>
    find.byWidgetPredicate((w) => w is TextField && w.decoration?.hintText == hint);
