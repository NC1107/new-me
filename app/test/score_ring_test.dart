import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:newme/theme/accent.dart';
import 'package:newme/widgets/score_ring.dart';

Widget _host({
  required int points,
  required int percent,
  bool countUp = false,
  bool reduceMotion = false,
}) => MaterialApp(
  theme: themeFor(kAccentPresets.first),
  home: MediaQuery(
    data: MediaQueryData(disableAnimations: reduceMotion),
    child: Scaffold(
      body: Center(
        child: ScoreRing(points: points, percent: percent, countUp: countUp),
      ),
    ),
  ),
);

int _shownPoints(WidgetTester tester) {
  final texts = tester.widgetList<Text>(
    find.descendant(of: find.byType(ScoreRing), matching: find.byType(Text)),
  );
  return int.parse(texts.first.data!.replaceAll(',', ''));
}

void main() {
  testWidgets('opening shows the final value at once, with no sweep', (tester) async {
    await tester.pumpWidget(_host(points: 120, percent: 40));
    expect(_shownPoints(tester), 120);
    expect(find.text('40%'), findsOneWidget);
  });

  testWidgets('a changed value sweeps from the old one to the new one', (tester) async {
    await tester.pumpWidget(_host(points: 100, percent: 25));
    await tester.pumpWidget(_host(points: 200, percent: 50));
    await tester.pump(const Duration(milliseconds: 100));
    final midway = _shownPoints(tester);
    expect(midway, greaterThan(100));
    expect(midway, lessThan(200));
    await tester.pump(const Duration(milliseconds: 300));
    expect(_shownPoints(tester), 200);
  });

  testWidgets('the first view of the day counts up from zero', (tester) async {
    await tester.pumpWidget(_host(points: 120, percent: 40, countUp: true));
    expect(_shownPoints(tester), 0);
    await tester.pump(const Duration(milliseconds: 400));
    expect(_shownPoints(tester), 120);
  });

  testWidgets('reduced motion skips both the count-up and the sweep', (tester) async {
    await tester.pumpWidget(_host(points: 120, percent: 40, countUp: true, reduceMotion: true));
    expect(_shownPoints(tester), 120);
    await tester.pumpWidget(_host(points: 200, percent: 50, reduceMotion: true));
    expect(_shownPoints(tester), 200);
  });

  testWidgets('the ring is described to screen readers', (tester) async {
    await tester.pumpWidget(_host(points: 120, percent: 40));
    expect(find.bySemanticsLabel('120 points, 40 percent of the day'), findsOneWidget);
  });
}
