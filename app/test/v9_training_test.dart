import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:newme/api/api_client.dart';
import 'package:newme/api/models.dart';
import 'package:newme/features/shell/home_tab.dart';
import 'package:newme/features/training/exercises_page.dart';
import 'package:newme/features/training/session_page.dart';
import 'package:newme/features/training/training_card.dart';
import 'package:newme/features/training/training_copy.dart';
import 'package:newme/features/training/train_screen.dart';
import 'package:newme/features/training/training_profile_page.dart';
import 'package:newme/features/training/training_progress_page.dart';
import 'package:newme/widgets/mascot.dart';
import 'package:newme/widgets/quest_copy.dart';

import 'fixtures.dart';
import 'test_support.dart';

/// The files in test/contract_v9 are real server responses, recorded by
/// server/internal/api/v9_contract_test.go with NEWME_CONTRACT_DIR set.
Map<String, dynamic> _load(String name) =>
    jsonDecode(File('test/contract_v9/$name.json').readAsStringSync()) as Map<String, dynamic>;

StubAdapter _server({String today = 'training_today'}) => fullServer()
  ..on('GET /api/training/today', StubResponse(200, _load(today)))
  ..on('GET /api/exercises', StubResponse(200, _load('exercises')))
  ..on('GET /api/training/profile', StubResponse(200, _load('training_profile')))
  ..on('GET /api/training/progress', StubResponse(200, _load('training_progress')))
  ..on('GET /api/sets', StubResponse(200, _load('sets')))
  ..on('POST /api/sets', StubResponse(201, _load('set_created')))
  ..on('POST /api/training/sessions/1/complete', StubResponse(200, _load('session_complete')));

Map<String, dynamic> _sentBody(StubAdapter s, String route) =>
    (s.to(route).last.data is String
            ? jsonDecode(s.to(route).last.data as String)
            : s.to(route).last.data)
        as Map<String, dynamic>;

/// Chunky buttons draw their labels in capitals.
Finder _button(String label) => find.text(label.toUpperCase());

