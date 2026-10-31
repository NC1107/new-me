import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:newme/api/models.dart';
import 'package:newme/features/recap/recap_logic.dart';
import 'package:newme/features/recap/recap_screen.dart';
import 'package:newme/widgets/mascot.dart';

import 'fixtures.dart';
import 'test_support.dart';

Map<String, dynamic> _stats({
  int points = 0,
  int countedDays = 0,
  int steps = 0,
  int sleepAvgMin = 0,
  int sleepNights = 0,
  int workouts = 0,
  int readingMinutes = 0,
}) => {
  'points': points,
  'countedDays': countedDays,
  'steps': steps,
  'sleepAvgMin': sleepAvgMin,
  'sleepNights': sleepNights,
  'workouts': workouts,
  'readingMinutes': readingMinutes,
};

Map<String, dynamic> _person(
  int id,
  String name, {
  required Map<String, dynamic> now,
  required Map<String, dynamic> before,
  String suggestion = '',
}) => {
  'userId': id,
  'name': name,
  'color': id == 1 ? 'sky' : 'rose',
  'this': now,
  'previous': before,
  'bestDay': now['points'] == 0 ? null : {'date': '2026-10-22', 'points': 94},
  'suggestion': suggestion,
};

Map<String, dynamic> _recap({
  required List<Map<String, dynamic>> people,
  required Map<String, dynamic> now,
  required Map<String, dynamic> before,
  bool complete = true,
  Map<String, dynamic>? challenge,
}) => {
  'week': '2026-W43',
  'from': '2026-10-19',
  'to': '2026-10-25',
  'complete': complete,
  'people': people,
  'pair': {
    'this': now,
    'previous': before,
    'bestDay': now['points'] == 0 ? null : {'date': '2026-10-22', 'points': 160},
  },
  'challenge': challenge,
};

Future<TestApp> _open(WidgetTester tester, Map<String, dynamic> body) async {
  final server = fullServer()..on('GET /api/recap', StubResponse(200, body));
  final app = TestApp(tester, server, surfaceHeight: 3000);
  await app.pump(const RecapScreen());
  return app;
}

double _top(WidgetTester tester, String text) => tester.getTopLeft(find.text(text)).dy;

