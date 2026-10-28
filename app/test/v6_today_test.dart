import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:newme/features/recap/recap_screen.dart';
import 'package:newme/features/today/plan_sheet.dart';
import 'package:newme/features/today/readiness_card.dart';
import 'package:newme/features/today/today_screen.dart';
import 'package:newme/state/me.dart';
import 'package:newme/widgets/dismiss_x.dart';
import 'package:newme/widgets/mascot.dart';

import 'fixtures.dart';
import 'habit_fixtures.dart';
import 'test_support.dart';

// 2026-10-27 is a Tuesday and 2026-10-26 a Monday; the server fixtures say it is the 26th.
final _tuesdayMorning = DateTime(2026, 10, 27, 8);
final _mondayMorning = DateTime(2026, 10, 26, 8);
final _mondayAfternoon = DateTime(2026, 10, 26, 14);
final _sundayEvening = DateTime(2026, 10, 25, 20);

const _bubble = 'Nice, keep it rolling.';
const _summary = '1 of 4 quests done. Easiest next: Steps: 5,000 to go.';

Map<String, dynamic> _plan() => {
  'items': [
    {'kind': 'done', 'key': 'pushups', 'text': 'Push-ups done'},
    {'kind': 'todo', 'key': 'steps', 'text': 'Steps: 5,000 to go. A 50-minute walk covers it.'},
    {'kind': 'habit', 'key': 'habit:1', 'text': 'Brush teeth at 22:00'},
  ],
  'summary': _summary,
};

Map<String, dynamic> _readiness({String level = 'easy', String basis = 'full'}) => {
  'level': level,
  'reasons': [
    {'kind': 'hrv', 'text': 'HRV 18% below your usual'},
    {'kind': 'sleep', 'text': 'Slept 6 h 10, 50 min under your target'},
    if (basis == 'sleep_only')
      {'kind': 'basis', 'text': 'Based on sleep only until there are 7 days of heart data'},
  ],
  'basis': basis,
};

Map<String, dynamic> _cheer(String kind) => {
  'from': 1,
  'fromName': 'Nadia',
  'kind': kind,
  'at': '2026-10-26T13:00:00Z',
};

Map<String, dynamic> _recapJson({bool complete = true}) => {
  'week': '2026-W43',
  'from': '2026-10-19',
  'to': '2026-10-25',
  'complete': complete,
  'people': [
    {
      'userId': 2,
      'name': 'Sam',
      'color': 'violet',
      'this': {
        'points': 900,
        'countedDays': 5,
        'steps': 60000,
        'sleepAvgMin': 440,
        'sleepNights': 6,
        'workouts': 3,
        'readingMinutes': 80,
      },
      'previous': {
        'points': 800,
        'countedDays': 4,
        'steps': 55000,
        'sleepAvgMin': 420,
        'sleepNights': 7,
        'workouts': 2,
        'readingMinutes': 60,
      },
      'bestDay': {'date': '2026-10-22', 'points': 210},
      'suggestion': 'Try a short walk after dinner.',
    },
    {
      'userId': 1,
      'name': 'Ana',
      'color': 'amber',
      'this': {
        'points': 700,
        'countedDays': 4,
        'steps': 40000,
        'sleepAvgMin': 400,
        'sleepNights': 5,
        'workouts': 1,
        'readingMinutes': 20,
      },
      'previous': {
        'points': 750,
        'countedDays': 5,
        'steps': 45000,
        'sleepAvgMin': 410,
        'sleepNights': 6,
        'workouts': 2,
        'readingMinutes': 30,
      },
      'bestDay': {'date': '2026-10-20', 'points': 180},
      'suggestion': 'Aim for 7 hours of sleep.',
    },
  ],
  'pair': {
    'this': {
      'points': 1600,
      'countedDays': 9,
      'steps': 100000,
      'sleepAvgMin': 420,
      'sleepNights': 11,
      'workouts': 4,
      'readingMinutes': 100,
    },
    'previous': {
      'points': 1550,
      'countedDays': 9,
      'steps': 100000,
      'sleepAvgMin': 415,
      'sleepNights': 13,
      'workouts': 4,
      'readingMinutes': 90,
    },
    'bestDay': {'date': '2026-10-22', 'points': 330},
  },
  'challenge': {
    'kind': 'steps',
    'title': 'Walk 100,000 steps together',
    'target': 100000,
    'progress': 100000,
    'completed': true,
  },
};

