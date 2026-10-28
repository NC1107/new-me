import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:newme/api/models.dart';
import 'package:newme/features/food/food_screen.dart';
import 'package:newme/features/food/meal_actions.dart';
import 'package:newme/features/today/day_detail_sheet.dart';
import 'package:newme/widgets/chunky_button.dart';
import 'package:newme/widgets/mascot.dart';

import 'fixtures.dart';
import 'hit_targets.dart';
import 'test_support.dart';

Map<String, dynamic> _patched([Map<String, dynamic>? meal]) => {
  'log': meal ?? mealLogJson(),
  'day': logResultJson()['day'],
};

StubAdapter _server({List<Map<String, dynamic>>? logs}) => fullServer()
  ..on('GET /api/today', StubResponse(200, richTodayJson()..['food'] = restingFoodJson()))
  ..on('GET /api/logs', StubResponse(200, logsJson(logs ?? [mealLogJson()])))
  ..on('PATCH /api/logs/78', StubResponse(200, _patched()))
  ..on('DELETE /api/logs/78', StubResponse(200, deleteLogJson()))
  ..on('POST /api/logs', StubResponse(201, logResultJson()));

Finder _chunky(String label) =>
    find.byWidgetPredicate((w) => w is ChunkyButton && w.label == label);

bool _saveEnabled(WidgetTester tester) =>
    tester.widget<ChunkyButton>(_chunky('Save')).onPressed != null;

Future<TestApp> _openFromFood(WidgetTester tester, StubAdapter adapter) async {
  final app = TestApp(tester, adapter, surfaceHeight: 2000);
  await app.pump(const FoodScreen());
  await app.tap(find.text('Chicken bowl'));
  return app;
}

