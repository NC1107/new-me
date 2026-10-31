import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:newme/features/habits/habit_editor_page.dart';
import 'package:newme/features/health/health_metrics.dart';
import 'package:newme/features/health/metric_screen.dart';
import 'package:newme/features/log/log_kind.dart';
import 'package:newme/features/log/log_sheet.dart';
import 'package:newme/features/shell/home_tab.dart';
import 'package:newme/features/today/day_detail_sheet.dart';
import 'package:newme/features/me/daily_goals_page.dart';
import 'package:newme/features/me/targets_page.dart';
import 'package:newme/features/training/training_profile_page.dart';
import 'package:newme/features/together/notifications_page.dart';
import 'package:newme/theme/accent.dart';
import 'package:newme/widgets/app_switch.dart';
import 'package:newme/widgets/chunky_button.dart';
import 'package:newme/widgets/mascot.dart';
import 'package:newme/widgets/page_scaffold.dart';
import 'package:newme/widgets/segmented.dart';

import 'fixtures.dart';
import 'habit_fixtures.dart';
import 'hit_targets.dart';
import 'test_support.dart';

Map<String, dynamic> _json(String path) =>
    jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>;

StubAdapter _server() => habitsServer()
  ..on('GET /api/targets', StubResponse(200, _json('test/contract_v8/targets.json')['body'] as Map))
  ..on(
    'GET /api/training/profile',
    StubResponse(200, _json('test/contract_v9/training_profile.json')),
  )
  ..on('GET /api/exercises', StubResponse(200, _json('test/contract_v9/exercises.json')))
  ..on(
    'GET /api/health/trends',
    const StubResponse(200, {
      'metric': 'steps',
      'days': 30,
      'points': [
        {'date': '2026-10-26', 'value': 4000},
        {'date': '2026-10-27', 'value': 5000},
      ],
    }),
  );

void main() {
  setUp(() {
    FakeStorage().install();
    Mascot.idleMotion = false;
  });

  for (final scale in [1.0, 1.3, 2.0]) {
    group('44pt tap targets at text scale $scale', () {
      Future<TestApp> open(WidgetTester tester, Widget page) async {
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        final app = TestApp(tester, _server(), surfaceHeight: 6000);
        await app.pump(page);
        await tester.pumpAndSettle();
        return app;
      }

      testWidgets('the Targets page', (tester) async {
        await open(tester, const TargetsPage());
        expect(find.textContaining('USE ALL RECOMMENDED'), findsOneWidget);
        expect(smallTargets(tester), isEmpty);
      });

      testWidgets('the training setup', (tester) async {
        await open(tester, const TrainingProfilePage());
        expect(find.text('Pull-up bar'), findsOneWidget);
        expect(smallTargets(tester), isEmpty);
      });

      testWidgets('the habit editor', (tester) async {
        await open(tester, const HabitEditorPage());
        expect(find.text('Start from'), findsOneWidget);
        expect(smallTargets(tester), isEmpty);
      });

      testWidgets('a health metric with its 30 and 90 day control', (tester) async {
        await open(
          tester,
          MetricScreen(metric: kHealthGroups.first.metrics.first, group: kHealthGroups.first),
        );
        expect(find.byType(Segmented<int>), findsOneWidget);
        expect(smallTargets(tester), isEmpty);
      });

      testWidgets('the daily goals and the notifications', (tester) async {
        await open(tester, const DailyGoalsPage());
        expect(smallTargets(tester), isEmpty);
        await open(tester, const NotificationsPage());
        expect(smallTargets(tester), isEmpty);
      });

      for (final kind in [LogKind.pushups, LogKind.meal, LogKind.activity]) {
        testWidgets('the ${kind.name} log sheet', (tester) async {
          final app = await open(
            tester,
            Builder(
              builder: (context) => TextButton(
                onPressed: () => showLogSheet(context, kind: kind),
                child: const Text('open sheet'),
              ),
            ),
          );
          await app.tap(find.text('open sheet'));
          expect(smallTargets(tester).where((t) => !t.startsWith('[open sheet]')), isEmpty);
        });
      }
    });
  }

  group("Today's entries", () {
    Future<TestApp> openEmpty(WidgetTester tester) async {
      final server = fullServer()..on('GET /api/logs', StubResponse(200, logsJson([])));
      final app = TestApp(tester, server);
      await app.pump(
        Builder(
          builder: (context) => TextButton(
            onPressed: () => showDayDetailSheet(context, date: '2026-10-26'),
            child: const Text('open entries'),
          ),
        ),
      );
      await app.tap(find.text('open entries'));
      return app;
    }

    testWidgets('an empty sheet sizes to its content and offers a meal or a set', (tester) async {
      await openEmpty(tester);
      expect(find.text('No meals or sets logged yet.'), findsOneWidget);
      expect(find.text('LOG A MEAL'), findsOneWidget);
      expect(find.text('LOG A SET'), findsOneWidget);
      expect(tester.getSize(find.byType(BottomSheet)).height, lessThan(400));
    });

    testWidgets('Log a set sends the person to the Train tab', (tester) async {
      final app = await openEmpty(tester);
      await app.tap(find.text('LOG A SET'));
      expect(app.container.read(homeTabProvider), HomeTab.train);
    });

    testWidgets('Log a meal opens the meal sheet', (tester) async {
      final app = await openEmpty(tester);
      await app.tap(find.text('LOG A MEAL'));
      expect(find.byType(LogSheet), findsOneWidget);
    });
  });

  group('one switch', () {
    testWidgets('has a white thumb on and off, and the track follows the person', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: themeFor(accentById('violet')),
          home: Scaffold(
            body: Row(
              children: [
                AppSwitch(value: true, onChanged: (_) {}),
                AppSwitch(value: false, onChanged: (_) {}),
              ],
            ),
          ),
        ),
      );
      final switches = tester.widgetList<Switch>(find.byType(Switch)).toList();
      for (final s in switches) {
        expect(s.activeThumbColor, const Color(0xFFFFFFFF));
        expect(s.inactiveThumbColor, const Color(0xFFFFFFFF));
      }
    });
  });

  group('page scaffold', () {
    testWidgets('the subtitle scrolls with the content instead of pinning over it', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: PageScaffold(
            title: 'Title',
            subtitle: 'A subtitle that explains the page',
            children: [for (var i = 0; i < 40; i++) Text('row $i')],
          ),
        ),
      );
      final before = tester.getTopLeft(find.text('A subtitle that explains the page')).dy;
      await tester.drag(find.byType(ListView), const Offset(0, -600));
      await tester.pump();
      expect(find.text('A subtitle that explains the page'), findsNothing);
      expect(before, greaterThan(0));
    });

    testWidgets('a footer has an opaque background and a top border, and content clears it', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: PageScaffold(
            title: 'Title',
            footer: const ChunkyButton(label: 'Save', onPressed: null),
            children: [for (var i = 0; i < 40; i++) Text('row $i')],
          ),
        ),
      );
      final bar = tester.widget<DecoratedBox>(
        find.ancestor(of: find.byType(ChunkyButton), matching: find.byType(DecoratedBox)).last,
      );
      final decoration = bar.decoration as BoxDecoration;
      expect(decoration.color!.a, 1.0);
      expect(decoration.border, isNotNull);
      final list = tester.getRect(find.byType(ListView));
      final footer = tester.getRect(find.byType(ChunkyButton));
      expect(list.bottom, lessThanOrEqualTo(footer.top), reason: 'the list ends above the bar');
    });
  });
}
