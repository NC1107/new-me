import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:newme/api/models.dart';
import 'package:newme/theme/accent.dart';
import 'package:newme/widgets/confetti.dart';
import 'package:newme/widgets/pop_in.dart';
import 'package:newme/widgets/quest_card.dart';
import 'package:newme/widgets/quest_copy.dart';
import 'package:newme/widgets/thick_progress_bar.dart';

import 'fixtures.dart';

Quest _quest({required bool completed, String key = 'pushups'}) => Quest.fromJson(
  quest(key, 'Push-ups', {
    'target': 30,
    'actual': completed ? 30 : 12,
    'basePoints': completed ? 100 : 40,
    'bonusPoints': completed ? 20 : 0,
    'done': completed,
  }),
);

Widget _host(Quest q, {bool reduceMotion = false, bool withAdd = true}) => MaterialApp(
  theme: themeFor(kAccentPresets.first),
  home: MediaQuery(
    data: MediaQueryData(disableAnimations: reduceMotion),
    child: Scaffold(
      body: Center(
        child: QuestCard(quest: q, onTap: () {}, onAdd: withAdd ? () {} : null),
      ),
    ),
  ),
);

List<Object?> _captureHaptics(WidgetTester tester) {
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
  return haptics;
}

void main() {
  testWidgets('automatic quests show the amount so far beside the bar', (tester) async {
    Quest q(String key, String unit, int target, int actual) => Quest.fromJson(
      quest(key, key, {'unit': unit, 'target': target, 'actual': actual, 'done': false}),
    );
    await tester.pumpWidget(_host(q('steps', 'steps', 7000, 4321), withAdd: false));
    expect(find.text('4,321'), findsOneWidget);
    await tester.pumpWidget(_host(q('sleep', 'min', 450, 432), withAdd: false));
    expect(find.text('7 h 12 min'), findsOneWidget);
    await tester.pumpWidget(_host(q('steps', 'steps', 7000, 0), withAdd: false));
    expect(find.text('0'), findsNothing);
  });

  testWidgets('the add button is a 44pt touch target', (tester) async {
    await tester.pumpWidget(_host(_quest(completed: false)));
    final size = tester.getSize(find.bySemanticsLabel('Add entry for Get stronger'));
    expect(size.width, greaterThanOrEqualTo(44));
    expect(size.height, greaterThanOrEqualTo(44));
  });

  testWidgets('completing a quest pops the badge, bursts confetti and gives one medium impact', (
    tester,
  ) async {
    final haptics = _captureHaptics(tester);

    await tester.pumpWidget(_host(_quest(completed: false)));
    expect(find.byIcon(Icons.check_rounded), findsNothing);
    expect(find.text('+20'), findsNothing);

    await tester.pumpWidget(_host(_quest(completed: true)));
    await tester.pump();
    expect(find.byIcon(Icons.check_rounded), findsOneWidget);
    expect(find.byType(PopIn), findsOneWidget);
    expect(find.byType(Confetti), findsOneWidget);
    expect(find.text('+20'), findsOneWidget);
    expect(haptics, ['HapticFeedbackType.mediumImpact']);

    await tester.pump(const Duration(milliseconds: 1500));
    expect(find.byType(Confetti), findsNothing, reason: 'the burst cleans up its overlay');

    await tester.pumpWidget(_host(_quest(completed: true)));
    expect(haptics, hasLength(1));
  });

  testWidgets('with animations disabled completing still checks the card but throws no confetti', (
    tester,
  ) async {
    await tester.pumpWidget(_host(_quest(completed: false), reduceMotion: true));
    await tester.pumpWidget(_host(_quest(completed: true), reduceMotion: true));
    await tester.pump();
    expect(find.byIcon(Icons.check_rounded), findsOneWidget);
    expect(find.byType(Confetti), findsNothing);
  });

  testWidgets('a quest already complete on open shows the badge with no pop and no haptic', (
    tester,
  ) async {
    final haptics = _captureHaptics(tester);
    await tester.pumpWidget(_host(_quest(completed: true)));
    await tester.pump();
    expect(find.byIcon(Icons.check_rounded), findsOneWidget);
    expect(find.byType(PopIn), findsNothing);
    expect(find.byType(Confetti), findsNothing);
    expect(haptics, isEmpty);
  });

  testWidgets('the bar takes the person colour when the quest is done', (tester) async {
    Color barColor() => tester.widget<ThickProgressBar>(find.byType(ThickProgressBar)).color!;

    await tester.pumpWidget(_host(_quest(completed: false)));
    expect(barColor(), isNot(kAccentPresets.first.fill));

    await tester.pumpWidget(_host(_quest(completed: true)));
    await tester.pump(const Duration(milliseconds: 1500));
    expect(barColor(), kAccentPresets.first.fill);
  });

  testWidgets('automatic quests have no plus and no per-card Health chip', (tester) async {
    await tester.pumpWidget(_host(_quest(completed: false, key: 'steps'), withAdd: false));
    expect(find.text('Apple Health'), findsNothing);
    expect(find.byIcon(Icons.add_rounded), findsNothing);
  });

  group('quest copy', () {
    Quest q(String key, Map<String, dynamic> f) => Quest.fromJson(quest(key, key, f));

    test('titles are plain sentences', () {
      expect(questTitle(q('steps', {'unit': 'steps', 'target': 8000})), 'Walk 8,000 steps');
      expect(questTitle(q('pushups', {'target': 30})), 'Get stronger');
      expect(
        questTitle(
          q('reading', {'unit': 'minutes', 'unitAlt': 'pages', 'target': 20, 'targetAlt': 15}),
        ),
        'Read 20 min or 15 pages',
      );
      expect(questTitle(q('sleep', {'unit': 'min', 'target': 450})), 'Sleep 7 h 30 min');
      expect(questTitle(q('exercise', {'unit': 'min', 'target': 30})), 'Exercise 30 min');
      expect(questTitle(q('meals_logged', {'unit': 'meals', 'target': 1})), 'Log 1 meal');
      expect(questTitle(q('protein', {'unit': 'g', 'target': 130})), 'Eat 130 g protein');
      expect(questTitle(q('yoga', {'unit': 'minutes', 'target': 15})), 'Yoga or stretch 15 min');
    });

    test('progress reads as a short phrase', () {
      expect(
        questProgress(q('steps', {'unit': 'steps', 'target': 8000, 'actual': 2000})),
        '2,000 of 8,000 steps',
      );
      expect(
        questProgress(q('protein', {'unit': 'g', 'target': 130, 'actual': 82})),
        '82 of 130 g',
      );
      expect(questProgress(q('sleep', {'unit': 'min', 'target': 420})), 'No sleep recorded');
      expect(
        questProgress(
          q('reading', {'unit': 'minutes', 'unitAlt': 'pages', 'target': 20, 'targetAlt': 15}),
        ),
        'Not started',
      );
    });
  });
}
