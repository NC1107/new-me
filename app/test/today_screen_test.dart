import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:newme/features/today/today_screen.dart';
import 'package:newme/health/fake_health_source.dart';
import 'package:newme/state/today.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fixtures.dart';
import 'test_support.dart';

void main() {
  setUp(FakeStorage().install);

  testWidgets('renders the ring, quest states, the connect card and the food card', (tester) async {
    final app = TestApp(tester, fullServer());
    await app.pump(const TodayScreen());

    expect(find.text('Monday, Oct 26'), findsOneWidget);
    expect(find.text('150'), findsOneWidget);
    expect(find.text('62%'), findsOneWidget);
    expect(find.text('Streak line: 70% - you are at 62%'), findsOneWidget);
    expect(find.text('Day 3'), findsOneWidget);
    expect(find.text('Rest day ready'), findsOneWidget);

    expect(find.text('Pushups'), findsOneWidget);
    expect(find.text('+20'), findsOneWidget);
    expect(find.byIcon(Icons.check_circle_rounded), findsOneWidget);
    expect(find.text('30 / 30 reps'), findsOneWidget);
    expect(find.text('12 min + 5 pages'), findsOneWidget);
    expect(find.text('1 / 2 meals'), findsOneWidget);

    expect(find.widgetWithText(OutlinedButton, 'Connect Health'), findsOneWidget);
    expect(find.text('8,000 steps'), findsNothing);

    expect(find.text('1,850 / 2,200 kcal'), findsOneWidget);
    expect(find.text('82 / 150 g'), findsOneWidget);
    expect(find.text('200 g'), findsOneWidget);
    expect(find.text('burned 540'), findsOneWidget);
    expect(find.text('Set your targets'), findsOneWidget);
    expect(find.text('Health synced 3h ago'), findsOneWidget);
    expect(find.text('Nothing yet today.'), findsNothing);
  });

  testWidgets('a counted day says so instead of showing the line', (tester) async {
    final adapter = fullServer()
      ..on('GET /api/today', StubResponse(200, richTodayJson(counted: true, percent: 75)));
    await TestApp(tester, adapter).pump(const TodayScreen());
    expect(find.text('Streak day counted'), findsOneWidget);
    expect(find.textContaining('Streak line'), findsNothing);
  });

  testWidgets('a zero streak reads Day 1 and tapping it explains the rule', (tester) async {
    final adapter = fullServer()..on('GET /api/today', StubResponse(200, richTodayJson(streak: 0)));
    final app = TestApp(tester, adapter);
    await app.pump(const TodayScreen());

    expect(find.text('Day 1'), findsOneWidget);
    await app.tap(find.text('Day 1'));
    expect(find.textContaining('reach the streak line, 70% of the day'), findsOneWidget);
    expect(find.textContaining('One missed day a week is forgiven'), findsOneWidget);
    expect(find.text('Rest day ready'), findsWidgets);
  });

  testWidgets('a used rest day names the weekday', (tester) async {
    final today = richTodayJson();
    (today['streak']! as Map<String, dynamic>)
      ..['restAvailable'] = false
      ..['restUsedOn'] = '2026-10-20';
    final adapter = fullServer()..on('GET /api/today', StubResponse(200, today));
    await TestApp(tester, adapter).pump(const TodayScreen());
    expect(find.text('Rest day used Tue'), findsOneWidget);
  });

  testWidgets('after the Health prompt a missing steps row shows the hint, not a button', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({'healthPrompted': true});
    await TestApp(tester, fullServer()).pump(const TodayScreen());

    expect(
      find.text('No steps yet. Open Health > Sharing > Apps > New Me and allow Steps.'),
      findsOneWidget,
    );
    expect(find.text('Connect Health'), findsNothing);
  });

  testWidgets('once steps have arrived the steps quest is a normal card', (tester) async {
    final today = richTodayJson(hasSteps: true);
    ((today['quests']! as List).first as Map<String, dynamic>)['actual'] = 2000;
    final adapter = fullServer()..on('GET /api/today', StubResponse(200, today));
    await TestApp(tester, adapter).pump(const TodayScreen());

    expect(find.text('Connect Health'), findsNothing);
    expect(find.text('2,000 / 8,000 steps'), findsOneWidget);
  });

  testWidgets('the connect card asks Health for access from a tap', (tester) async {
    final health = FakeHealthSource();
    final app = TestApp(tester, fullServer(), health: health);
    await app.pump(const TodayScreen());

    await app.tap(find.widgetWithText(OutlinedButton, 'Connect Health'));
    expect(health.accessRequests, 1);
    expect(
      find.text('No steps yet. Open Health > Sharing > Apps > New Me and allow Steps.'),
      findsOneWidget,
    );
  });

  testWidgets('the plus button opens the log sheet on that metric', (tester) async {
    final app = TestApp(tester, fullServer());
    await app.pump(const TodayScreen());

    await app.tap(find.byIcon(Icons.add_rounded).at(1));
    expect(find.text('Minutes'), findsWidgets);
    expect(find.text('Pages'), findsOneWidget);
    expect(find.text('Quick add'), findsNothing);
  });

  testWidgets('steps have no plus button', (tester) async {
    final today = richTodayJson(hasSteps: true);
    final adapter = fullServer()..on('GET /api/today', StubResponse(200, today));
    await TestApp(tester, adapter).pump(const TodayScreen());
    expect(find.byIcon(Icons.add_rounded), findsNWidgets(3));
  });

  testWidgets('a failed load with nothing cached says so and Try again recovers', (tester) async {
    final adapter = fullServer()..on('GET /api/today', const StubResponse.unreachable());
    final app = TestApp(tester, adapter);
    await app.pump(const TodayScreen());

    expect(find.text('Could not load today'), findsOneWidget);
    expect(find.textContaining('You are offline'), findsOneWidget);

    adapter.on('GET /api/today', StubResponse(200, richTodayJson()));
    await app.tap(find.text('Try again'));
    expect(find.text('Streak line: 70% - you are at 62%'), findsOneWidget);
  });

  testWidgets('with a cache the screen stays up under the offline banner', (tester) async {
    final adapter = fullServer();
    final app = TestApp(tester, adapter);
    await app.pump(const TodayScreen(), key: UniqueKey());
    expect(find.textContaining('Offline'), findsNothing);

    adapter.on('GET /api/today', const StubResponse.unreachable());
    await app.pump(const TodayScreen(), key: UniqueKey());
    expect(find.text('Offline - updated 09:00'), findsNothing);
    expect(find.textContaining('Offline - updated'), findsOneWidget);
    expect(find.text('Streak line: 70% - you are at 62%'), findsOneWidget);
  });

  testWidgets('a failed refresh keeps the day beneath the error', (tester) async {
    final adapter = fullServer();
    final app = TestApp(tester, adapter);
    await app.pump(const TodayScreen());

    adapter.on('GET /api/today', const StubResponse(422, {'error': 'nope'}));
    unawaited(app.container.read(todayProvider.notifier).refresh());
    await app.settle();
    expect(find.text('Could not load today'), findsOneWidget);
    expect(find.text('Streak line: 70% - you are at 62%'), findsOneWidget);
  });

  testWidgets('pull to refresh syncs Health and reloads the day', (tester) async {
    SharedPreferences.setMockInitialValues({'healthPrompted': true});
    final health = FakeHealthSource();
    final adapter = fullServer()
      ..on('PUT /api/health/daily', const StubResponse(200, {'days': <Object>[]}));
    final app = TestApp(tester, adapter, health: health);
    await app.pump(const TodayScreen());
    final loads = adapter.to('GET /api/today').length;
    final reads = health.reads.length;

    health.steps = 5000;
    await tester.fling(find.byType(ListView).first, const Offset(0, 400), 1000);
    await app.settle(30);

    expect(health.reads.length, greaterThan(reads));
    expect(adapter.to('GET /api/today').length, greaterThan(loads));
  });

  testWidgets('the ring counts up on the first view of a day only', (tester) async {
    final app = TestApp(tester, fullServer());
    await app.pump(const TodayScreen(), key: UniqueKey());
    expect(await _countUpDate(), '2026-10-26');

    await tester.pumpWidget(const SizedBox());
    await app.pump(const TodayScreen(), key: UniqueKey());
    await tester.pump();
    expect(find.text('150'), findsOneWidget);
  });
}

Future<String?> _countUpDate() async =>
    (await SharedPreferences.getInstance()).getString('countUpDate');
