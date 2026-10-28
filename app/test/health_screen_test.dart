import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:newme/features/health/health_metrics.dart';
import 'package:newme/features/health/health_screen.dart';
import 'package:newme/features/health/trend_chart.dart';
import 'package:newme/api/models.dart';
import 'package:newme/widgets/mascot.dart';

import 'fixtures.dart';
import 'test_support.dart';

Map<String, dynamic> _today({Map<String, num>? metrics, Map<String, dynamic>? latest}) {
  final base = richTodayJson(stepsEverSynced: true);
  return {
    ...base,
    'health': {
      'stepsEverSynced': true,
      'syncedAt': '2026-10-26T11:00:00Z',
      'metrics':
          metrics ??
          {
            'steps': 4321,
            'distance_m': 3200,
            'sleep_minutes': 432,
            'resting_hr': 58,
            'weight_kg': 82.4,
            'water_ml': 1500,
            'vo2max': 41.5,
          },
      'latest': ?latest,
    },
  };
}

Map<String, dynamic> _trend(String metric, List<(String, num)> points) => {
  'metric': metric,
  'points': [
    for (final (date, value) in points) {'date': date, 'value': value},
  ],
};

List<(String, num)> _line(int days, num Function(int i) value) => [
  for (var i = 0; i < days; i++)
    (formatDateKey(DateTime.utc(2026, 10, 26).subtract(Duration(days: days - 1 - i))), value(i)),
];

