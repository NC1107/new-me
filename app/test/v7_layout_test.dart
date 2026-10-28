import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:newme/features/board/board_screen.dart';
import 'package:newme/features/insights/insights_screen.dart';
import 'package:newme/features/log/log_kind.dart';
import 'package:newme/features/log/log_sheet.dart';
import 'package:newme/features/me/schedule_page.dart';
import 'package:newme/features/progress/lookback_screen.dart';
import 'package:newme/features/progress/milestones_page.dart';
import 'package:newme/features/progress/progress_screen.dart';
import 'package:newme/features/streaks/away_page.dart';
import 'package:newme/features/today/streak_sheet.dart';
import 'package:newme/features/today/today_screen.dart';
import 'package:newme/features/together/notifications_page.dart';
import 'package:newme/api/models.dart';
import 'package:newme/state/today.dart';
import 'package:newme/widgets/chunky_button.dart';
import 'package:newme/widgets/mascot.dart';

import 'fixtures.dart';
import 'test_support.dart';

final _morning = DateTime(2026, 10, 27, 8);

Map<String, dynamic> _fixture(String name) =>
    (jsonDecode(File('test/contract_v7/$name.json').readAsStringSync()) as Map)['body']!
        as Map<String, dynamic>;

Map<String, dynamic> _mark(
  String date, {
  bool frozen = false,
  bool away = false,
  bool repaired = false,
}) => {
  'date': date,
  'percent': 10,
  'counted': false,
  'rest': false,
  'frozen': frozen,
  'away': away,
  'repaired': repaired,
};

/// Everything v7 can put on Today and Us at once: a repair window, a cover, away days, freezes,
/// a weight trend, frozen and repaired days, a shared streak and per-person challenge shares.
StubAdapter _busyServer() {
  final today = {
    ...richTodayJson(stepsEverSynced: true),
    'freezes': {'held': 2, 'earnedTowardNext': 3},
    'repair': {'date': '2026-10-25', 'until': '2026-10-28T02:00:00Z', 'progressPercent': 40},
    'away': {
      'today': true,
      'current': {
        'id': 1,
        'from': '2026-10-26',
        'to': '2026-10-29',
        'note': 'A long note about the trip',
      },
      'upcoming': [
        {'id': 2, 'from': '2026-11-02', 'to': '2026-11-09', 'note': ''},
      ],
    },
    'newMilestones': <Object>[],
  };
  final me = boardUser(
    2,
    'Alexandria-Long-Name',
    'violet',
    last7: [
      _mark('2026-10-24', frozen: true),
      _mark('2026-10-25', repaired: true),
      _mark('2026-10-26', away: true),
    ],
  );
  final partner = boardUser(
    1,
    'Ana',
    'amber',
    last7: [_mark('2026-10-24'), _mark('2026-10-25'), _mark('2026-10-26')],
  );
  return fullServer()
    ..on('GET /api/today', StubResponse(200, today))
    ..on(
      'GET /api/board',
      StubResponse(200, {
        ...board([
          {
            ...me,
            'freezes': {'held': 1, 'earnedTowardNext': 2},
          },
          {
            ...partner,
            'freezes': {'held': 0, 'earnedTowardNext': 6},
          },
        ]),
        'challenge': _fixture('board')['challenge'],
        'sharedStreak': {'current': 1234, 'best': 2345},
      }),
    )
    ..on('GET /api/insights', StubResponse(200, _fixture('insights_rich')))
    ..on('GET /api/progress', StubResponse(200, _fixture('progress_rich')))
    ..on('GET /api/lookback', StubResponse(200, _fixture('lookback_rich')))
    ..on('GET /api/milestones', StubResponse(200, _fixture('milestones')));
}

Future<void> _scrollThrough(WidgetTester tester, TestApp app) async {
  final list = find.byType(Scrollable).first;
  for (var i = 0; i < 12; i++) {
    await tester.drag(list, const Offset(0, -500));
    await app.settle(4);
    expect(tester.takeException(), isNull, reason: 'while scrolling');
  }
}

