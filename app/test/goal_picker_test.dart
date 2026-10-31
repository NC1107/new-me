import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:newme/api/models.dart';
import 'package:newme/features/me/goal_advice.dart';
import 'package:newme/features/me/goal_picker_page.dart';
import 'package:newme/features/onboarding/goal_catalog.dart';
import 'package:newme/features/onboarding/steps_plan.dart';
import 'package:newme/widgets/chunky_button.dart';
import 'package:newme/widgets/mascot.dart';
import 'package:newme/widgets/page_scaffold.dart';

import 'fixtures.dart';
import 'test_support.dart';

Map<String, dynamic> _targets() =>
    (jsonDecode(File('test/contract_v8/targets.json').readAsStringSync()) as Map)['body']!
        as Map<String, dynamic>;

QuestTemplate _quest(String key, String unit, int target) => QuestTemplate.fromJson({
  'key': key,
  'title': key,
  'enabled': true,
  'target': target,
  'unit': unit,
  'points': 50,
  'position': 9,
});

Future<TestApp> _open(
  WidgetTester tester,
  QuestTemplate q, {
  Units units = Units.metric,
  bool withTargets = true,
}) async {
  final server = fullServer();
  if (withTargets) server.on('GET /api/targets', StubResponse(200, _targets()));
  final app = TestApp(tester, server, surfaceHeight: 2000);
  await app.pump(
    GoalPickerPage(quest: q, target: q.target.round(), targetAlt: null, units: units),
    key: UniqueKey(),
  );
  return app;
}

Finder _done() => find.byWidgetPredicate((w) => w is ChunkyButton && w.label == 'Done');

const _tiers = ['Casual', 'Regular', 'Serious', 'Intense'];

