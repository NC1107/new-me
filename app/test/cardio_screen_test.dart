import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:newme/features/health/cardio_screen.dart';
import 'package:newme/features/health/health_screen.dart';
import 'package:newme/util/format.dart';
import 'package:newme/widgets/mascot.dart';

import 'fixtures.dart';
import 'test_support.dart';

Map<String, dynamic> _cardio(String status, {Map<String, dynamic>? norm, List<String>? needs}) => {
  'status': status,
  'latest': status == 'no_reading' ? null : {'date': '2026-10-26', 'value': 41.5},
  'needs': needs ?? <String>[],
  'norm': norm,
};

const _norm = {
  'ageGroup': '40-49',
  'sex': 'male',
  'percentileLow': 60,
  'percentileHigh': 70,
  'median': 35.3,
  'source': 'FRIEND',
};

List<Map<String, dynamic>> _readings(int count, {int everyDays = 3}) => [
  for (var i = count - 1; i >= 0; i--)
    {
      'date': formatDateKey(DateTime.utc(2026, 10, 26).subtract(Duration(days: i * everyDays))),
      'value': 38 + (count - 1 - i) * 0.1,
    },
];

StubAdapter _server({
  required Map<String, dynamic> cardio,
  List<Map<String, dynamic>> vo2 = const [],
  List<Map<String, dynamic>> exercise = const [],
}) {
  final adapter = fullServer()..on('GET /api/health/cardio', StubResponse(200, cardio));
  adapter.routes['GET /api/health/trends'] = (request) {
    final metric = request.queryParameters['metric'];
    return StubResponse(200, {'metric': metric, 'points': metric == 'vo2max' ? vo2 : exercise});
  };
  return adapter;
}

