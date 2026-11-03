import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:newme/api/models.dart';
import 'package:newme/features/board/board_screen.dart';
import 'package:newme/features/together/reward_sheet.dart';
import 'package:newme/state/board.dart';
import 'package:newme/widgets/mascot.dart';

import 'fixtures.dart';
import 'test_support.dart';

// The signed-in user in these tests is Sam (id 2); Ana (id 1) is the partner.
Map<String, dynamic> _treat({
  int id = 10,
  String name = 'Monster energy drink',
  int price = 1000,
  int owner = 2,
  String status = 'approved',
  int proposedBy = 2,
  int progress = 0,
}) => {
  'id': id,
  'name': name,
  'price': price,
  'target': price,
  'progress': progress,
  'status': status,
  'focus': false,
  'ready': status == 'approved' && progress >= price,
  'startedAt': '2026-10-20T10:00:00Z',
  'reachedAt': null,
  'claimedAt': null,
  'proposedBy': proposedBy,
  'proposedByName': proposedBy == 1 ? 'Ana' : 'Sam',
  'createdBy': proposedBy,
  'ownerId': owner,
  'ownerName': owner == 1 ? 'Ana' : 'Sam',
};

Map<String, dynamic> _balance(int id, String name, int balance) => {
  'userId': id,
  'name': name,
  'earned': balance + 200,
  'paid': 200,
  'balance': balance,
};

StubAdapter _server({
  List<Map<String, dynamic>> treats = const [],
  List<Map<String, dynamic>> history = const [],
  int mine = 400,
  int theirs = 1500,
}) => fullServer()
  ..on(
    'GET /api/board',
    StubResponse(200, {
      ...board([
        boardUser(2, 'Sam', 'violet'),
        boardUser(1, 'Ana', 'amber', points: 90, percent: 20),
      ]),
      'challenge': null,
      'reward': null,
    }),
  )
  ..on(
    'GET /api/rewards',
    StubResponse(200, {
      'reward': null,
      'rewards': <Object>[],
      'history': <Object>[],
      'bank': mine + theirs,
      'priceHelp': null,
      'treats': treats,
      'treatHistory': history,
      'balances': [_balance(1, 'Ana', theirs), _balance(2, 'Sam', mine)],
    }),
  );

// The rewards sit below the weekly challenge and the shared rewards, so the surface is tall.
TestApp _app(WidgetTester tester, StubAdapter server) =>
    TestApp(tester, server, surfaceHeight: 3200);

Future<void> _openUs(TestApp app) async {
  await app.pump(const BoardScreen());
}

