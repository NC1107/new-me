import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:newme/api/models.dart';
import 'package:newme/features/breathing/breathing_pace.dart';
import 'package:newme/features/insights/sleep_insight_screen.dart';
import 'package:newme/features/log/log_kind.dart';
import 'package:newme/features/log/log_sheet.dart';
import 'package:newme/features/log/produce_pane.dart';
import 'package:newme/features/me/goal_picker_page.dart';
import 'package:newme/features/me/targets_logic.dart';
import 'package:newme/features/onboarding/goal_catalog.dart';
import 'package:newme/features/onboarding/steps_plan.dart';
import 'package:newme/features/today/today_screen.dart';
import 'package:newme/theme/quest_style.dart';
import 'package:newme/widgets/chunky_button.dart';
import 'package:newme/widgets/mascot.dart';
import 'package:newme/widgets/quest_copy.dart';

import 'fixtures.dart';
import 'hit_targets.dart';
import 'test_support.dart';

Quest _produce({num actual = 3, bool done = false}) => Quest.fromJson(
  quest('produce', 'Fruit and vegetables', {
    'unit': 'servings',
    'target': 5,
    'actual': actual,
    'points': 50,
    'basePoints': done ? 50 : (50 * actual / 5).round(),
    'done': done,
  }),
);

Quest _breathing({num actual = 2, bool done = false}) => Quest.fromJson(
  quest('breathing', 'Breathing', {
    'unit': 'min',
    'target': 5,
    'actual': actual,
    'points': 50,
    'basePoints': done ? 50 : (50 * actual / 5).round(),
    'done': done,
  }),
);

Map<String, dynamic> _measuredDetail({int bedOffset = 30, int wakeOffset = -15}) => {
  'measurable': true,
  'baselineNights': 7,
  'windowMin': 45,
  'bedMedian': 22 * 60 + 30,
  'wakeMedian': 6 * 60 + 30,
  'bedOffset': bedOffset,
  'wakeOffset': wakeOffset,
  'bedOk': bedOffset.abs() <= 45,
  'wakeOk': wakeOffset.abs() <= 45,
};

Quest _steady({int actual = 2, Map<String, dynamic>? detail, bool done = false}) => Quest.fromJson(
  quest('sleep_regularity', 'Steady bedtime', {
    'unit': 'min',
    'target': 45,
    'actual': actual,
    'points': 50,
    'basePoints': 25 * actual,
    'done': done,
    'detail': detail ?? _measuredDetail(),
  }),
);

class _Opener extends StatelessWidget {
  const _Opener(this.kind);

  final LogKind kind;

  @override
  Widget build(BuildContext context) => Center(
    child: ElevatedButton(
      onPressed: () => showLogSheet(context, kind: kind),
      child: const Text('Open'),
    ),
  );
}

StubAdapter _server() => fullServer()
  ..on('POST /api/logs', StubResponse(201, logResultJson()))
  ..on('DELETE /api/logs/77', StubResponse(200, deleteLogJson()));

Future<TestApp> _open(WidgetTester tester, LogKind kind) async {
  final app = TestApp(tester, _server());
  await app.pump(_Opener(kind));
  await app.tap(find.text('Open'));
  return app;
}

/// Starts the session and lets its first frame pass, so the clock reads zero.
Future<void> _begin(WidgetTester tester) async {
  await tester.tap(_chunky('Begin'));
  await tester.pump();
  await tester.pump();
}

/// Controls under 44pt, leaving out the test's own Open button that sits under the sheet.
List<String> _small(WidgetTester tester) =>
    smallTargets(tester).where((s) => !s.startsWith('[Open]')).toList();

Finder _chunky(String label) =>
    find.byWidgetPredicate((w) => w is ChunkyButton && w.label == label);