Map<String, dynamic> _proposals() => {
  'week': '2026-W44',
  'weekStart': '2026-10-26',
  'proposals': [
    {
      'key': 'steps',
      'title': 'Steps',
      'unit': 'steps',
      'current': 8000,
      'proposed': 9000,
      'reason': 'You reached 8,000 on 11 of the last 14 days',
    },
    {
      'key': 'sleep',
      'title': 'Sleep',
      'unit': 'minutes',
      'current': 480,
      'proposed': 450,
      'reason': 'You average 7 h 10 over the last 14 nights',
    },
  ],
};

StubAdapter _server({
  Map<String, dynamic>? readiness,
  bool plan = true,
  List<Map<String, dynamic>> cheers = const [],
  bool habits = false,
  bool proposals = false,
  Map<String, dynamic>? recap,
  Map<String, dynamic>? questOverride,
  Object? listening,
}) {
  final today = <String, dynamic>{
    ...richTodayJson(stepsEverSynced: true),
    'cheers': cheers,
    'habits': habits ? dueHabits() : <Map<String, dynamic>>[],
    'readiness': ?readiness,
    'plan': plan ? _plan() : null,
    'listening': ?listening,
  };
  if (questOverride != null) {
    final quests = [
      for (final q in today['quests']! as List) {...(q as Map<String, dynamic>)},
    ];
    quests[1] = {...quests[1], ...questOverride};
    today['quests'] = quests;
  }
  final server = fullServer()..on('GET /api/today', StubResponse(200, today));
  if (proposals) server.on('GET /api/goals/proposals', StubResponse(200, _proposals()));
  if (recap != null) server.on('GET /api/recap', StubResponse(200, recap));
  return server;
}

Future<TestApp> _open(
  WidgetTester tester,
  StubAdapter server, {
  DateTime? at,
  bool tall = true,
}) async {
  final app = TestApp(tester, server, surfaceHeight: 3200);
  await app.pump(const TodayScreen(), tall: tall, key: UniqueKey(), now: at ?? _tuesdayMorning);
  return app;
}