void main() {
  setUp(() {
    FakeStorage().install();
    Mascot.idleMotion = false;
  });

  group('treats on Us', () {
    testWidgets('one Rewards section shows both balances, mine first, and the bank', (
      tester,
    ) async {
      final app = _app(tester, _server(treats: [_treat(progress: 400)]));
      await _openUs(app);

      expect(find.text('Rewards'), findsOneWidget);
      expect(find.text('Treats'), findsNothing);
      expect(find.text('Your gems'), findsOneWidget);
      expect(find.text("Ana's gems"), findsOneWidget);
      expect(find.text('Shared bank'), findsOneWidget);
      expect(find.text('400'), findsOneWidget);
      expect(find.text('1,500'), findsOneWidget);
      expect(find.text('1,900'), findsOneWidget);
      expect(
        tester.getTopLeft(find.text('Your gems')).dx,
        lessThan(tester.getTopLeft(find.text("Ana's gems")).dx),
      );
    });

    testWidgets('gems earned elsewhere reach the balances once the board reloads', (tester) async {
      final server = _server();
      final app = _app(tester, server);
      await _openUs(app);
      expect(find.text('400'), findsOneWidget);

      // Ticking a habit or logging a meal reloads only the board, which now shows 25 more points.
      server
        ..on(
          'GET /api/board',
          StubResponse(200, {
            ...board([
              boardUser(2, 'Sam', 'violet', points: 125, season: 925),
              boardUser(1, 'Ana', 'amber', points: 90, percent: 20),
            ]),
            'challenge': null,
            'reward': null,
          }),
        )
        ..on(
          'GET /api/rewards',
          StubResponse(200, {
            'reward': null,
            'rewards': <Object>[],
            'history': <Object>[],
            'bank': 1925,
            'priceHelp': null,
            'treats': <Object>[],
            'treatHistory': <Object>[],
            'balances': [_balance(1, 'Ana', 1500), _balance(2, 'Sam', 425)],
          }),
        );
      unawaited(app.container.read(boardProvider.notifier).refresh());
      await app.settle();

      expect(find.text('425'), findsOneWidget);
      expect(find.text('400'), findsNothing);
    });

    testWidgets('a solo reward says what is left and hides Redeem until it is covered', (
      tester,
    ) async {
      final app = _app(
        tester,
        _server(
          treats: [
            _treat(id: 11, name: 'Big Gulp', price: 1500),
            _treat(progress: 400),
          ],
        ),
      );
      await _openUs(app);

      expect(find.text('Solo · 1,000 gems · 600 to go'), findsOneWidget);
      expect(find.text('Solo · 1,500 gems · 1,100 to go'), findsOneWidget);
      expect(find.text('REDEEM'), findsNothing);
      final names = tester.getTopLeft(find.text('Monster energy drink')).dy;
      expect(
        names,
        lessThan(tester.getTopLeft(find.text('Big Gulp')).dy),
        reason: 'cheapest first',
      );
    });

    testWidgets('redeeming confirms, sends one request id and reloads', (tester) async {
      final server = _server(treats: [_treat(progress: 1000)], mine: 1200)
        ..on(
          'POST /api/rewards/10/redeem',
          const StubResponse(201, {
            'redemption': {
              'id': 1,
              'treatId': 10,
              'userId': 2,
              'userName': 'Sam',
              'name': 'Monster energy drink',
              'price': 1000,
              'redeemedAt': '2026-10-26T14:00:00Z',
            },
          }),
        );
      final app = _app(tester, server);
      await _openUs(app);

      await app.tap(find.text('REDEEM'));
      expect(find.text('Redeem Monster energy drink?'), findsOneWidget);
      expect(app.adapter.to('POST /api/rewards/10/redeem'), isEmpty, reason: 'asks first');
      await app.tap(find.text('Redeem'));

      final body = app.body('POST /api/rewards/10/redeem');
      expect((body['requestId'] as String).length, greaterThanOrEqualTo(8));
      expect(app.adapter.to('GET /api/rewards').length, greaterThan(1));
    });

    testWidgets('cancelling the confirmation redeems nothing', (tester) async {
      final app = _app(tester, _server(treats: [_treat(progress: 1000)], mine: 1200));
      await _openUs(app);

      await app.tap(find.text('REDEEM'));
      await app.tap(find.text('Cancel'));
      expect(app.adapter.to('POST /api/rewards/10/redeem'), isEmpty);
    });

    testWidgets('a refused redemption says why', (tester) async {
      final server = _server(treats: [_treat(progress: 1000)], mine: 1200)
        ..on(
          'POST /api/rewards/10/redeem',
          const StubResponse(409, {
            'error': 'your own gems do not cover that treat yet',
            'code': 'insufficient_gems',
          }),
        );
      final app = _app(tester, server);
      await _openUs(app);

      await app.tap(find.text('REDEEM'));
      await app.tap(find.text('Redeem'));
      expect(find.textContaining('own gems do not cover'), findsOneWidget);
    });

    testWidgets("my partner's solo rewards are listed without a way to redeem them", (
      tester,
    ) async {
      final app = _app(
        tester,
        _server(treats: [_treat(id: 12, name: 'Latte', price: 300, owner: 1, proposedBy: 1)]),
      );
      await _openUs(app);

      expect(find.text('Latte'), findsOneWidget);
      expect(find.text("Ana's · 300 gems"), findsOneWidget);
      expect(find.text('REDEEM'), findsNothing);
    });

    testWidgets("my partner's solo reward waits for my answer", (tester) async {
      final server =
          _server(
            treats: [
              _treat(id: 12, name: 'Latte', price: 300, owner: 1, proposedBy: 1, status: 'pending'),
            ],
          )..on(
            'POST /api/rewards/12/approve',
            StubResponse(200, {'reward': _treat(id: 12, owner: 1)}),
          );
      final app = _app(tester, server);
      await _openUs(app);

      expect(find.text('Ana wants a solo reward: Latte for 300 gems'), findsOneWidget);
      await app.tap(find.text('APPROVE'));
      expect(app.adapter.to('POST /api/rewards/12/approve'), hasLength(1));
    });

    testWidgets('my pending solo reward shows who it waits on', (tester) async {
      final app = _app(tester, _server(treats: [_treat(status: 'pending')]));
      await _openUs(app);

      expect(find.text('Solo, 1,000 gems, Ana to approve'), findsOneWidget);
      expect(find.text('REDEEM'), findsNothing);
    });

    testWidgets('Solo in the one add sheet proposes a solo reward, with no suggested prices', (
      tester,
    ) async {
      final server = _server()
        ..on('POST /api/rewards', StubResponse(201, {'reward': _treat(status: 'pending')}));
      final app = _app(tester, server);
      await _openUs(app);

      await app.tap(find.text('ADD A REWARD'));
      expect(find.byType(RewardSheet), findsOneWidget);
      expect(find.text('Date night'), findsWidgets, reason: 'starts on Shared');
      await app.tap(find.bySemanticsLabel('Solo, just for you'));
      expect(find.textContaining('at your pace'), findsNothing);
      await app.tap(find.text('Big Gulp'));
      await tester.enterText(find.byType(TextField).last, '1000');
      await app.settle();
      await app.tap(find.text('PROPOSE REWARD'));

      expect(app.body('POST /api/rewards'), {'name': 'Big Gulp', 'price': 1000, 'treat': true});
    });

    testWidgets('rewards earned lists what either of you redeemed', (tester) async {
      final app = _app(
        tester,
        _server(
          history: [
            {
              'id': 2,
              'treatId': 10,
              'userId': 1,
              'userName': 'Ana',
              'name': 'Latte',
              'price': 300,
              'redeemedAt': '2026-10-25T14:00:00Z',
            },
          ],
        ),
      );
      await _openUs(app);

      expect(find.text('Rewards earned'), findsOneWidget);
      expect(find.textContaining('Ana · 300 gems'), findsOneWidget);
    });
  });

  group('treat models', () {
    test('a list parses treats, history and balances and keeps shared rewards apart', () {
      final list = RewardList.fromJson({
        'rewards': <Object>[],
        'bank': 1900,
        'treats': [_treat(id: 11, price: 1500), _treat(), _treat(id: 12, owner: 1, proposedBy: 1)],
        'balances': [_balance(1, 'Ana', 1500), _balance(2, 'Sam', 400)],
      });
      expect(list.balanceOf(2)!.balance, 400);
      expect([for (final t in list.myTreats(2)) t.price], [1000, 1500], reason: 'cheapest first');
      expect(list.partnerTreats(2).single.ownerName, 'Ana');
      expect(list.treats.every((t) => t.isTreat), isTrue);
    });

    test('an old server without treats parses to empty lists', () {
      final list = RewardList.fromJson({'rewards': <Object>[], 'bank': 5});
      expect(list.treats, isEmpty);
      expect(list.treatHistory, isEmpty);
      expect(list.balances, isEmpty);
    });
  });
}
