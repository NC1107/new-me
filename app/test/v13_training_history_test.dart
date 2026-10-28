import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:newme/api/models.dart';
import 'package:newme/features/training/exercises_page.dart';
import 'package:newme/features/training/strength_chart.dart';
import 'package:newme/features/training/training_history_page.dart';
import 'package:newme/features/training/train_screen.dart';

import 'fixtures.dart';
import 'test_support.dart';

Map<String, dynamic> _contract(String name) =>
    jsonDecode(File('test/contract_v9/$name.json').readAsStringSync()) as Map<String, dynamic>;

const _october = {
  'month': '2026-10',
  'days': [
    {
      'date': '2026-10-05',
      'sets': 2,
      'sessionCompleted': true,
      'yogaMinutes': 0,
      'workoutTypes': <String>[],
      'logged': [
        {'exercise': 'push_up', 'name': 'Push-up', 'reps': 12, 'seconds': null, 'loadKg': null},
        {
          'exercise': 'goblet_squat',
          'name': 'Goblet squat',
          'reps': 8,
          'seconds': null,
          'loadKg': 20.0,
        },
      ],
    },
    {
      'date': '2026-10-12',
      'sets': 1,
      'sessionCompleted': false,
      'yogaMinutes': 0,
      'workoutTypes': <String>[],
      'logged': [
        {'exercise': 'plank', 'name': 'Plank', 'reps': null, 'seconds': 45, 'loadKg': null},
      ],
    },
    {
      'date': '2026-10-14',
      'sets': 1,
      'sessionCompleted': false,
      'yogaMinutes': 0,
      'workoutTypes': <String>[],
      'logged': [
        {'exercise': 'plank', 'name': 'Plank', 'reps': null, 'seconds': 30, 'loadKg': null},
      ],
    },
    {
      'date': '2026-10-20',
      'sets': 0,
      'sessionCompleted': false,
      'yogaMinutes': 25,
      'workoutTypes': ['running', 'yoga'],
      'logged': <Map<String, dynamic>>[],
    },
  ],
};

const _september = {'month': '2026-09', 'days': <Map<String, dynamic>>[]};

StubAdapter _server() => fullServer()
  ..on('GET /api/training/history', const StubResponse(200, _october))
  ..on('GET /api/exercises', StubResponse(200, _contract('exercises')))
  ..on('GET /api/sets', StubResponse(200, _contract('sets')))
  ..on('GET /api/training/today', StubResponse(200, _todayWithPlan()));

Map<String, dynamic> _todayWithPlan() {
  final today = _contract('training_today');
  today['plan'] = {
    ...(today['plan'] as Map<String, dynamic>),
    'startsOn': '2026-10-05',
    'endsOn': '2026-11-29',
  };
  return today;
}

Finder _day(String label) => find.bySemanticsLabel(RegExp('^$label'));

ExerciseHistory _history(
  ChartMetric metric,
  List<(String, double)> points, {
  bool estimated = false,
  List<ChartMaxTest> maxTests = const [],
}) => ExerciseHistory(
  metric: metric,
  estimated: estimated,
  points: [for (final (d, v) in points) ChartPoint(date: d, value: v)],
  maxTests: maxTests,
);

Future<void> _pumpChart(WidgetTester tester, ExerciseHistory h, {Units units = Units.metric}) =>
    tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: StrengthChart(history: h, units: units),
          ),
        ),
      ),
    );

/// A widget test with the semantics tree on, so labels can be found and read.
void _semanticsTest(String name, Future<void> Function(WidgetTester tester) body) {
  testWidgets(name, (tester) async {
    final handle = tester.ensureSemantics();
    await body(tester);
    handle.dispose();
  });
}

