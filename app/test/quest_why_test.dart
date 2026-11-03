import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:newme/api/models.dart';
import 'package:newme/features/today/quest_sheet.dart';
import 'package:newme/features/today/quest_why.dart';
import 'package:newme/widgets/mascot.dart';

import 'fixtures.dart';

Quest _quest(String key, {required num target, String unit = 'min', Map<String, dynamic>? extra}) =>
    Quest.fromJson(quest(key, key, {'unit': unit, 'target': target, ...?extra}));

Target _target(
  String key,
  int? value,
  String unit, {
  String why = '',
  String formula = 'The working.',
  List<String> sources = const ['zourdos2016'],
  Map<String, dynamic> details = const {},
}) => Target.tryParse({
  'key': key,
  'value': value,
  'unit': unit,
  'formula': formula,
  'why': why,
  'sources': sources,
  'label': 'guideline',
  'details': details,
})!;

TargetsReport _report(List<Target> targets) => TargetsReport(
  asOf: '2026-10-31',
  disclaimer: '',
  inputs: const [],
  targets: targets,
  sources: const {
    'zourdos2016': 'Zourdos et al., J Strength Cond Res 2016',
    'nhs5aday': 'NHS, 5 A Day portion sizes',
    'phillips2017': 'Phillips et al., Sci Rep 2017',
  },
);

QuestWhy _why(Quest q, List<Target> targets, {Units units = Units.metric}) =>
    questWhy(q, _report(targets), units)!;