void main() {
  setUp(() {
    FakeStorage().install();
    Mascot.idleMotion = false;
  });

  testWidgets('tapping a meal opens "Edit meal" with its numbers filled in', (tester) async {
    await _openFromFood(tester, _server());

    expect(find.text('Edit meal'), findsOneWidget);
    for (final value in ['Chicken bowl', '600', '40', '60', '20', '5']) {
      expect(fieldWith(value), findsOneWidget, reason: value);
    }
    expect(find.text('0.5x'), findsOneWidget);
    expect(find.text('1.5x'), findsOneWidget);
    expect(find.text('2x'), findsOneWidget);
    expect(find.text('Delete meal'), findsOneWidget);
    expect(_saveEnabled(tester), isFalse, reason: 'nothing changed yet');
  });

  testWidgets('a scale chip multiplies every number and a second tap undoes it', (tester) async {
    final app = await _openFromFood(tester, _server());

    await app.tap(find.text('2x'));
    for (final value in ['1200', '80', '120', '40', '10']) {
      expect(fieldWith(value), findsOneWidget, reason: value);
    }

    await app.tap(find.text('0.5x'));
    for (final value in ['300', '20', '30', '10', '2.5']) {
      expect(fieldWith(value), findsOneWidget, reason: value);
    }

    await app.tap(find.text('0.5x'));
    expect(fieldWith('600'), findsOneWidget);
    expect(_saveEnabled(tester), isFalse);
  });

  testWidgets('scaling past the calorie cap refuses to save', (tester) async {
    final adapter = _server(logs: [mealLogJson()..['kcal'] = 6000]);
    final app = await _openFromFood(tester, adapter);

    await app.tap(find.text('2x'));
    expect(find.text('At most 10,000 kcal'), findsOneWidget);
    expect(_saveEnabled(tester), isFalse);
  });

  testWidgets('saving sends only the changed fields, refreshes and confirms', (tester) async {
    final adapter = _server();
    final app = await _openFromFood(tester, adapter);
    final todayLoads = adapter.to('GET /api/today').length;
    final mealLoads = adapter.to('GET /api/logs').length;

    await app.enter(fieldWith('600'), '700');
    expect(_saveEnabled(tester), isTrue);
    await app.tap(_chunky('Save'));

    expect(app.body('PATCH /api/logs/78'), {'kcal': 700});
    expect(find.text('Edit meal'), findsNothing);
    expect(find.text('Updated Chicken bowl'), findsOneWidget);
    expect(adapter.to('GET /api/today').length, greaterThan(todayLoads));
    expect(adapter.to('GET /api/logs').length, greaterThan(mealLoads));
  });

  testWidgets('a rename alone is sent, and the snack bar uses the new name', (tester) async {
    final adapter = _server();
    final app = await _openFromFood(tester, adapter);

    await app.enter(fieldWith('Chicken bowl'), '  Chicken wrap ');
    await app.tap(_chunky('Save'));

    expect(app.body('PATCH /api/logs/78'), {'name': 'Chicken wrap'});
    expect(find.text('Updated Chicken wrap'), findsOneWidget);
  });

  testWidgets('a scaled save sends every number it moved', (tester) async {
    final adapter = _server();
    final app = await _openFromFood(tester, adapter);

    await app.tap(find.text('1.5x'));
    await app.tap(_chunky('Save'));

    expect(app.body('PATCH /api/logs/78'), {
      'kcal': 900,
      'protein': 60,
      'carbs': 90,
      'fat': 30,
      'fiber': 7.5,
    });
  });

  testWidgets('a failed save says why, keeps the sheet and offers Try again', (tester) async {
    final adapter = _server()..on('PATCH /api/logs/78', const StubResponse.unreachable());
    final app = await _openFromFood(tester, adapter);

    await app.enter(fieldWith('600'), '700');
    await app.tap(_chunky('Save'));

    expect(find.textContaining('You are offline'), findsOneWidget);
    expect(find.text('Edit meal'), findsOneWidget);
    expect(fieldWith('700'), findsOneWidget);
    expect(_chunky('Try again'), findsOneWidget);
    expect(find.textContaining('Updated'), findsNothing);
  });

  testWidgets('a day that closed meanwhile is explained', (tester) async {
    final adapter = _server()
      ..on(
        'PATCH /api/logs/78',
        const StubResponse(422, {'error': 'that day is closed for entries', 'code': 'date_closed'}),
      );
    final app = await _openFromFood(tester, adapter);

    await app.enter(fieldWith('600'), '700');
    await app.tap(_chunky('Save'));

    expect(find.text('That day is closed, so this meal can no longer be edited.'), findsOneWidget);
    expect(find.text('Edit meal'), findsOneWidget);
  });

  testWidgets('a meal on a closed day is read-only with the reason', (tester) async {
    final closed = mealLogJson()..['localDate'] = '2026-10-24';
    final app = await _openFromFood(tester, _server(logs: [closed]));

    expect(find.text('Meal'), findsOneWidget);
    expect(find.text('Edit meal'), findsNothing);
    expect(find.byType(TextField), findsNothing);
    expect(find.text('600 kcal'), findsOneWidget);
    expect(find.text('40 g'), findsOneWidget);
    expect(find.text('This day is closed, so its meals can no longer be changed.'), findsOneWidget);
    expect(find.text('Delete meal'), findsNothing);
    expect(_chunky('Save'), findsNothing);

    await app.tap(_chunky('Done'));
    expect(find.text('Meal'), findsNothing);
  });

  testWidgets('Delete in the editor deletes the meal and offers Undo', (tester) async {
    final adapter = _server();
    final app = await _openFromFood(tester, adapter);

    await app.tap(find.text('Delete meal'));
    expect(adapter.to('DELETE /api/logs/78'), hasLength(1));
    expect(find.text('Edit meal'), findsNothing);
    expect(find.text('Deleted Chicken bowl'), findsOneWidget);

    await app.tap(find.text('Undo'));
    expect(app.body('POST /api/logs')['name'], 'Chicken bowl');
  });

  testWidgets('at text scale 2.0 nothing overflows and every target is 44pt', (tester) async {
    tester.platformDispatcher.textScaleFactorTestValue = 2.0;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final app = await _openFromFood(tester, _server());

    expect(tester.takeException(), isNull);
    await app.tap(find.text('2x'));
    expect(tester.takeException(), isNull);
    expect(smallTargets(tester), isEmpty);
  });

  testWidgets('the meal row stays a 44pt target', (tester) async {
    final handle = tester.ensureSemantics();
    final app = TestApp(tester, _server(), surfaceHeight: 2000);
    await app.pump(const FoodScreen());

    final row = find.bySemanticsLabel(RegExp('^Chicken bowl, 600 kcal'));
    expect(row, findsOneWidget);
    expect(
      tester
          .getSize(
            find.ancestor(of: find.text('Chicken bowl'), matching: find.byType(InkWell)).first,
          )
          .height,
      greaterThanOrEqualTo(44),
    );
    handle.dispose();
  });

  testWidgets('Today\'s entries opens the editor for a meal and reloads after a save', (
    tester,
  ) async {
    final adapter = _server();
    final app = TestApp(tester, adapter);
    await app.pump(
      Builder(
        builder: (context) => TextButton(
          onPressed: () => showDayDetailSheet(context, date: '2026-10-26'),
          child: const Text('open entries'),
        ),
      ),
    );
    await app.tap(find.text('open entries'));
    final loads = adapter.to('GET /api/logs').length;

    await app.tap(find.text('Chicken bowl'));
    expect(find.text('Edit meal'), findsOneWidget);
    await app.enter(fieldWith('600'), '650');
    await app.tap(_chunky('Save'));

    expect(app.body('PATCH /api/logs/78'), {'kcal': 650});
    expect(find.text('Updated Chicken bowl'), findsOneWidget);
    expect(adapter.to('GET /api/logs').length, greaterThan(loads));
    expect(find.text("Today's entries"), findsOneWidget);
  });

  group('mealIsEditable', () {
    final meal = MealLog.fromJson(mealLogJson()..['localDate'] = '2026-10-25');
    final until = DateTime.utc(2026, 10, 26, 15);

    test('today always, yesterday only inside the grace window', () {
      final today = MealLog.fromJson(mealLogJson());
      bool editable(MealLog m, DateTime now, {DateTime? backdate}) =>
          mealIsEditable(meal: m, localToday: '2026-10-26', backdateUntil: backdate, now: now);
      expect(editable(today, until), isTrue);
      expect(editable(meal, DateTime.utc(2026, 10, 26, 14), backdate: until), isTrue);
      expect(editable(meal, until, backdate: until), isFalse);
      expect(editable(meal, DateTime.utc(2026, 10, 26, 14)), isFalse);
      expect(
        editable(
          MealLog.fromJson(mealLogJson()..['localDate'] = '2026-10-24'),
          DateTime.utc(2026, 10, 26, 14),
          backdate: until,
        ),
        isFalse,
      );
    });

    test('without Today loaded the server decides', () {
      expect(mealIsEditable(meal: meal, localToday: null, backdateUntil: null, now: until), isTrue);
    });
  });
}