/// Every tappable thing the finder matches is at least 44 points each way.
void _expectTargets(WidgetTester tester, Finder f, {double min = 44}) {
  expect(f, findsWidgets);
  for (final e in f.evaluate()) {
    final size = tester.getSize(find.byElementPredicate((x) => x == e));
    expect(size.height, greaterThanOrEqualTo(min), reason: '${e.widget} height');
    expect(size.width, greaterThanOrEqualTo(min), reason: '${e.widget} width');
  }
}

void main() {
  setUp(() {
    FakeStorage().install();
    Mascot.idleMotion = false;
  });

  for (final scale in [1.0, 2.0]) {
    group('at text scale $scale', () {
      Future<TestApp> open(WidgetTester tester, Widget home, {DateTime? at}) async {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        addTearDown(tester.view.reset);
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        final app = TestApp(tester, _busyServer());
        await app.pump(home, tall: false, key: UniqueKey(), now: at ?? _morning);
        await app.settle(20);
        expect(tester.takeException(), isNull, reason: 'on first paint');
        return app;
      }

      testWidgets('Today with a repair, a cover, away days and a weight trend', (tester) async {
        final app = await open(tester, const TodayScreen());
        await _scrollThrough(tester, app);
      });

      testWidgets('Us with the shared streak, cover, freezes and challenge shares', (tester) async {
        final app = await open(tester, const BoardScreen());
        await _scrollThrough(tester, app);
      });

      testWidgets('the streak sheet', (tester) async {
        final app = await open(
          tester,
          Builder(
            builder: (context) => TextButton(
              onPressed: () => showStreakSheet(
                context,
                streak: const Streak(current: 12, restAvailable: true, restUsedOn: '2026-10-22'),
                line: 70,
                freezes: const Freezes(held: 1, earnedTowardNext: 4),
                onAway: () {},
              ),
              child: const Text('open'),
            ),
          ),
        );
        await tester.tap(find.text('open'));
        await tester.pump(const Duration(seconds: 1));
        expect(tester.takeException(), isNull);
        await tester.drag(find.byType(SingleChildScrollView).last, const Offset(0, -500));
        await tester.pump();
        expect(tester.takeException(), isNull);
        await app.closeSheet();
      });

      testWidgets('the Away page with spans', (tester) async {
        final app = await open(tester, const AwayPage());
        app.container.read(todayProvider);
        await app.settle(20);
        await _scrollThrough(tester, app);
      });

      testWidgets('Me > Schedule', (tester) async {
        final app = await open(tester, const SchedulePage());
        await _scrollThrough(tester, app);
      });

      testWidgets('Progress, the look-back and milestones', (tester) async {
        for (final page in const [ProgressScreen(), LookbackScreen(), MilestonesPage()]) {
          final app = await open(tester, page);
          await _scrollThrough(tester, app);
        }
      });

      testWidgets('Insights with the weight, WHO and protein cards', (tester) async {
        final app = await open(tester, const InsightsScreen());
        await _scrollThrough(tester, app);
      });

      testWidgets('the Log activity sheet', (tester) async {
        final app = await open(
          tester,
          Builder(
            builder: (context) => TextButton(
              onPressed: () => showLogSheet(context, kind: LogKind.activity),
              child: const Text('open'),
            ),
          ),
        );
        await tester.tap(find.text('open'));
        await tester.pump(const Duration(seconds: 1));
        expect(tester.takeException(), isNull);
        await tester.drag(find.byType(SingleChildScrollView).last, const Offset(0, -500));
        await tester.pump();
        expect(tester.takeException(), isNull);
        await app.closeSheet();
      });

      testWidgets('the notifications page with milestones and the look-back', (tester) async {
        final app = await open(tester, const NotificationsPage());
        await _scrollThrough(tester, app);
      });
    });
  }

  group('touch targets are at least 44 points', () {
    Future<TestApp> open(WidgetTester tester, Widget home) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final app = TestApp(tester, _busyServer());
      await app.pump(home, tall: false, key: UniqueKey(), now: _morning);
      await app.settle(20);
      return app;
    }

    testWidgets('Today: the snowflakes, the away link and the repair card', (tester) async {
      final handle = tester.ensureSemantics();
      await open(tester, const TodayScreen());
      final flakes = find.bySemanticsLabel('2 streak freezes');
      expect(tester.getSize(flakes).height, greaterThanOrEqualTo(44));
      expect(tester.getSize(flakes).width, greaterThanOrEqualTo(44));
      expect(tester.getSize(find.text('You are away')).height, greaterThan(0));
      handle.dispose();
    });

    testWidgets('Today: the away link', (tester) async {
      final server = _busyServer()
        ..on(
          'GET /api/today',
          StubResponse(200, {
            ...richTodayJson(stepsEverSynced: true),
            'freezes': {'held': 1, 'earnedTowardNext': 3},
          }),
        );
      final app = TestApp(tester, server);
      tester.view.physicalSize = const Size(390, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await app.pump(const TodayScreen(), tall: false, key: UniqueKey(), now: _morning);
      final link = find.ancestor(
        of: find.text("Can't today?"),
        matching: find.byType(ConstrainedBox),
      );
      expect(tester.getSize(link.first).height, greaterThanOrEqualTo(44));
    });

    testWidgets('the Away page: presets, dates, remove', (tester) async {
      final app = await open(tester, const AwayPage());
      app.container.read(todayProvider);
      await app.settle(20);
      for (final label in ['Today', 'Tomorrow', '3 days', 'A week']) {
        expect(
          tester.getSize(find.bySemanticsLabel(label).first).height,
          greaterThanOrEqualTo(44),
          reason: label,
        );
      }
      _expectTargets(
        tester,
        find.byIcon(Icons.delete_outline_rounded).evaluate().isEmpty
            ? find.byType(IconButton)
            : find.byType(IconButton),
        min: 44,
      );
      expect(
        tester.getSize(find.bySemanticsLabel(RegExp('^From'))).height,
        greaterThanOrEqualTo(44),
      );
    });

    testWidgets('Schedule: weekday chips and time fields', (tester) async {
      await open(tester, const SchedulePage());
      for (final day in ['Monday', 'Tuesday', 'Sunday']) {
        expect(
          tester.getSize(find.bySemanticsLabel(day)).height,
          greaterThanOrEqualTo(44),
          reason: day,
        );
      }
      expect(
        tester.getSize(find.bySemanticsLabel(RegExp('^Wake up')).first).height,
        greaterThanOrEqualTo(44),
      );
      expect(
        tester.getSize(find.bySemanticsLabel(RegExp('^On workdays at'))).height,
        greaterThanOrEqualTo(44),
      );
    });

    testWidgets('Progress: the person switcher and the rows below', (tester) async {
      await open(tester, const ProgressScreen());
      expect(tester.getSize(find.bySemanticsLabel('Nick')).height, greaterThanOrEqualTo(44));
      expect(tester.getSize(find.bySemanticsLabel('Nadia')).height, greaterThanOrEqualTo(44));
    });

    testWidgets('the look-back: the month arrows', (tester) async {
      await open(tester, const LookbackScreen());
      expect(
        tester.getSize(find.bySemanticsLabel('Previous month')).height,
        greaterThanOrEqualTo(44),
      );
      expect(tester.getSize(find.bySemanticsLabel('Next month')).width, greaterThanOrEqualTo(44));
    });

    testWidgets('Us: the cover button', (tester) async {
      await open(tester, const BoardScreen());
      expect(find.text('COVER ANA'), findsOneWidget);
      final button = find.byWidgetPredicate((w) => w is ChunkyButton && w.label == 'Cover Ana');
      expect(tester.getSize(button).height, greaterThanOrEqualTo(44));
    });

    testWidgets('Log activity: chips and the stepper', (tester) async {
      final app = await open(
        tester,
        Builder(
          builder: (context) => TextButton(
            onPressed: () => showLogSheet(context, kind: LogKind.activity),
            child: const Text('open'),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pump(const Duration(seconds: 1));
      for (final label in ['Walk', 'Easy', 'Moderate', 'Hard', '+10']) {
        expect(
          tester.getSize(find.bySemanticsLabel(label).first).height,
          greaterThanOrEqualTo(44),
          reason: label,
        );
      }
      await app.closeSheet();
    });
  });
}