void main() {
  group('push-ups', () {
    final target = _target(
      'pushups',
      27,
      'reps',
      why: 'About three quarters of your best set of 12, so each set ends with some reps left.',
      formula: '3 sets × 9 reps. Each set is 75% of your latest max of 12 push-ups.',
      details: {'sets': 3, 'repsPerSet': 9},
    );
    Quest pushups(num goal) => _quest('pushups', target: goal, unit: 'reps');

    test('leads with the recommendation in the quest unit, then the reason, then the goal', () {
      final why = _why(pushups(30), [target]);
      expect(why.recommended, 'Recommended: 27 push-ups a day, 3\u00a0sets\u00a0of\u00a09');
      expect(why.reason, startsWith('About three quarters of your best set of 12'));
      expect(why.comparison, 'Your goal is 30 push-ups, a little above the recommendation.');
      expect(why.yours, 'Yours is 30 push-ups.');
      expect(why.citation, 'Source: Zourdos et al., J Strength Cond Res 2016');
      expect(why.formula, contains('3 sets × 9 reps'));
    });

    test('says when the goal matches, is below and is far above', () {
      expect(
        _why(pushups(27), [target]).comparison,
        'Your goal is 27 push-ups, the same as the recommendation.',
      );
      expect(
        _why(pushups(25), [target]).comparison,
        'Your goal is 25 push-ups, a little below the recommendation.',
      );
      expect(
        _why(pushups(60), [target]).comparison,
        'Your goal is 60 push-ups, above the recommendation.',
      );
    });

    test('names the chosen exercise', () {
      final squats = _quest('pushups', target: 30, unit: 'reps', extra: {'exercise': 'air_squat'});
      expect(_why(squats, [target]).recommended, startsWith('Recommended: 27 squats a day'));
    });
  });

  group('every quest with a target reads in its own unit', () {
    test('steps, sleep, exercise, breathing, protein, water and produce', () {
      final cases = <(Quest, Target, String, String)>[
        (
          _quest('steps', target: 8000, unit: 'steps'),
          _target('steps', 7000, 'steps'),
          'Recommended: 7,000 steps a day',
          'Your goal is 8,000 steps, a little above the recommendation.',
        ),
        (
          _quest('sleep', target: 450),
          _target('sleep', 450, 'min'),
          'Recommended: 7 h 30 min of sleep a night',
          'Your goal is 7 h 30 min, the same as the recommendation.',
        ),
        (
          _quest('exercise', target: 30),
          _target('exercise', 22, 'min'),
          'Recommended: 22 min a day',
          'Your goal is 30 min, above the recommendation.',
        ),
        (
          _quest('breathing', target: 5),
          _target('breathing', 5, 'min'),
          'Recommended: 5 min of breathing a day',
          'Your goal is 5 min, the same as the recommendation.',
        ),
        (
          _quest('protein', target: 150, unit: 'g'),
          _target('protein', 165, 'g'),
          'Recommended: 165 g of protein a day',
          'Your goal is 150 g, a little below the recommendation.',
        ),
        (
          _quest('water', target: 2000, unit: 'ml'),
          _target('water', 3000, 'ml'),
          'Recommended: 3.0 L of drinks a day',
          'Your goal is 2.0 L, below the recommendation.',
        ),
        (
          _quest('produce', target: 5, unit: 'servings'),
          _target('produce', 5, 'servings', sources: const ['nhs5aday']),
          'Recommended: 5 servings of fruit and veg a day (400 g)',
          'Your goal is 5 servings, the same as the recommendation.',
        ),
      ];
      for (final (q, t, recommended, comparison) in cases) {
        final why = _why(q, [t]);
        expect(why.recommended, recommended, reason: q.key);
        expect(why.comparison, comparison, reason: q.key);
        expect(why.citation, startsWith('Source: '), reason: q.key);
        expect(why.formula, isNotNull, reason: q.key);
      }
    });

    test('a figure the server could not work out yet says what it needs', () {
      final why = _why(_quest('pushups', target: 30, unit: 'reps'), [
        _target('pushups', null, 'reps', formula: 'Record a max test to size it.'),
      ]);
      expect(why.recommended, isNull);
      expect(why.note, 'Record a max test to size it.');
      expect(why.formula, isNull);
    });

    test('nothing shows while the targets have not loaded', () {
      expect(questWhy(_quest('steps', target: 8000, unit: 'steps'), null, Units.metric), isNull);
    });
  });

  group('quests with no research figure', () {
    test('say so plainly and name the goal', () {
      final meals = questWhy(_quest('meals_logged', target: 3, unit: 'meals'), null, Units.metric)!;
      expect(
        meals.note,
        'No published research sets a number for this, so your goal of 3 meals is your own pick.',
      );
      expect(meals.recommended, isNull);

      final yoga = questWhy(_quest('yoga', target: 15), null, Units.metric)!;
      expect(yoga.note, contains('your goal of 15 min is your own pick'));
    });

    test('reading waits for the targets report, which derives its pages', () {
      final reading = Quest.fromJson(
        quest('reading', 'Reading', {
          'unit': 'minutes',
          'target': 20,
          'unitAlt': 'pages',
          'targetAlt': 10,
        }),
      );
      expect(questWhy(reading, null, Units.metric), isNull);
    });

    test('a steady bedtime cites the sleep regularity paper and gives no cut-off', () {
      final why = questWhy(
        _quest('sleep_regularity', target: 45),
        _report(const []),
        Units.metric,
      )!;
      expect(why.note, contains('no research gives a cut-off'));
      expect(why.citation, 'Source: Phillips et al., Sci Rep 2017');
    });
  });

  group('the section', () {
    setUp(() {
      Mascot.idleMotion = false;
    });

    testWidgets('keeps the working behind a tap', (tester) async {
      final app = TestApp(tester, fullServer(), surfaceHeight: 1200);
      await app.pump(
        const Scaffold(
          body: QuestWhySection(
            why: QuestWhy(
              recommended: 'Recommended: 27 push-ups a day, 3\u00a0sets\u00a0of\u00a09',
              comparison: 'Your goal is 30 push-ups, a little above the recommendation.',
              formula: '3 sets × 9 reps, the working.',
            ),
          ),
        ),
      );
      expect(
        find.text('Recommended: 27 push-ups a day, 3\u00a0sets\u00a0of\u00a09'),
        findsOneWidget,
      );
      expect(find.text('3 sets × 9 reps, the working.'), findsNothing);

      await app.tap(find.text('How this is worked out'));
      expect(find.text('3 sets × 9 reps, the working.'), findsOneWidget);
      expect(find.byType(QuestSheet), findsNothing);
    });
  });
}
