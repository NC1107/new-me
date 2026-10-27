import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:newme/features/shell/home_shell.dart';
import 'package:newme/health/fake_health_source.dart';
import 'package:newme/health/health_source_factory.dart';
import 'package:newme/state/session.dart';
import 'package:newme/theme/accent.dart';

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
}
