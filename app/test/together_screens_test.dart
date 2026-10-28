import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:newme/widgets/pressable.dart';
import 'package:newme/api/models.dart';
import 'package:newme/features/board/board_screen.dart';
import 'package:newme/features/me/me_screen.dart';
import 'package:newme/features/shell/home_tab.dart';
import 'package:newme/features/today/today_screen.dart';
import 'package:newme/features/together/celebration_sheet.dart';
import 'package:newme/features/together/challenge_card.dart';
import 'package:newme/features/together/cheer_chip.dart';
import 'package:newme/features/together/cheer_sheet.dart';
import 'package:newme/features/together/notifications_page.dart';
import 'package:newme/features/together/reward_card.dart';
import 'package:newme/features/together/reward_sheet.dart';
import 'package:newme/reminders/reminder_scheduler.dart';
import 'package:newme/widgets/confetti.dart';
import 'package:newme/widgets/mascot.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_reminder_scheduler.dart';
import 'fixtures.dart';
import 'test_support.dart';

Map<String, dynamic> _challenge({int progress = 21000, bool done = false}) => {
  'kind': 'steps',
  'title': 'Walk 70,000 steps together',
  'target': 70000,
  'progress': progress,
  'done': done,
  'endsOn': '2026-11-01',
};

Map<String, dynamic> _kindChallenge(String kind, String title, int target, int progress) => {
  ..._challenge(progress: progress),
  'kind': kind,
  'title': title,
  'target': target,
  'reason': 'Sleep was your lowest area against your own targets: 40% lately.',
};

Map<String, dynamic> _reward({
  int id = 3,
  int progress = 500,
  bool reached = false,
  bool claimed = false,
  String name = 'Date night',
  int price = 2000,
  String status = 'approved',
  bool focus = true,
  int proposedBy = 1,
}) => {
  'id': id,
  'name': name,
  'price': price,
  'target': price,
  'progress': claimed || reached ? price : progress,
  'status': claimed ? 'claimed' : status,
  'focus': focus,
  'ready': reached && !claimed,
  'startedAt': '2026-10-20T10:00:00Z',
  'reachedAt': reached ? '2026-10-25T10:00:00Z' : null,
  'claimedAt': claimed ? '2026-10-26T10:00:00Z' : null,
  'proposedBy': proposedBy,
  'proposedByName': proposedBy == 1 ? 'Ana' : 'Sam',
  'createdBy': proposedBy,
};

const _priceHelp = {
  'medianDaily': 100,
  'sampleDays': 14,
  'options': [
    {'days': 7, 'price': 700},
    {'days': 14, 'price': 1400},
    {'days': 30, 'price': 3000},
  ],
};

Map<String, dynamic> _cheer(String kind, {String from = 'Ana'}) => {
  'from': 1,
  'fromName': from,
  'kind': kind,
  'at': '2026-10-26T13:00:00Z',
};

StubAdapter _server({
  Map<String, dynamic>? challenge,
  Map<String, dynamic>? reward,
  List<Map<String, dynamic>> history = const [],
  List<Map<String, dynamic>> wishlist = const [],
  Map<String, dynamic>? priceHelp,
  int bank = 0,
  List<Map<String, dynamic>> cheers = const [],
}) => fullServer()
  ..on(
    'GET /api/board',
    StubResponse(200, {
      ...board([
        boardUser(2, 'Sam', 'violet'),
        boardUser(1, 'Ana', 'amber', points: 90, percent: 20),
      ]),
      'challenge': challenge,
      'reward': reward,
    }),
  )
  ..on('GET /api/today', StubResponse(200, {...richTodayJson(), 'cheers': cheers}))
  ..on(
    'GET /api/rewards',
    StubResponse(200, {
      'reward': reward,
      'rewards': [?reward, ...wishlist],
      'history': history,
      'bank': bank,
      'priceHelp': priceHelp,
    }),
  )
  ..on('POST /api/cheers', StubResponse(201, {'cheer': _cheer('fire', from: 'Sam'), 'to': 1}));

Future<void> _openUs(TestApp app, {bool onUsTab = false}) async {
  await app.pump(const BoardScreen());
  if (onUsTab) {
    app.container.read(homeTabProvider.notifier).select(HomeTab.board);
    await app.settle(30);
  }
}

