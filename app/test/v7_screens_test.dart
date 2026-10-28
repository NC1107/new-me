import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:newme/features/insights/insights_screen.dart';
import 'package:newme/features/insights/workouts_screen.dart';
import 'package:newme/features/log/log_kind.dart';
import 'package:newme/features/log/log_sheet.dart';
import 'package:newme/features/me/me_screen.dart';
import 'package:newme/features/me/schedule_page.dart';
import 'package:newme/features/progress/lookback_screen.dart';
import 'package:newme/features/progress/milestone_celebration.dart';
import 'package:newme/features/progress/milestones_page.dart';
import 'package:newme/features/progress/progress_screen.dart';
import 'package:newme/features/progress/sparkline.dart';
import 'package:newme/features/progress/metric_card.dart';
import 'package:newme/features/today/today_screen.dart';
import 'package:newme/features/together/notifications_page.dart';
import 'package:newme/api/models.dart';
import 'package:newme/state/right_now.dart';
import 'package:newme/state/today.dart';
import 'package:newme/widgets/chunky_button.dart';
import 'package:newme/widgets/mascot.dart';

import 'fixtures.dart';
import 'test_support.dart';

final _morning = DateTime(2026, 10, 27, 8);

Map<String, dynamic> _fixture(String name) =>
    (jsonDecode(File('test/contract_v7/$name.json').readAsStringSync()) as Map)['body']!
        as Map<String, dynamic>;

StubAdapter _server({Map<String, dynamic>? me}) => fullServer()
  ..on('GET /api/me', StubResponse(200, me ?? meJson()))
  ..on('GET /api/insights', StubResponse(200, _fixture('insights_rich')))
  ..on('GET /api/progress', StubResponse(200, _fixture('progress_rich')))
  ..on('GET /api/lookback', StubResponse(200, _fixture('lookback_rich')))
  ..on('GET /api/milestones', StubResponse(200, _fixture('milestones')))
  ..on('GET /api/workouts', const StubResponse(200, {'workouts': <Object>[]}))
  ..on('POST /api/logs', StubResponse(201, logResultJson()));

Finder _chunky(String label) =>
    find.byWidgetPredicate((w) => w is ChunkyButton && w.label == label);

bool _enabled(WidgetTester tester, String label) =>
    tester.widget<ChunkyButton>(_chunky(label)).onPressed != null;

