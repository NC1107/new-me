import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:newme/features/food/food_screen.dart';
import 'package:newme/features/log/log_sheet.dart';
import 'package:newme/features/me/food_targets_page.dart';
import 'package:newme/features/me/my_foods_page.dart';
import 'package:newme/widgets/chunky_button.dart';
import 'package:newme/widgets/mascot.dart';

import 'fixtures.dart';
import 'test_support.dart';

StubAdapter _server({List<Map<String, dynamic>>? logs}) => fullServer()
  ..on('GET /api/today', StubResponse(200, richTodayJson()..['food'] = restingFoodJson()))
  ..on('GET /api/logs', StubResponse(200, logsJson(logs ?? [logJson(), mealLogJson()])))
  ..on('DELETE /api/logs/78', StubResponse(200, deleteLogJson()))
  ..on('POST /api/logs', StubResponse(201, logResultJson()));

Finder _chunky(String label) =>
    find.byWidgetPredicate((w) => w is ChunkyButton && w.label == label);

void main() {
  setUp(() {
    FakeStorage().install();
    Mascot.idleMotion = false;
  });

  testWidgets('shows the title, the food card, today\'s meals and the food rows', (tester) async {
    final adapter = _server();
    final app = TestApp(tester, adapter, surfaceHeight: 2000);
    await app.pump(const FoodScreen());

    expect(find.text('Food'), findsOneWidget);
    expect(find.text('1,850 of 2,200 kcal'), findsOneWidget);
    expect(find.text('350 left'), findsOneWidget);
    expect(find.textContaining('burned in activity'), findsNothing);
    expect(find.text('+'), findsNothing, reason: 'the card has no add button any more');
    expect(find.text('Set your targets'), findsNothing);

    expect(_chunky('Log a meal'), findsOneWidget);
    expect(find.text('Meals today'), findsOneWidget);
    expect(find.text('Chicken bowl'), findsOneWidget);
    expect(find.textContaining('600 kcal'), findsOneWidget);
    expect(find.byTooltip('Delete Chicken bowl'), findsOneWidget);
    expect(find.text('Push-ups'), findsNothing, reason: 'only meals are listed');
    expect(adapter.to('GET /api/logs').single.queryParameters, {'date': '2026-10-26'});

    expect(find.text('Food targets'), findsOneWidget);
    expect(find.text('2,200 kcal a day'), findsOneWidget);
    expect(find.text('My foods'), findsOneWidget);
  });

  testWidgets('the activity line appears once something was burned', (tester) async {
    final app = TestApp(tester, fullServer(), surfaceHeight: 2000);
    await app.pump(const FoodScreen());
    expect(find.text('540 kcal burned in activity'), findsOneWidget);
  });

  testWidgets('over the target the header counts what is over', (tester) async {
    final today = richTodayJson();
    today['food'] = {...restingFoodJson(), 'kcal': 2450};
    final adapter = _server()..on('GET /api/today', StubResponse(200, today));
    final app = TestApp(tester, adapter, surfaceHeight: 2000);
    await app.pump(const FoodScreen());
    expect(find.text('2,450 of 2,200 kcal'), findsOneWidget);
    expect(find.text('250 over'), findsOneWidget);
  });

  testWidgets('with no meals it says so', (tester) async {
    final app = TestApp(tester, _server(logs: [logJson()]), surfaceHeight: 2000);
    await app.pump(const FoodScreen());
    expect(find.text('Nothing logged yet today.'), findsOneWidget);
  });

  testWidgets('Log a meal opens the meal form', (tester) async {
    final app = TestApp(tester, _server(), surfaceHeight: 2000);
    await app.pump(const FoodScreen());

    await app.tap(_chunky('Log a meal'));
    expect(find.byType(LogSheet), findsOneWidget);
    expect(find.text('Portion'), findsOneWidget);
    final search = find.ancestor(of: find.text('Search foods'), matching: find.byType(TextField));
    expect(tester.widget<TextField>(search).focusNode?.hasFocus, isTrue);
  });

  testWidgets('deleting a meal calls DELETE and offers an Undo that logs it again', (tester) async {
    final adapter = _server();
    final app = TestApp(tester, adapter, surfaceHeight: 2000);
    await app.pump(const FoodScreen());

    await app.tap(find.byTooltip('Delete Chicken bowl'));
    expect(adapter.to('DELETE /api/logs/78'), hasLength(1));
    expect(find.text('Deleted Chicken bowl'), findsOneWidget);
    expect(find.text('Undo'), findsOneWidget);

    await app.tap(find.text('Undo'));
    final repost = app.body('POST /api/logs');
    expect(repost['kind'], 'meal');
    expect(repost['name'], 'Chicken bowl');
    expect(repost['kcal'], 600);
    expect(repost['clientOpId'], isNot(isEmpty));
  });

  testWidgets('a failed delete says why and offers no Undo', (tester) async {
    final adapter = _server()..on('DELETE /api/logs/78', const StubResponse.unreachable());
    final app = TestApp(tester, adapter, surfaceHeight: 2000);
    await app.pump(const FoodScreen());

    await app.tap(find.byTooltip('Delete Chicken bowl'));
    expect(find.textContaining('You are offline'), findsOneWidget);
    expect(find.text('Undo'), findsNothing);
    expect(find.text('Chicken bowl'), findsOneWidget);
  });

  testWidgets('the delete button and rows are at least 44pt', (tester) async {
    final handle = tester.ensureSemantics();
    final app = TestApp(tester, _server(), surfaceHeight: 2000);
    await app.pump(const FoodScreen());

    final delete = tester.getSize(find.byTooltip('Delete Chicken bowl'));
    expect(delete.width, greaterThanOrEqualTo(44));
    expect(delete.height, greaterThanOrEqualTo(44));
    for (final label in [
      'Food targets, 2,200 kcal a day',
      'My foods, Saved foods with exact numbers',
    ]) {
      final row = find.bySemanticsLabel(label);
      expect(row, findsOneWidget, reason: label);
      expect(tester.getSize(row).height, greaterThanOrEqualTo(44), reason: label);
    }
    handle.dispose();
  });

  testWidgets('the food rows open their pages', (tester) async {
    final app = TestApp(tester, _server(), surfaceHeight: 2000);
    await app.pump(const FoodScreen());

    await app.tap(find.text('Food targets'));
    expect(find.byType(FoodTargetsPage), findsOneWidget);
    await app.tap(find.byTooltip('Back'));

    await app.tap(find.text('My foods'));
    expect(find.byType(MyFoodsPage), findsOneWidget);
  });
}
