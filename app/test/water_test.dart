import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:newme/features/onboarding/goal_catalog.dart';
import 'package:newme/features/onboarding/steps_plan.dart';
import 'package:newme/api/models.dart';
import 'package:newme/features/log/log_kind.dart';
import 'package:newme/features/log/log_sheet.dart';
import 'package:newme/features/me/targets_logic.dart';
import 'package:newme/features/today/today_screen.dart';
import 'package:newme/state/units.dart';
import 'package:newme/widgets/chunky_button.dart';
import 'package:newme/widgets/mascot.dart';
import 'package:newme/widgets/quest_copy.dart';

import 'fixtures.dart';
import 'test_support.dart';

Quest _water({num target = 3000, num actual = 1200, bool done = false}) => Quest.fromJson(
  quest('water', 'Water', {
    'unit': 'ml',
    'target': target,
    'actual': actual,
    'points': 50,
    'basePoints': done ? 50 : (50 * actual / target).round(),
    'done': done,
  }),
);

class _Opener extends StatelessWidget {
  const _Opener();

  @override
  Widget build(BuildContext context) => Center(
    child: ElevatedButton(
      onPressed: () => showLogSheet(context, kind: LogKind.water),
      child: const Text('Open'),
    ),
  );
}

StubAdapter _server() => fullServer()
  ..on('POST /api/logs', StubResponse(201, logResultJson()))
  ..on('DELETE /api/logs/77', StubResponse(200, deleteLogJson()));

Future<TestApp> _open(WidgetTester tester, {Units units = Units.metric}) async {
  final adapter = _server();
  final app = TestApp(tester, adapter);
  await app.pump(const _Opener(), overrides: [unitsProvider.overrideWithValue(units)]);
  await app.tap(find.text('Open'));
  return app;
}

Finder _save() => find.byWidgetPredicate((w) => w is ChunkyButton && w.label == 'Save');

