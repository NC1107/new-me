import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:newme/api/models.dart';
import 'package:newme/features/streaks/shared_streak_card.dart';
import 'package:newme/features/streaks/streak_visuals.dart';
import 'package:newme/features/today/day_card.dart';
import 'package:newme/features/today/today_screen.dart';
import 'package:newme/util/format.dart';
import 'package:newme/widgets/mascot.dart';

import 'fixtures.dart';
import 'test_support.dart';

DayMark _mark(
  String date, {
  bool counted = false,
  bool frozen = false,
  bool away = false,
  bool repaired = false,
  bool rest = false,
}) => DayMark(
  date: date,
  percent: counted ? 80 : 10,
  counted: counted,
  rest: rest,
  frozen: frozen,
  away: away,
  repaired: repaired,
);

String? _line(
  DayMark? yesterday, {
  Freezes freezes = const Freezes(),
  Repair? repair,
  DateTime? now,
}) => yesterdayStatusLine(
  localToday: '2026-10-26',
  last7: [?yesterday],
  freezes: freezes,
  repair: repair,
  now: now ?? DateTime.utc(2026, 10, 26, 9),
);

Map<String, dynamic> _plan(List<Map<String, String>> items) => {
  'items': items,
  'summary': 'Nothing counted yet.',
};

StubAdapter _server({
  required List<Map<String, dynamic>> last7,
  Map<String, dynamic>? plan,
  int points = 20,
}) => fullServer()
  ..on(
    'GET /api/today',
    StubResponse(200, {
      ...richTodayJson(points: points, percent: 0),
      'plan': ?plan,
      'freezes': {'held': 1, 'earnedTowardNext': 3},
    }),
  )
  ..on('GET /api/board', StubResponse(200, board([boardUser(2, 'Sam', 'violet', last7: last7)])));