void main() {
  setUp(() {
    FakeStorage().install();
    Mascot.idleMotion = false;
  });

  testWidgets(
    'Today reads top to bottom: greeting, plan bubble, day, right now, habits, quests, body',
    (tester) async {
      await _open(tester, _server(readiness: _readiness(), habits: true));
      final order = [
        find.text('Good morning, Sam'),
        find.text(_bubble),
        find.text('88%'),
        find.text('Take it easy today'),
        find.text('Habits'),
        find.text('Get stronger'),
        find.text('Body'),
      ];
      for (final f in order) {
        expect(f, findsOneWidget);
      }
      final tops = [for (final f in order) tester.getTopLeft(f).dy];
      expect([...tops]..sort(), tops, reason: 'in this order: $tops');
      expect(find.text('Food'), findsNothing, reason: 'the food card moved to the Food tab');
      expect(
        find.text('Walk 70,000 steps together'),
        findsNothing,
        reason: 'the challenge is on Us',
      );
    },
  );

  group('the bubble and the plan', () {
    testWidgets('the bubble is one short line and opens the plan with the full summary', (
      tester,
    ) async {
      final app = await _open(tester, _server());
      expect(find.text(_bubble), findsOneWidget);
      expect(find.text(_summary), findsNothing, reason: 'the bubble does not restate progress');
      expect(find.text("See today's plan"), findsOneWidget);

      await app.tap(find.text(_bubble));
      expect(find.byType(PlanSheet), findsOneWidget);
      expect(find.text(_summary), findsOneWidget);
      expect(find.text('Already done'), findsOneWidget);
      expect(find.text('Push-ups done'), findsOneWidget);
      expect(find.text('Still to do'), findsOneWidget);
      expect(find.textContaining('50-minute walk covers it'), findsOneWidget);
      expect(find.text('Habits, by time'), findsOneWidget);
      expect(find.text('Brush teeth at 22:00'), findsOneWidget);
    });

    testWidgets('without a plan the mascot keeps its short line and the bubble is plain', (
      tester,
    ) async {
      await _open(tester, _server(plan: false));
      expect(find.text(_summary), findsNothing);
      expect(find.text("See today's plan"), findsNothing);
      expect(find.text(_bubble), findsOneWidget);
    });
  });

  group('readiness', () {
    testWidgets('shows the level and plain reasons in the morning', (tester) async {
      await _open(tester, _server(readiness: _readiness()));
      expect(find.text('Take it easy today'), findsOneWidget);
      expect(find.text('HRV 18% below your usual'), findsOneWidget);
      expect(find.text('Slept 6 h 10, 50 min under your target'), findsOneWidget);
    });

    testWidgets('names the basis when it is sleep only', (tester) async {
      await _open(
        tester,
        _server(
          readiness: _readiness(level: 'ready', basis: 'sleep_only'),
        ),
      );
      expect(find.text('Ready to go'), findsOneWidget);
      expect(find.text('Based on sleep only until there are 7 days of heart data'), findsOneWidget);
    });

    testWidgets('tapping explains the numbers and leads on to the plan', (tester) async {
      final app = await _open(tester, _server(readiness: _readiness()));
      await app.tap(find.byType(ReadinessCard));
      expect(find.byType(ReadinessSheet), findsOneWidget);
      expect(find.text('How it is worked out'), findsOneWidget);
      expect(find.textContaining('30 days'), findsOneWidget);

      await app.tap(find.text("SEE TODAY'S PLAN"));
      expect(find.byType(ReadinessSheet), findsNothing);
      expect(find.byType(PlanSheet), findsOneWidget);
      expect(find.text('Take it easy today'), findsWidgets);
    });

    testWidgets('dismissing hides it and the choice is remembered for the day', (tester) async {
      final server = _server(readiness: _readiness());
      final app = await _open(tester, server);
      await app.tap(find.byType(DismissX));
      expect(find.byType(ReadinessCard), findsNothing);

      await app.pump(const TodayScreen(), key: UniqueKey(), now: _tuesdayMorning);
      expect(find.byType(ReadinessCard), findsNothing);
    });

    testWidgets('is gone by noon without anyone dismissing it', (tester) async {
      await _open(tester, _server(readiness: _readiness()), at: DateTime(2026, 10, 27, 12, 30));
      expect(find.byType(ReadinessCard), findsNothing);
    });

    testWidgets('no readiness from the server is no card, not an empty one', (tester) async {
      await _open(tester, _server());
      expect(find.byType(ReadinessCard), findsNothing);
    });
  });

  group('a received cheer', () {
    testWidgets('takes the slot, ahead of readiness, and dismissing brings readiness back', (
      tester,
    ) async {
      final app = await _open(
        tester,
        _server(readiness: _readiness(), cheers: [_cheer('fire'), _cheer('heart')]),
      );
      expect(find.text('Nadia cheered your day'), findsOneWidget);
      expect(find.byType(ReadinessCard), findsNothing);

      await app.tap(find.byIcon(Icons.close_rounded));
      expect(find.text('Nadia cheered your day'), findsNothing);
      expect(find.byType(ReadinessCard), findsOneWidget);
    });
  });

  group('Monday goals', () {
    testWidgets('list each proposal with a one tap accept or dismiss', (tester) async {
      final server = _server(proposals: true)
        ..on('POST /api/goals/proposals/steps/accept', StubResponse(200, meJson()))
        ..on('POST /api/goals/proposals/sleep/dismiss', const StubResponse(204));
      final app = await _open(tester, server, at: _mondayAfternoon);

      expect(find.text('Goals for this week'), findsOneWidget);
      expect(find.text('Steps: 8,000 to 9,000 steps'), findsOneWidget);
      expect(find.text('Sleep: 8 h to 7 h 30 min'), findsOneWidget);
      expect(find.text('You reached 8,000 on 11 of the last 14 days'), findsOneWidget);

      await app.tap(find.bySemanticsLabel('Accept 9,000 steps'));
      expect(server.to('POST /api/goals/proposals/steps/accept'), hasLength(1));
      expect(find.text('Steps: 8,000 to 9,000 steps'), findsNothing);
      expect(find.text('Sleep: 8 h to 7 h 30 min'), findsOneWidget);
      expect(app.container.read(meProvider).value!.data.user.name, 'Sam');

      await app.tap(find.bySemanticsLabel('Not now for Sleep'));
      expect(server.to('POST /api/goals/proposals/sleep/dismiss'), hasLength(1));
      expect(find.text('Goals for this week'), findsNothing);
    });

    testWidgets('a failed accept puts the proposal back and says why', (tester) async {
      final server = _server(proposals: true)
        ..on(
          'POST /api/goals/proposals/steps/accept',
          const StubResponse(404, {'error': 'No longer pending'}),
        );
      final app = await _open(tester, server, at: _mondayAfternoon);

      await app.tap(find.bySemanticsLabel('Accept 9,000 steps'));
      expect(find.text('Steps: 8,000 to 9,000 steps'), findsOneWidget);
      expect(find.text('No longer pending'), findsOneWidget);
    });

    testWidgets('are only asked for on Mondays', (tester) async {
      final server = _server(proposals: true);
      await _open(tester, server, at: _tuesdayMorning);
      expect(find.text('Goals for this week'), findsNothing);
      expect(server.to('GET /api/goals/proposals'), isEmpty);

      final monday = _server(proposals: true);
      await _open(tester, monday, at: _mondayAfternoon);
      expect(monday.to('GET /api/goals/proposals'), hasLength(1));
    });

    testWidgets('come after the morning readiness', (tester) async {
      final app = await _open(
        tester,
        _server(readiness: _readiness(), proposals: true),
        at: _mondayMorning,
      );
      expect(find.byType(ReadinessCard), findsOneWidget);
      expect(find.text('Goals for this week'), findsNothing);
      await app.tap(find.byType(DismissX));
      expect(find.text('Goals for this week'), findsOneWidget);
    });
  });

  group('the weekly recap card', () {
    testWidgets('appears Sunday evening, opens the recap and can be dismissed', (tester) async {
      final server = _server(recap: _recapJson());
      final app = await _open(tester, server, at: _sundayEvening);
      expect(find.text('Your week is in'), findsOneWidget);
      expect(find.textContaining('Together you earned 1,600 points'), findsOneWidget);

      await app.tap(find.text('Open the recap'));
      expect(find.byType(RecapScreen), findsOneWidget);
      expect(server.to('GET /api/recap').last.queryParameters, {'week': '2026-W43'});
      await app.closeSheet();

      await app.tap(find.bySemanticsLabel('Dismiss recap'));
      expect(find.text('Your week is in'), findsNothing);
    });

    testWidgets('appears on Monday and not on other days or before Sunday 19:00', (tester) async {
      await _open(tester, _server(recap: _recapJson()), at: _mondayAfternoon);
      expect(find.text('Your week is in'), findsOneWidget);

      final tuesday = _server(recap: _recapJson());
      await _open(tester, tuesday, at: _tuesdayMorning);
      expect(find.text('Your week is in'), findsNothing);
      expect(tuesday.to('GET /api/recap'), isEmpty);

      await _open(tester, _server(recap: _recapJson()), at: DateTime(2026, 10, 25, 18));
      expect(find.text('Your week is in'), findsNothing);
    });
  });

  group('quest cards', () {
    testWidgets('say what Health workout finished them', (tester) async {
      await _open(
        tester,
        _server(
          questOverride: {
            'actual': 0,
            'done': true,
            'basePoints': 100,
            'doneBy': {'kind': 'workout', 'type': 'strength', 'minutes': 42},
          },
        ),
      );
      expect(find.text('Done by your Strength workout, 42 min'), findsOneWidget);
    });

    testWidgets('a quest finished by logged entries has no such line', (tester) async {
      await _open(tester, _server());
      expect(find.textContaining('Done by your'), findsNothing);
    });

    testWidgets('the reading card says when listening last synced', (tester) async {
      final syncedAt = DateTime.utc(2026, 10, 27, 11, 57).toIso8601String();
      await _open(
        tester,
        _server(listening: {'minutes': 12, 'syncedAt': syncedAt}),
        at: DateTime.utc(2026, 10, 27, 12),
      );
      expect(find.text('Listening synced 3 min ago'), findsOneWidget);
      expect(find.text('12 min listened'), findsOneWidget);
    });

    testWidgets('an unlinked person sees no sync line', (tester) async {
      await _open(tester, _server(listening: {'minutes': 0, 'syncedAt': null}));
      expect(find.textContaining('Listening synced'), findsNothing);
    });
  });

  group('layout and touch targets', () {
    for (final scale in [1.0, 2.0]) {
      testWidgets('every right-now card and the new Today rows fit at text scale $scale', (
        tester,
      ) async {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        addTearDown(tester.view.reset);
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

        final cases = <(StubAdapter, DateTime)>[
          (_server(readiness: _readiness(basis: 'sleep_only'), habits: true), _tuesdayMorning),
          (_server(cheers: [_cheer('fire'), _cheer('flex')]), _tuesdayMorning),
          (_server(proposals: true), _mondayAfternoon),
          (_server(recap: _recapJson()), _sundayEvening),
        ];
        for (final (server, at) in cases) {
          final app = TestApp(tester, server);
          await app.pump(const TodayScreen(), tall: false, key: UniqueKey(), now: at);
          expect(tester.takeException(), isNull);
          await tester.drag(find.byType(Scrollable).first, const Offset(0, -5000));
          await app.settle();
          expect(tester.takeException(), isNull);
        }
        // Scrolling the last case brings cards into view that start their own loads.
        await tester.pump(Duration.zero);
      });
    }

    testWidgets('dismiss buttons, accept pills, the plan link and the Body row are 44pt targets', (
      tester,
    ) async {
      await _open(tester, _server(readiness: _readiness()));
      final dismiss = tester.getSize(find.byType(DismissX));
      expect((dismiss.width >= 44, dismiss.height >= 44), (true, true));
      expect(tester.getSize(find.byType(ReadinessCard)).height, greaterThanOrEqualTo(44));
      expect(
        tester
            .getSize(
              find
                  .ancestor(
                    of: find.text('See why and the plan'),
                    matching: find.byType(ConstrainedBox),
                  )
                  .first,
            )
            .height,
        greaterThanOrEqualTo(44),
      );
      expect(
        tester
            .getSize(find.ancestor(of: find.text('Body'), matching: find.byType(Row)).first)
            .height,
        greaterThanOrEqualTo(44),
      );

      final goals = _server(proposals: true);
      await _open(tester, goals, at: _mondayAfternoon);
      for (final label in ['Accept', 'Not now']) {
        final pill = find.ancestor(of: find.text(label), matching: find.byType(Container)).first;
        expect(tester.getSize(pill).height, greaterThanOrEqualTo(44), reason: label);
      }
    });
  });
}