void main() {
  final busy = _stats(
    points: 513,
    countedDays: 4,
    steps: 64100,
    sleepAvgMin: 413,
    sleepNights: 7,
    workouts: 4,
    readingMinutes: 110,
  );
  final slower = _stats(
    points: 346,
    countedDays: 2,
    steps: 62000,
    sleepAvgMin: 429,
    sleepNights: 7,
    workouts: 1,
    readingMinutes: 20,
  );

  group('the recap screen', () {
    testWidgets('reads in order: headline, what went well, what to work on, each of you', (
      tester,
    ) async {
      await _open(
        tester,
        _recap(
          now: _stats(points: 869, steps: 114500, workouts: 5, sleepAvgMin: 400, sleepNights: 13),
          before: _stats(
            points: 749,
            steps: 110300,
            workouts: 2,
            sleepAvgMin: 410,
            sleepNights: 13,
          ),
          people: [
            _person(
              1,
              'Nick',
              now: busy,
              before: slower,
              suggestion: 'Aim for an earlier bedtime on two nights.',
            ),
            _person(2, 'Nadia', now: busy, before: slower),
          ],
        ),
      );

      expect(find.text('869'), findsOneWidget);
      expect(find.text('120 more than the week before'), findsOneWidget);
      expect(find.text('Best day Thu, Oct 22'), findsOneWidget);
      final tops = [
        _top(tester, 'Together'),
        _top(tester, 'What went well'),
        _top(tester, 'To work on'),
        _top(tester, 'Each of you'),
      ];
      expect([...tops]..sort(), tops);
    });

    testWidgets('what went well lists only what moved up, and never the points twice', (
      tester,
    ) async {
      await _open(
        tester,
        _recap(
          now: _stats(points: 869, steps: 114500, workouts: 1),
          before: _stats(points: 749, steps: 110300, workouts: 2),
          people: [_person(1, 'Nick', now: busy, before: slower)],
        ),
      );
      expect(find.text('+4,200'), findsOneWidget, reason: 'steps went up');
      expect(find.text('-1'), findsNothing, reason: 'workouts went down, so not praised');
      expect(find.text('Counted days'), findsOneWidget, reason: 'only in the person card');
    });

    testWidgets('a week with nothing logged says so instead of showing zeros', (tester) async {
      await _open(
        tester,
        _recap(
          now: _stats(),
          before: _stats(),
          people: [
            _person(1, 'Nick', now: _stats(), before: _stats()),
            _person(2, 'Nadia', now: _stats(), before: _stats()),
          ],
        ),
      );
      expect(find.text('A quiet week'), findsOneWidget);
      expect(find.byType(Mascot), findsOneWidget);
      expect(find.text('Together'), findsNothing);
      expect(find.text('Each of you'), findsNothing);
      expect(find.text('What went well'), findsNothing);
    });

    testWidgets('a person who joined mid-week is not compared with a week of zeros', (
      tester,
    ) async {
      await _open(
        tester,
        _recap(
          now: _stats(points: 869, steps: 114500),
          before: _stats(points: 346, steps: 62000),
          people: [
            _person(1, 'Nick', now: busy, before: slower),
            _person(
              2,
              'Nadia',
              now: _stats(points: 356, countedDays: 1, steps: 50400),
              before: _stats(),
            ),
          ],
        ),
      );
      expect(find.text('A first week, so nothing to compare yet.'), findsOneWidget);
      expect(find.text('+50,400'), findsNothing);
      expect(find.text('356 points'), findsOneWidget);
    });

    testWidgets('a person with nothing logged gets one line, not a grid of zeros', (tester) async {
      await _open(
        tester,
        _recap(
          now: _stats(points: 513, steps: 64100),
          before: _stats(points: 300),
          people: [
            _person(1, 'Nick', now: busy, before: slower),
            _person(2, 'Nadia', now: _stats(), before: slower),
          ],
        ),
      );
      expect(find.text('Nothing was logged this week.'), findsOneWidget);
    });

    testWidgets('the first week on record says there is nothing to compare', (tester) async {
      await _open(
        tester,
        _recap(
          now: _stats(points: 400, steps: 30000),
          before: _stats(),
          people: [_person(1, 'Nick', now: busy, before: _stats())],
        ),
      );
      expect(find.text('Your first week, so there is nothing to compare it with.'), findsOneWidget);
      expect(find.text('What went well'), findsNothing);
    });

    testWidgets('a running week skips comparisons and the pep suggestion', (tester) async {
      await _open(
        tester,
        _recap(
          complete: false,
          now: _stats(points: 624, steps: 70000),
          before: _stats(points: 869, steps: 114500),
          people: [
            _person(
              1,
              'Nick',
              now: busy,
              before: slower,
              suggestion: 'The week is still running. Keep going to make it a good one.',
            ),
          ],
          challenge: {
            'kind': 'steps',
            'title': 'Walk 100,000 steps together',
            'target': 100000,
            'progress': 40000,
            'completed': false,
          },
        ),
      );
      expect(find.text('This week is still running.'), findsOneWidget);
      expect(find.text('Last week 869'), findsOneWidget);
      expect(find.textContaining('Keep going'), findsNothing);
      expect(find.text('What went well'), findsNothing);
      expect(find.text('Challenge'), findsOneWidget);
      expect(find.text('Challenge so far'), findsOneWidget);
    });

    testWidgets('fits at text scale 2.0 with gains, a joiner and a finished challenge', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 2.0;
      addTearDown(tester.view.reset);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final server = fullServer()
        ..on(
          'GET /api/recap',
          StubResponse(
            200,
            _recap(
              now: _stats(points: 869, steps: 114500, workouts: 5, readingMinutes: 140),
              before: _stats(points: 749, steps: 110300, workouts: 2, readingMinutes: 20),
              people: [
                _person(1, 'Nick', now: busy, before: slower, suggestion: 'Walk after dinner.'),
                _person(2, 'Nadia', now: busy, before: _stats()),
              ],
              challenge: {
                'kind': 'steps',
                'title': 'Walk 100,000 steps together',
                'target': 100000,
                'progress': 100000,
                'completed': true,
              },
            ),
          ),
        );
      final app = TestApp(tester, server);
      await app.pump(const RecapScreen(), tall: false);
      expect(tester.takeException(), isNull);
      for (var i = 0; i < 3; i++) {
        await tester.drag(find.byType(Scrollable).first, const Offset(0, -900));
        await app.settle();
        expect(tester.takeException(), isNull);
      }
    });

    testWidgets('the couple card leaves out counted days, a per-person count', (tester) async {
      await _open(
        tester,
        _recap(
          now: _stats(points: 869, countedDays: 5, steps: 114500),
          before: _stats(points: 749, countedDays: 2, steps: 110300),
          people: [_person(1, 'Nick', now: busy, before: slower)],
        ),
      );
      expect(find.text('Counted days'), findsOneWidget);
    });
  });

  group('recap logic', () {
    test('an empty week before is never compared', () {
      final rows = recapRows(const RecapStats(points: 300, steps: 5000), const RecapStats());
      expect(rows.every((r) => r.change == null && r.direction == 0), isTrue);
    });

    test('the pair rows drop counted days', () {
      final rows = recapRows(const RecapStats(points: 1), const RecapStats(), pair: true);
      expect(rows.map((r) => r.label), isNot(contains('Counted days')));
    });

    test('gains are the rows that went up', () {
      final rows = recapRows(
        const RecapStats(points: 200, steps: 50000, workouts: 1),
        const RecapStats(points: 100, steps: 60000, workouts: 1),
      );
      expect([for (final r in recapGains(rows)) r.label], ['Points']);
    });

    test('statsEmpty is true only when nothing was recorded', () {
      expect(statsEmpty(const RecapStats()), isTrue);
      expect(statsEmpty(const RecapStats(readingMinutes: 5)), isFalse);
    });
  });
}
