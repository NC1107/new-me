import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:newme/api/models.dart';
import 'package:newme/theme/accent.dart';
import 'package:newme/widgets/quest_card.dart';

import 'fixtures.dart';

Quest _quest({required bool completed}) => Quest.fromJson(
  quest('pushups', 'Pushups', {
    'target': 30,
    'actual': completed ? 30 : 12,
    'earned': completed ? 100 : 40,
    'bonus': completed ? 20 : 0,
    'completed': completed,
  }),
);

Widget _host(Quest q) => MaterialApp(
  theme: themeFor(kAccentPresets.first),
  home: Scaffold(
    body: QuestCard(quest: q, onTap: () {}, onAdd: () {}),
  ),
);

void main() {
  testWidgets('completing a quest plays the check and a medium impact, once', (tester) async {
    final haptics = <Object?>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (
      call,
    ) async {
      if (call.method == 'HapticFeedback.vibrate') haptics.add(call.arguments);
      return null;
    });
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );

    await tester.pumpWidget(_host(_quest(completed: false)));
    expect(find.byIcon(Icons.check_circle_rounded), findsNothing);
    expect(find.text('+20'), findsNothing);

    await tester.pumpWidget(_host(_quest(completed: true)));
    await tester.pump(const Duration(milliseconds: 110));
    expect(find.byIcon(Icons.check_circle_rounded), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('+20'), findsOneWidget);
    expect(haptics, ['HapticFeedbackType.mediumImpact']);

    await tester.pumpWidget(_host(_quest(completed: true)));
    expect(haptics, hasLength(1));
  });

  testWidgets('a quest already complete on open shows the check with no haptic', (tester) async {
    await tester.pumpWidget(_host(_quest(completed: true)));
    expect(find.byIcon(Icons.check_circle_rounded), findsOneWidget);
  });
}
