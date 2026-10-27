import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:newme/health/fake_health_source.dart';
import 'package:newme/health/health_source_factory.dart';
import 'package:newme/state/clock.dart';
import 'package:newme/state/session.dart';
import 'package:newme/state/timezone.dart';
import 'package:newme/theme/accent.dart';

import 'test_support.dart';

/// Midday UTC: 08:00 in New York, so yesterday is still open and the sync footer reads "3h ago".
final testNow = DateTime.utc(2026, 10, 26, 14, 0);

const _questDefaults = {
  'unit': 'reps',
  'targetAlt': null,
  'unitAlt': null,
  'actual': 0,
  'actualAlt': null,
  'points': 100,
  'basePoints': 0,
  'bonusPoints': 0,
  'done': false,
};

Map<String, dynamic> quest(String key, String title, Map<String, dynamic> fields) => {
  'key': key,
  'title': title,
  ..._questDefaults,
  ...fields,
};

Map<String, dynamic> dayJson({int points = 150, int percent = 62, bool counted = false}) => {
  'basePoints': points - 20,
  'bonusPoints': 20,
  'points': points,
  'maxBase': 400,
  'percent': percent,
  'counted': counted,
  'streakLine': 70,
};

final _richQuests = [
  quest('steps', 'Steps', {'unit': 'steps', 'target': 8000}),
  quest('pushups', 'Pushups', {
    'target': 30,
    'actual': 30,
    'basePoints': 100,
    'bonusPoints': 20,
    'done': true,
  }),
  quest('reading', 'Reading', {
    'unit': 'minutes',
    'unitAlt': 'pages',
    'target': 20,
    'targetAlt': 15,
    'actual': 12,
    'actualAlt': 5,
    'basePoints': 93,
  }),
  quest('meals_logged', 'Meals', {
    'unit': 'meals',
    'target': 2,
    'actual': 1,
    'basePoints': 25,
    'points': 50,
  }),
];

const _noTargets = {'kcal': null, 'protein': null, 'carbs': null, 'fat': null};

/// A mid-day fixture: pushups done with the bonus, reading and meals partway, steps never synced,
/// and only two of four food targets set.
Map<String, dynamic> richTodayJson({
  bool stepsEverSynced = false,
  int streak = 3,
  bool counted = false,
  Object? backdateUntil = '2026-10-26T15:00:00Z',
  int points = 150,
  int percent = 62,
}) => {
  'date': '2026-10-26',
  'localToday': '2026-10-26',
  'backdateUntil': backdateUntil,
  'serverNow': '2026-10-26T14:00:00Z',
  'quests': _richQuests,
  'day': dayJson(points: points, percent: percent, counted: counted),
  'streak': {'current': streak, 'restAvailable': true, 'restUsedOn': null},
  'food': {
    'kcal': 1850,
    'protein': 82,
    'carbs': 200,
    'fat': 60,
    'fiber': 24,
    'burned': 540,
    'targets': {..._noTargets, 'kcal': 2200, 'protein': 150},
  },
  'health': {'stepsEverSynced': stepsEverSynced, 'syncedAt': '2026-10-26T11:00:00Z'},
};

Map<String, dynamic> _template(
  String key,
  String title,
  num target,
  String unit,
  int points,
  int position, {
  bool enabled = true,
  num? targetAlt,
  String? unitAlt,
}) => {
  'key': key,
  'title': title,
  'enabled': enabled,
  'target': target,
  'unit': unit,
  'targetAlt': targetAlt,
  'unitAlt': unitAlt,
  'points': points,
  'position': position,
};

Map<String, dynamic> meJson({
  bool admin = false,
  bool yoga = false,
  String color = 'violet',
  String timezone = 'America/New_York',
}) => {
  'user': {'id': 2, 'name': 'Sam', 'color': color, 'timezone': timezone, 'isAdmin': admin},
  'targets': {..._noTargets, 'kcal': 2200, 'protein': 150},
  'questTemplates': [
    _template('steps', 'Steps', 8000, 'steps', 100, 0),
    _template('pushups', 'Pushups', 30, 'reps', 100, 1),
    _template('reading', 'Reading', 20, 'minutes', 100, 2, targetAlt: 15, unitAlt: 'pages'),
    _template('yoga', 'Yoga', 20, 'minutes', 50, 5, enabled: yoga),
  ],
  'localToday': '2026-10-26',
  'backdateUntil': '2026-10-26T15:00:00Z',
  'serverNow': '2026-10-26T14:00:00Z',
};

Map<String, dynamic> boardUser(
  int id,
  String name,
  String color, {
  int points = 120,
  int percent = 30,
  int week = 300,
  int season = 900,
  int streak = 4,
  List<Map<String, dynamic>>? last7,
}) => {
  'id': id,
  'name': name,
  'color': color,
  'today': {'points': points, 'percent': percent, 'counted': false},
  'week': {'points': week},
  'season': {'points': season},
  'streak': {'current': streak},
  'last7':
      last7 ??
      [
        {'date': '2026-10-20', 'percent': 90, 'counted': true, 'rest': false},
        {'date': '2026-10-21', 'percent': 20, 'counted': false, 'rest': false},
        {'date': '2026-10-22', 'percent': 10, 'counted': false, 'rest': true},
        {'date': '2026-10-23', 'percent': 80, 'counted': true, 'rest': false},
        {'date': '2026-10-24', 'percent': 75, 'counted': true, 'rest': false},
        {'date': '2026-10-25', 'percent': 100, 'counted': true, 'rest': false},
        {'date': '2026-10-26', 'percent': 30, 'counted': false, 'rest': false},
      ],
  'syncedAt': '2026-10-26T11:00:00Z',
};

