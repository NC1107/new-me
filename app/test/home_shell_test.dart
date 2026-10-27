import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:newme/features/shell/home_shell.dart';
import 'package:newme/theme/accent.dart';

void main() {
  testWidgets('renders three tabs and tapping switches the visible body', (tester) async {
    await tester.pumpWidget(
      MaterialApp(theme: themeFor(kAccentPresets.first), home: const HomeShell()),
    );

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
  });
}
