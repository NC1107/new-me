import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:newme/features/shell/home_shell.dart';
import 'package:newme/features/shell/home_tab.dart';
import 'package:newme/health/fake_health_source.dart';
import 'package:newme/health/health_source_factory.dart';
import 'package:newme/state/session.dart';
import 'package:newme/theme/accent.dart';

import 'fixtures.dart';
import 'test_support.dart';

void main() {
  setUp(FakeStorage().install);

  testWidgets('renders three tabs and tapping switches the visible body', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        retry: (_, _) => null,
        overrides: [
          sessionProvider.overrideWith(() => SessionController.seeded(testSession)),
          apiClientFactoryProvider.overrideWithValue(stubFactory(StubAdapter())),
          healthSourceProvider.overrideWithValue(FakeHealthSource()),
        ],
        child: MaterialApp(theme: themeFor(kAccentPresets.first), home: const HomeShell()),
      ),
    );

    await tester.pump(const Duration(milliseconds: 300));
    for (final label in ['Today', 'Board', 'Me']) {
      expect(find.text(label), findsWidgets);
    }
    expect(find.byIcon(Icons.add), findsOneWidget);
    expect(find.byIcon(Icons.today_rounded), findsOneWidget);

    await tester.tap(find.widgetWithText(InkResponse, 'Board'));
    await tester.pump();
    expect(find.byIcon(Icons.leaderboard_rounded), findsOneWidget);
    expect(find.byIcon(Icons.today_rounded), findsNothing);

    await tester.tap(find.widgetWithText(InkResponse, 'Me'));
    await tester.pump();
    expect(find.byIcon(Icons.person_rounded), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 300));
  });

  testWidgets('the center button opens the log sheet', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        retry: (_, _) => null,
        overrides: [
          sessionProvider.overrideWith(() => SessionController.seeded(testSession)),
          apiClientFactoryProvider.overrideWithValue(stubFactory(StubAdapter())),
          healthSourceProvider.overrideWithValue(FakeHealthSource()),
        ],
        child: MaterialApp(theme: themeFor(kAccentPresets.first), home: const HomeShell()),
      ),
    );

    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();
    expect(find.text('Pushups'), findsOneWidget);
    expect(find.text('Meal'), findsOneWidget);
  });

  testWidgets('a tab left under the offline banner reloads when it is opened again', (
    tester,
  ) async {
    final adapter = fullServer();
    final app = TestApp(tester, adapter);
    await app.pump(const HomeShell(), key: UniqueKey());

    adapter.on('GET /api/me', const StubResponse.unreachable());
    await app.pump(const HomeShell(), key: UniqueKey());
    await app.tap(find.widgetWithText(InkResponse, 'Me'));
    expect(find.textContaining('Offline - updated'), findsOneWidget);

    adapter.on('GET /api/me', StubResponse(200, meJson()));
    await app.tap(find.widgetWithText(InkResponse, 'Board'));
    await app.tap(find.widgetWithText(InkResponse, 'Me'));

    expect(find.textContaining('Offline - updated'), findsNothing);
  });

  testWidgets('a new session starts on Today instead of the tab the last one left', (tester) async {
    final app = TestApp(tester, fullServer());
    await app.pump(const HomeShell());
    await app.tap(find.widgetWithText(InkResponse, 'Me'));
    expect(app.container.read(homeTabProvider), HomeTab.me);

    await app.container.read(sessionProvider.notifier).signIn(testSession);
    await app.settle();
    expect(app.container.read(homeTabProvider), HomeTab.me, reason: 'same person, same tab');

    await app.container
        .read(sessionProvider.notifier)
        .signIn(
          const Session(
            baseUrl: 'https://me.invalid',
            token: 'other',
            userId: 9,
            userName: 'Ana',
            color: 'amber',
          ),
        );
    await app.settle();
    expect(app.container.read(homeTabProvider), HomeTab.today);
  });

  testWidgets('coming back to the app reloads a Today that crossed midnight', (tester) async {
    final adapter = fullServer();
    final app = TestApp(tester, adapter);
    await app.pump(const HomeShell());
    expect(find.text('Monday, Oct 26'), findsOneWidget);

    adapter.on(
      'GET /api/today',
      StubResponse(
        200,
        richTodayJson()..addAll({'date': '2026-10-27', 'localToday': '2026-10-27'}),
      ),
    );
    final binding = TestWidgetsFlutterBinding.instance;
    binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await app.settle();

    expect(find.text('Tuesday, Oct 27'), findsOneWidget);
    expect(find.text('Monday, Oct 26'), findsNothing);
  });

  testWidgets("the next person never sees the previous person's Today while theirs loads", (
    tester,
  ) async {
    final adapter = fullServer();
    final app = TestApp(tester, adapter);
    await app.pump(const HomeShell());
    expect(find.text('150'), findsOneWidget);

    final gate = Completer<void>();
    adapter.routes['GET /api/today'] = (_) async {
      await gate.future;
      return StubResponse(200, richTodayJson(points: 999));
    };
    await app.container
        .read(sessionProvider.notifier)
        .signIn(
          const Session(
            baseUrl: 'https://me.invalid',
            token: 'other',
            userId: 9,
            userName: 'Ana',
            color: 'amber',
          ),
        );
    await app.settle();
    expect(find.text('150'), findsNothing);
    expect(find.text('Monday, Oct 26'), findsNothing);

    gate.complete();
    await app.settle();
    expect(find.text('999'), findsOneWidget);
  });
}