void main() {
  setUp(() {
    FakeStorage().install();
    Mascot.idleMotion = false;
  });

  group('quest copy', () {
    test('fruit and vegetables reads servings', () {
      final q = _produce();
      expect(questTitle(q), 'Eat 5 a day');
      expect(questProgress(q), '3 of 5 servings of fruit and veg');
      expect(titleStatesTarget(q), isFalse);
      expect(isAutomaticQuest('produce'), isFalse);
      expect(LogKind.forQuest('produce'), LogKind.produce);
    });

    test('breathing reads minutes and can be logged by hand', () {
      final q = _breathing();
      expect(questTitle(q), 'Breathe 5 min');
      expect(questProgress(q), '2 of 5 min');
      expect(questActualLabel(q), '2 min');
      expect(isAutomaticQuest('breathing'), isFalse);
      expect(LogKind.forQuest('breathing'), LogKind.breathing);
    });

    test('a steady bedtime is fed by Health, so it has no log button', () {
      final q = _steady();
      expect(questTitle(q), 'Keep a steady bedtime');
      expect(isAutomaticQuest('sleep_regularity'), isTrue);
      expect(LogKind.forQuest('sleep_regularity'), isNull);
    });

    test('the steady bedtime shows the night against the usual times', () {
      final lines = steadyBedtimeLines(_steady());
      expect(lines.map((l) => l.ok), [true, true]);
      expect(lines[0].text, contains('11:00'));
      expect(lines[0].text, contains('30 min later than usual'));
      expect(lines[0].text, contains('10:30'));
      expect(lines[1].text, contains('15 min earlier than usual'));
      expect(steadyBedtimeProgress(_steady()), 'Bed and wake time both within 45 min of usual');

      final late = _steady(actual: 1, detail: _measuredDetail(bedOffset: 90));
      expect(steadyBedtimeLines(late).map((l) => l.ok), [false, true]);
      expect(steadyBedtimeProgress(late), 'One of bed and wake time within 45 min of usual');
      expect(
        steadyBedtimeProgress(
          _steady(actual: 0, detail: _measuredDetail(bedOffset: 90, wakeOffset: 80)),
        ),
        'Neither within 45 min of usual',
      );
    });

    test('before a routine exists it says what it is waiting for', () {
      final learning = _steady(
        actual: 0,
        detail: {'measurable': false, 'baselineNights': 1, 'minBaseline': 3},
      );
      expect(steadyBedtimeLines(learning), isEmpty);
      expect(steadyBedtimeProgress(learning), 'Learning your usual times: 1 of 3 nights');
      final noNight = _steady(
        actual: 0,
        detail: {'measurable': false, 'baselineNights': 5, 'minBaseline': 3},
      );
      expect(steadyBedtimeProgress(noNight), 'No sleep recorded');
    });

    test('each quest has its own colour and icon', () {
      for (final key in ['sleep_regularity', 'produce', 'breathing']) {
        expect(questIcon(key), isNot(Icons.star_rounded), reason: key);
      }
    });

    test('Targets lists the two guideline targets and their notes', () {
      expect(targetName('produce'), 'Fruit and vegetables');
      expect(targetName('breathing'), 'Breathing');
      expect(formatTargetValue(5, 'servings'), '5 servings');
      expect(formatTargetValue(5, 'min'), '5 min');
      expect(kTargetGroups.map((g) => g.title), containsAll(['Fruit and vegetables', 'Breathing']));
    });
  });

  group('the breathing pace', () {
    test('cyclic sighing is two inhales then a long exhale', () {
      const pace = kCyclicSighing;
      expect(pace.cycleSeconds, 8);
      expect(pace.at(Duration.zero).step.phase, BreathPhase.inhale);
      expect(pace.at(const Duration(milliseconds: 2500)).step.phase, BreathPhase.topUp);
      expect(pace.at(const Duration(seconds: 3)).step.phase, BreathPhase.exhale);
      expect(pace.at(const Duration(milliseconds: 7999)).step.phase, BreathPhase.exhale);
      expect(pace.at(const Duration(seconds: 8)).step.phase, BreathPhase.inhale);
      expect(pace.at(const Duration(seconds: 8)).breaths, 1);
      final exhale = kCyclicSighing.steps.last.seconds;
      final inhales = kCyclicSighing.steps.take(2).fold(0, (s, x) => s + x.seconds);
      expect(exhale, greaterThan(inhales));
    });

    test('slow breathing is six breaths a minute', () {
      expect(kSlowBreathing.breathsPerMinute, 6);
      expect(kSlowBreathing.at(const Duration(seconds: 5)).step.phase, BreathPhase.exhale);
    });

    test('the pacer grows on the way in and shrinks on the way out', () {
      final start = kSlowBreathing.at(Duration.zero).scale;
      final top = kSlowBreathing.at(const Duration(milliseconds: 4999)).scale;
      final end = kSlowBreathing.at(const Duration(milliseconds: 9999)).scale;
      expect(start, closeTo(0.5, 0.001));
      expect(top, closeTo(1, 0.01));
      expect(end, closeTo(0.5, 0.01));
      expect(kSlowBreathing.at(const Duration(milliseconds: 2500)).scale, closeTo(0.75, 0.01));
    });

    test('the counts go down to one', () {
      expect(kCyclicSighing.at(const Duration(seconds: 3)).secondsLeft, 5);
      expect(kCyclicSighing.at(const Duration(milliseconds: 7500)).secondsLeft, 1);
    });

    test('the session is five minutes', () {
      expect(kBreathingSession, const Duration(minutes: 5));
      expect(clockText(const Duration(seconds: 272)), '4:32');
    });
  });

  group('the fruit and vegetables form', () {
    testWidgets('one tap adds a serving at once', (tester) async {
      final app = await _open(tester, LogKind.produce);
      expect(find.text('Log fruit and vegetables'), findsOneWidget);
      await app.tap(_chunky('Add 1 serving'));
      final body = app.body('POST /api/logs');
      expect(body['kind'], 'activity');
      expect(body['type'], 'produce');
      expect(body['unit'], 'servings');
      expect(body['quantity'], 1);
      expect(find.text('Added 1 serving of fruit and veg'), findsOneWidget);
    });

    testWidgets('a chip adds several', (tester) async {
      final app = await _open(tester, LogKind.produce);
      await app.tap(find.bySemanticsLabel('Add 3 servings'));
      expect(app.body('POST /api/logs')['quantity'], 3);
      expect(find.text('Added 3 servings of fruit and veg'), findsOneWidget);
    });

    testWidgets('it lists what one serving is, from the NHS guide', (tester) async {
      await _open(tester, LogKind.produce);
      expect(find.text('One serving is about 80 g'), findsOneWidget);
      for (final line in kServingExamples) {
        expect(find.text(line), findsOneWidget, reason: line);
      }
      expect(find.textContaining('NHS 5 A Day'), findsOneWidget);
    });
  });

  group('the breathing form', () {
    testWidgets('typed minutes save as a breathing entry', (tester) async {
      final app = await _open(tester, LogKind.breathing);
      expect(find.text('Breathe'), findsWidgets);
      final field = find.byType(TextField);
      expect(tester.widget<TextField>(field).controller!.text, '5');
      await app.enter(field, '12');
      await app.tap(_chunky('Save'));
      final body = app.body('POST /api/logs');
      expect(body['type'], 'breathing');
      expect(body['unit'], 'minutes');
      expect(body['quantity'], 12);
      expect(find.text('Added 12 minutes of breathing'), findsOneWidget);
    });

    testWidgets('more than two hours in one entry is refused inline', (tester) async {
      final app = await _open(tester, LogKind.breathing);
      await app.enter(find.byType(TextField), '121');
      expect(find.text('At most 120 minutes'), findsOneWidget);
      expect(tester.widget<ChunkyButton>(_chunky('Save')).onPressed, isNull);
    });

    testWidgets('a finished session logs its five minutes', (tester) async {
      final app = await _open(tester, LogKind.breathing);
      await app.tap(_chunky('Start 5-minute session'));
      expect(find.text('Cyclic sighing'), findsWidgets);
      await _begin(tester);
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('Breathe in through your nose'), findsOneWidget);

      await tester.pump(const Duration(milliseconds: 2400));
      expect(find.text('A second sip of air on top'), findsOneWidget);
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('Long breath out through your mouth'), findsOneWidget);

      await tester.pump(const Duration(minutes: 5));
      expect(find.text('Well done'), findsOneWidget);
      await app.tap(_chunky('Log 5 min'));
      await app.settle(10);
      final body = app.body('POST /api/logs');
      expect(body['type'], 'breathing');
      expect(body['quantity'], 5);
      expect(find.text('Added 5 minutes of breathing'), findsOneWidget);
    });

    testWidgets('slow breathing runs at its own pace', (tester) async {
      final app = await _open(tester, LogKind.breathing);
      await app.tap(find.bySemanticsLabel('Slow breathing'));
      expect(find.textContaining('about 6 breaths a minute'), findsOneWidget);
      await app.tap(_chunky('Start 5-minute session'));
      await app.tap(_chunky('Begin'));
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 4));
      expect(find.text('Long breath out through your mouth'), findsOneWidget);
    });

    testWidgets('the time left counts down once a second', (tester) async {
      final app = await _open(tester, LogKind.breathing);
      await app.tap(_chunky('Start 5-minute session'));
      await _begin(tester);
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('4:59 left'), findsOneWidget);
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('4:58 left'), findsOneWidget);
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('4:57 left'), findsOneWidget);
    });

    testWidgets('ending inside the first minute logs nothing', (tester) async {
      final app = await _open(tester, LogKind.breathing);
      await app.tap(_chunky('Start 5-minute session'));
      await app.tap(_chunky('Begin'));
      await tester.pump(const Duration(seconds: 20));
      await app.tap(find.byTooltip('End session'));
      await app.settle(10);
      expect(app.adapter.to('POST /api/logs'), isEmpty);
      expect(find.text('Breathe'), findsWidgets);
    });

    testWidgets('pausing holds the clock, and ending after a minute logs the whole minutes', (
      tester,
    ) async {
      final app = await _open(tester, LogKind.breathing);
      await app.tap(_chunky('Start 5-minute session'));
      await _begin(tester);
      await tester.pump(const Duration(seconds: 100));
      await app.tap(_chunky('Pause'));
      expect(find.text('Paused'), findsOneWidget);
      expect(find.text('3:20 left'), findsOneWidget);
      await tester.pump(const Duration(minutes: 3));
      expect(find.text('3:20 left'), findsOneWidget);

      await app.tap(_chunky('Resume'));
      await tester.pump(const Duration(seconds: 1));
      await app.tap(_chunky('Pause'));
      await app.tap(_chunky('End and log 1 min'));
      await app.settle(10);
      expect(app.body('POST /api/logs')['quantity'], 1);
    });

    testWidgets('with reduced motion the circle holds still and the words carry the breath', (
      tester,
    ) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue = const FakeAccessibilityFeatures(
        disableAnimations: true,
      );
      addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
      final app = await _open(tester, LogKind.breathing);
      await app.tap(_chunky('Start 5-minute session'));
      await app.tap(_chunky('Begin'));
      Size circle() =>
          tester.getSize(find.ancestor(of: find.text('In'), matching: find.byType(SizedBox)).first);
      await tester.pump(const Duration(milliseconds: 100));
      final first = circle();
      await tester.pump(const Duration(milliseconds: 1000));
      expect(circle(), first);
      expect(find.text('Breathe in through your nose'), findsOneWidget);
    });

    testWidgets('the cue is a live region for VoiceOver', (tester) async {
      final handle = tester.ensureSemantics();
      final app = await _open(tester, LogKind.breathing);
      await app.tap(_chunky('Start 5-minute session'));
      await app.tap(_chunky('Begin'));
      await tester.pump(const Duration(milliseconds: 100));
      final node = tester.getSemantics(find.text('Breathe in through your nose'));
      expect(node.flagsCollection.isLiveRegion, isTrue);
      handle.dispose();
    });

    testWidgets('the session page fits at text scale 2.0 with 44pt targets', (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = 2.0;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final app = await _open(tester, LogKind.breathing);
      expect(tester.takeException(), isNull);
      expect(_small(tester), isEmpty);
      await app.tap(_chunky('Start 5-minute session'));
      expect(tester.takeException(), isNull);
      expect(_small(tester), isEmpty);
      await app.tap(_chunky('Begin'));
      await tester.pump(const Duration(seconds: 3));
      expect(tester.takeException(), isNull);
      expect(_small(tester), isEmpty);
    });
  });

  group('forms at large text', () {
    for (final kind in [LogKind.produce, LogKind.breathing]) {
      testWidgets('${kind.label} fits at text scale 2.0 with 44pt targets', (tester) async {
        tester.platformDispatcher.textScaleFactorTestValue = 2.0;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        await _open(tester, kind);
        expect(tester.takeException(), isNull);
        expect(_small(tester), isEmpty);
      });
    }
  });

  group('Today', () {
    Map<String, dynamic> todayWith(List<Quest> quests) {
      final today = richTodayJson(stepsEverSynced: true);
      today['quests'] = [...(today['quests']! as List), for (final q in quests) q.toJson()];
      return today;
    }

    testWidgets('the steady bedtime card shows the night against the usual times', (tester) async {
      final adapter = fullServer()..on('GET /api/today', StubResponse(200, todayWith([_steady()])));
      final app = TestApp(tester, adapter, surfaceHeight: 3000);
      await app.pump(const TodayScreen());
      expect(find.text('Keep a steady bedtime'), findsOneWidget);
      expect(find.text('Bed and wake time both within 45 min of usual'), findsOneWidget);
      expect(find.textContaining('30 min later than usual'), findsOneWidget);
      expect(find.textContaining('15 min earlier than usual'), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp('Add entry for Keep a steady bedtime')), findsNothing);
    });

    testWidgets('fruit and vegetables and breathing cards open their forms', (tester) async {
      final adapter = fullServer()
        ..on('GET /api/today', StubResponse(200, todayWith([_produce(), _breathing()])));
      final app = TestApp(tester, adapter, surfaceHeight: 3000);
      await app.pump(const TodayScreen());
      expect(find.text('Eat 5 a day'), findsOneWidget);
      expect(find.text('3 of 5 servings of fruit and veg'), findsOneWidget);
      expect(find.text('Breathe 5 min'), findsOneWidget);
      expect(find.text('2 min'), findsOneWidget);

      await app.tap(find.bySemanticsLabel('Add entry for Eat 5 a day'));
      expect(find.text('Log fruit and vegetables'), findsOneWidget);
      await app.closeSheet();
      await app.tap(find.bySemanticsLabel('Add entry for Breathe 5 min'));
      expect(_chunky('Start 5-minute session'), findsOneWidget);
    });

    testWidgets('the three cards fit at text scale 2.0', (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = 2.0;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final adapter = fullServer()
        ..on('GET /api/today', StubResponse(200, todayWith([_steady(), _produce(), _breathing()])));
      final app = TestApp(tester, adapter, surfaceHeight: 6000);
      await app.pump(const TodayScreen());
      expect(tester.takeException(), isNull);
      expect(_small(tester), isEmpty);
    });
  });

  group('onboarding and daily goals', () {
    test('each quest is a focus of its own', () {
      final keys = [for (final f in kFocuses) ...f.questKeys];
      expect(keys, containsAll(['sleep_regularity', 'produce', 'breathing']));
      expect(kAllQuestKeys, containsAll(['sleep_regularity', 'produce', 'breathing']));
    });

    test('the goals start from the research figures', () {
      final report = TargetsReport.parse({
        'targets': [
          {'key': 'produce', 'value': 5, 'unit': 'servings'},
          {'key': 'breathing', 'value': 5, 'unit': 'min'},
        ],
      });
      final goals = {
        for (final g in planGoals(['sleep_regularity', 'produce', 'breathing'], false, report))
          g.key: g,
      };
      expect(goals['produce']!.value, 5);
      expect(goals['produce']!.label(5), '5 servings');
      expect(goals['breathing']!.value, 5);
      expect(goals['breathing']!.label(5), '5 min');
      expect(goals['sleep_regularity']!.value, 45);
      expect(goals['sleep_regularity']!.min, 15);
      expect(goals['sleep_regularity']!.label(45), 'within 45 min');
      expect(goals['sleep_regularity']!.why, contains('starting point'));
    });

    test('daily goal labels read in plain words', () {
      expect(kGoalSpecs['produce']!.label(1), '1 serving');
      expect(kGoalSpecs['breathing']!.label(10), '10 min');
      expect(kGoalSpecs['sleep_regularity']!.options.map((o) => o.value), [30, 45, 60, 90]);
    });
  });

  group('sleep regularity in the Sleep insights', () {
    testWidgets('shows the index when there are enough nights', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: RegularityCard(regularity: SleepRegularity(score: 78.4, nights: 9, pairs: 7)),
          ),
        ),
      );
      expect(find.text('Sleep regularity 78 of 100'), findsOneWidget);
    });

    testWidgets('says what it needs when there are not', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: RegularityCard(regularity: SleepRegularity())),
        ),
      );
      expect(find.text('Sleep regularity'), findsOneWidget);
      expect(find.textContaining('Needs 5 nights'), findsOneWidget);
    });

    test('the model reads the server answer', () {
      final r = SleepRegularity.fromJson({
        'score': 100,
        'nights': 8,
        'pairs': 7,
        'windowDays': 14,
        'minNights': 5,
      });
      expect(r.score, 100);
      expect(r.pairs, 7);
      expect(SleepRegularity.fromJson(null).score, isNull);
    });
  });

  group('the goal picker', () {
    QuestTemplate template(String key, String unit, int target) => QuestTemplate.fromJson({
      'key': key,
      'title': key,
      'enabled': false,
      'target': target,
      'unit': unit,
      'points': 50,
      'position': 9,
    });

    Future<TestApp> open(WidgetTester tester, QuestTemplate q) async {
      final app = TestApp(tester, _server());
      await app.pump(
        GoalPickerPage(quest: q, target: q.target.round(), targetAlt: null),
        key: UniqueKey(),
      );
      return app;
    }

    Finder done() => find.byWidgetPredicate((w) => w is ChunkyButton && w.label == 'Done');

    testWidgets('only accepts what the server accepts', (tester) async {
      for (final c in [
        ('sleep_regularity', 'min', 45, '14', '121'),
        ('produce', 'servings', 5, '0', '31'),
        ('breathing', 'min', 5, '0', '61'),
      ]) {
        final app = await open(tester, template(c.$1, c.$2, c.$3));
        expect(tester.widget<ChunkyButton>(done()).onPressed, isNotNull, reason: c.$1);
        await app.enter(find.byType(TextField).first, c.$4);
        expect(tester.widget<ChunkyButton>(done()).onPressed, isNull, reason: '${c.$1} ${c.$4}');
        await app.enter(find.byType(TextField).first, c.$5);
        expect(tester.widget<ChunkyButton>(done()).onPressed, isNull, reason: '${c.$1} ${c.$5}');
      }
    });

    testWidgets('offers the named windows for the steady bedtime', (tester) async {
      await open(tester, template('sleep_regularity', 'min', 45));
      expect(find.text('How close to your usual times?'), findsOneWidget);
      expect(find.text('within 60 min'), findsOneWidget);
    });
  });
}