Map<String, dynamic> board(List<Map<String, dynamic>> users) => {
  'season': {'name': 'Season 0', 'startsOn': '2026-10-01', 'endsOn': '2026-12-31'},
  'serverNow': '2026-10-26T14:00:00Z',
  'users': users,
};

Map<String, dynamic> logJson({int id = 77, int quantity = 20}) => {
  'id': id,
  'kind': 'activity',
  'localDate': '2026-10-26',
  'loggedAt': '2026-10-26T13:30:00Z',
  'type': 'pushups',
  'quantity': quantity,
  'unit': 'reps',
};

Map<String, dynamic> mealLogJson({int id = 78}) => {
  'id': id,
  'kind': 'meal',
  'localDate': '2026-10-26',
  'loggedAt': '2026-10-26T12:00:00Z',
  'name': 'Chicken bowl',
  'kcal': 600,
  'protein': 40,
  'carbs': 60,
  'fat': 20,
  'fiber': 5,
};

Map<String, dynamic> logResultJson({int id = 77, int quantity = 20}) => {
  'log': logJson(id: id, quantity: quantity),
  'day': {
    'date': '2026-10-26',
    ...dayJson(points: 170, percent: 70, counted: true),
    'quests': _richQuests,
  },
};

Map<String, dynamic> deleteLogJson() => {'day': logResultJson()['day']};

Map<String, dynamic> logsJson(List<Map<String, dynamic>> logs) => {
  'date': '2026-10-26',
  'logs': logs,
};

const recentMealsJson = {
  'meals': [
    {'name': 'Chicken bowl', 'kcal': 600, 'protein': 40, 'carbs': 60, 'fat': 20, 'fiber': 5},
    {'name': 'Oats', 'kcal': 300, 'protein': 10, 'carbs': 50, 'fat': 6, 'fiber': 8},
  ],
};

/// A server with every read a signed-in screen makes; tests replace routes they care about.
StubAdapter fullServer() => StubAdapter()
  ..on('GET /api/today', StubResponse(200, richTodayJson()))
  ..on('GET /api/me', StubResponse(200, meJson()))
  ..on('GET /api/board', StubResponse(200, board([boardUser(2, 'Sam', 'violet')])))
  ..on('GET /api/meals/recent', const StubResponse(200, recentMealsJson))
  ..on('GET /api/logs', StubResponse(200, logsJson([logJson(), mealLogJson()])));

class TestApp {
  TestApp(
    this.tester,
    this.adapter, {
    FakeHealthSource? health,
    this.accent = 'violet',
    this.surfaceHeight = 1500,
  }) : health = health ?? FakeHealthSource();

  final double surfaceHeight;

  final WidgetTester tester;
  final StubAdapter adapter;
  final FakeHealthSource health;
  final String accent;

  /// A tall phone-width surface so a lazily built list shows every card.
  void tallSurface() {
    tester.view.physicalSize = Size(390, surfaceHeight);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  Future<void> pump(
    Widget home, {
    List<Override> overrides = const [],
    Key? key,
    Session session = testSession,
    bool tall = true,
  }) async {
    if (tall) tallSurface();
    await tester.pumpWidget(
      ProviderScope(
        key: key,
        retry: (_, _) => null,
        overrides: [
          sessionProvider.overrideWith(() => SessionController.seeded(session)),
          apiClientFactoryProvider.overrideWithValue(stubFactory(adapter)),
          clockProvider.overrideWithValue(() => testNow),
          healthSourceProvider.overrideWithValue(health),
          deviceTimezoneProvider.overrideWithValue(() async => 'America/New_York'),
          ...overrides,
        ],
        child: MaterialApp(
          theme: themeFor(accentById(accent)),
          home: Scaffold(body: home),
        ),
      ),
    );
    await settle();
  }

  Future<void> settle([int frames = 14]) async {
    for (var i = 0; i < frames; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  ProviderContainer get container =>
      ProviderScope.containerOf(tester.element(find.byType(Scaffold).first));

  Map<String, dynamic> body(String route, {bool first = false}) {
    final requests = adapter.to(route);
    final data = (first ? requests.first : requests.last).data;
    return (data as Map).cast<String, dynamic>();
  }

  Future<void> tap(Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.tap(finder);
    await settle();
  }

  /// Pops the top route; a tall sheet leaves no barrier to tap.
  Future<void> closeSheet() async {
    Navigator.of(tester.element(find.byType(Scaffold).first)).pop();
    await settle();
  }

  Future<void> enter(Finder finder, String text) async {
    await tester.enterText(finder, text);
    await settle(2);
  }
}

FilledButton filledButton(WidgetTester tester, String label) =>
    tester.widget<FilledButton>(find.widgetWithText(FilledButton, label));

/// Awaits [action] with a few frames pumped, for code that completes through timers.
Future<void> pumpAfter(WidgetTester tester, FutureOr<void> Function() action) async {
  await action();
  await tester.pump(const Duration(milliseconds: 100));
}

/// The text field whose current text is [text].
Finder fieldWith(String text) =>
    find.byWidgetPredicate((w) => w is TextField && w.controller?.text == text);