void main() {
  setUp(() {
    FakeStorage().install();
    Mascot.idleMotion = false;
  });

  group('yesterday status line', () {
    test('a counted yesterday is named', () {
      expect(_line(_mark('2026-10-25', counted: true)), 'Yesterday counted.');
    });

    test('a frozen yesterday says a freeze held the streak and how many are left', () {
      expect(
        _line(_mark('2026-10-25', frozen: true), freezes: const Freezes(held: 1)),
        'Yesterday missed. A freeze held your streak, 1 freeze left.',
      );
      expect(
        _line(_mark('2026-10-25', frozen: true)),
        'Yesterday missed. A freeze held your streak, no freezes left.',
      );
    });

    test('a missed yesterday inside the repair window names the closing time', () {
      final repair = Repair(
        date: '2026-10-25',
        until: DateTime.utc(2026, 10, 26, 22),
        progressPercent: 10,
      );
      expect(
        _line(_mark('2026-10-25'), repair: repair),
        startsWith('Yesterday missed. You can repair it until '),
      );
    });

    test('a missed yesterday after the window closed starts a fresh streak', () {
      final repair = Repair(
        date: '2026-10-25',
        until: DateTime.utc(2026, 10, 26, 8),
        progressPercent: 10,
      );
      expect(
        _line(_mark('2026-10-25'), repair: repair),
        'Yesterday missed. Today starts a fresh streak.',
      );
    });

    test('repaired and away days read as such, a rest day and no mark say nothing', () {
      expect(
        _line(_mark('2026-10-25', repaired: true)),
        'Yesterday was repaired and counts as a frozen day.',
      );
      expect(_line(_mark('2026-10-25', away: true)), 'Yesterday was an away day.');
      expect(_line(_mark('2026-10-25', rest: true)), isNull);
      expect(_line(null), isNull);
    });
  });

  group('first step', () {
    final plan = Plan.tryParse(
      _plan([
        {'kind': 'done', 'key': 'meals_logged', 'text': 'Meals done'},
        {'kind': 'todo', 'key': 'steps', 'text': 'Steps: 4,491 to go (about 45 min).'},
      ]),
    );

    test('is the first open item while nothing is earned', () {
      final day = DayScore.fromJson({...dayJson(), 'basePoints': 0});
      expect(firstStepOf(day, plan), 'Steps: 4,491 to go (about 45 min)');
    });

    test('goes once anything is earned, or the day counts, or the plan has no open item', () {
      expect(firstStepOf(DayScore.fromJson(dayJson()), plan), isNull);
      final counted = DayScore.fromJson({...dayJson(), 'basePoints': 0, 'counted': true});
      expect(firstStepOf(counted, plan), isNull);
      final empty = DayScore.fromJson({...dayJson(), 'basePoints': 0});
      expect(firstStepOf(empty, const Plan()), isNull);
      expect(firstStepOf(empty, null), isNull);
    });
  });

  group('Today at 0 gems', () {
    testWidgets('opens with yesterday and a concrete first step, not a flat 0%', (tester) async {
      final server = _server(
        last7: [
          {'date': '2026-10-25', 'percent': 90, 'counted': true, 'rest': false},
        ],
        plan: _plan([
          {'kind': 'todo', 'key': 'steps', 'text': 'Steps: 4,491 to go (about 45 min).'},
        ]),
      );
      await TestApp(tester, server).pump(const TodayScreen());

      expect(find.text('Yesterday counted.'), findsOneWidget);
      expect(find.text('First step'), findsOneWidget);
      expect(find.text('Steps: 4,491 to go (about 45 min)'), findsOneWidget);
      expect(find.text('0'), findsWidgets);
      expect(find.text('of 400 gems'), findsOneWidget);
      expect(find.textContaining('%'), findsNothing);
    });

    testWidgets('a missed, frozen yesterday is said on Today', (tester) async {
      final server = _server(
        last7: [
          {'date': '2026-10-25', 'percent': 10, 'counted': false, 'rest': false, 'frozen': true},
        ],
      );
      await TestApp(tester, server).pump(const TodayScreen());

      expect(find.text('Yesterday missed. A freeze held your streak, 1 freeze left.'), findsOne);
      expect(find.text('First step'), findsNothing, reason: 'the fixture has no plan');
    });

    testWidgets('the first step goes once gems are earned', (tester) async {
      final server = _server(
        last7: [
          {'date': '2026-10-25', 'percent': 90, 'counted': true, 'rest': false},
        ],
        plan: _plan([
          {'kind': 'todo', 'key': 'steps', 'text': 'Steps: 4,491 to go (about 45 min).'},
        ]),
        points: 150,
      );
      await TestApp(tester, server).pump(const TodayScreen());
      expect(find.text('First step'), findsNothing);
    });
  });

  group('two streaks', () {
    testWidgets('Today shows the personal streak bare and Together has its own icon', (
      tester,
    ) async {
      await TestApp(tester, fullServer()).pump(const TodayScreen());
      expect(find.text('Your streak'), findsNothing);
      expect(find.bySemanticsLabel('Your streak, 3 day streak'), findsOneWidget);
      expect(find.byIcon(Icons.local_fire_department_rounded), findsWidgets);

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SharedStreakCard(
              streak: SharedStreak(current: 0, best: 3),
              names: ['Sam', 'Ana'],
            ),
          ),
        ),
      );
      expect(find.byIcon(kTogetherStreakIcon), findsOneWidget);
      expect(find.byIcon(Icons.local_fire_department_rounded), findsNothing);
      expect(find.text('Together'), findsOneWidget);
      expect(kTogetherStreakIcon, isNot(Icons.local_fire_department_rounded));
    });
  });

  group('wallet wording', () {
    test('one name for the balance, and the preseason is the unscored stretch', () {
      expect(kGemsToSpend, 'Gems to spend');
      expect(gemsToSpendLine(1929), '1,929 gems to spend');
      expect(isPreseason('Season 0'), isTrue);
      expect(isPreseason('Season 1'), isFalse);
    });
  });
}
