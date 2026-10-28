import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:newme/features/board/board_screen.dart';
import 'package:newme/features/board/person_card.dart';
import 'package:newme/features/insights/insight_charts.dart';
import 'package:newme/features/insights/insights_screen.dart';
import 'package:newme/features/insights/sleep_insight_screen.dart';
import 'package:newme/features/insights/steps_insight_screen.dart';
import 'package:newme/features/insights/workouts_screen.dart';
import 'package:newme/features/me/me_screen.dart';
import 'package:newme/features/shell/home_shell.dart';
import 'package:newme/util/format.dart';
import 'package:newme/widgets/mascot.dart';

import 'fixtures.dart';
import 'test_support.dart';

Map<String, dynamic> _steps({
  Map<String, dynamic>? suggestion = const {
    'target': 8500,
    'median14': 7400,
    'bandLow': 8000,
    'bandHigh': 10000,
    'ageKnown': false,
  },
  int goal = 8000,
  bool empty = false,
}) => {
  'avg7': empty ? null : 7421.5,
  'avg30': empty ? null : 6900,
  'median14': empty ? null : 7400,
  'trend': 'up',
  'best': empty ? null : {'date': '2026-10-20', 'value': 12044},
  'daysAtGoal30': 11,
  'goal': goal,
  'suggestion': empty ? null : suggestion,
};

Map<String, dynamic> _sleep({bool empty = false, bool stages = true, int avg7 = 421}) => empty
    ? {
        'avg7Min': null,
        'avg30Min': null,
        'targetMin': 420,
        'avgBedtime': null,
        'avgWake': null,
        'bedtimeSpreadMin': null,
        'stages7': null,
        'lastNight': null,
        'nights': <Map<String, dynamic>>[],
      }
    : {
        'avg7Min': avg7,
        'avg30Min': 410,
        'targetMin': 450,
        'avgBedtime': '23:10',
        'avgWake': '06:50',
        'bedtimeSpreadMin': 38.5,
        'stages7': {'deepMin': 62, 'remMin': 91, 'coreMin': 240, 'awakeMin': 20},
        'lastNight': {
          'date': '2026-10-26',
          'bedAt': '2026-10-26T02:55:00Z',
          'wakeAt': '2026-10-26T10:40:00Z',
          'asleepMin': 431,
          'deepMin': stages ? 70 : 0,
          'remMin': stages ? 95 : 0,
          'coreMin': stages ? 266 : 0,
          'awakeMin': stages ? 18 : 0,
        },
        'nights': [
          for (var d = 13; d >= 0; d--)
            {
              'date': formatDateKey(DateTime.utc(2026, 10, 26).subtract(Duration(days: d))),
              'asleepMin': 380 + d * 8,
            },
        ],
      };

Map<String, dynamic> _insights({
  Map<String, dynamic>? steps,
  Map<String, dynamic>? sleep,
  bool noWorkouts = false,
}) => {
  'steps': steps ?? _steps(),
  'sleep': sleep ?? _sleep(),
  'workouts': noWorkouts
      ? {
          'week': {'count': 0, 'minutes': 0},
          'last30': {'count': 0, 'minutes': 0, 'byType': <Map<String, dynamic>>[]},
        }
      : {
          'week': {'count': 3, 'minutes': 127},
          'last30': {
            'count': 9,
            'minutes': 410,
            'byType': [
              {'type': 'strength', 'count': 5, 'minutes': 260},
              {'type': 'running', 'count': 4, 'minutes': 150},
            ],
          },
        },
};

Map<String, dynamic> _workout(
  String id,
  String type,
  String date, {
  num duration = 34.5,
  int? kcal = 362,
  int? distance = 5480,
  int? hr = 158,
}) => {
  'id': id,
  'type': type,
  'date': date,
  'startedAt': '${date}T11:10:00Z',
  'endedAt': '${date}T11:44:00Z',
  'durationMin': duration,
  'kcal': kcal,
  'distanceM': distance,
  'avgHr': hr,
};

