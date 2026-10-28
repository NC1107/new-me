import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:newme/api/models.dart';
import 'package:newme/features/today/day_card.dart';

import 'fixtures.dart';

DayScore _day({required int base, required int goalPercent}) =>
    DayScore.fromJson({...dayJson(), 'basePoints': base, 'goalPercent': goalPercent});

void main() {
  test('goalPercent is computed from the points when an older server omits it', () {
    final json = Map<String, dynamic>.of(dayJson(points: 300))
      ..remove('goalPercent')
      ..['basePoints'] = 280;
    expect(DayScore.fromJson(json).goalPercent, 100);
    json['basePoints'] = 140;
    expect(DayScore.fromJson(json).goalPercent, 50);
    expect(DayScore.fromJson(json).toJson()['goalPercent'], 50);
  });

  test('a day mark and a board day fall back to the percent when goalPercent is absent', () {
    expect(
      DayMark.fromJson({'date': '2026-10-26', 'percent': 70, 'counted': true}).goalPercent,
      100,
    );
    expect(BoardDay.fromJson({'points': 1, 'percent': 35, 'counted': false}).goalPercent, 50);
  });

  testWidgets('the day card is full at the goal and shows the extra as a bonus', (tester) async {
    Widget card(DayScore day) => MaterialApp(
      home: Scaffold(
        body: DayCard(
          day: day,
          streak: const Streak(current: 1, restAvailable: false),
          onEntries: () {},
        ),
      ),
    );
    await tester.pumpWidget(card(_day(base: 280, goalPercent: 100)));
    expect(find.text('100%'), findsOneWidget);
    expect(find.textContaining('bonus'), findsNothing);
    expect(find.byIcon(Icons.flag_rounded), findsNothing);

    await tester.pumpWidget(card(_day(base: 400, goalPercent: 142)));
    expect(find.text('142%'), findsOneWidget);
    expect(find.text('+42% bonus'), findsOneWidget);
  });
}
