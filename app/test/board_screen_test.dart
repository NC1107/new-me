import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:newme/features/board/board_screen.dart';
import 'package:newme/theme/accent.dart';

import 'fixtures.dart';
import 'test_support.dart';

StubAdapter _server(List<Map<String, dynamic>> users) =>
    fullServer()..on('GET /api/board', StubResponse(200, board(users)));

Color? _avatarColor(WidgetTester tester, String name) {
  final column = find.ancestor(of: find.text(name), matching: find.byType(Row)).first;
  final avatar = find.descendant(of: column, matching: find.byType(CircleAvatar));
  return tester.widget<CircleAvatar>(avatar.first).backgroundColor;
}

void main() {
  setUp(FakeStorage().install);

  testWidgets('with one user the other column is a dashed placeholder with a how-to sheet', (
    tester,
  ) async {
    final app = TestApp(tester, _server([boardUser(2, 'Sam', 'violet')]));
    await app.pump(const BoardScreen());

    expect(find.text('Sam'), findsOneWidget);
    expect(find.text('Waiting for your partner'), findsOneWidget);
    expect(find.text('How they join'), findsOneWidget);

    await app.tap(find.text('Waiting for your partner'));
    expect(find.text('Send them the TestFlight invite for New Me.'), findsOneWidget);
    expect(find.textContaining('Create a pairing code in Me'), findsOneWidget);
    expect(find.text('How they join'), findsWidgets);
  });

  testWidgets('a zero streak reads as no streak yet instead of a 0-day streak', (tester) async {
    final app = TestApp(tester, _server([boardUser(2, 'Sam', 'violet', streak: 0)]));
    await app.pump(const BoardScreen());

    expect(find.text('No streak yet'), findsOneWidget);
    expect(find.text('0-day streak'), findsNothing);
  });

  testWidgets('two users show two columns, each in their own accent', (tester) async {
    final app = TestApp(
      tester,
      _server([
        boardUser(2, 'Sam', 'violet', points: 120, percent: 30),
        boardUser(1, 'Ana', 'amber', points: 2400, percent: 88, week: 1200, season: 8000),
      ]),
    );
    await app.pump(const BoardScreen());

    expect(find.text('Waiting for your partner'), findsNothing);
    expect(find.text('Sam'), findsOneWidget);
    expect(find.text('Ana'), findsOneWidget);
    expect(find.text('120'), findsOneWidget);
    expect(find.text('2,400'), findsOneWidget);
    expect(find.text('30%'), findsOneWidget);
    expect(find.text('88%'), findsOneWidget);
    expect(find.text('1,200'), findsOneWidget);
    expect(find.text('8,000'), findsOneWidget);
    expect(find.text('4-day streak'), findsNWidgets(2));
    expect(find.text('1 rest day'), findsNWidgets(2));
    expect(find.text('synced 3h ago'), findsNWidgets(2));
    expect(find.text('Season 0 - ends Dec 31'), findsOneWidget);
    expect(find.text('Nobody has moved yet.'), findsNothing);

    expect(_avatarColor(tester, 'Sam'), accentById('violet').base);
    expect(_avatarColor(tester, 'Ana'), accentById('amber').base);
  });

  testWidgets('the 7 day strip marks counted, rest and missed days differently', (tester) async {
    final app = TestApp(tester, _server([boardUser(2, 'Sam', 'violet')]));
    await app.pump(const BoardScreen());

    final dots = tester
        .widgetList<Container>(
          find.byWidgetPredicate((w) => w is Container && w.constraints?.maxWidth == 14),
        )
        .map((c) => c.decoration! as BoxDecoration)
        .toList();
    expect(dots, hasLength(7));
    final accent = accentById('violet').base;
    final filled = dots.where((d) => d.color == accent).length;
    final hollow = dots.where((d) => d.color == null && d.border != null).length;
    expect(filled, 4);
    expect(hollow, 1);
    expect(dots.length - filled - hollow, 2);
  });

  testWidgets('a user with no sync yet says so', (tester) async {
    final user = boardUser(2, 'Sam', 'violet')..['syncedAt'] = null;
    final app = TestApp(tester, _server([user]));
    await app.pump(const BoardScreen());
    expect(find.text('Health not synced'), findsOneWidget);
  });

  testWidgets('day one reads as empty, not broken', (tester) async {
    final app = TestApp(
      tester,
      _server([
        boardUser(2, 'Sam', 'violet', points: 0, percent: 0, week: 0, season: 0, last7: []),
      ]),
    );
    await app.pump(const BoardScreen());
    expect(find.text('Nobody has moved yet.'), findsOneWidget);
    expect(find.text('Waiting for your partner'), findsOneWidget);
  });

  testWidgets('loading shows a skeleton, failure shows Try again', (tester) async {
    final adapter = fullServer()..on('GET /api/board', const StubResponse.unreachable());
    final app = TestApp(tester, adapter);
    await app.pump(const BoardScreen());
    expect(find.text('Could not load the board'), findsOneWidget);

    adapter.on('GET /api/board', StubResponse(200, board([boardUser(2, 'Sam', 'violet')])));
    await app.tap(find.text('Try again'));
    expect(find.text('Sam'), findsOneWidget);
  });

  testWidgets('the 7 day strip follows the server counted flag, not a percent of its own', (
    tester,
  ) async {
    final user = boardUser(
      2,
      'Sam',
      'violet',
      last7: [
        {'date': '2026-10-24', 'percent': 95, 'counted': false, 'rest': false},
        {'date': '2026-10-25', 'percent': 96, 'counted': false, 'rest': false},
      ],
    );
    final app = TestApp(tester, _server([user]));
    await app.pump(const BoardScreen());

    final accent = accentById('violet').base;
    final filled = tester
        .widgetList<Container>(
          find.byWidgetPredicate((w) => w is Container && w.constraints?.maxWidth == 14),
        )
        .where((c) => (c.decoration! as BoxDecoration).color == accent);
    expect(filled, isEmpty);
  });
}
