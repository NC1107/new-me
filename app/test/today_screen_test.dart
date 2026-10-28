import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:newme/features/food/food_card.dart';
import 'package:newme/features/insights/insights_screen.dart';
import 'package:newme/features/shell/home_tab.dart';
import 'package:newme/features/today/day_counted_sheet.dart';
import 'package:newme/features/today/today_screen.dart';
import 'package:newme/health/fake_health_source.dart';
import 'package:newme/state/local_prefs.dart';
import 'package:newme/state/today.dart';
import 'package:newme/widgets/chunky_button.dart';
import 'package:newme/widgets/mascot.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fixtures.dart';
import 'test_support.dart';

Finder _chunky(String label) =>
    find.byWidgetPredicate((w) => w is ChunkyButton && w.label == label);

/// Today is long with every card present, so the surface is tall enough to build all of it.
TestApp _app(
  WidgetTester tester,
  StubAdapter adapter, {
  FakeHealthSource? health,
  double height = 2800,
}) => TestApp(tester, adapter, health: health, surfaceHeight: height);

StubAdapter _serverWithBody({Map<String, dynamic>? health}) {
  final today = richTodayJson(stepsEverSynced: true);
  if (health != null) today['health'] = {...today['health']! as Map<String, dynamic>, ...health};
  return fullServer()
    ..on('GET /api/today', StubResponse(200, today))
    ..on(
      'GET /api/health/trends',
      const StubResponse(200, {
        'metric': 'weight_kg',
        'points': [
          {'date': '2026-10-20', 'value': 82.8},
          {'date': '2026-10-26', 'value': 82.4},
        ],
      }),
    );
}