Map<String, dynamic> _workouts({bool empty = false}) => {
  'workouts': empty
      ? <Map<String, dynamic>>[]
      : [
          _workout('a', 'running', '2026-10-26'),
          _workout('b', 'strength', '2026-10-24', kcal: null, distance: null, hr: null),
          _workout('c', 'cycling', '2026-10-20', duration: 62, distance: 21500),
        ],
  'week': {'count': empty ? 0 : 2, 'minutes': empty ? 0 : 69},
};

Map<String, dynamic> _trend({bool empty = false}) => {
  'metric': 'steps',
  'points': empty
      ? <Map<String, dynamic>>[]
      : [
          for (var d = 29; d >= 0; d--)
            {
              'date': formatDateKey(DateTime.utc(2026, 10, 26).subtract(Duration(days: d))),
              'value': 5000 + (d * 397) % 6000,
            },
        ],
};

StubAdapter _server({
  Map<String, dynamic>? insights,
  bool emptyWorkouts = false,
  bool emptySteps = false,
}) {
  final today = richTodayJson(stepsEverSynced: true);
  (today['health'] as Map)['metrics'] = {'sleep_minutes': 432, 'resting_hr': 58};
  return fullServer()
    ..on('GET /api/today', StubResponse(200, today))
    ..on('GET /api/insights', StubResponse(200, insights ?? _insights()))
    ..on('GET /api/workouts', StubResponse(200, _workouts(empty: emptyWorkouts)))
    ..on('GET /api/health/trends', StubResponse(200, _trend(empty: emptySteps)))
    ..on('PATCH /api/me', StubResponse(200, meJson()));
}