void main() {
  setUp(() {
    FakeStorage().install();
    Mascot.idleMotion = false;
  });

  group('Me > Schedule', () {
    Future<TestApp> open(
      WidgetTester tester, {
      Map<String, dynamic>? me,
      StubAdapter? server,
    }) async {
      final app = TestApp(tester, server ?? _server(me: me), surfaceHeight: 1800);
      await app.pump(const SchedulePage(), key: UniqueKey(), now: _morning);
      return app;
    }

    testWidgets('shows the defaults: Monday to Friday, 7:00 AM and 11:00 PM, 10 minutes', (
      tester,
    ) async {
      await open(tester);
      expect(find.text('Mon to Fri'), findsOneWidget);
      expect(find.text('7:00 AM'), findsNWidgets(2));
      expect(find.text('11:00 PM'), findsNWidgets(2));
      expect(find.text('7:10 AM'), findsOneWidget);
      expect(find.text('10 min after you wake. On days off: 7:10 AM.'), findsOneWidget);
      expect(_enabled(tester, 'Save'), isFalse, reason: 'nothing changed yet');
    });

    testWidgets('shows what the server has', (tester) async {
      await open(tester, me: {...meJson(), 'schedule': _fixture('me')['schedule']});
      expect(find.text('6:30 AM'), findsOneWidget);
      expect(find.text('6:45 AM'), findsOneWidget);
      expect(find.text('15 min after you wake. On days off: 7:15 AM.'), findsOneWidget);
    });

    testWidgets('edits workdays and the offset, then saves one schedule object', (tester) async {
      final server = _server()..on('PATCH /api/me', StubResponse(200, meJson()));
      final app = await open(tester, server: server);
      await app.tap(find.bySemanticsLabel('Saturday'));
      expect(find.text('Mon to Sat'), findsNothing);
      await app.tap(find.bySemanticsLabel('Friday'));
      expect(find.text('Mon, Tue, Wed, Thu, Sat'), findsOneWidget);
      expect(_enabled(tester, 'Save'), isTrue);

      await app.tap(_chunky('Save'));
      expect(app.body('PATCH /api/me'), {
        'schedule': {
          'workdays': [1, 2, 3, 4, 6],
          'workday': {'wake': '07:00', 'bed': '23:00'},
          'dayOff': {'wake': '07:00', 'bed': '23:00'},
          'firstNotificationOffsetMin': 10,
        },
      });
    });

    test('a day start is the wait after waking, up to six hours', () {
      expect(dayStartOffset(3 * 60 + 40, 5 * 60 + 30), 110);
      expect(dayStartOffset(7 * 60, 7 * 60), 0);
      expect(dayStartOffset(7 * 60, 13 * 60), 360);
      expect(
        dayStartOffset(7 * 60, 6 * 60),
        0,
        reason: 'a start before waking is as soon as you wake',
      );
      expect(offsetLabel(110), '1 h 50 min after you wake');
      expect(offsetLabel(0), 'As soon as you wake');
    });

    testWidgets('a time field opens the time picker', (tester) async {
      final app = await open(tester);
      await app.tap(find.text('7:00 AM').first);
      expect(find.text('Wake up'), findsWidgets);
      expect(find.text('OK'), findsOneWidget);
      await app.tap(find.text('Cancel'));
      expect(_enabled(tester, 'Save'), isFalse);
    });

    testWidgets('a refused save says why and keeps the edit', (tester) async {
      final server = _server()
        ..on(
          'PATCH /api/me',
          const StubResponse(422, {'error': 'workday wake and bed must differ'}),
        );
      final app = await open(tester, server: server);
      await app.tap(find.bySemanticsLabel('Saturday'));
      await app.tap(_chunky('Save'));
      expect(find.text('workday wake and bed must differ'), findsOneWidget);
      expect(_enabled(tester, 'Save'), isTrue, reason: 'the edit is kept');
    });

    testWidgets('Me links to it with a summary', (tester) async {
      final app = TestApp(tester, _server(), surfaceHeight: 2400);
      await app.pump(const MeScreen(), key: UniqueKey(), now: _morning);
      expect(find.text('Mon to Fri, up at 7:00 AM'), findsOneWidget);
      await app.tap(find.text('Schedule'));
      expect(find.byType(SchedulePage), findsOneWidget);
    });
  });

  group('Log activity', () {
    Future<TestApp> open(WidgetTester tester) async {
      final app = TestApp(tester, _server());
      await app.pump(
        Builder(
          builder: (context) => Center(
            child: ElevatedButton(
              onPressed: () => showLogSheet(context, kind: LogKind.activity),
              child: const Text('Open'),
            ),
          ),
        ),
      );
      await app.tap(find.text('Open'));
      return app;
    }

    testWidgets('needs a name and minutes before it saves', (tester) async {
      final app = await open(tester);
      expect(find.text('Log activity'), findsOneWidget);
      expect(_enabled(tester, 'Save'), isFalse);
      await app.enter(find.byType(TextField).first, 'Swimming');
      expect(_enabled(tester, 'Save'), isTrue);
      await app.enter(find.byType(TextField).last, '0');
      expect(_enabled(tester, 'Save'), isFalse);
    });

    testWidgets('sends the name, minutes and intensity', (tester) async {
      final app = await open(tester);
      await app.enter(find.byType(TextField).first, '  Swimming ');
      await app.tap(find.text('+15'));
      await app.tap(find.text('Hard'));
      expect(find.text('Hard minutes count in full.'), findsOneWidget);
      await app.tap(_chunky('Save'));

      final body = app.body('POST /api/logs');
      expect(body['type'], 'other');
      expect(body['name'], 'Swimming');
      expect(body['quantity'], 45);
      expect(body['unit'], 'minutes');
      expect(body['intensity'], 'hard');
      expect(find.text('Added 45 min of Swimming'), findsOneWidget);
    });

    testWidgets('moderate is the default and easy says it counts half', (tester) async {
      final app = await open(tester);
      expect(find.text('Moderate minutes count in full.'), findsOneWidget);
      await app.tap(find.text('Easy'));
      expect(find.text('Easy minutes count half toward your exercise goal.'), findsOneWidget);
      await app.enter(find.byType(TextField).first, 'Stretching');
      await app.tap(_chunky('Save'));
      expect(app.body('POST /api/logs')['intensity'], 'easy');
    });

    testWidgets('a suggestion fills the name', (tester) async {
      final app = await open(tester);
      await app.tap(find.text('Run'));
      expect(tester.widget<TextField>(find.byType(TextField).first).controller!.text, 'Run');
    });

    testWidgets('caps the minutes at a day', (tester) async {
      final app = await open(tester);
      await app.enter(find.byType(TextField).first, 'Hike');
      await app.enter(find.byType(TextField).last, '1500');
      expect(find.text('At most 1,440 minutes'), findsOneWidget);
      expect(_enabled(tester, 'Save'), isFalse);
    });

    testWidgets('the exercise quest card has a plus that opens it', (tester) async {
      final today = richTodayJson(stepsEverSynced: true);
      today['quests'] = [
        ...today['quests']! as List<dynamic>,
        quest('exercise', 'Exercise', {'unit': 'min', 'target': 30}),
      ];
      final server = _server()..on('GET /api/today', StubResponse(200, today));
      final app = TestApp(tester, server, surfaceHeight: 3000);
      await app.pump(const TodayScreen(), key: UniqueKey(), now: _morning);
      await app.tap(find.bySemanticsLabel('Log an activity'));
      expect(find.text('Log activity'), findsOneWidget);
    });

    testWidgets('the workouts screen offers it even with no workouts', (tester) async {
      final app = TestApp(tester, _server(), surfaceHeight: 1600);
      await app.pump(const WorkoutsScreen(), key: UniqueKey(), now: _morning);
      await app.tap(find.text('LOG AN ACTIVITY'));
      expect(find.text('Log activity'), findsOneWidget);
    });

    test('exercise feeds the activity form', () {
      expect(LogKind.forQuest('exercise'), LogKind.activity);
      expect(LogKind.activity.questKey, 'exercise');
    });
  });

  group('Insights', () {
    Future<TestApp> open(WidgetTester tester, {Map<String, dynamic>? insights}) async {
      final server = _server();
      if (insights != null) server.on('GET /api/insights', StubResponse(200, insights));
      final app = TestApp(tester, server, surfaceHeight: 3200);
      await app.pump(const InsightsScreen(), key: UniqueKey(), now: _morning);
      return app;
    }

    testWidgets('weight is a smoothed trend with its weekly rate', (tester) async {
      await open(tester);
      expect(find.text('Weight'), findsOneWidget);
      expect(find.textContaining(' kg'), findsWidgets);
      expect(find.text('smoothed trend'), findsOneWidget);
      expect(find.text('down 0.4 kg a week'), findsOneWidget);
      expect(find.byType(Sparkline), findsOneWidget);
      expect(
        find.textContaining('Latest reading 82.4\u00a0kg'),
        findsOneWidget,
        reason: 'the raw reading is secondary, after the trend',
      );
    });

    testWidgets('with one weigh-in there is no rate and no chart', (tester) async {
      await open(
        tester,
        insights: {
          ..._fixture('insights'),
          'weight': {
            'latestKg': 82.6,
            'smoothedKg': 82.4,
            'weeklyRateKg': null,
            'points': [
              {'date': '2026-10-27', 'kg': 82.6, 'smoothed': 82.4},
            ],
          },
        },
      );
      expect(find.text('82.4\u00a0kg'), findsOneWidget);
      expect(find.textContaining('A weekly rate shows after a week'), findsOneWidget);
      expect(find.byType(Sparkline), findsNothing);
      expect(find.textContaining('Latest reading 82.6\u00a0kg'), findsOneWidget);
    });

    testWidgets('no weigh-ins at all says so', (tester) async {
      await open(
        tester,
        insights: {
          ..._fixture('insights'),
          'weight': {
            'latestKg': null,
            'smoothedKg': null,
            'weeklyRateKg': null,
            'points': <Object>[],
          },
        },
      );
      expect(find.textContaining('No weigh-ins yet'), findsOneWidget);
    });

    testWidgets('the WHO card compares minutes with 150 to 300 and strength days with 2', (
      tester,
    ) async {
      await open(tester);
      expect(find.text('Activity this week'), findsOneWidget);
      expect(find.text('285'), findsOneWidget);
      expect(find.text('of 150 to 300 min'), findsOneWidget);
      expect(find.text('In the 150 to 300 range'), findsOneWidget);
      expect(find.text('of 2 days'), findsOneWidget);
      expect(find.text('Done'), findsOneWidget);
      expect(find.textContaining('Hard minutes count double'), findsOneWidget);
    });

    testWidgets('below the range it says by how much, without advice', (tester) async {
      final base = _fixture('insights');
      await open(
        tester,
        insights: {
          ...base,
          'activity': {
            ...(base['activity'] as Map<String, dynamic>),
            'moderateEquivalentMin': 110,
            'strengthDays': 1,
            'meetsAerobic': false,
            'meetsStrength': false,
          },
        },
      );
      expect(find.text('Short by 40 min'), findsOneWidget);
      expect(find.text('1 more day'), findsOneWidget);
      expect(find.textContaining('should'), findsNothing);
    });

    testWidgets('protein shows the hit rate and where the target comes from', (tester) async {
      await open(tester);
      expect(find.text('5 of the last 7 days'), findsOneWidget);
      expect(find.text('71% of days'), findsOneWidget);
      expect(find.text('Target 130 g a day.'), findsOneWidget);
    });

    testWidgets('protein with nothing logged says so', (tester) async {
      await open(tester, insights: _fixture('insights'));
      expect(find.text('No protein logged in the last 7 days.'), findsOneWidget);
    });

    testWidgets('an older server shows no new cards, and nothing breaks', (tester) async {
      final base = {..._fixture('insights')}
        ..remove('activity')
        ..remove('protein')
        ..remove('weight');
      await open(tester, insights: base);
      expect(find.text('Activity this week'), findsNothing);
      expect(find.text('Protein'), findsNothing);
      expect(find.textContaining('No weigh-ins yet'), findsOneWidget);
    });

    testWidgets('Progress is the first card and opens the Progress screen', (tester) async {
      final app = await open(tester);
      final progressTop = tester.getTopLeft(find.text('Progress').first).dy;
      expect(progressTop, lessThan(tester.getTopLeft(find.text('Steps')).dy));
      await app.tap(find.text('Progress').first);
      expect(find.byType(ProgressScreen), findsOneWidget);
    });
  });

  group('Today shows the smoothed weight', () {
    testWidgets('a weight tile with the trend rides on the Body row', (tester) async {
      final handle = tester.ensureSemantics();
      final app = TestApp(tester, _server(), surfaceHeight: 3200);
      await app.pump(const TodayScreen(), key: UniqueKey(), now: _morning);
      expect(find.text('82.9\u00a0kg'), findsOneWidget);
      expect(find.text('down 0.4 kg a week'), findsOneWidget);
      expect(find.byIcon(Icons.trending_down_rounded), findsOneWidget);
      expect(
        find.bySemanticsLabel(RegExp('Body, .*weight 82.9\u00a0kg, down 0.4 kg a week')),
        findsOneWidget,
      );
      handle.dispose();
    });

    testWidgets('without a weigh-in the Body row has no tile', (tester) async {
      final server = _server()
        ..on(
          'GET /api/insights',
          StubResponse(200, {
            ..._fixture('insights'),
            'weight': {
              'latestKg': null,
              'smoothedKg': null,
              'weeklyRateKg': null,
              'points': <Object>[],
            },
          }),
        );
      final app = TestApp(tester, server, surfaceHeight: 3200);
      await app.pump(const TodayScreen(), key: UniqueKey(), now: _morning);
      expect(find.byIcon(Icons.monitor_weight_rounded), findsNothing);
    });
  });

  group('Progress', () {
    Future<TestApp> open(WidgetTester tester, {StubAdapter? server, double scale = 1.0}) async {
      tester.platformDispatcher.textScaleFactorTestValue = scale;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final app = TestApp(tester, server ?? _server(), surfaceHeight: 6000);
      await app.pump(const ProgressScreen(), key: UniqueKey(), now: _morning);
      return app;
    }

    testWidgets('starts on you, with a card per metric', (tester) async {
      await open(tester);
      expect(find.text('Reading'), findsOneWidget);
      expect(find.text('Steps'), findsOneWidget);
      expect(find.text('Resting heart rate'), findsOneWidget);
      expect(find.byType(Sparkline), findsWidgets);
      expect(find.textContaining(', 30 days'), findsWidgets);
      expect(find.textContaining('(30-day average)'), findsNothing);
    });

    testWidgets('lists you first, selected, with the partner second', (tester) async {
      await open(tester);
      final you = tester.getTopLeft(find.text('Nadia')).dx;
      final partner = tester.getTopLeft(find.text('Nick')).dx;
      expect(you, lessThan(partner));
      expect(
        tester.widget<Semantics>(find.widgetWithText(Semantics, 'Nadia').first).properties.selected,
        isTrue,
      );
    });

    testWidgets('each card has both comparisons and no line restating the number', (tester) async {
      await open(tester);
      expect(find.textContaining('Reading: 24 min a day'), findsNothing);
      expect(find.text('+6 (+33%) vs the previous month, better'), findsOneWidget);
      expect(find.text('+13 (+118%) vs your first month, better'), findsOneWidget);
      expect(find.text('-680 (-8%) vs the previous month, worse'), findsOneWidget);
      expect(find.text('About the same as the previous month'), findsWidgets);
    });

    testWidgets('arrows point where the number went, in the good colour', (tester) async {
      await open(tester);
      final readingCard = find
          .ancestor(of: find.text('Reading'), matching: find.byType(MergeSemantics))
          .first;
      final up = find.descendant(
        of: readingCard,
        matching: find.byIcon(Icons.arrow_upward_rounded),
      );
      expect(up, findsWidgets);
      expect(tester.widget<Icon>(up.first).color, isNot(const Color(0xFFB23C38)));
      final stepsCard = find
          .ancestor(of: find.text('Steps'), matching: find.byType(MergeSemantics))
          .first;
      final down = find.descendant(
        of: stepsCard,
        matching: find.byIcon(Icons.arrow_downward_rounded),
      );
      expect(
        tester.widget<Icon>(down.first).color,
        const Color(0xFFB23C38),
        reason: 'down is worse here',
      );
    });

    testWidgets('weight has no good direction, so its arrows stay neutral', (tester) async {
      await open(tester);
      final card = find
          .ancestor(of: find.text('Weight'), matching: find.byType(MergeSemantics))
          .first;
      final arrows = find.descendant(of: card, matching: find.byType(Icon));
      for (final icon in tester.widgetList<Icon>(arrows)) {
        expect(icon.color, isNot(const Color(0xFFB23C38)));
        expect(icon.color, isNot(const Color(0xFF237A4B)));
      }
    });

    testWidgets('a metric with no reading is left out instead of an empty card', (tester) async {
      await open(tester);
      expect(find.text('No data yet'), findsNothing);
      expect(find.byType(MetricCard), findsNWidgets(10));
    });

    testWidgets('a person with no habits kept gets no habits card', (tester) async {
      final data = _fixture('progress_rich');
      for (final person in data['people'] as List) {
        for (final m in (person as Map)['metrics'] as List) {
          if ((m as Map)['key'] == 'habits_kept') {
            m['current'] = 0.0;
          }
        }
      }
      await open(tester, server: _server()..on('GET /api/progress', StubResponse(200, data)));
      expect(find.text('Habits kept'), findsNothing);
    });

    testWidgets('the switcher shows the partner and back', (tester) async {
      final app = await open(tester);
      await app.tap(find.text('Nick'));
      expect(find.text('Reading'), findsOneWidget);
      final chip = find.bySemanticsLabel('Nick');
      expect(chip, findsOneWidget);
      await app.tap(find.text('Nadia'));
      expect(find.text('Reading'), findsOneWidget);
    });

    testWidgets('a new person sees one page note instead of the same lines on every card', (
      tester,
    ) async {
      final fresh = _fixture('progress');
      await open(tester, server: _server()..on('GET /api/progress', StubResponse(200, fresh)));
      expect(find.textContaining('Trends show after a second week'), findsOneWidget);
      expect(find.text('A trend shows after a second week.'), findsNothing);
      expect(find.textContaining('Comparisons appear once'), findsNothing);
    });

    testWidgets('a full history shows no sparse note', (tester) async {
      await open(tester);
      expect(find.textContaining('Trends show after a second week'), findsNothing);
    });

    testWidgets('a failure offers Try again', (tester) async {
      final server = _server()..on('GET /api/progress', const StubResponse(500, {'error': 'x'}));
      final app = await open(tester, server: server);
      expect(find.text('Could not load progress'), findsOneWidget);
      server.on('GET /api/progress', StubResponse(200, _fixture('progress_rich')));
      await app.tap(find.text('Try again'));
      expect(find.text('Reading'), findsOneWidget);
    });

    testWidgets('links to the look-back and the milestones', (tester) async {
      final app = await open(tester);
      await app.tap(find.text('Monthly look-back'));
      expect(find.byType(LookbackScreen), findsOneWidget);
      await app.tap(find.bySemanticsLabel('Back'));
      await app.tap(find.text('Milestones'));
      expect(find.byType(MilestonesPage), findsOneWidget);
    });

    testWidgets('the sparkline needs two readings, and breaks at a missing week', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Sparkline(values: [1, null, null], color: Colors.green, semanticLabel: 'x'),
        ),
      );
      expect(
        find.descendant(of: find.byType(Sparkline), matching: find.byType(CustomPaint)),
        findsNothing,
        reason: 'one reading draws no line',
      );
      const painter = SparklinePainter([1, null, 3, 2], Colors.green);
      final points = painter.points(const Size(100, 50));
      expect(points[1], isNull);
      expect(points[0]!.dx, lessThan(points[2]!.dx));
      expect(points[2]!.dy, lessThan(points[0]!.dy), reason: 'higher values sit higher');
      expect(
        const SparklinePainter([
          5,
          5,
          5,
        ], Colors.green).points(const Size(100, 50)).map((p) => p!.dy).toSet(),
        {25.0},
        reason: 'a flat series sits in the middle',
      );
    });
  });

  group('the monthly look-back', () {
    Future<TestApp> open(WidgetTester tester, {String? month, StubAdapter? server}) async {
      final app = TestApp(tester, server ?? _server(), surfaceHeight: 2400);
      await app.pump(
        LookbackScreen(month: month),
        key: UniqueKey(),
        now: _morning,
      );
      return app;
    }

    testWidgets('shows the couple and each person with their three biggest improvements', (
      tester,
    ) async {
      await open(tester);
      expect(find.text('September 2026'), findsWidgets);
      expect(find.text('Together'), findsOneWidget);
      expect(find.text('Nick'), findsOneWidget);
      expect(find.text('Nadia'), findsOneWidget);
      expect(find.text('Workouts: 3.3 a week, up from 2.6'), findsOneWidget);
      expect(find.text('Push-ups: 40 a day, up from 32'), findsOneWidget);
      expect(find.text('+25%'), findsOneWidget);
      expect(find.text('8,000 points, both counted on 19 days'), findsOneWidget);
      expect(find.text('4,120 points, 24 days counted'), findsOneWidget);
    });

    testWidgets('moves to the month before and back', (tester) async {
      final server = _server()
        ..routes['GET /api/lookback'] = (r) => StubResponse(200, {
          ..._fixture('lookback_rich'),
          'month': r.queryParameters['month'] ?? '2026-09',
        });
      final app = await open(tester, server: server);
      final loads = server.to('GET /api/lookback').length;
      await app.tap(find.bySemanticsLabel('Next month'));
      expect(
        server.to('GET /api/lookback'),
        hasLength(loads),
        reason: 'September is the newest month it may show',
      );
      await app.tap(find.bySemanticsLabel('Previous month'));
      expect(server.to('GET /api/lookback').last.queryParameters, {'month': '2026-08'});
      await app.tap(find.bySemanticsLabel('Next month'));
      expect(server.to('GET /api/lookback').last.queryParameters, {'month': '2026-09'});
    });

    testWidgets('a month in progress says so', (tester) async {
      final lb = {..._fixture('lookback_rich'), 'complete': false};
      await open(tester, server: _server()..on('GET /api/lookback', StubResponse(200, lb)));
      expect(find.textContaining('still going'), findsOneWidget);
    });

    testWidgets('a month with nothing to celebrate yet is honest about it', (tester) async {
      await open(
        tester,
        server: _server()..on('GET /api/lookback', StubResponse(200, _fixture('lookback'))),
      );
      expect(find.textContaining('No standout improvement this month'), findsNWidgets(3));
    });

    testWidgets('a failure offers Try again', (tester) async {
      final server = _server()..on('GET /api/lookback', const StubResponse(500, {'error': 'x'}));
      final app = await open(tester, server: server);
      expect(find.text('Could not load the look-back'), findsOneWidget);
      server.on('GET /api/lookback', StubResponse(200, _fixture('lookback_rich')));
      await app.tap(find.text('Try again'));
      expect(find.text('Together'), findsOneWidget);
    });
  });

  group('milestones', () {
    testWidgets('the list shows streaks and firsts, newest first, with who earned them', (
      tester,
    ) async {
      final app = TestApp(tester, _server());
      await app.pump(const MilestonesPage(), key: UniqueKey(), now: _morning);
      final titles = [
        '7 days together',
        '7-day streak',
        'First 10,000-step day',
        'First day with every quest done',
        'First fully counted week',
      ];
      var last = -1.0;
      for (final t in titles) {
        final y = tester.getTopLeft(find.text(t)).dy;
        expect(y, greaterThan(last), reason: t);
        last = y;
      }
      expect(find.textContaining('Together · '), findsOneWidget);
      expect(find.textContaining('You · '), findsNWidgets(4));
    });

    testWidgets('an empty list says what the first ones are', (tester) async {
      final server = _server()
        ..on('GET /api/milestones', StubResponse(200, _fixture('milestones_empty')));
      await TestApp(tester, server).pump(const MilestonesPage(), key: UniqueKey(), now: _morning);
      expect(find.textContaining('Your first one is a 7 day streak'), findsOneWidget);
    });

    group('the full-screen celebration', () {
      Map<String, dynamic> m(int id, String kind, int value, {bool shared = false}) => {
        'id': id,
        'kind': kind,
        'value': value,
        'shared': shared,
        'title': kind == 'streak' ? '$value-day streak' : '$value days together',
        'achievedOn': '2026-10-27',
      };

      Future<TestApp> open(WidgetTester tester, List<Map<String, dynamic>> ms) async {
        final today = {...richTodayJson(stepsEverSynced: true), 'newMilestones': ms};
        final server = _server()..on('GET /api/today', StubResponse(200, today));
        final app = TestApp(tester, server, surfaceHeight: 3000);
        await app.pump(const TodayScreen(), key: UniqueKey(), now: _morning);
        await app.settle(24);
        return app;
      }

      testWidgets('plays once, full screen, and is remembered', (tester) async {
        final app = await open(tester, [m(4, 'streak', 7)]);
        expect(find.byType(MilestoneCelebration), findsOneWidget);
        expect(find.text('7-day streak'), findsOneWidget);
        expect(find.text('7 days in a row. That is real consistency.'), findsOneWidget);
        expect(find.text('You'), findsOneWidget);
        expect(app.container.read(rightNowMemoryProvider).has(milestoneSeenKey(4)), isTrue);

        await app.tap(_chunky('Keep going'));
        expect(find.byType(MilestoneCelebration), findsNothing);
        unawaited(app.container.read(todayProvider.notifier).refresh());
        await app.settle(24);
        expect(find.byType(MilestoneCelebration), findsNothing, reason: 'once each');
      });

      testWidgets('shows several in a row and the shared one as Together', (tester) async {
        final app = await open(tester, [m(5, 'shared_streak', 7, shared: true), m(4, 'streak', 7)]);
        expect(find.text('7 days together'), findsOneWidget);
        expect(find.text('Together'), findsOneWidget);
        await app.tap(_chunky('Keep going'));
        await app.settle(24);
        expect(find.text('7-day streak'), findsOneWidget);
        await app.tap(_chunky('Keep going'));
        expect(find.byType(MilestoneCelebration), findsNothing);
      });

      testWidgets('a flood of firsts plays three and marks the rest seen', (tester) async {
        final app = await open(tester, [for (var i = 1; i <= 5; i++) m(i, 'first_week', 0)]);
        for (var i = 0; i < 3; i++) {
          expect(find.byType(MilestoneCelebration), findsOneWidget);
          await app.tap(_chunky('Keep going'));
          await app.settle(24);
        }
        expect(find.byType(MilestoneCelebration), findsNothing);
        final memory = app.container.read(rightNowMemoryProvider);
        expect([
          for (var i = 1; i <= 5; i++) memory.has(milestoneSeenKey(i)),
        ], everyElement(isTrue));
      });

      testWidgets('nothing new, nothing plays', (tester) async {
        await open(tester, const []);
        expect(find.byType(MilestoneCelebration), findsNothing);
      });

      testWidgets('fits at text scale 2.0 with a 44pt button', (tester) async {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        tester.platformDispatcher.textScaleFactorTestValue = 2.0;
        addTearDown(tester.view.reset);
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        await TestApp(tester, _server()).pump(
          MilestoneCelebration(
            milestone: Milestone.tryParse(m(5, 'shared_streak', 365, shared: true))!,
          ),
          tall: false,
        );
        expect(tester.takeException(), isNull);
        expect(tester.getSize(_chunky('Keep going')).height, greaterThanOrEqualTo(44));
      });
    });
  });

  group('notification switches for milestones and the look-back', () {
    testWidgets('each sends a partial PATCH and the count follows', (tester) async {
      final server = _server()
        ..on(
          'PATCH /api/me',
          StubResponse(200, {
            ...meJson(),
            'notifications': {'milestones': false},
          }),
        );
      final app = TestApp(tester, server, surfaceHeight: 2200);
      await app.pump(const NotificationsPage(), key: UniqueKey(), now: _morning);
      expect(find.text('Milestones'), findsOneWidget);
      expect(find.text('Monthly look-back'), findsOneWidget);
      await app.tap(find.text('Milestones'));
      expect(app.body('PATCH /api/me'), {
        'notifications': {'milestones': false},
      });
      server.on(
        'PATCH /api/me',
        StubResponse(200, {
          ...meJson(),
          'notifications': {'lookback': false},
        }),
      );
      await app.tap(find.text('Monthly look-back'));
      expect(app.body('PATCH /api/me'), {
        'notifications': {'lookback': false},
      });
    });
  });
}