void main() {
  setUp(() {
    FakeStorage().install();
    Mascot.idleMotion = false;
  });

  group('quest copy', () {
    test('metric reads litres with one decimal', () {
      final q = _water();
      expect(questTitle(q), 'Drink 3.0 L');
      expect(questProgress(q), '1.2 of 3.0 L');
      expect(questActualLabel(q), '1.2 L');
    });

    test('imperial reads US fluid ounces rounded', () {
      final q = _water();
      expect(questTitle(q, units: Units.imperial), 'Drink 101 fl oz');
      expect(questProgress(q, units: Units.imperial), '41 of 101 fl oz');
      expect(questActualLabel(q, units: Units.imperial), '41 fl oz');
    });

    test('nothing drunk yet has no actual label but still reads its progress', () {
      final q = _water(actual: 0);
      expect(questActualLabel(q), isNull);
      expect(questProgress(q), '0.0 of 3.0 L');
      expect(questProgress(q, units: Units.imperial), '0 of 101 fl oz');
    });

    test('water is hand-loggable, so it is not an automatic quest', () {
      expect(isAutomaticQuest('water'), isFalse);
      expect(LogKind.forQuest('water'), LogKind.water);
    });

    test('a water target reads in the person units on the Targets page', () {
      expect(formatTargetValue(2200, 'ml'), '2.2 L');
      expect(formatTargetValue(2200, 'ml', units: Units.imperial), '74 fl oz');
    });
  });

  group('Today', () {
    Map<String, dynamic> todayWithWater() {
      final today = richTodayJson(stepsEverSynced: true);
      today['quests'] = [
        ...(today['quests']! as List),
        quest('water', 'Water', {
          'unit': 'ml',
          'target': 3000,
          'actual': 1200,
          'points': 50,
          'basePoints': 20,
        }),
      ];
      return today;
    }

    testWidgets('the card reads in litres and offers a log button', (tester) async {
      final adapter = fullServer()..on('GET /api/today', StubResponse(200, todayWithWater()));
      final app = TestApp(tester, adapter, surfaceHeight: 2800);
      await app.pump(const TodayScreen());

      expect(find.text('Drink 3.0 L'), findsOneWidget);
      expect(find.text('1.2 L'), findsOneWidget);
      expect(find.bySemanticsLabel('Add entry for Drink 3.0 L'), findsOneWidget);
    });

    testWidgets('an imperial person reads fluid ounces, and + opens the water form', (
      tester,
    ) async {
      final adapter = fullServer()..on('GET /api/today', StubResponse(200, todayWithWater()));
      final app = TestApp(tester, adapter, surfaceHeight: 2800);
      await app.pump(
        const TodayScreen(),
        overrides: [unitsProvider.overrideWithValue(Units.imperial)],
      );

      expect(find.text('Drink 101 fl oz'), findsOneWidget);
      expect(find.text('41 fl oz'), findsOneWidget);

      await app.tap(find.bySemanticsLabel('Add entry for Drink 101 fl oz'));
      expect(find.text('Log water'), findsOneWidget);
      expect(find.text('+8 fl oz'), findsOneWidget);
    });
  });

  group('the water form', () {
    testWidgets('metric chips add 250 and 500 ml to the number and nothing is posted yet', (
      tester,
    ) async {
      final adapter = _server();
      final app = TestApp(tester, adapter);
      await app.pump(const _Opener(), overrides: [unitsProvider.overrideWithValue(Units.metric)]);
      await app.tap(find.text('Open'));
      final field = find.byType(TextField);
      expect(find.text('Log water'), findsOneWidget);
      expect(tester.widget<TextField>(field).controller!.text, '0');
      expect(tester.widget<ChunkyButton>(_save()).onPressed, isNull, reason: 'nothing to save yet');

      await app.tap(find.text('+500 ml'));
      expect(tester.widget<TextField>(field).controller!.text, '500');
      await app.tap(find.text('+250 ml'));
      expect(tester.widget<TextField>(field).controller!.text, '750');
      expect(adapter.to('POST /api/logs'), isEmpty);

      await app.tap(_save());
      final body = app.body('POST /api/logs');
      expect(body['kind'], 'activity');
      expect(body['type'], 'water');
      expect(body['unit'], 'ml');
      expect(body['quantity'], 750);
      expect(find.text('Log water'), findsNothing, reason: 'the sheet closes after the save');
      expect(find.text('Added 750 ml of water'), findsOneWidget);
    });

    testWidgets('imperial chips add 8 and 16 fl oz and Save posts the total in ml', (tester) async {
      final app = await _open(tester, units: Units.imperial);
      expect(find.text('+8 fl oz'), findsOneWidget);
      expect(find.text('+16 fl oz'), findsOneWidget);
      expect(find.text('+250 ml'), findsNothing);

      await app.tap(find.text('+16 fl oz'));
      await app.tap(find.text('+8 fl oz'));
      expect(tester.widget<TextField>(find.byType(TextField)).controller!.text, '24');

      await app.tap(_save());
      final body = app.body('POST /api/logs');
      expect(body['type'], 'water');
      expect(body['unit'], 'ml');
      expect(body['quantity'], 710);
      expect(find.text('Added 24 fl oz of water'), findsOneWidget);
    });

    testWidgets('a typed amount saves in ml, and the number steps by 50', (tester) async {
      final app = await _open(tester);
      final field = find.byType(TextField);

      await app.tap(find.bySemanticsLabel('More'));
      expect(tester.widget<TextField>(field).controller!.text, '50');

      await app.enter(field, '750');
      await app.tap(_save());
      expect(app.body('POST /api/logs')['quantity'], 750);
    });

    testWidgets('a chip adds on top of a typed amount', (tester) async {
      final app = await _open(tester, units: Units.imperial);
      final field = find.byType(TextField);

      await app.enter(field, '12');
      await app.tap(find.text('+8 fl oz'));
      expect(tester.widget<TextField>(field).controller!.text, '20');
      await app.tap(_save());
      expect(app.body('POST /api/logs')['quantity'], 591);
    });

    testWidgets('today so far reads against the goal in the person unit', (tester) async {
      final today = richTodayJson(stepsEverSynced: true);
      today['quests'] = [
        ...(today['quests']! as List),
        quest('water', 'Water', {
          'unit': 'ml',
          'target': 3000,
          'actual': 1200,
          'points': 50,
          'basePoints': 20,
        }),
      ];
      final adapter = _server()..on('GET /api/today', StubResponse(200, today));
      final app = TestApp(tester, adapter);
      await app.pump(const _Opener(), overrides: [unitsProvider.overrideWithValue(Units.imperial)]);
      await app.tap(find.text('Open'));
      await app.settle();

      expect(find.text('Today so far: 41 of 101 fl oz'), findsOneWidget);
    });

    testWidgets('over 5 L in one entry is refused inline', (tester) async {
      final app = await _open(tester);
      await app.enter(find.byType(TextField), '5001');
      expect(find.text('At most 5000 ml'), findsOneWidget);
      expect(tester.widget<ChunkyButton>(_save()).onPressed, isNull);

      await app.enter(find.byType(TextField), '0');
      expect(tester.widget<ChunkyButton>(_save()).onPressed, isNull);
    });

    testWidgets('chips stop adding at the 5 L cap', (tester) async {
      final app = await _open(tester);
      await app.enter(find.byType(TextField), '4800');
      await app.tap(find.text('+500 ml'));
      expect(tester.widget<TextField>(find.byType(TextField)).controller!.text, '5000');
    });

    testWidgets('more than 2 L at once asks first', (tester) async {
      final app = await _open(tester);
      await app.enter(find.byType(TextField), '2500');
      await app.tap(_save());
      expect(find.textContaining('2.5 L in one go'), findsOneWidget);
      await app.tap(find.text('Log it'));
      expect(app.body('POST /api/logs')['quantity'], 2500);
    });

    testWidgets('chips building a total over 2 L also ask first', (tester) async {
      final app = await _open(tester);
      for (var i = 0; i < 5; i++) {
        await app.tap(find.text('+500 ml'));
      }
      await app.tap(_save());
      expect(find.textContaining('2.5 L in one go'), findsOneWidget);
      await app.tap(find.text('Log it'));
      expect(app.body('POST /api/logs')['quantity'], 2500);
    });
  });

  group('onboarding', () {
    test('water is a focus of its own', () {
      expect([for (final f in kFocuses) ...f.questKeys], contains('water'));
    });

    test('the daily goal takes the target for the person and reads in their units', () {
      final report = TargetsReport.parse({
        'targets': [
          {'key': 'water', 'value': 3000, 'unit': 'ml'},
        ],
      });
      final water = planGoals(['water'], false, report, units: Units.imperial).single;
      expect(water.value, 3000);
      expect(water.label(water.value), '101 fl oz');
      expect(planGoals(['water'], false, null).single.value, 2200);
    });
  });
}
