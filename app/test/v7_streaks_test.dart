import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:newme/api/models.dart';
import 'package:newme/features/board/board_screen.dart';
import 'package:newme/features/board/person_card.dart';
import 'package:newme/features/me/me_screen.dart';
import 'package:newme/features/streaks/away_line.dart';
import 'package:newme/features/streaks/away_page.dart';
import 'package:newme/features/streaks/shared_streak_card.dart';
import 'package:newme/features/streaks/streak_visuals.dart';
import 'package:newme/features/today/right_now.dart';
import 'package:newme/features/today/today_screen.dart';
import 'package:newme/features/today/week_card.dart';
import 'package:newme/state/right_now.dart';
import 'package:newme/state/today.dart';
import 'package:newme/widgets/dismiss_x.dart';
import 'package:newme/widgets/mascot.dart';

import 'fixtures.dart';
import 'test_support.dart';

// Tuesday 08:00 on the phone; the server fixtures say it is Monday the 26th, so yesterday is the
// 25th and the cover window (until 10:00) is open.
final _morning = DateTime(2026, 10, 27, 8);
final _afternoon = DateTime(2026, 10, 27, 14);
final _firstOfMonth = DateTime(2026, 11, 1, 9);

Map<String, dynamic> _fixture(String name) =>
    (jsonDecode(File('test/contract_v7/$name.json').readAsStringSync()) as Map)['body']!
        as Map<String, dynamic>;

Map<String, dynamic> _mark(
  String date, {
  bool counted = false,
  bool frozen = false,
  bool away = false,
  bool repaired = false,
}) => {
  'date': date,
  'percent': counted ? 90 : 10,
  'counted': counted,
  'rest': false,
  'frozen': frozen,
  'away': away,
  'repaired': repaired,
};

Map<String, dynamic> _user(
  int id,
  String name,
  String color, {
  int freezes = 0,
  List<Map<String, dynamic>>? last7,
  Map<String, dynamic>? away,
}) => {
  ...boardUser(id, name, color, last7: last7),
  'freezes': {'held': freezes, 'earnedTowardNext': 3},
  'away': ?away,
};

Map<String, dynamic> _today({
  Map<String, dynamic>? repair,
  int percent = 62,
  Map<String, dynamic>? away,
  List<Map<String, dynamic>> milestones = const [],
  Map<String, dynamic>? freezes,
  List<Map<String, dynamic>> cheers = const [],
}) => {
  ...richTodayJson(stepsEverSynced: true, percent: percent),
  'freezes': freezes ?? {'held': 2, 'earnedTowardNext': 3},
  'repair': repair,
  'away': away ?? {'today': false, 'current': null, 'upcoming': <Object>[]},
  'newMilestones': milestones,
  'cheers': cheers,
};

Map<String, dynamic> _repair({int progress = 62}) => {
  'date': '2026-10-25',
  'until': '2026-10-28T02:00:00Z',
  'progressPercent': progress,
};

StubAdapter _server({
  Map<String, dynamic>? today,
  List<Map<String, dynamic>>? users,
  Map<String, dynamic>? challenge,
  Map<String, dynamic>? sharedStreak,
}) {
  final server = fullServer()
    ..on('GET /api/today', StubResponse(200, today ?? _today()))
    ..on(
      'GET /api/board',
      StubResponse(200, {
        ...board(users ?? [_user(2, 'Sam', 'violet', freezes: 1), _user(1, 'Ana', 'amber')]),
        'challenge': challenge,
        'sharedStreak': sharedStreak ?? {'current': 9, 'best': 21},
      }),
    );
  return server;
}

Future<TestApp> _openToday(
  WidgetTester tester,
  StubAdapter server, {
  DateTime? at,
  double scale = 1.0,
}) async {
  tester.platformDispatcher.textScaleFactorTestValue = scale;
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  final app = TestApp(tester, server, surfaceHeight: 3600);
  await app.pump(const TodayScreen(), key: UniqueKey(), now: at ?? _morning);
  return app;
}

