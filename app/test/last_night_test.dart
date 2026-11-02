import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:newme/api/models.dart';
import 'package:newme/features/today/last_night.dart';

Quest _q(
  String key, {
  num actual = 0,
  bool done = false,
  int base = 0,
  Map<String, dynamic>? detail,
}) => Quest.fromJson({
  'key': key,
  'title': key,
  'unit': 'min',
  'target': key == 'sleep' ? 450 : 45,
  'actual': actual,
  'points': 20,
  'basePoints': done ? 20 : base,
  'bonusPoints': 0,
  'done': done,
  'detail': ?detail,
});

List<String> _keys(List<Quest> qs) => [for (final q in qs) q.key];

void main() {
  test('a night that met the goal leads the list', () {
    final o = orderQuests([_q('steps'), _q('sleep', actual: 470, done: true), _q('water')]);
    expect(_keys(o.list), ['sleep', 'steps', 'water']);
    expect(o.missed, isEmpty);
  });

  test('a short night leaves the list for the last night note', () {
    final o = orderQuests([_q('steps'), _q('sleep', actual: 334), _q('water')]);
    expect(_keys(o.list), ['steps', 'water']);
    expect(_keys(o.missed), ['sleep']);
    expect(lastNightLine(o.missed.single), 'Slept 5 h 34 min of 7 h 30 min');
  });

  test('a night not yet in from Health stays an open quest in its place', () {
    final o = orderQuests([_q('steps'), _q('sleep'), _q('water')]);
    expect(_keys(o.list), ['steps', 'sleep', 'water']);
    expect(o.missed, isEmpty);
  });

  test('the steady bedtime settles once its night can be measured', () {
    final measured = _q('sleep_regularity', detail: {'measurable': true, 'windowMin': 45});
    final learning = _q('sleep_regularity', detail: {'measurable': false, 'baselineNights': 1});
    expect(_keys(orderQuests([measured]).missed), ['sleep_regularity']);
    expect(_keys(orderQuests([learning]).list), ['sleep_regularity']);
    expect(lastNightLine(measured), 'Neither within 45 min of usual');
  });

  test('the note counts what a short night still earned', () {
    expect(lastNightGems(_q('sleep', actual: 334, base: 16)), 'Last night, 16 of 20 gems');
    expect(
      lastNightGems(_q('sleep_regularity', detail: {'measurable': true})),
      'Last night, no gems',
    );
  });

  testWidgets('the note names the night and opens the quest', (tester) async {
    String? opened;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LastNightCard(
            missed: [_q('sleep', actual: 334, base: 16)],
            onOpen: (k) => opened = k,
          ),
        ),
      ),
    );
    expect(find.text('Slept 5 h 34 min of 7 h 30 min'), findsOneWidget);
    expect(
      find.bySemanticsLabel('Slept 5 h 34 min of 7 h 30 min. Last night, 16 of 20 gems.'),
      findsOneWidget,
    );
    await tester.tap(find.text('Slept 5 h 34 min of 7 h 30 min'));
    expect(opened, 'sleep');
    expect(tester.getSize(find.byType(LastNightCard)).height, greaterThanOrEqualTo(44));
  });
}