String formatDateKey(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

StubAdapter _server({Map<String, dynamic>? today}) => fullServer()
  ..on('GET /api/today', StubResponse(200, today ?? _today()))
  ..on(
    'GET /api/health/trends',
    StubResponse(200, _trend('weight_kg', _line(30, (i) => 84 - i * 0.1))),
  );

void main() {
  setUp(() {
    FakeStorage().install();
    Mascot.idleMotion = false;
  });

  group('formatting', () {
    test('reads like a person would say it', () {
      String f(String key, num v) => healthMetricSpec(key)!.format(v);
      expect(formatDuration(432), '7 h 12 min');
      expect(formatDuration(420), '7 h');
      expect(formatDuration(45), '45 min');
      expect(f('weight_kg', 82.4), '82.4 kg');
      expect(f('weight_kg', 82), '82 kg');
      expect(f('resting_hr', 58), '58 bpm');
      expect(f('distance_m', 3200), '3.2 km');
      expect(f('distance_m', 850), '850 m');
      expect(f('water_ml', 1500), '1.5 L');
      expect(f('water_ml', 250), '250 ml');
      expect(f('steps', 4321), '4,321 steps');
      expect(f('steps', 1), '1 step');
      expect(f('body_fat_pct', 18.24), '18.2%');
      expect(f('vo2max', 41.5), '41.5 ml/kg/min');
      expect(f('workouts', 2), '2 workouts');
    });

    test('every key Apple Health sends has a home in exactly one group', () {
      final keys = [
        for (final g in kHealthGroups)
          for (final m in g.metrics) m.key,
      ];
      expect(keys.toSet().length, keys.length);
      expect(keys, hasLength(17));
    });
  });

  group('the list', () {
    testWidgets('shows every metric under its group with today\'s value', (tester) async {
      final app = TestApp(tester, _server(), surfaceHeight: 2200);
      await app.pump(const HealthScreen());

      for (final group in kHealthGroups) {
        expect(find.text(group.name), findsWidgets, reason: group.name);
        for (final metric in group.metrics) {
          expect(find.text(metric.name), findsWidgets, reason: metric.name);
        }
      }
      expect(find.text('4,321 steps'), findsOneWidget);
      expect(find.text('3.2 km'), findsOneWidget);
      expect(find.text('7 h 12 min'), findsOneWidget);
      expect(find.text('58 bpm'), findsOneWidget);
      expect(find.text('82.4 kg'), findsOneWidget);
      expect(find.text('1.5 L'), findsOneWidget);
      expect(find.text('41.5 ml/kg/min'), findsOneWidget);
    });

    testWidgets('a metric with no data shows a dash, not zero', (tester) async {
      final app = TestApp(tester, _server(), surfaceHeight: 2200);
      await app.pump(const HealthScreen());
      expect(find.text('-'), findsNWidgets(10));
    });

    testWidgets('a slow-moving metric falls back to its latest reading and says when', (
      tester,
    ) async {
      final today = _today(
        metrics: {'steps': 100},
        latest: {
          'weight_kg': {'value': 81.6, 'date': '2026-10-20'},
        },
      );
      final app = TestApp(tester, _server(today: today), surfaceHeight: 2200);
      await app.pump(const HealthScreen());
      expect(find.text('81.6 kg'), findsOneWidget);
      expect(find.text('As of Oct 20'), findsOneWidget);
    });

    testWidgets('rows are labelled buttons at least 44pt tall', (tester) async {
      final handle = tester.ensureSemantics();
      final app = TestApp(tester, _server(), surfaceHeight: 2200);
      await app.pump(const HealthScreen());

      final row = find.bySemanticsLabel('Weight, 82.4 kg');
      expect(row, findsOneWidget);
      expect(tester.getSize(row).height, greaterThanOrEqualTo(44));
      expect(find.bySemanticsLabel('Body fat, no data yet'), findsOneWidget);
      handle.dispose();
    });

    testWidgets('failure shows Try again', (tester) async {
      final adapter = _server()..on('GET /api/today', const StubResponse.unreachable());
      final app = TestApp(tester, adapter);
      await app.pump(const HealthScreen());
      expect(find.text('Could not load your health numbers'), findsOneWidget);
    });
  });

  group('a metric', () {
    Future<TestApp> open(
      WidgetTester tester,
      StubAdapter adapter, {
      String metric = 'Weight',
    }) async {
      final app = TestApp(tester, adapter, surfaceHeight: 2200);
      await app.pump(const HealthScreen());
      await app.tap(find.text(metric));
      return app;
    }

    testWidgets('draws the trend with its latest value, range and summary label', (tester) async {
      final handle = tester.ensureSemantics();
      final adapter = _server();
      await open(tester, adapter);

      expect(adapter.to('GET /api/health/trends').single.queryParameters, {
        'metric': 'weight_kg',
        'days': 30,
      });
      expect(find.text('81.1 kg'), findsWidgets);
      expect(find.text('Latest, Oct 26'), findsOneWidget);
      expect(find.byType(CustomPaint), findsWidgets);
      expect(find.text('Lowest'), findsOneWidget);
      expect(find.text('Highest'), findsOneWidget);
      expect(find.text('Average'), findsOneWidget);
      expect(
        find.bySemanticsLabel(
          RegExp(
            r'Weight, last 30 days\. Latest 81\.1 kg on Oct 26\. Lowest 81\.1 kg, highest 84 kg',
          ),
        ),
        findsOneWidget,
      );
      handle.dispose();
    });

    testWidgets('the toggle buttons are at least 44pt tall and keep their motion off when asked', (
      tester,
    ) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue = const FakeAccessibilityFeatures(
        disableAnimations: true,
      );
      addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
      await open(tester, _server());

      expect(tester.getSize(find.text('90 days')).height, lessThan(44));
      final target = find.ancestor(
        of: find.text('90 days'),
        matching: find.byType(AnimatedContainer),
      );
      expect(tester.getSize(target.first).height, greaterThanOrEqualTo(44));
      expect(tester.widget<AnimatedContainer>(target.first).duration, Duration.zero);
    });

    testWidgets('the 90 day toggle asks the server for 90 days', (tester) async {
      final adapter = _server();
      await open(tester, adapter);
      await tester.tap(find.text('90 days'));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));

      expect(adapter.to('GET /api/health/trends').last.queryParameters['days'], 90);
    });

    testWidgets('no readings is a friendly empty state', (tester) async {
      final adapter = _server()
        ..on('GET /api/health/trends', StubResponse(200, _trend('weight_kg', const [])));
      await open(tester, adapter);
      expect(find.text('No weight yet'), findsOneWidget);
      expect(find.byType(Mascot), findsOneWidget);
    });

    testWidgets('one reading says so instead of drawing a line', (tester) async {
      final adapter = _server()
        ..on(
          'GET /api/health/trends',
          StubResponse(200, _trend('weight_kg', [('2026-10-26', 82.4)])),
        );
      await open(tester, adapter);
      expect(find.text('Not enough data yet'), findsOneWidget);
      expect(find.textContaining('Only one reading so far'), findsOneWidget);
      expect(find.text('Lowest'), findsNothing);
      expect(find.text('82.4 kg'), findsOneWidget);
    });

    testWidgets('loading shows placeholders, a failure shows Try again and recovers', (
      tester,
    ) async {
      final gate = Completer<void>();
      final adapter = _server()
        ..routes['GET /api/health/trends'] = (_) async {
          await gate.future;
          return const StubResponse(503, {'error': 'later'});
        };
      final app = TestApp(tester, adapter, surfaceHeight: 2200);
      await app.pump(const HealthScreen());
      await app.tap(find.text('Weight'));
      expect(find.bySemanticsLabel('Loading'), findsOneWidget);
      expect(find.text('Lowest'), findsNothing);

      gate.complete();
      await app.settle();
      expect(find.text('Could not load the trend'), findsOneWidget);

      adapter.on(
        'GET /api/health/trends',
        StubResponse(200, _trend('weight_kg', _line(5, (i) => 80 + i))),
      );
      await app.tap(find.text('Try again'));
      expect(find.text('Lowest'), findsOneWidget);
    });
  });

  group('the chart painter', () {
    test('places readings by date so a gap stays a gap', () {
      final placed = placeOnWindow(const [
        HealthTrendPoint(date: '2026-10-01', value: 1),
        HealthTrendPoint(date: '2026-10-25', value: 2),
        HealthTrendPoint(date: '2026-10-26', value: 3),
      ], 30);
      expect(placed.last.x, 1);
      expect(placed[1].x, closeTo(1 - 1 / 29, 1e-9));
      expect(placed.first.x, closeTo(1 - 25 / 29, 1e-9));
    });

    test('drops readings older than the window', () {
      final placed = placeOnWindow(const [
        HealthTrendPoint(date: '2026-01-01', value: 1),
        HealthTrendPoint(date: '2026-10-26', value: 3),
      ], 30);
      expect(placed, hasLength(1));
    });

    testWidgets('scrubbing reports the nearest reading and lets go', (tester) async {
      final points = placeOnWindow([
        for (final (d, v) in _line(30, (i) => i)) HealthTrendPoint(date: d, value: v),
      ], 30);
      final selected = <int?>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 300,
              child: TrendChart(
                points: points,
                color: Colors.teal,
                format: (v) => '$v',
                onSelect: selected.add,
              ),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(seconds: 1));
      final gesture = await tester.startGesture(
        tester.getTopLeft(find.byType(TrendChart)) + const Offset(0, 100),
      );
      await gesture.moveBy(const Offset(150, 0));
      await tester.pump();
      await gesture.up();
      await tester.pump();

      expect(selected.whereType<int>().last, greaterThan(10));
      expect(selected.last, isNull);
    });
  });
}