void main() {
  setUp(() {
    FakeStorage().install();
    Mascot.idleMotion = false;
  });

  group('cheers', () {
    testWidgets('tapping the partner opens four reactions; sending marks one sent', (tester) async {
      final handle = tester.ensureSemantics();
      final app = TestApp(tester, _server());
      await _openUs(app);

      await app.tap(find.text('Cheer'));
      expect(find.text('Cheer Ana'), findsOneWidget);
      for (final label in ['Clap', 'Fire', 'Flex', 'Heart']) {
        expect(find.text(label), findsOneWidget);
      }
      expect(find.byIcon(Icons.local_fire_department_rounded), findsWidgets);

      await app.tap(find.text('Fire'));
      expect(app.body('POST /api/cheers'), {'to': 1, 'kind': 'fire'});
      expect(find.bySemanticsLabel('Fire sent to Ana'), findsOneWidget);
      expect(find.byIcon(Icons.check_circle_rounded), findsOneWidget);
      expect(find.text('Fire'), findsOneWidget, reason: 'the tile keeps its name');
      expect(
        tester
            .widget<Confetti>(
              find.descendant(of: find.byType(CheerSheet), matching: find.byType(Confetti)),
            )
            .burst,
        1,
      );

      await app.tap(find.text('Fire'));
      expect(app.adapter.to('POST /api/cheers'), hasLength(1), reason: 'a sent kind is inert');
      handle.dispose();
    });

    testWidgets('a kind sent earlier today still shows as sent when the sheet reopens', (
      tester,
    ) async {
      final app = TestApp(tester, _server());
      await _openUs(app);
      await app.tap(find.text('Cheer'));
      await app.tap(find.text('Heart'));
      await app.closeSheet();

      await app.tap(find.text('Cheer'));
      expect(find.byIcon(Icons.check_circle_rounded), findsOneWidget);
      expect(find.text('Clap'), findsOneWidget);
    });

    testWidgets('a failed send takes the mark back and says so', (tester) async {
      final server = _server()
        ..on('POST /api/cheers', const StubResponse(422, {'error': 'no such person'}));
      final app = TestApp(tester, server);
      await _openUs(app);
      await app.tap(find.text('Cheer'));
      await app.tap(find.text('Clap'));

      expect(find.text('no such person'), findsOneWidget);
      expect(find.byIcon(Icons.check_circle_rounded), findsNothing);
    });

    testWidgets('the person on the left is not cheerable', (tester) async {
      final app = TestApp(tester, _server());
      await _openUs(app);
      expect(find.text('Cheer'), findsOneWidget);
    });

    testWidgets('Today shows who cheered with their icons and remembers a dismissal', (
      tester,
    ) async {
      final server = _server(cheers: [_cheer('fire'), _cheer('heart')]);
      final app = TestApp(tester, server);
      await app.pump(const TodayScreen());

      expect(find.text('Ana cheered your day'), findsOneWidget);
      expect(
        find.descendant(of: find.byType(CheerChip), matching: find.byIcon(Icons.favorite_rounded)),
        findsOneWidget,
      );

      await app.tap(find.byIcon(Icons.close_rounded));
      expect(find.text('Ana cheered your day'), findsNothing);

      await app.pump(const TodayScreen(), key: UniqueKey());
      expect(find.text('Ana cheered your day'), findsNothing, reason: 'dismissed for the day');
    });

    testWidgets('a new kind arriving after a dismissal brings the chip back', (tester) async {
      var cheers = [_cheer('fire')];
      final server = _server();
      server.routes['GET /api/today'] = (_) =>
          StubResponse(200, {...richTodayJson(), 'cheers': cheers});
      final app = TestApp(tester, server);
      await app.pump(const TodayScreen());
      await app.tap(find.byIcon(Icons.close_rounded));

      cheers = [_cheer('fire'), _cheer('flex')];
      await app.pump(const TodayScreen(), key: UniqueKey());
      expect(find.text('Ana cheered your day'), findsOneWidget);
    });

    testWidgets('no cheers means no chip', (tester) async {
      final app = TestApp(tester, _server());
      await app.pump(const TodayScreen());
      expect(find.byType(CheerChip), findsNothing);
      expect(find.textContaining('cheered your day'), findsNothing);
    });
  });

  group('weekly challenge', () {
    testWidgets('Us shows title, numbers and days left', (tester) async {
      final app = TestApp(tester, _server(challenge: _challenge()));
      await _openUs(app);

      expect(find.text('Walk 70,000 steps together'), findsOneWidget);
      expect(find.text('21,000 of 70,000 steps'), findsOneWidget);
      expect(find.text('7 days left'), findsOneWidget);
    });

    testWidgets('no challenge means no card', (tester) async {
      final app = TestApp(tester, _server());
      await _openUs(app);
      expect(find.byType(ChallengeCard), findsNothing);
    });

    testWidgets('done shows the bonus and plays its celebration once', (tester) async {
      final app = TestApp(tester, _server(challenge: _challenge(progress: 72000, done: true)));
      await _openUs(app, onUsTab: true);

      expect(find.text('Challenge complete!'), findsOneWidget);
      expect(find.byType(CelebrationSheet), findsOneWidget);
      await app.tap(find.text('CONTINUE'));
      expect(find.text('Done! +50 points each'), findsOneWidget);

      await app.pump(const BoardScreen(), key: UniqueKey());
      app.container.read(homeTabProvider.notifier).select(HomeTab.board);
      await app.settle(30);
      expect(find.byType(CelebrationSheet), findsNothing, reason: 'played once');
    });

    testWidgets('the celebration waits for the Us tab', (tester) async {
      final app = TestApp(tester, _server(challenge: _challenge(done: true)));
      await _openUs(app);
      expect(find.byType(CelebrationSheet), findsNothing);
    });

    testWidgets('Today no longer carries the challenge; it lives on Us', (tester) async {
      final app = TestApp(tester, _server(challenge: _challenge()));
      await app.pump(const TodayScreen());

      expect(find.text('Walk 70,000 steps together'), findsNothing);
      expect(find.textContaining('21,000 of 70,000 steps'), findsNothing);
    });

    test('every kind has its own unit, icon and colour', () {
      const kinds = {
        'steps': 'steps',
        'workouts': 'workouts',
        'counted_days': 'days',
        'reading': 'min',
        'sleep_nights': 'nights',
        'meal_days': 'days',
        'protein_days': 'days',
        'pushup_reps': 'push-ups',
        'yoga_minutes': 'min',
        'habit_marks': 'marks',
        'active_days': 'days',
      };
      for (final MapEntry(key: kind, value: unit) in kinds.entries) {
        expect(challengeUnit(kind), unit, reason: kind);
        expect(challengeIcon(kind), isNot(Icons.flag_rounded), reason: kind);
      }
      expect(challengeUnit('something_new'), isEmpty);
      expect(challengeIcon('something_new'), Icons.flag_rounded);
    });

    testWidgets('a v13 kind shows its figures, unit and the reason it was picked', (tester) async {
      final app = TestApp(
        tester,
        _server(
          challenge: _kindChallenge(
            'sleep_nights',
            'Sleep your target on 10 nights together',
            10,
            4,
          ),
        ),
      );
      await _openUs(app);

      expect(find.text('Sleep your target on 10 nights together'), findsOneWidget);
      expect(find.text('4 of 10 nights'), findsOneWidget);
      expect(find.textContaining('lowest area'), findsOneWidget);
      expect(find.byIcon(Icons.bedtime_rounded), findsWidgets);
    });

    testWidgets('last week missed shows a quiet card with nothing lost', (tester) async {
      final server = _server(challenge: _challenge())
        ..on(
          'GET /api/board',
          StubResponse(200, {
            ...board([
              boardUser(2, 'Sam', 'violet'),
              boardUser(1, 'Ana', 'amber', points: 90, percent: 20),
            ]),
            'challenge': _challenge(),
            'lastChallenge': {
              ..._kindChallenge('pushup_reps', 'Do 250 push-ups together', 250, 180),
              'missed': true,
              'done': false,
            },
          }),
        );
      final app = TestApp(tester, server);
      await _openUs(app);

      expect(find.text('Last week'), findsOneWidget);
      expect(find.text('Do 250 push-ups together'), findsOneWidget);
      expect(find.textContaining('Missed, with nothing lost'), findsOneWidget);
      expect(find.textContaining('180 of 250 push-ups'), findsWidgets);
      expect(
        find.textContaining('days left'),
        findsOneWidget,
        reason: 'only this week counts down',
      );
    });

    test('missed and the reason survive a parse and a re-encode', () {
      final c = Challenge.tryParse({..._challenge(), 'missed': true, 'reason': 'Because.'})!;
      expect((c.missed, c.reason), (true, 'Because.'));
      expect(Challenge.tryParse(c.toJson())!.missed, isTrue);
      final plain = Challenge.tryParse(_challenge())!;
      expect((plain.missed, plain.reason), (false, ''));
      expect(plain.toJson().containsKey('missed'), isFalse);
      expect(plain.toJson().containsKey('reason'), isFalse);
    });

    test('days left counts today and names the last day', () {
      final c = Challenge.tryParse(_challenge())!;
      expect(challengeDaysLeft(c, '2026-10-26'), '7 days left');
      expect(challengeDaysLeft(c, '2026-11-01'), 'Last day');
      expect(challengeDaysLeft(c, '2026-11-02'), isNull);
    });
  });

  group('shared reward', () {
    testWidgets('the add sheet needs a name and a price, and proposes in gems', (tester) async {
      final server = _server(priceHelp: _priceHelp)
        ..on('POST /api/rewards', StubResponse(201, {'reward': _reward(status: 'pending')}));
      final app = TestApp(tester, server);
      await _openUs(app);

      await app.tap(find.text('ADD A REWARD'));
      for (final label in ['700 - 1 week', '1,400 - 2 weeks', '3,000 - about a month']) {
        expect(find.text(label), findsOneWidget);
      }
      expect(
        find.text('About 2 weeks at your pace.'),
        findsOneWidget,
        reason: 'two weeks is preset',
      );
      await app.tap(find.text('PROPOSE REWARD'));
      expect(app.adapter.to('POST /api/rewards'), isEmpty, reason: 'a name is required');

      await app.tap(find.text('Date night').last);
      await app.tap(find.text('3,000 - about a month'));
      await app.tap(find.text('PROPOSE REWARD'));

      expect(app.body('POST /api/rewards'), {'name': 'Date night', 'price': 3000});
      expect(find.byType(RewardSheet), findsNothing);
    });

    testWidgets('without history there are no suggested prices, only the field', (tester) async {
      final app = TestApp(tester, _server());
      await _openUs(app);
      await app.tap(find.text('ADD A REWARD'));
      expect(find.textContaining(' - 1 week'), findsNothing);
      expect(find.text('Gems, like 1,500'), findsOneWidget);
    });

    testWidgets('a typed price outside 1 to 100,000 is refused', (tester) async {
      final app = TestApp(tester, _server());
      await _openUs(app);
      await app.tap(find.text('ADD A REWARD'));
      await app.enter(find.byType(TextField).first, 'Pizza');
      await app.enter(find.byType(TextField).last, '100001');
      expect(find.text('Between 1 and 100,000'), findsOneWidget);
      await app.tap(find.text('PROPOSE REWARD'));
      expect(app.adapter.to('POST /api/rewards'), isEmpty);
    });

    testWidgets('a refused proposal says why and keeps the sheet', (tester) async {
      final server = _server()
        ..on(
          'POST /api/rewards',
          const StubResponse(409, {'code': 'wishlist_full', 'error': 'the wishlist is full'}),
        );
      final app = TestApp(tester, server);
      await _openUs(app);
      await app.tap(find.text('ADD A REWARD'));
      await app.tap(find.text('Dinner out'));
      await app.enter(find.byType(TextField).last, '500');
      await app.tap(find.text('PROPOSE REWARD'));

      expect(find.byType(RewardSheet), findsOneWidget);
      expect(find.text('the wishlist is full'), findsOneWidget);
    });

    testWidgets('my partner\'s proposal waits for my answer', (tester) async {
      final server = _server(
        reward: _reward(),
        wishlist: [
          _reward(id: 4, name: 'Weekend away', price: 3000, status: 'pending', focus: false),
        ],
      )..on('POST /api/rewards/4/decline', StubResponse(200, {'reward': _reward(id: 4)}));
      final app = TestApp(tester, server);
      await _openUs(app);

      expect(find.text('Ana wants Weekend away for 3,000 gems'), findsOneWidget);
      expect(find.text('Weekend away'), findsNothing, reason: 'it is not on the wishlist yet');
      await app.tap(find.text('DECLINE'));
      expect(app.adapter.to('POST /api/rewards/4/decline'), hasLength(1));
    });

    testWidgets('approving sends the answer and reloads', (tester) async {
      final server = _server(
        wishlist: [_reward(id: 4, name: 'Trip', status: 'pending', focus: false)],
      )..on('POST /api/rewards/4/approve', StubResponse(200, {'reward': _reward(id: 4)}));
      final app = TestApp(tester, server);
      await _openUs(app);
      await app.tap(find.text('APPROVE'));
      expect(app.adapter.to('POST /api/rewards/4/approve'), hasLength(1));
      expect(app.adapter.to('GET /api/rewards').length, greaterThan(1));
    });

    testWidgets('the wishlist lists queued rewards and my own proposals with their state', (
      tester,
    ) async {
      final app = TestApp(
        tester,
        _server(
          reward: _reward(),
          wishlist: [
            _reward(id: 5, name: 'Movie night', price: 600, focus: false),
            _reward(
              id: 6,
              name: 'Spa day',
              price: 4000,
              status: 'pending',
              focus: false,
              proposedBy: 2,
            ),
            _reward(
              id: 7,
              name: 'Skydive',
              price: 9000,
              status: 'declined',
              focus: false,
              proposedBy: 2,
            ),
          ],
        ),
      );
      await _openUs(app);

      expect(find.text('Movie night'), findsOneWidget);
      expect(find.text('600 gems'), findsOneWidget);
      expect(find.text('4,000 gems - waiting for Ana'), findsOneWidget);
      expect(find.text('9,000 gems - declined'), findsOneWidget);
    });

    testWidgets('opening my pending proposal edits it and can withdraw it', (tester) async {
      final server =
          _server(
              wishlist: [
                _reward(
                  id: 6,
                  name: 'Spa day',
                  price: 4000,
                  status: 'pending',
                  focus: false,
                  proposedBy: 2,
                ),
              ],
              reward: _reward(),
            )
            ..on('PATCH /api/rewards/6', StubResponse(200, {'reward': _reward(id: 6)}))
            ..on('DELETE /api/rewards/6', const StubResponse(204, <String, dynamic>{}));
      final app = TestApp(tester, server);
      await _openUs(app);

      await app.tap(find.text('Spa day'));
      expect(find.text('Edit reward'), findsOneWidget);
      await app.enter(find.byType(TextField).last, '3500');
      await app.tap(find.text('SAVE'));
      expect(app.body('PATCH /api/rewards/6'), {'price': 3500});

      await app.tap(find.text('Spa day'));
      await app.tap(find.text('WITHDRAW'));
      expect(app.adapter.to('DELETE /api/rewards/6'), hasLength(1));
    });

    testWidgets('a queued reward can become the focus or be cancelled', (tester) async {
      final server =
          _server(
              reward: _reward(),
              wishlist: [_reward(id: 5, name: 'Movie night', price: 600, focus: false)],
            )
            ..on('POST /api/rewards/5/focus', StubResponse(200, {'reward': _reward(id: 5)}))
            ..on('POST /api/rewards/5/cancel', StubResponse(200, {'reward': _reward(id: 5)}));
      final app = TestApp(tester, server);
      await _openUs(app);

      await app.tap(find.text('Movie night'));
      await app.tap(find.text('MAKE IT THE FOCUS'));
      expect(app.adapter.to('POST /api/rewards/5/focus'), hasLength(1));

      await app.tap(find.text('Movie night'));
      await app.tap(find.text('CANCEL REWARD'));
      expect(app.adapter.to('POST /api/rewards/5/cancel'), hasLength(1));
    });

    testWidgets('a new price on an approved reward is proposed again', (tester) async {
      final server =
          _server(
            reward: _reward(),
            wishlist: [_reward(id: 5, name: 'Movie night', price: 600, focus: false)],
          )..on(
            'PATCH /api/rewards/5',
            StubResponse(200, {'reward': _reward(id: 5, status: 'pending')}),
          );
      final app = TestApp(tester, server);
      await _openUs(app);

      await app.tap(find.text('Movie night'));
      expect(find.text('Both of you can rename it.'), findsOneWidget);
      await app.enter(find.byType(TextField).last, '900');
      expect(find.text('A new price goes to Ana to approve again.'), findsOneWidget);
      await app.tap(find.text('PROPOSE NEW PRICE'));
      expect(app.body('PATCH /api/rewards/5'), {'price': 900});
    });

    testWidgets('a queued reward the bank covers can be claimed from its sheet', (tester) async {
      final server =
          _server(
            reward: _reward(),
            wishlist: [
              _reward(id: 5, name: 'Movie night', price: 600, focus: false, reached: true),
            ],
          )..on(
            'POST /api/rewards/5/claim',
            StubResponse(200, {'reward': _reward(id: 5, claimed: true)}),
          );
      final app = TestApp(tester, server);
      await _openUs(app);

      expect(find.text('600 gems - ready'), findsOneWidget);
      await app.tap(find.text('Movie night'));
      await app.tap(find.text('WE DID IT'));
      expect(app.adapter.to('POST /api/rewards/5/claim'), hasLength(1));
    });

    testWidgets('an active reward shows its bar and what is left', (tester) async {
      final app = TestApp(tester, _server(reward: _reward()));
      await _openUs(app);

      expect(find.text('Date night'), findsOneWidget);
      expect(find.text('500 of 2,000 gems'), findsOneWidget);
      expect(find.text('1,500 to go'), findsOneWidget);
      expect(find.text('ADD A REWARD'), findsNothing);
    });

    testWidgets('a reached reward celebrates once and We did it claims it', (tester) async {
      final server = _server(reward: _reward(reached: true))
        ..on(
          'POST /api/rewards/3/claim',
          StubResponse(200, {'reward': _reward(reached: true, claimed: true)}),
        );
      final app = TestApp(tester, server);
      await _openUs(app, onUsTab: true);

      expect(find.text('Reward ready!'), findsOneWidget);
      await app.tap(find.text('WE DID IT').last);
      expect(app.adapter.to('POST /api/rewards/3/claim'), hasLength(1));
      expect(find.byType(CelebrationSheet), findsNothing);
    });

    testWidgets('the card keeps the claim button when the celebration is skipped', (tester) async {
      final server = _server(reward: _reward(reached: true))
        ..on(
          'POST /api/rewards/3/claim',
          StubResponse(200, {'reward': _reward(reached: true, claimed: true)}),
        );
      final app = TestApp(tester, server);
      await _openUs(app);

      expect(find.text('Reward ready'), findsOneWidget);
      await app.tap(find.text('WE DID IT'));
      expect(app.adapter.to('POST /api/rewards/3/claim'), hasLength(1));
    });

    testWidgets('a failed claim says so and keeps the button', (tester) async {
      final server = _server(reward: _reward(reached: true))
        ..on(
          'POST /api/rewards/3/claim',
          const StubResponse(409, {
            'code': 'reward_not_reached',
            'error': 'the gem bank does not cover that reward yet',
          }),
        );
      final app = TestApp(tester, server);
      await _openUs(app);
      await app.tap(find.text('WE DID IT'));

      expect(find.text('the gem bank does not cover that reward yet'), findsOneWidget);
      expect(find.text('WE DID IT'), findsOneWidget);
    });

    testWidgets('history lists rewards earned, newest first, without the one on the card', (
      tester,
    ) async {
      final server = _server(
        reward: _reward(id: 9),
        history: [
          {..._reward(id: 2, reached: true, claimed: true), 'name': 'Pizza night'},
          {..._reward(id: 1, reached: true), 'name': 'Movie night'},
        ],
      );
      final app = TestApp(tester, server);
      await _openUs(app);

      expect(find.text('Rewards earned'), findsOneWidget);
      expect(find.byType(RewardHistory), findsOneWidget);
      expect(find.text('Pizza night'), findsOneWidget);
      expect(find.textContaining('enjoyed Oct 26'), findsOneWidget);
      expect(find.textContaining('reached Oct 25'), findsOneWidget);
    });

    testWidgets('no history means no heading', (tester) async {
      final app = TestApp(tester, _server());
      await _openUs(app);
      expect(find.text('Rewards earned'), findsNothing);
    });
  });

  group('notifications page', () {
    Future<(TestApp, FakeReminderScheduler)> open(
      WidgetTester tester, {
      bool allowed = true,
      Map<String, dynamic>? prefs,
    }) async {
      SharedPreferences.setMockInitialValues({});
      final scheduler = FakeReminderScheduler(allowed: allowed);
      final server = fullServer()
        ..on('GET /api/me', StubResponse(200, {...meJson(), 'notifications': ?prefs}))
        ..on(
          'PATCH /api/me',
          StubResponse(200, {
            ...meJson(),
            'notifications': {
              'partnerDone': true,
              'cheers': false,
              'challenge': true,
              'reward': true,
            },
          }),
        );
      final app = TestApp(tester, server);
      await app.pump(
        const MeScreen(),
        overrides: [reminderSchedulerProvider.overrideWithValue(scheduler)],
      );
      return (app, scheduler);
    }

    testWidgets('Me links to it with a count of what is on', (tester) async {
      final (app, _) = await open(
        tester,
        prefs: {'partnerDone': false, 'cheers': true, 'challenge': true, 'reward': false},
      );
      final handle = tester.ensureSemantics();
      expect(find.bySemanticsLabel('Notifications, 10 of 14 on'), findsOneWidget);
      await app.tap(find.text('Notifications'));
      expect(find.byType(NotificationsPage), findsOneWidget);
      handle.dispose();
    });

    testWidgets('a switch sends a partial PATCH and follows the server', (tester) async {
      final (app, _) = await open(tester);
      await app.tap(find.text('Notifications'));

      expect(
        tester.widgetList<Switch>(find.byType(Switch)).skip(1).take(4).every((s) => s.value),
        isTrue,
      );
      await app.tap(find.text('Cheers'));

      expect(app.body('PATCH /api/me'), {
        'notifications': {'cheers': false},
      });
      final cheers = find.descendant(
        of: find.ancestor(of: find.text('Cheers'), matching: find.byType(Pressable)).first,
        matching: find.byType(Switch),
      );
      expect(tester.widget<Switch>(cheers).value, isFalse);
    });

    testWidgets('a failed save puts the switch back and says so', (tester) async {
      final (app, _) = await open(tester);
      app.adapter.on('PATCH /api/me', const StubResponse(422, {'error': 'nope'}));
      await app.tap(find.text('Notifications'));
      await app.tap(find.text('Cheers'));

      expect(find.text('nope'), findsOneWidget);
      expect(
        tester.widgetList<Switch>(find.byType(Switch)).skip(1).take(4).every((s) => s.value),
        isTrue,
      );
    });

    testWidgets('the v13 switches send their own PATCH keys', (tester) async {
      final (app, _) = await open(tester);
      await app.tap(find.text('Notifications'));

      for (final (title, key) in [
        ('Nudges about your partner', 'partnerNudges'),
        ('Cover', 'cover'),
        ('Approvals', 'approvals'),
      ]) {
        await tester.scrollUntilVisible(
          find.text(title),
          100,
          scrollable: find.byType(Scrollable).first,
        );
        await app.tap(find.text(title));
        expect(app.body('PATCH /api/me'), {
          'notifications': {key: false},
        }, reason: title);
      }
    });

    testWidgets('the quiet hours are read off the schedule', (tester) async {
      final (app, _) = await open(tester);
      await app.tap(find.text('Notifications'));
      expect(find.textContaining('Quiet from 23:00 to 07:10, and on away days.'), findsOneWidget);
    });

    test('quiet hours words follow workdays, days off and a bedtime after midnight', () {
      const late = DayTimes(wake: 10 * 60, bed: 60);
      expect(
        quietHoursText(const Schedule(workday: late, dayOff: late, firstNotificationOffsetMin: 30)),
        'Quiet from 00:00 to 10:30, and on away days.',
      );
      expect(
        quietHoursText(
          const Schedule(
            workday: DayTimes(wake: 6 * 60, bed: 22 * 60),
            dayOff: DayTimes(wake: 9 * 60, bed: 23 * 60),
          ),
        ),
        'Quiet from 22:00 to 06:10 on workdays and 23:00 to 09:10 on days off, and on away days.',
      );
    });

    testWidgets('it holds the evening reminder instead of linking to a page', (tester) async {
      final (app, _) = await open(tester);
      await app.tap(find.text('Notifications'));
      expect(find.text('Reminders'), findsOneWidget);
      expect(find.text('Evening reminder'), findsOneWidget);
    });

    testWidgets('without permission it offers to ask, then hides the card', (tester) async {
      final (app, scheduler) = await open(tester, allowed: false);
      await app.tap(find.text('Notifications'));

      expect(find.text('ALLOW NOTIFICATIONS'), findsOneWidget);
      await app.tap(find.text('ALLOW NOTIFICATIONS'));
      expect(scheduler.permissionRequests, 1);
      expect(find.text('ALLOW NOTIFICATIONS'), findsNothing);
    });

    testWidgets('with permission there is no permission card', (tester) async {
      final (app, _) = await open(tester);
      await app.tap(find.text('Notifications'));
      expect(find.text('ALLOW NOTIFICATIONS'), findsNothing);
    });
  });

  group('layout at text scale 2.0 and touch targets', () {
    void configure(WidgetTester tester, double scale) {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = scale;
      addTearDown(tester.view.reset);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    }

    for (final scale in [1.0, 2.0]) {
      testWidgets('Us, cheer sheet, add sheet and celebration fit at $scale', (tester) async {
        configure(tester, scale);
        final app = TestApp(
          tester,
          _server(challenge: _challenge(), reward: _reward(reached: true)),
        );
        await app.pump(const BoardScreen(), tall: false);
        expect(tester.takeException(), isNull);
        await tester.drag(find.byType(Scrollable).first, const Offset(0, -3000));
        await app.settle();
        expect(tester.takeException(), isNull);

        await tester.drag(find.byType(Scrollable).first, const Offset(0, 3000));
        await app.settle();
        // The shared streak card pushes the partner's card down at large text.
        await tester.drag(find.byType(Scrollable).first, const Offset(0, -400));
        await app.settle();
        await app.tap(find.text('Cheer'));
        expect(tester.takeException(), isNull);
        await app.tap(find.text('Heart'));
        expect(tester.takeException(), isNull);
        await app.closeSheet();

        showCelebrationSheet(
          tester.element(find.byType(Scaffold).first),
          title: 'Reward ready!',
          message: 'A very long reward name that wraps over several lines',
          users: const [],
          buttonLabel: 'We did it',
        );
        await app.settle();
        expect(tester.takeException(), isNull);
        await app.closeSheet();
      });

      testWidgets('the add sheet fits at $scale', (tester) async {
        configure(tester, scale);
        final app = TestApp(tester, _server());
        await app.pump(const BoardScreen());
        tester.view.physicalSize = const Size(390, 4000);
        await app.settle();
        await app.tap(find.text('ADD A REWARD'));
        expect(tester.takeException(), isNull);
        await app.enter(find.byType(TextField).first, 'Pizza');
        expect(tester.takeException(), isNull);
      });

      testWidgets('Today with a cheer, and the notifications page fit at $scale', (tester) async {
        configure(tester, scale);
        final server = _server(challenge: _challenge(), cheers: [_cheer('fire'), _cheer('flex')]);
        final app = TestApp(tester, server);
        await app.pump(const TodayScreen(), tall: false);
        expect(tester.takeException(), isNull);
        await tester.drag(find.byType(Scrollable).first, const Offset(0, -3000));
        await app.settle();
        expect(tester.takeException(), isNull);

        final page = TestApp(tester, _server());
        await page.pump(const NotificationsPage(), tall: false, key: UniqueKey());
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('reactions, the chip dismiss, switches and sheet buttons are at least 44 tall', (
      tester,
    ) async {
      configure(tester, 1.0);
      final app = TestApp(tester, _server(cheers: [_cheer('fire')]));
      await app.pump(const TodayScreen(), tall: false);
      expect(
        tester
            .getSize(
              find
                  .ancestor(of: find.byIcon(Icons.close_rounded), matching: find.byType(SizedBox))
                  .first,
            )
            .shortestSide,
        greaterThanOrEqualTo(44),
      );

      final us = TestApp(tester, _server());
      await us.pump(const BoardScreen(), tall: false, key: UniqueKey());
      await us.tap(find.text('Cheer'));
      for (final label in ['Clap', 'Fire', 'Flex', 'Heart']) {
        final box = find.ancestor(of: find.text(label), matching: find.byType(Column)).first;
        final size = tester.getSize(box);
        expect(size.height, greaterThanOrEqualTo(44), reason: label);
        expect(size.width, greaterThanOrEqualTo(44), reason: label);
      }
      await us.closeSheet();

      await us.tap(find.text('ADD A REWARD'));
      for (final label in ['Date night']) {
        final h = tester
            .getSize(find.ancestor(of: find.text(label), matching: find.byType(Container)).first)
            .height;
        expect(h, greaterThanOrEqualTo(44), reason: label);
      }
    });
  });
}
