import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:newme/features/me/me_screen.dart';
import 'package:newme/features/onboarding/steps_finish.dart';
import 'package:newme/theme/accent.dart';
import 'package:newme/features/me/reminders_page.dart';
import 'package:newme/reminders/reminder_plan.dart';
import 'package:newme/reminders/reminder_scheduler.dart';
import 'package:newme/widgets/mascot.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_reminder_scheduler.dart';
import 'fixtures.dart';
import 'test_support.dart';

Future<(TestApp, FakeReminderScheduler)> _open(
  WidgetTester tester, {
  bool allowed = true,
  bool grants = true,
  Map<String, Object> prefs = const {},
}) async {
  FakeStorage().install();
  SharedPreferences.setMockInitialValues(prefs);
  final scheduler = FakeReminderScheduler(allowed: allowed, grantsOnRequest: grants);
  final app = TestApp(tester, fullServer());
  await app.pump(
    const MeScreen(),
    overrides: [reminderSchedulerProvider.overrideWithValue(scheduler)],
  );
  return (app, scheduler);
}

void main() {
  setUp(() => Mascot.idleMotion = false);

  testWidgets('the Me row says Off, then the time once reminders are on', (tester) async {
    final (app, _) = await _open(tester);
    final row = find.bySemanticsLabel('Reminders, Off');
    final handle = tester.ensureSemantics();
    expect(find.text('Reminders'), findsOneWidget);
    expect(row, findsOneWidget);

    await app.tap(find.text('Reminders'));
    await app.tap(find.text('Evening reminder'));
    await app.tap(find.byTooltip('Back'));

    expect(find.bySemanticsLabel('Reminders, 8:00 PM'), findsOneWidget);
    handle.dispose();
  });

  testWidgets('the page switches reminders on, picks a preset time and turns them off', (
    tester,
  ) async {
    final (app, scheduler) = await _open(tester);
    await app.tap(find.text('Reminders'));

    expect(find.text('What time?'), findsNothing, reason: 'the time only matters when on');
    await app.tap(find.text('Evening reminder'));
    expect(scheduler.permissionRequests, 1);
    expect(find.text('What time?'), findsOneWidget);
    expect(scheduler.pending[kTomorrowReminderId]?.at.hour, 20);

    await app.tap(find.text('9:00 PM'));
    expect(scheduler.pending[kTomorrowReminderId]?.at.hour, 21);
    expect(find.text('PICK ANOTHER TIME'), findsOneWidget);

    await app.tap(find.text('Evening reminder'));
    expect(scheduler.pending, isEmpty);
    expect(find.text('What time?'), findsNothing);
  });

  testWidgets('a denied permission explains how to enable it in iOS Settings', (tester) async {
    final (app, scheduler) = await _open(tester, grants: false);
    await app.tap(find.text('Reminders'));
    expect(find.textContaining('Open the Settings app'), findsNothing);

    await app.tap(find.text('Evening reminder'));

    expect(find.textContaining('Open the Settings app'), findsOneWidget);
    expect(find.text('What time?'), findsNothing);
    expect(scheduler.pending, isEmpty);
  });

  testWidgets('a custom time shows on the button and picks through the time picker', (
    tester,
  ) async {
    final (app, scheduler) = await _open(
      tester,
      prefs: {'remindersEnabled': true, 'reminderMinutes': 21 * 60 + 30},
    );
    await app.tap(find.text('Reminders'));

    expect(find.text('9:30 PM'), findsOneWidget);
    await app.tap(find.text('9:30 PM'));
    expect(find.text('Remind me at'), findsOneWidget);
    expect(scheduler.pending[kTomorrowReminderId]?.at.minute, 30);
  });

  for (final scale in [1.0, 2.0]) {
    testWidgets('the Reminders page fits 390 wide at text scale $scale', (tester) async {
      FakeStorage().install();
      SharedPreferences.setMockInitialValues({'remindersEnabled': true});
      tester.platformDispatcher.textScaleFactorTestValue = scale;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final app = TestApp(tester, fullServer());
      await app.pump(
        const RemindersPage(),
        overrides: [reminderSchedulerProvider.overrideWithValue(FakeReminderScheduler())],
      );
      expect(tester.takeException(), isNull);
      expect(find.text('What time?'), findsOneWidget);

      final blocked = TestApp(tester, fullServer());
      await blocked.pump(
        const RemindersPage(),
        key: UniqueKey(),
        overrides: [
          reminderSchedulerProvider.overrideWithValue(FakeReminderScheduler(allowed: false)),
        ],
      );
      expect(tester.takeException(), isNull);
      expect(find.textContaining('Open the Settings app'), findsOneWidget);
    });
  }

  testWidgets('the onboarding reminder step fits 390 wide at text scale 2.0', (tester) async {
    FakeStorage().install();
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 2.0;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpWidget(
      ProviderScope(
        retry: (_, _) => null,
        child: MaterialApp(
          theme: themeFor(accentById('violet')),
          home: const Scaffold(body: ReminderStep()),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.takeException(), isNull);
    expect(find.text('ALLOW'), findsOneWidget);
    expect(find.text('NOT NOW'), findsOneWidget);
  });
}