void main() {
  setUp(() {
    FakeStorage().install();
    Mascot.idleMotion = false;
  });

  group('contract', () {
    test('today parses the session with targets, reasons and logged sets', () {
      final t = TrainingToday.parse(_load('training_today'));
      expect(t.date, '2026-11-02');
      expect(t.plan!.days.map((d) => d.label), ['Full body A', 'Full body B']);
      final s = t.session!;
      expect(s.label, 'Full body A');
      expect(s.exercises, hasLength(5));
      final row = s.exercises.firstWhere((e) => e.exercise == 'db_row');
      expect(row.loaded, isTrue);
      expect(row.target.amount, 6);
      expect(row.reason, startsWith('First time'));
      expect(row.logged.single.loadKg, 20);
      expect(row.logged.single.rir, 2);
      expect(row.planName, 'Dumbbell row');
      expect(s.setsLogged, 1);
      expect(s.setsPlanned, 10);
    });

    test('today round-trips through the cache shape', () {
      final t = TrainingToday.parse(_load('training_today'));
      final again = TrainingToday.parse(jsonDecode(jsonEncode(t.toJson())));
      expect(jsonEncode(again.toJson()), jsonEncode(t.toJson()));
    });

    test('rest day and no plan', () {
      final rest = TrainingToday.parse(_load('training_today_rest'));
      expect(rest.restDay, isTrue);
      expect(rest.session, isNull);
      expect(rest.plan, isNotNull);
      final none = TrainingToday.parse(_load('training_today_none'));
      expect(none.plan, isNull);
      expect(none.restDay, isFalse);
    });

    test('catalog, bests and max tests', () {
      final c = ExerciseCatalog.parse(_load('exercises'));
      expect(c.exercises.length, greaterThan(35));
      expect(c.muscles, contains('hamstrings'));
      final row = c.byKey('db_row')!;
      expect(row.best!.e1rmKg, 26.7);
      final pull = c.byKey('pull_up')!;
      expect(pull.maxTest!.reps, 6);
      expect(pull.easierKey, 'negative_pull_up');
      expect(c.byKey('plank')!.timed, isTrue);
      final again = ExerciseCatalog.parse(jsonDecode(jsonEncode(c.toJson())));
      expect(again.byKey('db_row')!.best!.e1rmKg, 26.7);
    });

    test('profile, plan, progress, sets, lifts and the completed day', () {
      final p = TrainingProfile.tryParse(_load('training_profile')['profile'])!;
      expect(p.experience, Experience.newcomer);
      expect(p.dumbbellMaxKg, 30);
      expect(TrainingProfile.tryParse(_load('training_profile_empty')['profile']), isNull);
      final plan = TrainingPlan.tryParse(_load('plan')['plan'])!;
      expect(plan.endsOn, '2026-11-29');
      expect(plan.days.first.exercises.first.restSec, 90);
      final progress = TrainingProgress.parse(_load('training_progress'));
      expect(progress.rangeMin, 4);
      expect(progress.muscles.firstWhere((m) => m.muscle == 'back').thisWeek, 1);
      final result = SetResult.parse(_load('set_created'));
      expect(result.set!.sessionId, 1);
      expect(result.day.quests, isNotEmpty);
      final lifts = Lookback.parse(_load('lookback_lifts')).people.first.lifts;
      expect(lifts.map((l) => l.key), ['db_row', 'plank']);
      expect(lifts.first.measure, 'e1rm');
      final day = DayDetail.fromJson(_load('session_complete')['day'] as Map<String, dynamic>);
      final push = day.quests.firstWhere((q) => q.key == 'pushups');
      expect(push.done, isTrue);
      expect(push.doneBy!.kind, 'session');
      expect(doneByLabel(push.doneBy!), 'Done by your Full body A session');
    });

    test('a rejected plan keeps its violations on the exception', () async {
      final stub = StubAdapter()
        ..on('POST /api/training/plan', StubResponse(422, _load('plan_invalid')));
      final client = ApiClient(baseUrl: 'https://me.invalid', adapter: stub);
      try {
        await client.generatePlan();
        fail('expected a 422');
      } on ApiException catch (e) {
        expect(e.code, 'plan_invalid');
        expect(parseViolations(e.body), hasLength(5));
        expect(parseViolations(e.body).first.message, 'the block must last 4 to 6 weeks, not 9');
        expect(parseViolations(e.body).last.message, contains('2 short of the 4 minimum'));
      }
    });
  });

  group('copy', () {
    SessionExercise ex({bool timed = false, double? load, int amount = 8}) => SessionExercise(
      exercise: 'x',
      name: 'X',
      measure: timed ? Measure.seconds : Measure.reps,
      load: load == null ? LoadKind.bodyweight : LoadKind.external,
      plan: const Prescription(exercise: 'x'),
      target: SessionTarget(exercise: 'x', sets: 3, amount: amount, loadKg: load),
    );

    test('targets and sets', () {
      expect(targetLabel(ex(), Units.metric), '3 × 8 reps');
      expect(targetLabel(ex(load: 22.5), Units.metric), '3 × 8 reps at 22.5\u00a0kg');
      expect(targetLabel(ex(timed: true, amount: 45), Units.metric), '3 × 45 s');
      expect(
        setLabel(const ExerciseSet(id: 1, exercise: 'x', localDate: '', reps: 1), Units.metric),
        '1 rep',
      );
      expect(
        setLabel(
          const ExerciseSet(id: 1, exercise: 'x', localDate: '', reps: 10, loadKg: 20),
          Units.metric,
        ),
        '10 reps at 20\u00a0kg',
      );
      expect(rirLabel(null), '');
      expect(clockLabel(90), '1:30');
      expect(clockLabel(-3), '0:00');
    });

    test('lift lines name the first month', () {
      Lift lift(double v, double? first, {String measure = 'reps'}) => Lift(
        key: 'pull_up',
        name: 'Pull-up',
        measure: measure,
        value: v,
        first: first,
        firstMonth: first == null ? null : '2026-09',
      );
      expect(
        liftLine(lift(8, 3), Units.metric),
        'Pull-up: best set 8, up from 3 in your first month',
      );
      expect(liftLine(lift(8, null), Units.metric), 'Pull-up: best set 8, first month logged');
      expect(liftLine(lift(3, 3), Units.metric), 'Pull-up: best set 3, same as your first month');
      expect(
        liftLine(lift(30.4, 26.7, measure: 'e1rm'), Units.metric),
        'Pull-up: estimated one-rep max 30.4\u00a0kg, up from 26.7\u00a0kg in your first month',
      );
      expect(
        liftLine(lift(60, 45, measure: 'seconds'), Units.metric),
        'Pull-up: best set 60 s, up from 45 s in your first month',
      );
    });

    test('a workout still reads as a workout', () {
      expect(
        doneByLabel(const DoneBy(kind: 'workout', type: 'strength', minutes: 42)),
        'Done by your Strength workout, 42 min',
      );
    });

    test('next plan day wraps around the week', () {
      final plan = TrainingPlan.tryParse(_load('plan')['plan'])!;
      expect(nextPlanDay(plan, '2026-11-03')!.label, 'Full body B');
      expect(nextPlanDay(plan, '2026-11-06')!.label, 'Full body A');
      expect(planDaysLabel(plan), 'Mon, Thu');
    });

    test('exercise groups follow the muscle order and the search', () {
      final c = ExerciseCatalog.parse(_load('exercises'));
      final all = groupExercises(c, '');
      expect(all.first.$1, 'chest');
      final pulls = groupExercises(c, 'pull');
      expect(pulls.map((g) => g.$1), ['back']);
      expect(groupExercises(c, 'zzz'), isEmpty);
    });

    test('volume bands against the range', () {
      const p = TrainingProgress(rangeMin: 4, rangeMax: 12);
      expect(volumeBand(0, p), VolumeBand.none);
      expect(volumeBand(3, p), VolumeBand.under);
      expect(volumeBand(4, p), VolumeBand.inRange);
      expect(volumeBand(13, p), VolumeBand.over);
    });
  });

  group('Today', () {
    testWidgets('shows the session with a start button', (tester) async {
      final app = TestApp(tester, _server());
      await app.pump(const TrainingSlot(localToday: '2026-11-02'));
      await tester.pumpAndSettle();
      expect(find.text('Full body A'), findsOneWidget);
      expect(find.text('Training'), findsNothing, reason: 'the caption line is gone');
      expect(find.text('1 of 10 sets'), findsOneWidget);
      expect(find.text('Continue'), findsOneWidget);
      // One label, read once: the visible text is not merged in a second time.
      expect(
        find.bySemanticsLabel('Training. Full body A. 1 of 10 sets. Continue'),
        findsOneWidget,
      );
    });

    testWidgets('a rest day shows nothing on Today but names the next session on Train', (
      tester,
    ) async {
      final app = TestApp(tester, _server(today: 'training_today_rest'));
      await app.pump(const TrainingSlot(localToday: '2026-11-03'));
      await tester.pumpAndSettle();
      expect(find.text('Rest day'), findsNothing);

      await app.pump(
        const TrainingSlot(localToday: '2026-11-03', onTrainTab: true),
        key: UniqueKey(),
      );
      await tester.pumpAndSettle();
      expect(find.text('Rest day'), findsOneWidget);
      expect(find.text('Next: Full body B, Thu'), findsOneWidget);
      expect(find.text('Log sets'), findsOneWidget);
      await tester.tap(find.text('Rest day'));
      await tester.pumpAndSettle();
      expect(find.text('Search exercises'), findsWidgets, reason: 'the card opens the Exercises');
      expect(find.text('Training'), findsNothing, reason: 'the caption line is gone');
    });

    testWidgets('a finished session leaves Today but stays on Train', (tester) async {
      final done = _load('training_today');
      (done['session']! as Map<String, dynamic>)['completed'] = true;
      final app = TestApp(
        tester,
        _server()..on('GET /api/training/today', StubResponse(200, done)),
      );
      await app.pump(const TrainingSlot(localToday: '2026-11-02'));
      await tester.pumpAndSettle();
      expect(find.text('Full body A'), findsNothing);

      await app.pump(
        const TrainingSlot(localToday: '2026-11-02', onTrainTab: true),
        key: UniqueKey(),
      );
      await tester.pumpAndSettle();
      expect(find.text('Full body A'), findsOneWidget);
    });

    testWidgets('a finished block shows on Today and its Plan opens the Train tab', (tester) async {
      final ended = {..._load('training_today_rest'), 'blockEnded': true};
      final app = TestApp(
        tester,
        _server()..on('GET /api/training/today', StubResponse(200, ended)),
      );
      await app.pump(const TrainingSlot(localToday: '2026-11-03'));
      await tester.pumpAndSettle();
      expect(find.text('Your 4-week block is done'), findsOneWidget);
      expect(find.text('Plan'), findsOneWidget);

      await tester.tap(find.text('Plan'));
      await tester.pumpAndSettle();
      expect(app.container.read(homeTabProvider), HomeTab.train);

      await app.pump(
        const TrainingSlot(localToday: '2026-11-03', onTrainTab: true),
        key: UniqueKey(),
      );
      await tester.pumpAndSettle();
      expect(find.text('Your 4-week block is done'), findsOneWidget);
      expect(find.text('Plan'), findsNothing, reason: 'the plan sits right below on Train');
    });

    testWidgets('nothing without a plan', (tester) async {
      final app = TestApp(tester, _server(today: 'training_today_none'));
      await app.pump(const TrainingSlot(localToday: '2026-11-02'));
      await tester.pumpAndSettle();
      expect(find.text('Training'), findsNothing);
    });
  });

  group('session', () {
    testWidgets('logs a set from the target, rests, and finishes', (tester) async {
      final server = _server();
      final app = TestApp(tester, server);
      await app.pump(const SessionPage());
      await tester.pumpAndSettle();

      expect(find.text('Push-up'), findsOneWidget);
      expect(find.text('2 × 6 reps'), findsNWidgets(3));
      expect(find.textContaining('First time in this plan'), findsWidgets);
      expect(find.text('10 reps at 20\u00a0kg · 2 RIR'), findsOneWidget);

      await tester.tap(_button('Log set 1 of 2').first);
      await tester.pumpAndSettle();
      expect(find.text('Set 1 of 2 · aim for 6 reps'), findsOneWidget);
      await tester.tap(_button('Log set'));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle(
        const Duration(milliseconds: 100),
        EnginePhase.sendSemanticsUpdate,
        const Duration(seconds: 1),
      );

      final sent = _sentBody(server, 'POST /api/sets');
      expect(sent['exercise'], 'push_up');
      expect(sent['reps'], 6);
      expect(sent['rir'], 2);
      expect(sent['sessionId'], 1);
      expect(sent['clientOpId'], isA<String>());
      expect(find.text('Rest'), findsOneWidget);
      expect(find.text('1:30'), findsOneWidget);
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('1:29'), findsOneWidget);
      await tester.tap(find.text('Skip'));
      await tester.pump();
      expect(find.text('Rest'), findsNothing);

      await tester.tap(_button('Finish session'));
      await tester.pumpAndSettle();
      expect(find.text('Finish the session?'), findsOneWidget);
      await tester.tap(find.text('Finish'));
      await tester.pumpAndSettle();
      expect(server.to('POST /api/training/sessions/1/complete'), hasLength(1));
      expect(find.text('Done. Get stronger is complete.'), findsOneWidget);
      expect(_button('Finish session'), findsNothing);
    });

    testWidgets('fits at text scale 2.0', (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final app = TestApp(tester, _server(), surfaceHeight: 6000);
      await app.pump(const SessionPage());
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });

  group('Training page', () {
    testWidgets('without a profile offers the setup', (tester) async {
      final server = _server()
        ..on('GET /api/training/profile', StubResponse(200, _load('training_profile_empty')));
      final app = TestApp(tester, server);
      await app.pump(const TrainScreen());
      await tester.pumpAndSettle();
      expect(_button('Set up training'), findsOneWidget);
      expect(find.textContaining('WHO 2020'), findsNothing, reason: 'the sources are one tap away');
      await tester.tap(find.byTooltip('Sources for plans and progression'));
      await tester.pumpAndSettle();
      expect(find.textContaining('WHO 2020'), findsOneWidget);
    });

    testWidgets('shows the plan with exercise names and ranges', (tester) async {
      final app = TestApp(tester, _server(), surfaceHeight: 4000);
      await app.pump(const TrainScreen());
      await tester.pumpAndSettle();
      expect(find.text('2 days a week, 40 min'), findsOneWidget);
      expect(find.textContaining('Dumbbells to 30\u00a0kg'), findsOneWidget);
      expect(find.text('Plan · 4 weeks, until Nov 29'), findsOneWidget);
      expect(find.text('Train'), findsOneWidget);
      expect(find.text('Full body A'), findsWidgets, reason: "today's card and the plan day");
      expect(find.text('Dumbbell row'), findsNWidgets(2));
      expect(find.text('Exercises'), findsOneWidget);
      expect(find.text('Weekly sets'), findsOneWidget);
      expect(find.text('2 × 6 to 10 reps'), findsWidgets);
      expect(_button('Change plan'), findsOneWidget);
    });

    testWidgets('a rejected design lists the broken rules', (tester) async {
      final server = _server(today: 'training_today_none')
        ..on('POST /api/training/plan', StubResponse(422, _load('plan_invalid')));
      final app = TestApp(tester, server);
      await app.pump(const TrainScreen());
      await tester.pumpAndSettle();
      await tester.tap(_button('Design my plan'));
      await tester.pumpAndSettle();
      expect(find.textContaining('still broke the training rules after repair'), findsOneWidget);
      expect(find.textContaining('chest gets 2 weekly sets, 2 short'), findsOneWidget);
    });

    testWidgets('a change sends its kind and detail', (tester) async {
      final server = _server()
        ..on('POST /api/training/plan/change', StubResponse(201, _load('plan')));
      final app = TestApp(tester, server, surfaceHeight: 4000);
      await app.pump(const TrainScreen());
      await tester.pumpAndSettle();
      await tester.tap(_button('Change plan'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Something hurts'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).last, 'left elbow');
      await tester.pumpAndSettle();
      await tester.tap(_button('Change plan').last);
      await tester.pumpAndSettle();
      expect(_sentBody(server, 'POST /api/training/plan/change'), {
        'kind': 'pain',
        'detail': 'left elbow',
      });
      expect(find.text('Plan updated'), findsOneWidget);
    });

    testWidgets('the profile form saves every field', (tester) async {
      final server = _server()
        ..on('PUT /api/training/profile', StubResponse(200, _load('training_profile')));
      final app = TestApp(tester, server, surfaceHeight: 3000);
      await app.pump(const TrainingProfilePage());
      await tester.pumpAndSettle();
      await tester.tap(find.text('Pull-up bar'));
      await tester.tap(find.text('4'));
      await tester.tap(find.text('30 min'));
      await tester.tap(find.text('Experienced'));
      await tester.enterText(find.byType(TextField).last, 'bigger back');
      await tester.pumpAndSettle();
      await tester.tap(_button('Save'));
      await tester.pumpAndSettle();
      expect(_sentBody(server, 'PUT /api/training/profile'), {
        'equipment': ['pullup_bar'],
        'dumbbellMaxKg': null,
        'daysPerWeek': 4,
        'sessionMinutes': 30,
        'experience': 'experienced',
        'focus': 'bigger back',
      });
    });
  });

  group('exercises', () {
    testWidgets('search narrows the library and a row opens its page', (tester) async {
      final app = TestApp(tester, _server(), surfaceHeight: 8000);
      await app.pump(const ExercisesPage());
      await tester.pumpAndSettle();
      expect(find.text('Chest'), findsOneWidget);
      await tester.enterText(find.byType(TextField).first, 'row');
      await tester.pumpAndSettle();
      expect(find.text('Chest'), findsNothing);
      expect(find.text('Dumbbell row'), findsOneWidget);
      await tester.tap(find.text('Dumbbell row'));
      await tester.pumpAndSettle();
      expect(
        find.text('Best 10 reps at 20\u00a0kg, estimated one-rep max 26.7\u00a0kg'),
        findsOneWidget,
      );
      expect(find.textContaining('Epley'), findsOneWidget);
      expect(find.text('Could not load the strength chart'), findsNothing);
    });

    testWidgets('weekly sets show the evidence range and the source', (tester) async {
      final app = TestApp(tester, _server());
      await app.pump(const TrainingProgressPage());
      await tester.pumpAndSettle();
      expect(find.textContaining('Aim for 4 to 12 hard sets'), findsOneWidget);
      expect(find.textContaining('Schoenfeld, Ogborn and Krieger'), findsOneWidget);
      expect(find.text('Back'), findsWidgets);
      expect(find.text('3 wk'), findsOneWidget);
      expect(find.text('1 wk'), findsOneWidget);
      expect(find.text('This week'), findsOneWidget);
    });
  });
}