void main() {
  setUp(() {
    FakeStorage().install();
    Mascot.idleMotion = false;
  });

  group('Insights hub', () {
    testWidgets('three cards with their headline numbers that open the screens', (tester) async {
      final app = TestApp(tester, _server());
      await app.pump(const InsightsScreen());

      expect(find.text('7,422'), findsOneWidget);
      expect(find.text('7 h 1 min'), findsOneWidget);
      expect(find.text('3'), findsOneWidget);
      expect(find.text('workouts this week'), findsOneWidget);

      await app.tap(find.text('Steps'));
      expect(find.byType(StepsInsightScreen), findsOneWidget);
      await app.closeSheet();
      await app.tap(find.text('Sleep'));
      expect(find.byType(SleepInsightScreen), findsOneWidget);
      await app.closeSheet();
      await app.tap(find.text('Workouts'));
      expect(find.byType(WorkoutsScreen), findsOneWidget);
    });

    testWidgets('says there is no data yet instead of showing zeros', (tester) async {
      final app = TestApp(
        tester,
        _server(
          insights: _insights(
            steps: _steps(empty: true),
            sleep: _sleep(empty: true),
            noWorkouts: true,
          ),
        ),
      );
      await app.pump(const InsightsScreen());
      expect(find.text('No data yet'), findsNWidgets(3));
    });

    testWidgets('shows an error with a retry when nothing can be loaded', (tester) async {
      final adapter = _server()..on('GET /api/insights', const StubResponse(500, {'error': 'x'}));
      final app = TestApp(tester, adapter);
      await app.pump(const InsightsScreen());
      expect(find.text('Could not load insights'), findsOneWidget);
    });
  });

  group('Steps screen', () {
    testWidgets('shows the chart, the averages, the best day and the days at goal', (tester) async {
      final handle = tester.ensureSemantics();
      final app = TestApp(tester, _server());
      await app.pump(const StepsInsightScreen());

      expect(find.byType(DayBarChart), findsOneWidget);
      expect(
        find.bySemanticsLabel(RegExp('Steps for the last 30 days, 30 days with data')),
        findsOneWidget,
      );
      expect(find.text('7,422'), findsWidgets);
      expect(find.text('6,900'), findsOneWidget);
      expect(find.text('12,044'), findsOneWidget);
      expect(find.text('11 of 30'), findsOneWidget);
      expect(find.text('Up on last week'), findsOneWidget);
      handle.dispose();
    });

    testWidgets('builds the suggestion from its fields and invites a birth year', (tester) async {
      final app = TestApp(tester, _server());
      await app.pump(const StepsInsightScreen());

      expect(find.text('Try 8,500 a day'), findsOneWidget);
      expect(
        find.textContaining(
          'You have averaged 7,400 over two weeks, and most of the benefit for adults comes by '
          '8,000 to 10,000.',
        ),
        findsOneWidget,
      );
      expect(find.text('ADD BIRTH YEAR'), findsOneWidget);
      expect(find.text('General guidance, not medical advice.'), findsWidgets);
    });

    testWidgets('a known age says "for your age" and hides the invite', (tester) async {
      final suggestion = {..._steps()['suggestion'] as Map<String, dynamic>, 'ageKnown': true};
      final app = TestApp(
        tester,
        _server(
          insights: _insights(steps: _steps(suggestion: suggestion)),
        ),
      );
      await app.pump(const StepsInsightScreen());
      expect(find.textContaining('for your age'), findsOneWidget);
      expect(find.text('ADD BIRTH YEAR'), findsNothing);
    });

    testWidgets('without enough days it asks for a week of wearing the phone', (tester) async {
      final app = TestApp(
        tester,
        _server(insights: _insights(steps: _steps(empty: true)), emptySteps: true),
      );
      await app.pump(const StepsInsightScreen());
      expect(find.text('Not enough steps yet'), findsOneWidget);
      expect(find.textContaining('Wear your phone or Watch for a week'), findsOneWidget);
      expect(find.text('USE THIS GOAL'), findsNothing);
      expect(find.byType(DayBarChart), findsNothing);
      expect(find.byType(Mascot), findsOneWidget);
    });

    testWidgets('USE THIS GOAL patches the steps target, says it starts tomorrow and toasts', (
      tester,
    ) async {
      final app = TestApp(tester, _server());
      await app.pump(const StepsInsightScreen());
      expect(find.textContaining('starts tomorrow'), findsOneWidget);

      await app.tap(find.text('USE THIS GOAL'));
      expect(app.body('PATCH /api/me'), {
        'questTemplates': [
          {'key': 'steps', 'target': 8500},
        ],
      });
      expect(find.text('Steps goal set to 8,500. It starts tomorrow.'), findsOneWidget);
    });

    testWidgets('a goal that already matches has no button', (tester) async {
      final app = TestApp(tester, _server(insights: _insights(steps: _steps(goal: 8500))));
      await app.pump(const StepsInsightScreen());
      expect(find.text('USE THIS GOAL'), findsNothing);
      expect(find.text('This is already your goal.'), findsOneWidget);
      expect(find.text('Stay at 8,500 a day'), findsOneWidget);
    });

    testWidgets('a failed save keeps the button and shows why', (tester) async {
      final adapter = _server()
        ..on('PATCH /api/me', const StubResponse(422, {'error': 'steps target out of range'}));
      final app = TestApp(tester, adapter);
      await app.pump(const StepsInsightScreen());
      await app.tap(find.text('USE THIS GOAL'));
      expect(find.text('TRY AGAIN'), findsOneWidget);
    });

    testWidgets('the birth year sheet saves a year, and the optional field can be skipped', (
      tester,
    ) async {
      final app = TestApp(tester, _server());
      await app.pump(const StepsInsightScreen());
      await app.tap(find.text('ADD BIRTH YEAR'));
      expect(find.text('Your birth year'), findsOneWidget);
      expect(find.text('REMOVE BIRTH YEAR'), findsNothing);
      await app.tap(find.text('SAVE'));
      expect(app.body('PATCH /api/me'), {'birthYear': 1990});
    });

    testWidgets('the explainer opens to the evidence and closes again', (tester) async {
      final app = TestApp(tester, _server());
      await app.pump(const StepsInsightScreen());
      expect(find.textContaining('Paluch'), findsNothing);
      await app.tap(find.text('Why not based on height or weight?'));
      expect(find.textContaining('Paluch et al.'), findsOneWidget);
      expect(find.textContaining('Height changes your stride'), findsOneWidget);
      await app.tap(find.text('Why not based on height or weight?'));
      expect(find.textContaining('Paluch'), findsNothing);
    });
  });

  group('Sleep screen', () {
    testWidgets('last night card shows bed and wake in the person zone, stages and legend', (
      tester,
    ) async {
      final app = TestApp(tester, _server());
      await app.pump(const SleepInsightScreen());

      expect(find.text('Last night'), findsOneWidget);
      expect(find.text('7 h 11 min'), findsOneWidget);
      // 02:55Z and 10:40Z in New York (UTC-4 on 26 Oct 2026).
      expect(find.text('10:55 PM'), findsOneWidget);
      expect(find.text('6:40 AM'), findsOneWidget);
      expect(find.byType(StageBar), findsOneWidget);
      expect(find.text('Deep 1 h 10 min'), findsOneWidget);
      expect(find.text('Core 4 h 26 min'), findsOneWidget);
      expect(find.text('REM 1 h 35 min'), findsOneWidget);
      expect(find.text('Awake 18 min'), findsOneWidget);
    });

    testWidgets('14 nights, averages, bed and wake times and the consistency line', (tester) async {
      final app = TestApp(tester, _server());
      await app.pump(const SleepInsightScreen());
      expect(find.byType(DayBarChart), findsOneWidget);
      expect(find.text('7 h 1 min'), findsOneWidget);
      expect(find.text('6 h 50 min'), findsOneWidget);
      expect(find.text('11:10 PM'), findsOneWidget);
      expect(find.text('6:50 AM'), findsOneWidget);
      expect(find.text('Your bedtime varies by about 40 min'), findsOneWidget);
    });

    testWidgets('the tips follow the numbers: short average, so a tip and no positive note', (
      tester,
    ) async {
      final app = TestApp(tester, _server(insights: _insights(sleep: _sleep(avg7: 400))));
      await app.pump(const SleepInsightScreen());
      await tester.drag(find.byType(Scrollable).first, const Offset(0, -2000));
      await app.settle();
      expect(find.text('Gentle tips'), findsOneWidget);
      expect(find.textContaining('50 min less'), findsOneWidget);
      expect(find.text('Nicely done'), findsNothing);
    });

    testWidgets('a night with only total sleep says there are no stages', (tester) async {
      final app = TestApp(tester, _server(insights: _insights(sleep: _sleep(stages: false))));
      await app.pump(const SleepInsightScreen());
      expect(find.byType(StageBar), findsNothing);
      expect(find.textContaining('only reported total sleep'), findsOneWidget);
    });

    testWidgets('no nights shows the mascot', (tester) async {
      final app = TestApp(tester, _server(insights: _insights(sleep: _sleep(empty: true))));
      await app.pump(const SleepInsightScreen());
      expect(find.text('No sleep yet'), findsOneWidget);
      expect(find.byType(Mascot), findsOneWidget);
      expect(find.byType(DayBarChart), findsNothing);
    });
  });

  group('Workouts screen', () {
    testWidgets('week summary, by-type bars and the recent list', (tester) async {
      final app = TestApp(tester, _server());
      await app.pump(const WorkoutsScreen());

      expect(find.text('3 workouts'), findsOneWidget);
      expect(find.text('2 h 7 min moving'), findsOneWidget);
      expect(find.text('Strength'), findsWidgets);
      expect(find.text('5x, 4 h 20 min'), findsOneWidget);
      expect(find.byType(RankedBar), findsNWidgets(2));
      expect(find.text('Recent workouts'), findsOneWidget);
      expect(find.text('Run'), findsWidgets);
      expect(find.text('35 min'), findsWidgets);
      expect(find.text('362 kcal'), findsWidgets);
      expect(find.text('5.5 km'), findsWidgets);
      expect(find.text('158 bpm'), findsWidgets);
    });

    testWidgets('a workout without energy, distance or heart rate shows only its time', (
      tester,
    ) async {
      final app = TestApp(tester, _server());
      await app.pump(const WorkoutsScreen());
      await app.tap(find.text('Strength').last);
      expect(find.textContaining('did not record energy'), findsOneWidget);
      expect(find.text('Energy'), findsNothing);
    });

    testWidgets('tapping a workout opens its detail in the person zone', (tester) async {
      final app = TestApp(tester, _server());
      await app.pump(const WorkoutsScreen());
      await app.tap(find.text('Ride'));
      expect(find.text('Duration'), findsOneWidget);
      expect(find.text('1 h 2 min'), findsWidgets);
      expect(find.text('21.5 km'), findsWidgets);
      expect(find.text('Avg heart rate'), findsOneWidget);
      // 11:10Z to 11:44Z is 7:10 AM to 7:44 AM in New York.
      expect(find.textContaining('7:10 AM to 7:44 AM'), findsOneWidget);
    });

    testWidgets('no workouts shows the mascot and how they arrive', (tester) async {
      final app = TestApp(
        tester,
        _server(insights: _insights(noWorkouts: true), emptyWorkouts: true),
      );
      await app.pump(const WorkoutsScreen());
      expect(find.text('No workouts yet'), findsOneWidget);
      expect(find.byType(Mascot), findsOneWidget);
      expect(find.text('Recent workouts'), findsNothing);
    });
  });

  group('entry points', () {
    testWidgets('Today: the Body row carries the week and opens Insights', (tester) async {
      final app = TestApp(tester, _server());
      await app.pump(const HomeShell());
      await tester.drag(find.byType(Scrollable).first, const Offset(0, -4000));
      await app.settle();

      expect(find.textContaining('3 workouts this week'), findsOneWidget);
      await app.tap(find.text('Body'));
      expect(find.byType(InsightsScreen), findsOneWidget);
    });

    testWidgets('Today: with no workouts the Body row says what Insights holds', (tester) async {
      final app = TestApp(tester, _server(insights: _insights(noWorkouts: true)));
      await app.pump(const HomeShell());
      await tester.drag(find.byType(Scrollable).first, const Offset(0, -4000));
      await app.settle();
      expect(find.textContaining('workouts this week'), findsNothing);
      expect(find.text('Body'), findsOneWidget);
    });

    testWidgets('Me: an Insights row opens the hub', (tester) async {
      final app = TestApp(tester, _server());
      await app.pump(const MeScreen());
      await app.tap(find.text('Insights'));
      expect(find.byType(InsightsScreen), findsOneWidget);
    });

    testWidgets('Us: workouts this week shows when known and hides when null', (tester) async {
      final withCount = boardUser(2, 'Sam', 'violet')..['workoutsThisWeek'] = 3;
      final app = TestApp(
        tester,
        _server()..on(
          'GET /api/board',
          StubResponse(200, board([withCount, boardUser(1, 'Alex', 'amber')])),
        ),
      );
      await app.pump(const BoardScreen());
      await app.tap(find.byType(PersonCard).first);
      expect(find.text('Workouts'), findsOneWidget);
      expect(find.text('3 workouts'), findsOneWidget);
    });
  });

  group('Profile birth year', () {
    testWidgets('can be set from About you and cleared again', (tester) async {
      final me = meJson();
      (me['user'] as Map)['birthYear'] = 1962;
      final adapter = _server()..on('GET /api/me', StubResponse(200, me));
      final app = TestApp(tester, adapter);
      await app.pump(const MeScreen());
      await app.tap(find.text('About you'));
      expect(find.text('1962'), findsOneWidget);

      await app.tap(find.text('1962'));
      await app.tap(find.text('REMOVE BIRTH YEAR'));
      expect(find.text('Not set'), findsOneWidget);
      await app.tap(find.text('SAVE'));
      expect(app.body('PATCH /api/me'), {'birthYear': null});
    });
  });

  group('layout at large text and reduced motion', () {
    for (final scale in [1.0, 2.0]) {
      testWidgets('no overflow on any insight screen at text scale $scale', (tester) async {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        addTearDown(tester.view.reset);
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

        final screens = <String, Widget>{
          'hub': const InsightsScreen(),
          'steps': const StepsInsightScreen(),
          'sleep': const SleepInsightScreen(),
          'workouts': const WorkoutsScreen(),
        };
        var n = 0;
        for (final entry in screens.entries) {
          final app = TestApp(tester, _server());
          await app.pump(entry.value, tall: false, key: ValueKey('${entry.key}${n++}'));
          for (var i = 0; i < 6; i++) {
            final error = tester.takeException();
            expect(error, isNull, reason: 'overflow on ${entry.key}: $error');
            await tester.drag(find.byType(Scrollable).first, const Offset(0, -500));
            await app.settle(4);
          }
          expect(tester.takeException(), isNull, reason: '${entry.key} scrolled');
        }
      });
    }

    testWidgets('sheets and the explainer fit at text scale 2.0', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.view.reset);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

      final steps = TestApp(tester, _server());
      await steps.pump(const StepsInsightScreen(), tall: false);
      Future<void> reveal(Finder f) async {
        for (var i = 0; i < 30 && f.hitTestable().evaluate().isEmpty; i++) {
          await tester.drag(find.byType(Scrollable).first, const Offset(0, -200));
          await tester.pump(const Duration(milliseconds: 100));
        }
        expect(f.hitTestable(), findsOneWidget);
      }

      await reveal(find.text('Why not based on height or weight?'));
      await steps.tap(find.text('Why not based on height or weight?'));
      expect(tester.takeException(), isNull);
      await reveal(find.text('ADD BIRTH YEAR'));
      await steps.tap(find.text('ADD BIRTH YEAR'));
      expect(tester.takeException(), isNull);
      await steps.closeSheet();

      final workouts = TestApp(tester, _server());
      await workouts.pump(const WorkoutsScreen(), tall: false, key: UniqueKey());
      await reveal(find.text('Ride'));
      await workouts.tap(find.text('Ride'));
      expect(tester.takeException(), isNull);
    });

    testWidgets('with animations disabled the charts draw at once', (tester) async {
      tester.view.physicalSize = const Size(390, 1500);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final app = TestApp(tester, _server());
      await app.pump(
        const MediaQuery(
          data: MediaQueryData(disableAnimations: true, size: Size(390, 1500)),
          child: StepsInsightScreen(),
        ),
        tall: false,
      );
      final painter =
          tester
                  .widget<CustomPaint>(
                    find
                        .descendant(
                          of: find.byType(DayBarChart),
                          matching: find.byType(CustomPaint),
                        )
                        .first,
                  )
                  .painter!
              as DayBarPainter;
      expect(painter.reveal, 1);
    });
  });

  group('touch targets', () {
    testWidgets('every tappable insight control is at least 44 tall', (tester) async {
      final app = TestApp(tester, _server());
      await app.pump(const StepsInsightScreen());
      for (final label in [
        'Why not based on height or weight?',
        'ADD BIRTH YEAR',
        'USE THIS GOAL',
      ]) {
        final size = tester.getSize(find.text(label).hitTestable().first);
        final box = tester.getRect(
          find.ancestor(of: find.text(label), matching: find.byType(GestureDetector)).first,
        );
        expect(box.height, greaterThanOrEqualTo(44), reason: label);
        expect(size.height, greaterThan(0));
      }
    });
  });
}