void main() {
  setUp(() {
    FakeStorage().install();
    Mascot.idleMotion = false;
  });

  testWidgets('with no VO2 max it says so and offers no comparison', (tester) async {
    final app = TestApp(tester, _server(cardio: _cardio('no_reading')));
    await app.pump(const CardioScreen());

    expect(find.text('No VO2 max yet'), findsOneWidget);
    expect(find.text('How you compare'), findsNothing);
    expect(find.text('3 months'), findsNothing);
    expect(find.text('An estimate, not a lab test'), findsOneWidget);
  });

  testWidgets('draws the trend, the percentile band and what moves it', (tester) async {
    final handle = tester.ensureSemantics();
    final adapter = _server(
      cardio: _cardio('ready', norm: _norm),
      vo2: _readings(40),
      exercise: [
        {'date': '2026-10-24', 'value': 30},
        {'date': '2026-10-25', 'value': 45},
      ],
    );
    final app = TestApp(tester, adapter, surfaceHeight: 2400);
    await app.pump(const CardioScreen());

    expect(adapter.to('GET /api/health/trends').map((r) => r.queryParameters), [
      {'metric': 'vo2max', 'days': 365},
      {'metric': 'exercise_minutes', 'days': 7},
    ]);
    expect(find.text('41.9 ml/kg/min'), findsOneWidget);
    expect(find.text('Latest, Oct 26'), findsOneWidget);
    expect(find.byType(CustomPaint), findsWidgets);
    expect(find.text('60th to 70th percentile'), findsOneWidget);
    expect(find.textContaining('Among men aged 40-49'), findsOneWidget);
    expect(find.textContaining('35.3 ml/kg/min'), findsOneWidget);
    expect(find.textContaining('75 minutes of exercise'), findsOneWidget);
    expect(find.textContaining('150 to 300 minutes'), findsOneWidget);
    expect(find.textContaining('13 to 16 percent'), findsOneWidget);
    expect(
      find.bySemanticsLabel(RegExp(r'VO2 max, last 3 months\. Latest 41\.9 ml/kg/min on Oct 26')),
      findsOneWidget,
    );

    await app.tap(find.text('12 months'));
    expect(find.bySemanticsLabel(RegExp(r'VO2 max, last 12 months\.')), findsOneWidget);
    expect(adapter.to('GET /api/health/trends'), hasLength(2));
    handle.dispose();
  });

  testWidgets('a shorter window keeps only readings inside it', (tester) async {
    final handle = tester.ensureSemantics();
    final app = TestApp(
      tester,
      _server(
        cardio: _cardio('ready', norm: _norm),
        vo2: _readings(80, everyDays: 4),
      ),
      surfaceHeight: 2400,
    );
    await app.pump(const CardioScreen());

    // 80 readings four days apart span 316 days; 90 days hold 23 of them.
    expect(find.bySemanticsLabel(RegExp(r'last 3 months\..*23 readings')), findsOneWidget);
    await app.tap(find.text('6 months'));
    expect(find.bySemanticsLabel(RegExp(r'last 6 months\..*45 readings')), findsOneWidget);
    handle.dispose();
  });

  testWidgets('old readings alone say the window is empty, not that there is no data', (
    tester,
  ) async {
    final app = TestApp(
      tester,
      _server(
        cardio: _cardio('ready', norm: _norm),
        vo2: [
          {'date': '2026-03-01', 'value': 40},
          {'date': '2026-03-05', 'value': 40.5},
        ],
      ),
    );
    await app.pump(const CardioScreen());

    expect(find.text('No readings in this window'), findsOneWidget);
    expect(find.text('No VO2 max yet'), findsNothing);
  });

  testWidgets('one reading is not a trend yet', (tester) async {
    final app = TestApp(
      tester,
      _server(
        cardio: _cardio('ready', norm: _norm),
        vo2: _readings(1),
      ),
    );
    await app.pump(const CardioScreen());

    expect(find.text('Not enough data yet'), findsOneWidget);
    expect(find.text('60th to 70th percentile'), findsOneWidget);
  });

  testWidgets('without birth year or sex it shows the trend and says what is needed', (
    tester,
  ) async {
    final app = TestApp(
      tester,
      _server(
        cardio: _cardio('needs_profile', needs: ['birthYear', 'sex']),
        vo2: _readings(20),
      ),
    );
    await app.pump(const CardioScreen());

    expect(find.text('Add your birth year and your sex to compare'), findsOneWidget);
    expect(find.textContaining('on your profile in Me'), findsOneWidget);
    expect(find.text('How you compare'), findsNothing);
    expect(find.byType(CustomPaint), findsWidgets);
  });

  testWidgets('one missing field is named alone', (tester) async {
    final app = TestApp(
      tester,
      _server(
        cardio: _cardio('needs_profile', needs: ['sex']),
        vo2: _readings(20),
      ),
    );
    await app.pump(const CardioScreen());
    expect(find.text('Add your sex to compare'), findsOneWidget);
  });

  testWidgets('the ends of the table read as below the 10th and above the 90th', (tester) async {
    final low = TestApp(
      tester,
      _server(
        cardio: _cardio('ready', norm: {..._norm, 'percentileLow': 0, 'percentileHigh': 10}),
        vo2: _readings(20),
      ),
    );
    await low.pump(const CardioScreen());
    expect(find.text('Below the 10th percentile'), findsOneWidget);

    final high = TestApp(
      tester,
      _server(
        cardio: _cardio('ready', norm: {..._norm, 'percentileLow': 90, 'percentileHigh': 100}),
        vo2: _readings(20),
      ),
    );
    await high.pump(const CardioScreen(), key: UniqueKey());
    expect(find.text('Above the 90th percentile'), findsOneWidget);
  });

  testWidgets('outside the table ages it says why there is no comparison', (tester) async {
    final app = TestApp(tester, _server(cardio: _cardio('age_out_of_range'), vo2: _readings(20)));
    await app.pump(const CardioScreen());
    expect(find.text('No comparison for your age'), findsOneWidget);
  });

  testWidgets('fits at text scale 2.0', (tester) async {
    tester.platformDispatcher.textScaleFactorTestValue = 2.0;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final app = TestApp(
      tester,
      _server(
        cardio: _cardio('ready', norm: _norm),
        vo2: _readings(40),
        exercise: [
          {'date': '2026-10-25', 'value': 45},
        ],
      ),
      surfaceHeight: 4000,
    );
    await app.pump(const CardioScreen());

    expect(tester.takeException(), isNull);
    expect(find.text('60th to 70th percentile'), findsOneWidget);
  });

  testWidgets('the missing-profile page fits at text scale 2.0', (tester) async {
    tester.platformDispatcher.textScaleFactorTestValue = 2.0;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final app = TestApp(
      tester,
      _server(
        cardio: _cardio('needs_profile', needs: ['birthYear', 'sex']),
        vo2: _readings(40),
      ),
      surfaceHeight: 4000,
    );
    await app.pump(const CardioScreen());
    expect(tester.takeException(), isNull);
  });

  testWidgets('the VO2 max row on the Health list opens this page', (tester) async {
    final today = richTodayJson(stepsEverSynced: true);
    final adapter =
        _server(
          cardio: _cardio('ready', norm: _norm),
          vo2: _readings(20),
        )..on(
          'GET /api/today',
          StubResponse(200, {
            ...today,
            'health': {
              'stepsEverSynced': true,
              'syncedAt': '2026-10-26T11:00:00Z',
              'metrics': {'vo2max': 41.5},
            },
          }),
        );
    final app = TestApp(tester, adapter, surfaceHeight: 2200);
    await app.pump(const HealthScreen());
    await app.tap(find.text('VO2 max'));

    expect(find.text('Cardio fitness'), findsOneWidget);
    expect(adapter.to('GET /api/health/cardio'), hasLength(1));
  });
}
