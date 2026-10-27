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
  'earned': 0,
  'bonus': 0,
  'completed': false,
  'actual': 0,
  'points': 100,
};

Map<String, dynamic> quest(String key, String title, Map<String, dynamic> fields) => {
  'key': key,
  'title': title,
  ..._questDefaults,
  ...fields,
};

/// A mid-day fixture: pushups done with the bonus, reading and meals partway, steps never synced,
/// and only two of four food targets set.
Map<String, dynamic> richTodayJson({
  bool hasSteps = false,
  int streak = 3,
  bool counted = false,
  Object? backdateUntil = '2026-10-26T15:00:00Z',
  int points = 150,
  int percent = 62,
}) => {
  'localToday': '2026-10-26',
  'serverNow': '2026-10-26T14:00:00Z',
  'backdateUntil': backdateUntil,
  'day': {
    'points': points,
    'maxPoints': 400,
    'percent': percent,
    'counted': counted,
    'threshold': 70,
  },
  'quests': [
    quest('steps', 'Steps', {'unit': 'steps', 'target': 8000, 'actual': 0}),
    quest('pushups', 'Pushups', {
      'target': 30,
      'actual': 30,
      'earned': 100,
      'bonus': 20,
      'completed': true,
    }),
    quest('reading', 'Reading', {
      'unit': 'minutes',
      'unitAlt': 'pages',
      'target': 20,
      'targetAlt': 15,
      'actual': 12,
      'actualAlt': 5,
      'earned': 93,
    }),
    quest('meals_logged', 'Meals', {
      'unit': 'meals',
      'target': 2,
      'actual': 1,
      'earned': 25,
      'points': 50,
    }),
  ],
  'streak': {'current': streak, 'restAvailable': true},
  'food': {
    'kcal': 1850,
    'protein': 82,
    'carbs': 200,
    'fat': 60,
    'burned': 540,
    'kcalTarget': 2200,
    'proteinTarget': 150,
  },
  'health': {'hasSteps': hasSteps, 'syncedAt': '2026-10-26T11:00:00Z'},
};

Map<String, dynamic> meJson({bool admin = false, bool yoga = false, String color = 'violet'}) => {
  'id': 2,
  'name': 'Sam',
  'color': color,
  'timezone': 'America/New_York',
  'isAdmin': admin,
  'quests': [
    {
      'key': 'steps',
      'title': 'Steps',
      'enabled': true,
      'target': 8000,
      'unit': 'steps',
      'points': 100,
    },
    {
      'key': 'pushups',
      'title': 'Pushups',
      'enabled': true,
      'target': 30,
      'unit': 'reps',
      'points': 100,
    },
    {
      'key': 'reading',
      'title': 'Reading',
      'enabled': true,
      'target': 20,
      'unit': 'minutes',
      'targetAlt': 15,
      'unitAlt': 'pages',
      'points': 100,
    },
    {
      'key': 'yoga',
      'title': 'Yoga',
      'enabled': yoga,
      'target': 20,
      'unit': 'minutes',
      'points': 50,
    },
  ],
  'localToday': '2026-10-26',
  'serverNow': '2026-10-26T14:00:00Z',
  'backdateUntil': '2026-10-26T15:00:00Z',
  'kcalTarget': 2200,
  'proteinTarget': 150,
};

Map<String, dynamic> boardUser(
  int id,
  String name,
  String color, {
  int points = 120,
  int percent = 30,
  int week = 300,
  int season = 900,
  List<Map<String, dynamic>>? last7,
}) => {
  'id': id,
  'name': name,
  'color': color,
  'today': {'points': points, 'percent': percent, 'counted': false},
  'week': week,
  'season': season,
  'streak': 4,
  'last7':
      last7 ??
      [
        {'date': '2026-10-20', 'percent': 90, 'rest': false},
        {'date': '2026-10-21', 'percent': 20, 'rest': false},
        {'date': '2026-10-22', 'percent': 10, 'rest': true},
        {'date': '2026-10-23', 'percent': 80, 'rest': false},
        {'date': '2026-10-24', 'percent': 75, 'rest': false},
        {'date': '2026-10-25', 'percent': 100, 'rest': false},
        {'date': '2026-10-26', 'percent': 30, 'rest': false},
      ],
  'syncedAt': '2026-10-26T11:00:00Z',
};

Map<String, dynamic> board(List<Map<String, dynamic>> users) => {
  'season': {'name': 'Season 0', 'startsOn': '2026-10-01', 'endsOn': '2026-12-31'},
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
  'proteinG': 40,
  'carbsG': 60,
  'fatG': 20,
  'fiberG': 5,
};

Map<String, dynamic> logResultJson({int id = 77, int quantity = 20}) => {
  'log': logJson(id: id, quantity: quantity),
  'day': {'points': 170, 'maxPoints': 400, 'percent': 70, 'counted': true, 'threshold': 70},
  'quests': richTodayJson()['quests'],
};

const recentMealsJson = [
  {'name': 'Chicken bowl', 'kcal': 600, 'proteinG': 40, 'carbsG': 60, 'fatG': 20, 'fiberG': 5},
  {'name': 'Oats', 'kcal': 300, 'proteinG': 10, 'carbsG': 50, 'fatG': 6, 'fiberG': 8},
];

/// A server with every read a signed-in screen makes; tests replace routes they care about.
StubAdapter fullServer() => StubAdapter()
  ..on('GET /api/today', StubResponse(200, richTodayJson()))
  ..on('GET /api/me', StubResponse(200, meJson()))
  ..on('GET /api/board', StubResponse(200, board([boardUser(2, 'Sam', 'violet')])))
  ..on('GET /api/meals/recent', const StubResponse(200, recentMealsJson))
  ..on('GET /api/logs', StubResponse(200, [logJson(), mealLogJson()]));

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
