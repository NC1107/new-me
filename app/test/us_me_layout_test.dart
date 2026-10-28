import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:newme/features/board/board_screen.dart';
import 'package:newme/features/food/food_screen.dart';
import 'package:newme/features/health/health_screen.dart';
import 'package:newme/features/me/me_screen.dart';
import 'package:newme/features/training/train_screen.dart';
import 'package:newme/widgets/mascot.dart';

import 'fixtures.dart';
import 'test_support.dart';

Map<String, dynamic> _withHighlights(Map<String, dynamic> user) => {
  ...user,
  'highlights': {'steps': 12345, 'exercise_minutes': 95, 'sleep_minutes': 505},
};

/// A recorded server response from test/contract_v9.
Map<String, dynamic> _contract(String name) =>
    jsonDecode(File('test/contract_v9/$name.json').readAsStringSync()) as Map<String, dynamic>;

StubAdapter _server({bool paired = true}) {
  final me = meJson(admin: true, yoga: true);
  me['questTemplates'] = [
    ...(me['questTemplates'] as List),
    {
      'key': 'exercise',
      'title': 'Exercise',
      'enabled': false,
      'target': 30,
      'unit': 'minutes',
      'targetAlt': null,
      'unitAlt': null,
      'points': 100,
      'position': 6,
    },
    {
      'key': 'sleep',
      'title': 'Sleep',
      'enabled': true,
      'target': 420,
      'unit': 'minutes',
      'targetAlt': null,
      'unitAlt': null,
      'points': 50,
      'position': 7,
    },
  ];
  final today = richTodayJson(stepsEverSynced: true);
  (today['health'] as Map)['metrics'] = {
    'steps': 12345,
    'distance_m': 9800,
    'sleep_minutes': 505,
    'vo2max': 41.5,
    'resting_hr': 58,
    'weight_kg': 82.4,
  };
  return fullServer()
    ..on('GET /api/me', StubResponse(200, me))
    ..on('GET /api/today', StubResponse(200, today))
    ..on(
      'GET /api/board',
      StubResponse(
        200,
        board([
          _withHighlights(boardUser(2, 'Sam', 'violet', points: 1234, season: 12345)),
          if (paired)
            _withHighlights(
              boardUser(1, 'Alexandria-Long-Name', 'amber', points: 24000, percent: 100),
            ),
        ]),
      ),
    )
    ..on(
      'GET /api/health/trends',
      StubResponse(200, {
        'metric': 'weight_kg',
        'points': [
          for (var i = 0; i < 30; i++)
            {'date': '2026-10-${(i % 26 + 1).toString().padLeft(2, '0')}', 'value': 80 + i % 5},
        ]..sort((a, b) => (a['date']! as String).compareTo(b['date']! as String)),
      }),
    );
}

void _suite(double scale) {
  group('at text scale $scale on a 390x844 phone', () {
    setUp(() {
      FakeStorage().install();
      Mascot.idleMotion = false;
    });

    void configure(WidgetTester tester) {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = scale;
      addTearDown(tester.view.reset);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    }

    void noOverflow(WidgetTester tester, String where) {
      final error = tester.takeException();
      expect(error, isNull, reason: 'overflow on $where: $error');
    }

    Future<void> scrollAll(WidgetTester tester, TestApp app, String where) async {
      // A lazy list learns its length as it builds, so one drag can stop short of the end.
      for (var i = 0; i < 3; i++) {
        await tester.drag(find.byType(Scrollable).first, const Offset(0, -3000));
        await app.settle();
      }
      noOverflow(tester, '$where scrolled');
    }

    testWidgets('Us, paired and waiting', (tester) async {
      configure(tester);
      final app = TestApp(tester, _server());
      await app.pump(const BoardScreen(), tall: false);
      noOverflow(tester, 'Us');
      await scrollAll(tester, app, 'Us');

      final waiting = TestApp(tester, _server(paired: false));
      await waiting.pump(const BoardScreen(), tall: false, key: UniqueKey());
      noOverflow(tester, 'Us waiting');
      await scrollAll(tester, waiting, 'Us waiting');
    });

    testWidgets('Me and every page behind it', (tester) async {
      configure(tester);
      final app = TestApp(tester, _server());
      await app.pump(const MeScreen(), tall: false);
      noOverflow(tester, 'Me');

      for (final row in ['Daily goals', 'About you', 'Schedule', 'Apple Health', 'Pairing code']) {
        await app.tap(find.text(row));
        noOverflow(tester, row);
        if (row == 'Daily goals') {
          await app.tap(find.text('Steps'));
          noOverflow(tester, 'goal picker');
          await app.tap(find.byTooltip('Back'));
          await scrollAll(tester, app, row);
        }
        if (row == 'Pairing code') await app.tap(find.text('CREATE PAIRING CODE'));
        if (row == 'Apple Health') {
          await app.tap(find.text('CONNECT APPLE HEALTH'));
          noOverflow(tester, 'Apple Health connected');
          await scrollAll(tester, app, row);
        }
        await app.tap(find.byTooltip('Back'));
      }
      await scrollAll(tester, app, 'Me');
    });

    testWidgets('Food and every page behind it', (tester) async {
      configure(tester);
      final app = TestApp(tester, _server());
      await app.pump(const FoodScreen(), tall: false);
      noOverflow(tester, 'Food');
      await scrollAll(tester, app, 'Food');

      for (final row in ['Food targets', 'My foods']) {
        await app.tap(find.text(row));
        noOverflow(tester, row);
        await app.tap(find.byTooltip('Back'));
      }
    });

    testWidgets('Train and every page behind it', (tester) async {
      configure(tester);
      final server = _server();
      for (final (route, file) in [
        ('GET /api/training/today', 'training_today'),
        ('GET /api/exercises', 'exercises'),
        ('GET /api/training/profile', 'training_profile'),
        ('GET /api/training/progress', 'training_progress'),
        ('GET /api/sets', 'sets'),
      ]) {
        server.on(route, StubResponse(200, _contract(file)));
      }
      final app = TestApp(tester, server);
      await app.pump(const TrainScreen(), tall: false);
      noOverflow(tester, 'Train');
      await scrollAll(tester, app, 'Train');

      for (final row in ['Exercises', 'Weekly sets']) {
        await app.tap(find.text(row));
        noOverflow(tester, row);
        await app.tap(find.byTooltip('Back'));
      }
    });

    testWidgets('Health list and a metric chart', (tester) async {
      configure(tester);
      final app = TestApp(tester, _server());
      await app.pump(const HealthScreen(), tall: false);
      noOverflow(tester, 'Health');
      await scrollAll(tester, app, 'Health');

      await app.tap(find.text('Weight'));
      noOverflow(tester, 'metric');
      await app.tap(find.text('90 days'));
      noOverflow(tester, 'metric 90');
      await scrollAll(tester, app, 'metric');
    });
  });
}

void main() {
  _suite(1);
  _suite(1.3);
  _suite(2);
}