void main() {
  setUp(() {
    FakeStorage().install();
    Mascot.idleMotion = false;
  });

  group('freezes on Today', () {
    testWidgets('the top bar leaves the freezes to the streak sheet', (tester) async {
      final handle = tester.ensureSemantics();
      final app = await _openToday(tester, _server());
      expect(find.bySemanticsLabel(RegExp('streak freeze')), findsNothing);
      expect(find.byIcon(Icons.ac_unit_rounded), findsNothing);

      await app.tap(find.bySemanticsLabel(RegExp('day streak')));
      expect(find.text('2 of 2 freezes'), findsOneWidget);
      final flakes = tester.widgetList<Icon>(find.byIcon(Icons.ac_unit_rounded));
      expect(flakes.take(2).map((i) => i.color), [kFreezeFill, kFreezeFill]);
      handle.dispose();
    });

    testWidgets('one freeze left leaves the second snowflake dim in the streak sheet', (
      tester,
    ) async {
      final app = await _openToday(
        tester,
        _server(today: _today(freezes: {'held': 1, 'earnedTowardNext': 5})),
      );
      await app.tap(find.bySemanticsLabel(RegExp('day streak')));
      final flakes = tester.widgetList<Icon>(find.byIcon(Icons.ac_unit_rounded)).take(2).toList();
      expect(flakes.map((i) => i.color), [kFreezeFill, isNot(kFreezeFill)]);
    });

    testWidgets('tapping the flame explains earning and using freezes', (tester) async {
      final app = await _openToday(
        tester,
        _server(today: _today(freezes: {'held': 1, 'earnedTowardNext': 4})),
      );
      await app.tap(find.bySemanticsLabel(RegExp('day streak')));
      expect(find.text('1 of 2 freezes'), findsOneWidget);
      expect(find.text('4 of 7 counted days to your next freeze, 3 to go'), findsOneWidget);
      expect(find.text('Earning and using freezes'), findsOneWidget);
      expect(find.textContaining('earn 1 more for every 7 counted days'), findsOneWidget);
      expect(find.text('Repair'), findsOneWidget);
      expect(find.text('Away days'), findsOneWidget);
    });

    testWidgets('the streak sheet links on to away days', (tester) async {
      final app = await _openToday(tester, _server());
      await app.tap(find.bySemanticsLabel(RegExp('day streak')));
      await app.tap(find.text("CAN'T TODAY?"));
      expect(find.byType(AwayPage), findsOneWidget);
    });
  });

  group('week strip statuses', () {
    testWidgets('frozen, away, repaired and counted days each get their own look', (tester) async {
      final handle = tester.ensureSemantics();
      final days = [
        for (final (i, m) in [
          _mark('2026-10-19', counted: true),
          _mark('2026-10-20', frozen: true),
          _mark('2026-10-21', away: true),
          _mark('2026-10-22', repaired: true, frozen: true),
          _mark('2026-10-23'),
        ].indexed)
          DayMark.fromJson({...m, 'i': i}),
      ];
      await TestApp(
        tester,
        fullServer(),
      ).pump(WeekCard(days: days, today: '2026-10-23', todayCounted: false), tall: false);
      expect(find.bySemanticsLabel('Mon, streak day counted'), findsOneWidget);
      expect(find.bySemanticsLabel('Tue, frozen day'), findsOneWidget);
      expect(find.bySemanticsLabel('Wed, away day'), findsOneWidget);
      expect(find.bySemanticsLabel('Thu, repaired day'), findsOneWidget);
      expect(find.bySemanticsLabel('Fri, today'), findsOneWidget);
      expect(find.byIcon(Icons.ac_unit_rounded), findsOneWidget);
      expect(find.byIcon(Icons.pause_circle_rounded), findsOneWidget);
      expect(find.byIcon(Icons.healing_rounded), findsOneWidget);
      handle.dispose();
    });

    testWidgets('Today no longer draws a week strip, even when the board has marks', (
      tester,
    ) async {
      await _openToday(
        tester,
        _server(
          users: [
            _user(
              2,
              'Sam',
              'violet',
              last7: [
                _mark('2026-10-24', frozen: true),
                _mark('2026-10-25', away: true),
                _mark('2026-10-26'),
              ],
            ),
          ],
        ),
      );
      expect(find.byType(WeekCard), findsNothing);
      expect(find.text('This week'), findsNothing);
    });
  });

  group('Repair yesterday', () {
    testWidgets('shows in the right-now slot with progress while the window is open', (
      tester,
    ) async {
      await _openToday(tester, _server(today: _today(repair: _repair(), percent: 62)));
      expect(find.text('Repair yesterday'), findsOneWidget);
      expect(find.textContaining('You missed Sunday'), findsOneWidget);
      expect(find.text('62% of today\'s points'), findsOneWidget);
    });

    testWidgets('follows today progress and says so at 100%', (tester) async {
      await _openToday(
        tester,
        _server(today: _today(repair: _repair(progress: 100), percent: 100)),
      );
      expect(find.text('Yesterday is repaired'), findsOneWidget);
      expect(find.text('100% of today\'s points'), findsOneWidget);
    });

    testWidgets('is gone once its window has closed', (tester) async {
      await _openToday(
        tester,
        _server(today: _today(repair: _repair())),
        at: DateTime(2026, 10, 28, 23),
      );
      expect(find.text('Repair yesterday'), findsNothing);
    });

    testWidgets('has no card when there is nothing to repair', (tester) async {
      await _openToday(tester, _server());
      expect(find.text('Repair yesterday'), findsNothing);
    });

    test('wins over a cheer, the look-back and readiness in the slot', () {
      final repair = Repair.tryParse(_repair())!;
      final picked = pickRightNow(
        now: _morning,
        repair: repair.withProgress(10),
        percent: 10,
        cheers: const [Cheer(from: 1, fromName: 'Ana', kind: CheerKind.fire)],
        readiness: const Readiness(level: ReadinessLevel.ready),
      );
      expect(picked, isA<RightNowRepair>());
    });
  });

  group("Can't today?", () {
    testWidgets('is not on Today; the streak sheet opens the Away page', (tester) async {
      final app = await _openToday(tester, _server());
      expect(find.text("Can't today?"), findsNothing);
      expect(find.byType(AwayLine), findsNothing, reason: "AwayLine only renders while away");
      expect(find.text('You are away'), findsNothing);

      await app.tap(find.bySemanticsLabel(RegExp('day streak')));
      await app.tap(find.text("CAN'T TODAY?"));
      expect(find.byType(AwayPage), findsOneWidget);
      expect(find.text('Away days'), findsWidgets);
    });

    testWidgets('becomes an away card while the person is away', (tester) async {
      final app = await _openToday(
        tester,
        _server(
          today: _today(
            away: {
              'today': true,
              'current': {'id': 1, 'from': '2026-10-26', 'to': '2026-10-28', 'note': 'Flu'},
              'upcoming': <Object>[],
            },
          ),
        ),
      );
      expect(find.text('You are away'), findsOneWidget);
      expect(find.text('Your streak is paused until Wed, Oct 28.'), findsOneWidget);
      expect(find.text("Can't today?"), findsNothing);
      await app.tap(find.text('You are away'));
      expect(find.byType(AwayPage), findsOneWidget);
    });
  });

  group('the Away page', () {
    StubAdapter away({
      List<Map<String, dynamic>> upcoming = const [],
      Map<String, dynamic>? current,
    }) => _server(
      today: _today(away: {'today': current != null, 'current': current, 'upcoming': upcoming}),
    );

    Future<TestApp> open(WidgetTester tester, StubAdapter server) async {
      final app = TestApp(tester, server, surfaceHeight: 1800);
      await app.pump(const AwayPage(), key: UniqueKey(), now: _morning);
      // The page reads the away state from Today, which loads on first use.
      app.container.read(todayProvider);
      await app.settle();
      return app;
    }

    testWidgets('lists the spans with their note and length, current first', (tester) async {
      final server = away(
        current: {'id': 1, 'from': '2026-10-26', 'to': '2026-10-28', 'note': 'Flu'},
        upcoming: [
          {'id': 2, 'from': '2026-11-02', 'to': '2026-11-02', 'note': ''},
        ],
      );
      await open(tester, server);
      expect(find.text('Mon, Oct 26 to Wed, Oct 28'), findsOneWidget);
      expect(find.text('Away now · 3 days · Flu'), findsOneWidget);
      expect(find.text('Mon, Nov 2'), findsOneWidget);
      expect(find.text('1 day'), findsOneWidget);
    });

    testWidgets('says what away days do when there are none', (tester) async {
      await open(tester, away());
      expect(find.textContaining('No away days set'), findsOneWidget);
      expect(find.textContaining('neither break nor extend your streak'), findsOneWidget);
    });

    testWidgets('creates a span from a preset and a note, then reloads Today and Us', (
      tester,
    ) async {
      final server = away()..on('POST /api/away', StubResponse(201, _fixture('away_created')));
      final app = await open(tester, server);
      await app.tap(find.text('3 days'));
      await app.enter(find.byType(TextField), 'Lisbon trip');
      expect(find.text('MARK 3 DAYS AS AWAY'), findsOneWidget);
      final before = server.to('GET /api/today').length;
      await app.tap(find.text('MARK 3 DAYS AS AWAY'));

      expect(app.body('POST /api/away'), {
        'from': '2026-10-26',
        'to': '2026-10-28',
        'note': 'Lisbon trip',
      });
      expect(server.to('GET /api/today').length, greaterThan(before));
    });

    testWidgets('a span that overlaps another says so', (tester) async {
      final server = away()
        ..on(
          'POST /api/away',
          const StubResponse(409, {'error': 'overlap', 'code': 'away_overlap'}),
        );
      final app = await open(tester, server);
      await app.tap(find.text('MARK 1 DAY AS AWAY'));
      expect(find.text('You already have away days on some of those dates.'), findsOneWidget);
    });

    testWidgets('removing a span asks first, then deletes it', (tester) async {
      final server = away(
        upcoming: [
          {'id': 2, 'from': '2026-11-02', 'to': '2026-11-03', 'note': 'Lisbon'},
        ],
      )..on('DELETE /api/away/2', const StubResponse(204));
      final app = await open(tester, server);
      await app.tap(find.byIcon(Icons.delete_outline_rounded));
      expect(find.text('Remove these away days?'), findsOneWidget);
      expect(server.to('DELETE /api/away/2'), isEmpty);
      await app.tap(find.text('Remove'));
      expect(server.to('DELETE /api/away/2'), hasLength(1));
    });

    testWidgets('cancelling the removal keeps it', (tester) async {
      final server = away(
        upcoming: [
          {'id': 2, 'from': '2026-11-02', 'to': '2026-11-03', 'note': ''},
        ],
      );
      final app = await open(tester, server);
      await app.tap(find.byIcon(Icons.delete_outline_rounded));
      await app.tap(find.text('Cancel'));
      expect(server.to('DELETE /api/away/2'), isEmpty);
    });

    testWidgets('Me has a row for it that shows what is set', (tester) async {
      final server = away(
        upcoming: [
          {'id': 2, 'from': '2026-11-02', 'to': '2026-11-03', 'note': ''},
        ],
      );
      final app = TestApp(tester, server, surfaceHeight: 2400);
      await app.pump(const MeScreen(), key: UniqueKey(), now: _morning);
      app.container.read(todayProvider);
      await app.settle();
      expect(find.text('Away days'), findsOneWidget);
      expect(find.text('Next: Mon, Nov 2 to Tue, Nov 3'), findsOneWidget);
      await app.tap(find.text('Away days'));
      expect(find.byType(AwayPage), findsOneWidget);
    });
  });

  group('Us', () {
    Future<TestApp> openUs(
      WidgetTester tester,
      StubAdapter server, {
      DateTime? at,
      double scale = 1.0,
    }) async {
      tester.platformDispatcher.textScaleFactorTestValue = scale;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final app = TestApp(tester, server, surfaceHeight: 3600);
      await app.pump(const BoardScreen(), key: UniqueKey(), now: at ?? _morning);
      return app;
    }

    testWidgets('the shared streak is the first element, above both people', (tester) async {
      await openUs(tester, _server());
      expect(find.byType(SharedStreakCard), findsOneWidget);
      expect(find.text('9 day streak'), findsOneWidget);
      expect(find.text('Sam and Ana kept it going.'), findsOneWidget);
      expect(find.text('21'), findsOneWidget);
      final streakTop = tester.getTopLeft(find.byType(SharedStreakCard)).dy;
      final peopleTop = tester.getTopLeft(find.text('Sam').first).dy;
      expect(streakTop, lessThan(peopleTop));
      expect(streakTop, lessThan(tester.getTopLeft(find.text('Weekly recap')).dy));
    });

    testWidgets('a couple with no shared streak is invited to start one', (tester) async {
      await openUs(tester, _server(sharedStreak: {'current': 0, 'best': 0}));
      expect(find.text('0 day streak'), findsOneWidget);
      expect(find.text('Start a streak today'), findsOneWidget);
    });

    testWidgets('a person alone has no shared streak', (tester) async {
      await openUs(tester, _server(users: [_user(2, 'Sam', 'violet')]));
      expect(find.byType(SharedStreakCard), findsNothing);
    });

    testWidgets('freezes sit in the person sheet, and away shows instead of a percent', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      final app = await openUs(
        tester,
        _server(
          users: [
            _user(2, 'Sam', 'violet', freezes: 1),
            _user(
              1,
              'Ana',
              'amber',
              away: {
                'today': true,
                'current': {'id': 1, 'from': '2026-10-26', 'to': '2026-10-28', 'note': ''},
                'upcoming': <Object>[],
              },
            ),
          ],
        ),
      );
      expect(find.text('1 freeze'), findsNothing);
      expect(find.text('Away today'), findsOneWidget);

      await app.tap(find.byType(PersonCard).at(0));
      expect(find.text('Freezes'), findsOneWidget);
      expect(find.bySemanticsLabel('1 streak freeze'), findsOneWidget);
      await app.closeSheet();
      await app.tap(find.byType(PersonCard).at(1));
      expect(find.bySemanticsLabel('0 streak freezes'), findsOneWidget);
      handle.dispose();
    });

    testWidgets('the week chart marks frozen, away and repaired days with a legend', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await openUs(
        tester,
        _server(
          users: [
            _user(
              2,
              'Sam',
              'violet',
              last7: [
                _mark('2026-10-24', frozen: true),
                _mark('2026-10-25', away: true),
                _mark('2026-10-26', repaired: true, frozen: true),
              ],
            ),
            _user(
              1,
              'Ana',
              'amber',
              last7: [_mark('2026-10-24'), _mark('2026-10-25'), _mark('2026-10-26')],
            ),
          ],
        ),
      );
      expect(
        find.bySemanticsLabel(
          RegExp('Sam counted 0 of 3 days, 1 frozen day, 1 repaired day, 1 away day'),
        ),
        findsOneWidget,
      );
      expect(find.text('frozen'), findsOneWidget);
      expect(find.text('repaired'), findsOneWidget);
      expect(find.text('away'), findsOneWidget);
      handle.dispose();
    });

    testWidgets('the weekly challenge shows each person their own share and the combined bar', (
      tester,
    ) async {
      await openUs(
        tester,
        _server(challenge: _fixture('board')['challenge']! as Map<String, dynamic>),
      );
      expect(find.text('22,421 of 113,000 steps'), findsOneWidget);
      expect(find.text('13,221 of 62,000 steps'), findsOneWidget);
      expect(find.text('9,200 of 51,000 steps'), findsOneWidget);
    });

    testWidgets('a challenge without shares keeps the single bar', (tester) async {
      final challenge = {...(_fixture('board')['challenge']! as Map<String, dynamic>)}
        ..remove('people');
      await openUs(tester, _server(challenge: challenge));
      expect(find.text('22,421 of 113,000 steps'), findsOneWidget);
      expect(find.text('13,221 of 62,000 steps'), findsNothing);
    });

    group('Cover Ana', () {
      // Sam (the signed-in person) holds a freeze; Ana missed Sunday and holds none.
      List<Map<String, dynamic>> users({int mine = 1, int hers = 0, bool counted = false}) => [
        _user(2, 'Sam', 'violet', freezes: mine),
        _user(
          1,
          'Ana',
          'amber',
          freezes: hers,
          last7: [
            _mark('2026-10-24', counted: true),
            _mark('2026-10-25', counted: counted),
            _mark('2026-10-26'),
          ],
        ),
      ];

      testWidgets('is one tap that spends my freeze on her missed day', (tester) async {
        final server = _server(users: users())
          ..on('POST /api/streak/cover', StubResponse(201, _fixture('cover_done')));
        final app = await openUs(tester, server);
        expect(find.text('Ana missed yesterday'), findsOneWidget);
        await app.tap(find.text('COVER ANA'));
        expect(app.body('POST /api/streak/cover'), {'date': '2026-10-25'});
        expect(server.to('GET /api/board').length, greaterThan(1), reason: 'Us reloads after it');
      });

      testWidgets('shows the server refusal in sentence case', (tester) async {
        final server = _server(users: users())
          ..on('POST /api/streak/cover', StubResponse(422, _fixture('cover_closed')));
        final app = await openUs(tester, server);
        await app.tap(find.text('COVER ANA'));
        expect(find.text('That day can no longer be covered.'), findsOneWidget);
      });

      testWidgets('is hidden when she holds a freeze, I hold none, or her day counted', (
        tester,
      ) async {
        for (final u in [users(hers: 1), users(mine: 0), users(counted: true)]) {
          await openUs(tester, _server(users: u));
          expect(find.text('Ana missed yesterday'), findsNothing);
        }
      });

      testWidgets('is hidden after 10:00, when the window has closed', (tester) async {
        await openUs(tester, _server(users: users()), at: _afternoon);
        expect(find.text('Ana missed yesterday'), findsNothing);
      });

      testWidgets('also appears on Today, after a repair but before anything else', (tester) async {
        final app = await _openToday(tester, _server(users: users()));
        expect(find.text('Ana missed yesterday'), findsOneWidget);
        await app.tap(find.text('COVER ANA'));
        expect(app.adapter.to('POST /api/streak/cover'), hasLength(1));
      });
    });
  });

  group('the look-back card on the 1st', () {
    StubAdapter withLookback() =>
        _server()..on('GET /api/lookback', StubResponse(200, _fixture('lookback_rich')));

    testWidgets('shows a headline from the month, opens it, and remembers a dismissal', (
      tester,
    ) async {
      final app = await _openToday(tester, withLookback(), at: _firstOfMonth);
      expect(find.text('Your September look-back'), findsOneWidget);
      expect(find.text('Workouts: 3.3 a week, up from 2.6'), findsOneWidget);
      await app.tap(find.byType(DismissX));
      expect(find.text('Your September look-back'), findsNothing);
      final prefs = app.container.read(rightNowMemoryProvider);
      expect(prefs.has(lookbackDismissKey('2026-09')), isTrue);
    });

    testWidgets('opens the look-back screen for that month', (tester) async {
      final server = withLookback();
      final app = await _openToday(tester, server, at: _firstOfMonth);
      await app.tap(find.text('Open the look-back'));
      expect(find.text('Monthly look-back'), findsOneWidget);
      expect(find.text('September 2026'), findsWidgets);
    });

    testWidgets('does not show on any other day', (tester) async {
      final server = withLookback();
      await _openToday(tester, server, at: DateTime(2026, 11, 2, 9));
      expect(find.textContaining('look-back'), findsNothing);
      expect(server.to('GET /api/lookback'), isEmpty, reason: 'not even fetched');
    });
  });
}