void main() {
  setUp(() {
    FakeStorage().install();
    Mascot.idleMotion = false;
  });

  testWidgets('renders the top bar, header, day card, quest states, connect card and food', (
    tester,
  ) async {
    final app = _app(tester, fullServer());
    await app.pump(const TodayScreen());

    expect(find.text('Monday, Oct 26'), findsOneWidget);
    expect(find.textContaining('Sam'), findsWidgets);
    expect(find.text('150'), findsOneWidget, reason: "today's points beside the gem");
    expect(find.text('3'), findsOneWidget, reason: 'the streak beside the flame');
    expect(find.text('88%'), findsOneWidget);
    expect(find.text('130 of 280 points'), findsOneWidget);
    expect(find.textContaining('Reach 100% to keep your streak going'), findsOneWidget);
    expect(find.text('Nice, keep it rolling.'), findsOneWidget);

    expect(find.text('Get stronger'), findsOneWidget);
    expect(find.text('+20'), findsOneWidget);
    expect(find.byIcon(Icons.check_rounded), findsOneWidget);
    expect(find.text('30 of 30 push-ups'), findsOneWidget);
    expect(find.text('Read 20 min or 15 pages'), findsOneWidget);
    expect(find.text('12 min + 5 pages'), findsOneWidget);
    expect(find.text('Log 2 meals'), findsOneWidget);

    expect(_chunky('Connect Health'), findsOneWidget);
    expect(find.text('Walk 8,000 steps'), findsNothing);

    expect(find.text('Log 2 meals'), findsOneWidget, reason: 'food is a quest here');
    expect(find.text('1,850 of 2,200 kcal'), findsNothing, reason: 'the food card lives on Food');
    expect(find.byType(FoodCard), findsNothing);
    expect(find.textContaining('Health synced'), findsNothing, reason: 'synced 3h ago is quiet');
  });

  testWidgets('Today mentions Health only once it has been silent for over 12 hours', (
    tester,
  ) async {
    Future<void> openAt(DateTime now) async {
      await _app(tester, fullServer()).pump(const TodayScreen(), key: UniqueKey(), now: now);
    }

    // The fixture synced at 11:00Z; the clock sits at 14:00Z in the other tests.
    await openAt(testNow.add(const Duration(hours: 9)));
    expect(find.textContaining('Health synced'), findsNothing, reason: '12 hours is not stale');

    await openAt(testNow.add(const Duration(hours: 10)));
    expect(find.text('Health synced 13h ago'), findsOneWidget);
  });

  testWidgets('manual quests get a plus, automatic ones one Health note', (tester) async {
    final today = richTodayJson(stepsEverSynced: true);
    today['quests'] = [
      ...today['quests']! as List<dynamic>,
      quest('sleep', 'Sleep', {'unit': 'min', 'target': 420, 'actual': 330, 'basePoints': 39}),
      quest('exercise', 'Exercise', {'unit': 'min', 'target': 30}),
    ];
    final adapter = fullServer()..on('GET /api/today', StubResponse(200, today));
    await _app(tester, adapter).pump(const TodayScreen());

    expect(find.text('Walk 8,000 steps'), findsOneWidget);
    expect(find.text('Sleep 7 h'), findsOneWidget);
    expect(find.text('5 h 30 min of 7 h'), findsNothing, reason: 'the title states the target');
    expect(find.text('Exercise 30 min'), findsOneWidget);
    expect(find.text('From Apple Health'), findsOneWidget, reason: 'once, not on every card');
    expect(find.text('Apple Health'), findsNothing);
    expect(
      find.byIcon(Icons.add_rounded),
      findsNWidgets(4),
      reason: '3 manual quests and the food quest',
    );
  });

  testWidgets('a counted day says so in the bubble and the day card', (tester) async {
    final adapter = fullServer()
      ..on('GET /api/today', StubResponse(200, richTodayJson(counted: true, percent: 75)));
    final app = _app(tester, adapter);
    await app.pump(const TodayScreen());
    expect(find.text('Streak saved for today!'), findsOneWidget);
    expect(find.textContaining('Goal reached'), findsOneWidget);
    expect(find.textContaining('Reach 100%'), findsNothing);
    await app.closeSheet();
  });

  testWidgets('tapping the flame explains the streak rule and the freezes', (tester) async {
    final adapter = fullServer()..on('GET /api/today', StubResponse(200, richTodayJson(streak: 0)));
    final app = _app(tester, adapter);
    await app.pump(const TodayScreen());

    await app.tap(find.bySemanticsLabel(RegExp(r'day streak')));
    expect(find.text('Day 1'), findsOneWidget);
    expect(find.textContaining('reach 100% of the day'), findsOneWidget);
    expect(find.text('Earning and using freezes'), findsOneWidget);
    expect(find.text('0 of 2 freezes'), findsOneWidget);
  });

  testWidgets('a freeze that covered a day names the weekday', (tester) async {
    final today = richTodayJson();
    (today['streak']! as Map<String, dynamic>)
      ..['restAvailable'] = false
      ..['restUsedOn'] = '2026-10-20';
    final adapter = fullServer()..on('GET /api/today', StubResponse(200, today));
    final app = _app(tester, adapter);
    await app.pump(const TodayScreen());
    await app.tap(find.bySemanticsLabel(RegExp(r'day streak')));
    expect(find.text('A freeze covered Tue.'), findsOneWidget);
  });

  testWidgets('with nothing logged and a rest day ready the mascot says so', (tester) async {
    final adapter = fullServer()
      ..on('GET /api/today', StubResponse(200, richTodayJson(points: 0, percent: 0)));
    await _app(tester, adapter).pump(const TodayScreen());
    expect(find.text('A freeze is ready'), findsOneWidget);
  });

  testWidgets('the partner mini avatar opens Us and the own avatar opens Me', (tester) async {
    final adapter = fullServer()
      ..on(
        'GET /api/board',
        StubResponse(
          200,
          board([boardUser(2, 'Sam', 'violet'), boardUser(1, 'Nick', 'green', percent: 41)]),
        ),
      );
    final app = _app(tester, adapter);
    await app.pump(const TodayScreen());

    await app.tap(find.bySemanticsLabel('Nick, 58 percent of the goal today, open Us'));
    expect(app.container.read(homeTabProvider), HomeTab.board);
    await app.tap(find.bySemanticsLabel('Sam, open Me'));
    expect(app.container.read(homeTabProvider), HomeTab.me);
  });

  testWidgets('no partner on the board leaves the corner empty', (tester) async {
    final app = _app(tester, fullServer());
    await app.pump(const TodayScreen());
    expect(find.bySemanticsLabel(RegExp(r'open Us')), findsNothing);
  });

  testWidgets('Today has no week strip and no food card, only the top bar flame', (tester) async {
    final app = _app(tester, fullServer());
    await app.pump(const TodayScreen());

    expect(find.text('This week'), findsNothing);
    expect(find.byIcon(Icons.bedtime_rounded), findsNothing);
    expect(
      find.byIcon(Icons.local_fire_department_rounded),
      findsOneWidget,
      reason: 'the top bar flame; burned calories moved to Food',
    );
  });

  testWidgets('the Body row summarises sleep and opens Insights; weight stays off Today', (
    tester,
  ) async {
    final adapter = _serverWithBody(
      health: {
        'metrics': {'sleep_minutes': 432, 'resting_hr': 58, 'hrv_ms': 47},
        'latest': {
          'weight_kg': {'value': 82.4, 'date': '2026-10-26'},
        },
      },
    );
    final app = _app(tester, adapter);
    await app.pump(const TodayScreen());

    expect(find.text('Body'), findsOneWidget);
    expect(find.textContaining('Slept 7 h 12 min'), findsOneWidget);
    expect(find.text('82.4'), findsNothing);
    expect(find.text('58'), findsNothing);
    expect(adapter.to('GET /api/health/trends'), isEmpty);

    await app.tap(find.text('Body'));
    expect(find.byType(InsightsScreen), findsOneWidget);
  });

  testWidgets('without health metrics the Body row still points at Insights', (tester) async {
    await _app(tester, fullServer()).pump(const TodayScreen());
    expect(find.text('Body'), findsOneWidget);
    expect(find.text('Steps, sleep and workouts'), findsOneWidget);
  });

  testWidgets('after the Health prompt a missing steps row shows the hint, not a button', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({'healthPrompted': true});
    await _app(tester, fullServer()).pump(const TodayScreen());

    expect(
      find.text('No steps yet. Open Health > Sharing > Apps > New Me and allow Steps.'),
      findsOneWidget,
    );
    expect(_chunky('Connect Health'), findsNothing);
  });

  testWidgets('once steps have arrived the steps quest is a normal card', (tester) async {
    final today = richTodayJson(stepsEverSynced: true);
    ((today['quests']! as List).first as Map<String, dynamic>)['actual'] = 2000;
    final adapter = fullServer()..on('GET /api/today', StubResponse(200, today));
    await _app(tester, adapter).pump(const TodayScreen());

    expect(_chunky('Connect Health'), findsNothing);
    expect(find.text('2,000 of 8,000 steps'), findsNothing);
    expect(find.text('Walk 8,000 steps'), findsOneWidget);
  });

  testWidgets('the connect card asks Health for access from a tap', (tester) async {
    final health = FakeHealthSource();
    final app = _app(tester, fullServer(), health: health);
    await app.pump(const TodayScreen());

    await app.tap(_chunky('Connect Health'));
    expect(health.accessRequests, 1);
    expect(
      find.text('No steps yet. Open Health > Sharing > Apps > New Me and allow Steps.'),
      findsOneWidget,
    );
  });

  testWidgets('a quest plus opens the log sheet for that metric', (tester) async {
    final app = _app(tester, fullServer());
    await app.pump(const TodayScreen());

    await app.tap(find.bySemanticsLabel('Add entry for Read 20 min or 15 pages'));
    expect(find.text('Log reading'), findsOneWidget);
    expect(find.text('Minutes'), findsWidgets);
    expect(find.text('Pages'), findsOneWidget);
  });

  testWidgets('the food quest plus opens the meal form', (tester) async {
    final app = _app(tester, fullServer());
    await app.pump(const TodayScreen());

    await app.tap(find.bySemanticsLabel('Add entry for Log 2 meals'));
    expect(find.text('Log a meal'), findsOneWidget);
    expect(find.text('Portion'), findsOneWidget);
  });

  testWidgets('steps have no plus button', (tester) async {
    final today = richTodayJson(stepsEverSynced: true);
    final adapter = fullServer()..on('GET /api/today', StubResponse(200, today));
    await _app(tester, adapter).pump(const TodayScreen());
    expect(
      find.byIcon(Icons.add_rounded),
      findsNWidgets(3),
      reason: '3 manual quests, food is the third',
    );
    expect(find.bySemanticsLabel(RegExp(r'^Add entry for Walk')), findsNothing);
  });

  testWidgets('a failed load with nothing cached says so and Try again recovers', (tester) async {
    final adapter = fullServer()..on('GET /api/today', const StubResponse.unreachable());
    final app = _app(tester, adapter);
    await app.pump(const TodayScreen());

    expect(find.text('Could not load today'), findsOneWidget);
    expect(find.textContaining('You are offline'), findsOneWidget);

    adapter.on('GET /api/today', StubResponse(200, richTodayJson()));
    await app.tap(find.text('Try again'));
    expect(find.text('88%'), findsOneWidget);
  });

  testWidgets('with a cache the screen stays up under the offline banner', (tester) async {
    final adapter = fullServer();
    final app = _app(tester, adapter);
    await app.pump(const TodayScreen(), key: UniqueKey());
    expect(find.textContaining('Offline'), findsNothing);

    adapter.on('GET /api/today', const StubResponse.unreachable());
    await app.pump(const TodayScreen(), key: UniqueKey());
    expect(find.textContaining('Offline - updated'), findsOneWidget);
    expect(find.text('88%'), findsOneWidget);
  });

  testWidgets('a failed refresh keeps the day beneath the error', (tester) async {
    final adapter = fullServer();
    final app = _app(tester, adapter);
    await app.pump(const TodayScreen());

    adapter.on('GET /api/today', const StubResponse(422, {'error': 'nope'}));
    unawaited(app.container.read(todayProvider.notifier).refresh());
    await app.settle();
    expect(find.text('Could not load today'), findsOneWidget);
    expect(find.text('88%'), findsOneWidget);
  });

  testWidgets('pull to refresh syncs Health and reloads the day', (tester) async {
    SharedPreferences.setMockInitialValues({'healthPrompted': true});
    final health = FakeHealthSource();
    final adapter = fullServer()
      ..on('PUT /api/health/daily', const StubResponse(200, {'days': <Object>[]}));
    // A surface much taller than the list leaves the drag starting below the content.
    final app = _app(tester, adapter, health: health, height: 1500);
    await app.pump(const TodayScreen());
    final loads = adapter.to('GET /api/today').length;
    final reads = health.reads.length;

    health.steps = 5000;
    await tester.fling(find.byType(ListView).first, const Offset(0, 400), 1000);
    await app.settle(30);

    expect(health.reads.length, greaterThan(reads));
    expect(adapter.to('GET /api/today').length, greaterThan(loads));
  });

  group('day counted celebration', () {
    StubAdapter counted() =>
        fullServer()..on('GET /api/today', StubResponse(200, richTodayJson(counted: true)));

    testWidgets('plays once, remembers the date, and does not play again', (tester) async {
      final app = _app(tester, counted());
      await app.pump(const TodayScreen(), key: UniqueKey());

      expect(find.byType(DayCountedSheet), findsOneWidget);
      expect(find.text('Day counted!'), findsOneWidget);
      expect(await LocalPrefs.celebratedDate(), '2026-10-26');

      await app.closeSheet();
      expect(find.byType(DayCountedSheet), findsNothing);

      await tester.pumpWidget(const SizedBox());
      await app.pump(const TodayScreen(), key: UniqueKey());
      expect(find.byType(DayCountedSheet), findsNothing);
    });

    testWidgets('a new date celebrates again', (tester) async {
      SharedPreferences.setMockInitialValues({'celebratedDate': '2026-10-25'});
      await _app(tester, counted()).pump(const TodayScreen());
      expect(find.byType(DayCountedSheet), findsOneWidget);
    });

    testWidgets('an uncounted day never celebrates', (tester) async {
      await _app(tester, fullServer()).pump(const TodayScreen());
      expect(find.byType(DayCountedSheet), findsNothing);
      expect(await LocalPrefs.celebratedDate(), isNull);
    });

    testWidgets('the streak counts up to today and Continue closes the sheet', (tester) async {
      final app = _app(tester, counted());
      await app.pump(const TodayScreen());
      await app.settle(30);
      expect(find.text('3'), findsWidgets);
      expect(find.text('days in a row'), findsOneWidget);

      await app.tap(_chunky('Continue'));
      expect(find.byType(DayCountedSheet), findsNothing);
    });

    Finder streakNumber() => find.descendant(
      of: find.byType(DayCountedSheet),
      matching: find.byWidgetPredicate(
        (w) => w is Text && w.style?.fontSize == 72 && w.data != null,
      ),
    );

    testWidgets('with animations disabled the streak is already final', (tester) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue = const FakeAccessibilityFeatures(
        disableAnimations: true,
      );
      addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
      final app = _app(tester, counted());
      await app.pump(const TodayScreen());
      expect(tester.widget<Text>(streakNumber()).data, '3');
    });

    testWidgets('a day drawn from the offline cache does not celebrate', (tester) async {
      final adapter = counted();
      final app = _app(tester, adapter);
      await app.pump(const TodayScreen(), key: UniqueKey());
      await app.closeSheet();
      await (await SharedPreferences.getInstance()).remove('celebratedDate');

      adapter.on('GET /api/today', const StubResponse.unreachable());
      await app.pump(const TodayScreen(), key: UniqueKey());
      expect(find.textContaining('Offline - updated'), findsOneWidget);
      expect(find.byType(DayCountedSheet), findsNothing);
    });
  });
}
