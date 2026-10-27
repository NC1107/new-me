import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:newme/features/board/board_screen.dart';
import 'package:newme/features/board/person_card.dart';
import 'package:newme/features/me/pairing_page.dart';
import 'package:newme/theme/accent.dart';
import 'package:newme/widgets/avatar.dart';
import 'package:newme/widgets/mascot.dart';

import 'fixtures.dart';
import 'test_support.dart';

StubAdapter _server(List<Map<String, dynamic>> users, {bool admin = false}) => fullServer()
  ..on('GET /api/board', StubResponse(200, board(users)))
  ..on('GET /api/me', StubResponse(200, meJson(admin: admin)));

Map<String, dynamic> _withHighlights(
  Map<String, dynamic> user, {
  num? steps,
  num? exercise,
  num? sleep,
}) => {
  ...user,
  'highlights': {'steps': ?steps, 'exercise_minutes': ?exercise, 'sleep_minutes': ?sleep},
};

void main() {
  setUp(() {
    FakeStorage().install();
    Mascot.idleMotion = false;
  });

  testWidgets('with one person the second card waits, with a how-to for a non admin', (
    tester,
  ) async {
    final app = TestApp(tester, _server([boardUser(2, 'Sam', 'violet')]));
    await app.pump(const BoardScreen());

    expect(find.text('Sam'), findsWidgets);
    expect(find.text('Waiting for your partner'), findsOneWidget);
    expect(find.byType(Mascot), findsOneWidget);
    expect(find.textContaining('pairing code from whoever set up New Me'), findsOneWidget);
    expect(find.text('CREATE PAIRING CODE'), findsNothing);
  });

  testWidgets('the admin can go straight to the pairing page from the empty state', (tester) async {
    final app = TestApp(tester, _server([boardUser(2, 'Sam', 'violet')], admin: true));
    await app.pump(const BoardScreen());

    await app.tap(find.text('CREATE PAIRING CODE'));
    expect(find.byType(PairingPage), findsOneWidget);
  });

  testWidgets('a zero streak reads as no streak yet instead of a 0-day streak', (tester) async {
    final app = TestApp(tester, _server([boardUser(2, 'Sam', 'violet', streak: 0)]));
    await app.pump(const BoardScreen());

    expect(find.text('No streak yet'), findsOneWidget);
    expect(find.text('0-day streak'), findsNothing);
  });

  testWidgets('two people show two cards, each in their own colour, with no winner wording', (
    tester,
  ) async {
    final app = TestApp(
      tester,
      _server([
        boardUser(2, 'Sam', 'violet', points: 120, percent: 30),
        boardUser(1, 'Ana', 'amber', points: 2400, percent: 88, week: 1200, season: 8000),
      ]),
    );
    await app.pump(const BoardScreen());

    expect(find.text('Waiting for your partner'), findsNothing);
    expect(find.byType(PersonCard), findsNWidgets(2));
    expect(find.text('120'), findsOneWidget);
    expect(find.text('2,400'), findsOneWidget);
    expect(find.text('30%'), findsOneWidget);
    expect(find.text('88%'), findsOneWidget);
    expect(find.text('1,200'), findsOneWidget);
    expect(find.text('8,000'), findsOneWidget);
    expect(find.text('4-day streak'), findsNWidgets(2));
    expect(find.text('synced 3h ago'), findsNWidgets(2));
    expect(find.text('Season 0 - ends Dec 31'), findsOneWidget);
    expect(find.text('Together: 1,500 points this week'), findsOneWidget);
    expect(find.textContaining('Nobody has moved yet'), findsNothing);
    expect(find.textContaining(RegExp('win|lead|behind|rank', caseSensitive: false)), findsNothing);

    final avatars = tester.widgetList<Avatar>(find.byType(Avatar)).map((a) => a.palette.id);
    expect(avatars, containsAll(['violet', 'amber']));
    expect(accentById('violet').fill, isNot(accentById('amber').fill));
  });

  testWidgets('this week groups one bar per person per day under a summary label', (tester) async {
    final handle = tester.ensureSemantics();
    final app = TestApp(
      tester,
      _server([boardUser(2, 'Sam', 'violet'), boardUser(1, 'Ana', 'amber')]),
    );
    await app.pump(const BoardScreen());

    expect(find.text('This week'), findsOneWidget);
    expect(
      find.bySemanticsLabel('Last 7 days. Sam counted 4 of 7 days. Ana counted 4 of 7 days'),
      findsOneWidget,
    );
    handle.dispose();
  });

  testWidgets('a rest day shows a moon under its letter', (tester) async {
    final app = TestApp(tester, _server([boardUser(2, 'Sam', 'violet')]));
    await app.pump(const BoardScreen());
    expect(find.byIcon(Icons.bedtime_rounded), findsNWidgets(1 + 1));
  });

  testWidgets(
    "today's highlights show steps, exercise and sleep for both, with a dash when missing",
    (tester) async {
      final app = TestApp(
        tester,
        _server([
          _withHighlights(boardUser(2, 'Sam', 'violet'), steps: 4321, exercise: 23, sleep: 432),
          _withHighlights(boardUser(1, 'Ana', 'amber'), steps: 10234),
        ]),
      );
      await app.pump(const BoardScreen());

      expect(find.text("Today's highlights"), findsOneWidget);
      expect(find.text('4,321 steps'), findsOneWidget);
      expect(find.text('10,234 steps'), findsOneWidget);
      expect(find.text('23 min'), findsOneWidget);
      expect(find.text('7 h 12 min'), findsOneWidget);
      expect(find.text('-'), findsNWidgets(2));
    },
  );

  testWidgets('highlights from an older server are all dashes, not an error', (tester) async {
    final app = TestApp(tester, _server([boardUser(2, 'Sam', 'violet')]));
    await app.pump(const BoardScreen());
    expect(find.text('-'), findsNWidgets(3));
  });

  testWidgets('a user with no sync yet says so', (tester) async {
    final user = boardUser(2, 'Sam', 'violet')..['syncedAt'] = null;
    final app = TestApp(tester, _server([user]));
    await app.pump(const BoardScreen());
    expect(find.text('Health not synced'), findsOneWidget);
  });

  testWidgets('day one reads as a fresh start, not broken', (tester) async {
    final app = TestApp(
      tester,
      _server([
        boardUser(2, 'Sam', 'violet', points: 0, percent: 0, week: 0, season: 0, last7: []),
      ]),
    );
    await app.pump(const BoardScreen());
    expect(find.textContaining('Nobody has moved yet'), findsOneWidget);
    expect(find.text('Bars appear after your first day.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('loading shows a skeleton, failure shows Try again', (tester) async {
    final adapter = fullServer()..on('GET /api/board', const StubResponse.unreachable());
    final app = TestApp(tester, adapter);
    await app.pump(const BoardScreen());
    expect(find.text('Could not load Us'), findsOneWidget);

    adapter.on('GET /api/board', StubResponse(200, board([boardUser(2, 'Sam', 'violet')])));
    await app.tap(find.text('Try again'));
    expect(find.text('Sam'), findsWidgets);
  });

  testWidgets('with reduced motion the ring shows its value at once', (tester) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue = const FakeAccessibilityFeatures(
      disableAnimations: true,
    );
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    final app = TestApp(tester, _server([boardUser(2, 'Sam', 'violet', percent: 64)]));
    await app.pump(const BoardScreen());
    await tester.pump();
    expect(find.text('64%'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
