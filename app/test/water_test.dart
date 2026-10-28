import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
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
      expect(find.text('8 fl oz'), findsOneWidget);
    });
  });

  group('the water form', () {
    testWidgets('metric offers 250 and 500 ml and a chip posts that many ml at once', (
      tester,
    ) async {
      final app = await _open(tester);
      expect(find.text('Log water'), findsOneWidget);
      expect(find.text('250 ml'), findsOneWidget);
      expect(find.text('500 ml'), findsOneWidget);

      await app.tap(find.text('500 ml'));
      final body = app.body('POST /api/logs');
      expect(body['kind'], 'activity');
      expect(body['type'], 'water');
      expect(body['unit'], 'ml');
      expect(body['quantity'], 500);
      expect(find.text('Log water'), findsNothing, reason: 'the sheet closes after the save');
      expect(find.text('Added 500 ml of water'), findsOneWidget);
    });

    testWidgets('imperial chips are 8 and 16 fl oz and post their size in ml', (tester) async {
      final app = await _open(tester, units: Units.imperial);
      expect(find.text('8 fl oz'), findsOneWidget);
      expect(find.text('16 fl oz'), findsOneWidget);
      expect(find.text('250 ml'), findsNothing);

      await app.tap(find.text('16 fl oz'));
      final body = app.body('POST /api/logs');
      expect(body['type'], 'water');
      expect(body['unit'], 'ml');
      expect(body['quantity'], 473);
      expect(find.text('Added 16 fl oz of water'), findsOneWidget);
    });

    testWidgets('a typed amount saves in ml, and the number steps by 50', (tester) async {
      final app = await _open(tester);
      final field = find.byType(TextField);
      expect(tester.widget<TextField>(field).controller!.text, '250');

      await app.tap(find.bySemanticsLabel('More'));
      expect(tester.widget<TextField>(field).controller!.text, '300');

      await app.enter(field, '750');
      await app.tap(_save());
      expect(app.body('POST /api/logs')['quantity'], 750);
    });

    testWidgets('a typed imperial amount converts to ml', (tester) async {
      final app = await _open(tester, units: Units.imperial);
      final field = find.byType(TextField);
      expect(tester.widget<TextField>(field).controller!.text, '8');

      await app.enter(field, '12');
      await app.tap(_save());
      expect(app.body('POST /api/logs')['quantity'], 355);
    });

    testWidgets('over 5 L in one entry is refused inline', (tester) async {
      final app = await _open(tester);
      await app.enter(find.byType(TextField), '5001');
      expect(find.text('At most 5000 ml'), findsOneWidget);
      expect(tester.widget<ChunkyButton>(_save()).onPressed, isNull);

      await app.enter(find.byType(TextField), '0');
      expect(tester.widget<ChunkyButton>(_save()).onPressed, isNull);
    });

    testWidgets('more than 2 L at once asks first', (tester) async {
      final app = await _open(tester);
      await app.enter(find.byType(TextField), '2500');
      await app.tap(_save());
      expect(find.textContaining('2.5 L in one go'), findsOneWidget);
      await app.tap(find.text('Log it'));
      expect(app.body('POST /api/logs')['quantity'], 2500);
    });
  });
}