void main() {
  setUp(() {
    FakeStorage().install();
  });

  group('monthWeeks', () {
    test('lays a month out in Monday-first weeks padded with nulls', () {
      final weeks = monthWeeks(2026, 10);
      expect(weeks.length, 5);
      expect(weeks.every((w) => w.length == 7), isTrue);
      expect(weeks.first.take(3), [null, null, null]);
      expect(weeks.first[3], DateTime.utc(2026, 10, 1));
      expect(weeks.last.whereType<DateTime>().last, DateTime.utc(2026, 10, 31));
    });

    test('a month that starts on Monday has no leading blanks', () {
      expect(monthWeeks(2026, 6).first.first, DateTime.utc(2026, 6, 1));
      expect(monthWeeks(2027, 2).length, 4);
    });
  });

  group('history calendar', () {
    _semanticsTest('marks sessions, sets and yoga, and reads each day out', (tester) async {
      final app = TestApp(tester, _server());
      await app.pump(const TrainingHistoryPage());

      expect(find.text('October 2026'), findsOneWidget);
      expect(_day('Monday, Oct 5, 2 sets, session completed'), findsOneWidget);
      expect(_day('Monday, Oct 12, 1 set, session not completed'), findsOneWidget);
      expect(_day('Wednesday, Oct 14, 1 set logged'), findsOneWidget, reason: 'no session planned');
      expect(
        _day('Tuesday, Oct 20, 25 minutes of yoga or mobility, workouts: Running, Yoga'),
        findsOneWidget,
      );
      expect(_day('Monday, Oct 26, today'), findsOneWidget);
      expect(_day('Tuesday, Oct 6, nothing logged'), findsOneWidget);
      expect(find.text('Session completed'), findsOneWidget);
      expect(find.text('Sets only'), findsOneWidget);
      expect(find.text('Yoga or mobility'), findsOneWidget);
      expect(
        app.adapter.to('GET /api/training/history').single.queryParameters['month'],
        '2026-10',
      );
    });

    _semanticsTest('a day opens a sheet of its exercises, sets and yoga', (tester) async {
      final app = TestApp(tester, _server());
      await app.pump(const TrainingHistoryPage());

      await app.tap(_day('Monday, Oct 5'));
      expect(find.text('Monday, Oct 5'), findsWidgets);
      expect(find.text('Session completed'), findsNWidgets(2));
      expect(find.text('Push-up'), findsOneWidget);
      expect(find.text('12 reps'), findsOneWidget);
      expect(find.text('Goblet squat'), findsOneWidget);
      expect(find.text('8 reps at 20\u00a0kg'), findsOneWidget);
      await app.closeSheet();

      await app.tap(_day('Monday, Oct 12'));
      expect(find.text('Session not completed'), findsOneWidget);
      await app.closeSheet();

      await app.tap(_day('Wednesday, Oct 14'));
      expect(find.text('Sets logged'), findsOneWidget);
      expect(find.text('Session not completed'), findsNothing);
      await app.closeSheet();

      await app.tap(_day('Tuesday, Oct 20'));
      expect(find.text('Yoga and mobility'), findsOneWidget);
      expect(find.text('25 minutes'), findsOneWidget);
      expect(find.text('Running, Yoga'), findsOneWidget);
      await app.closeSheet();

      await app.tap(_day('Tuesday, Oct 6'));
      expect(find.text('Nothing was logged this day.'), findsOneWidget);
    });

    _semanticsTest('steps between months and stops at the current one', (tester) async {
      final server = _server();
      server.routes['GET /api/training/history'] = (r) =>
          StubResponse(200, r.queryParameters['month'] == '2026-09' ? _september : _october);
      final app = TestApp(tester, server);
      await app.pump(const TrainingHistoryPage());

      await app.tap(find.bySemanticsLabel('Previous month'));
      expect(find.text('September 2026'), findsOneWidget);
      expect(
        app.adapter.to('GET /api/training/history').map((r) => r.queryParameters['month']),
        contains('2026-09'),
      );
      expect(_day('Tuesday, Sep 1, nothing logged'), findsOneWidget);

      await app.tap(find.bySemanticsLabel('Next month'));
      expect(find.text('October 2026'), findsOneWidget);
      await app.tap(find.bySemanticsLabel('Next month'));
      expect(find.text('October 2026'), findsOneWidget);
    });

    _semanticsTest('keeps day cells and month buttons at 44 points or more', (tester) async {
      final app = TestApp(tester, _server());
      await app.pump(const TrainingHistoryPage());

      final cell = tester.getSize(_day('Monday, Oct 5'));
      expect(cell.width, greaterThanOrEqualTo(44));
      expect(cell.height, greaterThanOrEqualTo(44));
      final previous = tester.getSize(find.bySemanticsLabel('Previous month'));
      expect(previous.width, greaterThanOrEqualTo(44));
      expect(previous.height, greaterThanOrEqualTo(44));
    });

    _semanticsTest('says so when the month cannot load', (tester) async {
      final server = _server()
        ..on('GET /api/training/history', const StubResponse(500, {'error': 'boom'}));
      final app = TestApp(tester, server);
      await app.pump(const TrainingHistoryPage());
      expect(find.text('Could not load this month'), findsOneWidget);
    });

    _semanticsTest('the Train tab opens History from one row', (tester) async {
      final server = _server()
        ..on('GET /api/training/profile', StubResponse(200, _contract('training_profile')))
        ..on('GET /api/training/progress', StubResponse(200, _contract('training_progress')));
      final app = TestApp(tester, server, surfaceHeight: 4000);
      await app.pump(const TrainScreen());
      await tester.pumpAndSettle();
      expect(find.bySemanticsLabel(RegExp('^History')), findsOneWidget);
      await app.tap(find.bySemanticsLabel(RegExp('^History')));
      expect(find.text('October 2026'), findsOneWidget);
    });
  });

  group('strength chart', () {
    _semanticsTest('labels an estimated one-rep max with the Epley and Nuzzo notes', (
      tester,
    ) async {
      await _pumpChart(
        tester,
        _history(ChartMetric.e1rm, [
          ('2026-10-01', 60),
          ('2026-10-12', 66.5),
          ('2026-10-20', 72),
        ], estimated: true),
      );
      expect(find.text('Estimated one-rep max (estimated)'), findsOneWidget);
      expect(find.textContaining('Epley formula, load x (1 + reps / 30)'), findsOneWidget);
      expect(find.textContaining('Nuzzo et al., Sports Med 2024'), findsOneWidget);
      expect(find.text('72'), findsOneWidget);
      expect(find.text('60'), findsOneWidget);
      expect(find.text('Oct 1'), findsOneWidget);
      expect(find.text('Oct 20'), findsOneWidget);
      expect(find.text('Axis in kg.'), findsOneWidget);
      expect(
        find.bySemanticsLabel(
          'Estimated one-rep max (estimated), 3 days from Oct 1 to Oct 20. '
          'First ${Units.metric.load(60)}, latest ${Units.metric.load(72)}, best ${Units.metric.load(72)}.',
        ),
        findsOneWidget,
      );
    });

    _semanticsTest('converts weights to pounds for imperial units', (tester) async {
      await _pumpChart(
        tester,
        _history(ChartMetric.e1rm, [('2026-10-01', 45.36), ('2026-10-20', 90.72)], estimated: true),
        units: Units.imperial,
      );
      expect(find.text('200'), findsOneWidget);
      expect(find.text('100'), findsOneWidget);
      expect(find.text('Axis in lb.'), findsOneWidget);
    });

    _semanticsTest('volume load carries its own note and no estimate label', (tester) async {
      await _pumpChart(
        tester,
        _history(ChartMetric.volume, [('2026-10-01', 240), ('2026-10-20', 300)]),
      );
      expect(find.text('Volume load'), findsOneWidget);
      expect(find.textContaining('Epley'), findsNothing);
      expect(find.textContaining('above 10 reps'), findsOneWidget);
    });

    _semanticsTest('marks max tests on a bodyweight chart and reads them out', (tester) async {
      await _pumpChart(
        tester,
        _history(
          ChartMetric.reps,
          [('2026-10-01', 4), ('2026-10-12', 6)],
          maxTests: const [ChartMaxTest(date: '2026-10-12', reps: 7)],
        ),
      );
      expect(find.text('Best reps in a set'), findsOneWidget);
      expect(find.textContaining('Rings mark max tests.'), findsOneWidget);
      expect(find.text('7'), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp('Max tests: 7 reps on Oct 12')), findsOneWidget);
    });

    _semanticsTest('marks max tests on a load chart along the bottom line', (tester) async {
      await _pumpChart(
        tester,
        _history(
          ChartMetric.e1rm,
          [('2026-10-01', 60), ('2026-10-20', 72)],
          estimated: true,
          maxTests: const [ChartMaxTest(date: '2026-10-12', reps: 7)],
        ),
      );
      expect(find.textContaining('Rings on the bottom line mark max tests.'), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp('Max tests: 7 reps on Oct 12')), findsOneWidget);
    });

    _semanticsTest('the exercise page has a visible delete button on each set', (tester) async {
      final app = TestApp(tester, _server(), surfaceHeight: 3000);
      await app.pump(const ExercisePage(exerciseKey: 'plank'));
      await tester.pumpAndSettle();
      expect(find.text('Long press a set to delete it.'), findsNothing);
      await tester.tap(find.byTooltip('Delete set').first);
      await tester.pumpAndSettle();
      expect(find.text('Delete this set?'), findsOneWidget);
    });

    _semanticsTest('an exercise with nothing logged says so once', (tester) async {
      final app = TestApp(tester, _server(), surfaceHeight: 3000);
      await app.pump(const ExercisePage(exerciseKey: 'push_up'));
      await tester.pumpAndSettle();
      expect(find.text('No sets or max test yet'), findsOneWidget);
      expect(find.text('No sets yet'), findsNothing);
      expect(find.text('No max test yet'), findsNothing);
    });

    _semanticsTest('holds chart seconds', (tester) async {
      await _pumpChart(
        tester,
        _history(ChartMetric.seconds, [('2026-10-01', 30), ('2026-10-08', 55)]),
      );
      expect(find.text('Longest hold'), findsOneWidget);
      expect(find.text('Axis in s.'), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp('latest 55 s, best 55 s')), findsOneWidget);
    });

    _semanticsTest('shows an empty state under two points', (tester) async {
      await _pumpChart(tester, _history(ChartMetric.reps, [('2026-10-01', 4)]));
      expect(find.text('Your chart shows after sets on two different days.'), findsOneWidget);
      expect(
        find.descendant(of: find.byType(StrengthChart), matching: find.byType(CustomPaint)),
        findsNothing,
      );
      await _pumpChart(tester, _history(ChartMetric.reps, const []));
      expect(find.text('Your chart shows after sets on two different days.'), findsOneWidget);
    });

    _semanticsTest('the exercise page shows the chart from the history endpoint', (tester) async {
      final server = _server()
        ..on(
          'GET /api/exercises/pull_up/history',
          const StubResponse(200, {
            'exercise': 'pull_up',
            'metric': 'reps',
            'estimated': false,
            'days': 180,
            'points': [
              {'date': '2026-10-01', 'value': 4},
              {'date': '2026-10-17', 'value': 6},
            ],
            'maxTests': [
              {'date': '2026-10-17', 'reps': 7, 'seconds': null},
            ],
          }),
        );
      final app = TestApp(tester, server, surfaceHeight: 3000);
      await app.pump(const ExercisePage(exerciseKey: 'pull_up'));
      await tester.pumpAndSettle();
      expect(find.text('Best reps in a set'), findsOneWidget);
      expect(
        find.bySemanticsLabel(RegExp('Best reps in a set, 2 days from Oct 1 to Oct 17')),
        findsOneWidget,
      );
    });
  });
}