void main() {
  setUp(() {
    FakeStorage().install();
    Mascot.idleMotion = false;
  });

  group('the goal picker', () {
    testWidgets('water leads with the personal figure, its reason and its source', (tester) async {
      await _open(tester, _quest('water', 'ml', 2200));

      expect(find.text('Recommended for you'), findsOneWidget);
      expect(find.text('3.0 L'), findsOneWidget);
      expect(find.textContaining('adequate intake of drinks for men'), findsOneWidget);
      expect(find.text('Source: National Academies 2005'), findsOneWidget);
      // Another published figure says what it is.
      expect(find.text('EFSA: 2.5 L of total water for men, the drinks part'), findsOneWidget);
      expect(find.text('2.0 L'), findsOneWidget);
      for (final tier in _tiers) {
        expect(find.text(tier), findsNothing, reason: tier);
      }
    });

    testWidgets('choosing the recommendation hands back that number', (tester) async {
      GoalChoice? choice;
      final server = fullServer()..on('GET /api/targets', StubResponse(200, _targets()));
      final app = TestApp(tester, server, surfaceHeight: 2000);
      await app.pump(
        Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              choice = await pushPage<GoalChoice>(
                context,
                GoalPickerPage(quest: _quest('water', 'ml', 2200), target: 2200, targetAlt: null),
              );
            },
            child: const Text('Open'),
          ),
        ),
        key: UniqueKey(),
      );
      await app.tap(find.text('Open'));
      await app.tap(find.bySemanticsLabel(RegExp('^Recommended for you, 3.0 L')));
      await app.tap(find.text('DONE'));
      expect(choice?.target, 3000);
    });

    testWidgets('an imperial person reads the figures in fluid ounces', (tester) async {
      await _open(tester, _quest('water', 'ml', 2200), units: Units.imperial);
      expect(find.text('101 fl oz'), findsOneWidget);
      expect(find.text('68 fl oz'), findsOneWidget);
    });

    testWidgets('fruit and vegetables read in grams with what one serving looks like', (
      tester,
    ) async {
      await _open(tester, _quest('produce', 'servings', 5));

      expect(find.text('5 servings (400 g)'), findsOneWidget);
      expect(find.text('10 servings (800 g)'), findsOneWidget);
      expect(find.text('One serving is 80 g, for example:'), findsOneWidget);
      expect(find.text('- 3 heaped tablespoons of cooked vegetables'), findsOneWidget);
      expect(find.text('- 1 cereal bowl of salad'), findsOneWidget);
      expect(find.text('Source: WHO, NHS 5 A Day'), findsOneWidget);
    });

    testWidgets('exercise is the weekly guideline spread over the week, honestly', (tester) async {
      await _open(tester, _quest('exercise', 'minutes', 30));

      expect(find.text('22 min'), findsOneWidget);
      expect(find.textContaining('150 to 300 minutes of moderate activity a week'), findsOneWidget);
      expect(find.textContaining('rest day is fine'), findsOneWidget);
      expect(find.text('43 min'), findsOneWidget);
    });

    testWidgets('a goal with no research figure says so and offers plain numbers', (tester) async {
      await _open(tester, _quest('reading', 'minutes', 20));

      expect(find.textContaining('no research figure'), findsOneWidget);
      expect(find.text('Recommended for you'), findsNothing);
      for (final text in ['10 min', '20 min', '30 min', '45 min']) {
        expect(find.text(text), findsOneWidget, reason: text);
      }
      for (final tier in _tiers) {
        expect(find.text(tier), findsNothing, reason: tier);
      }
    });

    testWidgets('the steady bedtime window says the research names none', (tester) async {
      await _open(tester, _quest('sleep_regularity', 'min', 45));
      expect(find.textContaining('does not name a window'), findsOneWidget);
      expect(find.text('within 60 min'), findsOneWidget);
    });

    testWidgets('without a recommendation the plain numbers still work', (tester) async {
      final app = await _open(tester, _quest('steps', 'steps', 8000), withTargets: false);

      expect(find.text('Recommended for you'), findsNothing);
      expect(find.textContaining('not available yet'), findsOneWidget);
      await app.tap(find.text('10,000 steps'));
      expect(tester.widget<ChunkyButton>(_done()).onPressed, isNotNull);
    });

    testWidgets('a number of your own still replaces the choice', (tester) async {
      final app = await _open(tester, _quest('water', 'ml', 2200));
      await app.enter(find.byType(TextField).first, '2750');
      expect(tester.widget<ChunkyButton>(_done()).onPressed, isNotNull);
      await app.enter(find.byType(TextField).first, '9000');
      expect(tester.widget<ChunkyButton>(_done()).onPressed, isNull);
    });
  });

  group('goal advice', () {
    final report = TargetsReport.parse(_targets());

    test('maps each quest to its target and leaves the rest without one', () {
      expect(goalAdvice('steps', report)!.value, 7000);
      expect(goalAdvice('exercise', report)!.value, 22);
      expect(goalAdvice('water', report)!.cite, 'National Academies 2005');
      expect(goalAdvice('reading', report), isNull);
      expect(goalAdvice('yoga', report), isNull);
      expect(goalAdvice('meals_logged', report), isNull);
      expect(goalAdvice('sleep_regularity', report), isNull);
      expect(goalAdvice('steps', null), isNull);
    });

    test('a target the server could not work out gives no advice', () {
      final missing = TargetsReport.parse({
        'targets': [
          {'key': 'protein', 'unit': 'g', 'value': null},
        ],
      });
      expect(goalAdvice('protein', missing), isNull);
    });

    test('every goal with a published figure names its target, every other says why not', () {
      for (final spec in kGoalSpecs.values) {
        if (spec.questKey == 'pushups') continue;
        expect(
          spec.targetKey != null || spec.noResearch != null,
          isTrue,
          reason: '${spec.questKey} must lead with a figure or say there is none',
        );
      }
    });
  });

  group('onboarding goals', () {
    test('lead with the recommendation, its source and the grams in a serving', () {
      final goals = {
        for (final g in planGoals(
          ['water', 'produce', 'exercise', 'reading'],
          false,
          TargetsReport.parse(_targets()),
        ))
          g.key: g,
      };
      expect(goals['water']!.value, 3000);
      expect(goals['water']!.why, contains('National Academies 2005'));
      expect(goals['produce']!.label(goals['produce']!.value), '5 servings (400 g)');
      expect(goals['produce']!.extra.single, contains('3 heaped tablespoons of cooked vegetables'));
      expect(goals['exercise']!.value, 22);
      expect(goals['exercise']!.why, contains('WHO 2020'));
      expect(goals['reading']!.why, contains('no research figure'));
      expect(goals['reading']!.extra, isEmpty);
    });
  });
}
