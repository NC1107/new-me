import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:newme/api/models.dart';
import 'package:newme/features/recap/recap_screen.dart';
import 'package:newme/features/shell/home_shell.dart';
import 'package:newme/features/today/today_screen.dart';
import 'package:newme/features/together/notifications_page.dart';
import 'package:newme/state/listening_sync.dart';
import 'package:newme/widgets/mascot.dart';

import 'fixtures.dart';
import 'test_support.dart';

Map<String, dynamic> _linkedMe() => {
  ...meJson(),
  'audiobookshelf': {'linked': true, 'username': 'sam', 'syncedAt': null, 'lastError': null},
};

const _syncBody = {
  'linked': true,
  'username': 'sam',
  'syncedAt': '2026-10-26T14:00:00Z',
  'lastError': null,
  'minutesToday': 5,
};

void main() {
  setUp(() {
    FakeStorage().install();
    Mascot.idleMotion = false;
  });

  group('models are tolerant', () {
    test('unknown readiness levels and plan kinds drop out instead of failing', () {
      expect(Readiness.tryParse({'level': 'great'}), isNull);
      expect(Readiness.tryParse(null), isNull);
      final plan = Plan.tryParse({
        'items': [
          {'kind': 'done', 'key': 'a', 'text': 'A'},
          {'kind': 'mystery', 'key': 'b', 'text': 'B'},
          {'kind': 'todo', 'key': 'c', 'text': ''},
          'junk',
        ],
        'summary': 's',
      })!;
      expect(plan.items.map((i) => i.key), ['a']);
    });

    test('a today without v6 fields has none of them', () {
      final today = Today.fromJson(richTodayJson());
      expect((today.readiness, today.plan, today.listeningSyncedAt), (null, null, null));
      expect(today.quests.every((q) => q.doneBy == null), isTrue);
    });

    test('notification defaults follow the server and an unknown confidence is low', () {
      final p = NotificationPrefs.fromJson(null);
      expect(
        (p.behindPace, p.windDown, p.closeToDone, p.morningPlan, p.weeklyRecap),
        (false, false, true, true, true),
      );
      expect(EstimateConfidence.parse('certain'), EstimateConfidence.low);
      expect(const NotificationPatch(windDown: true).toJson(), {'windDown': true});
    });

    test('a bare recap parses to zeros', () {
      final r = Recap.fromJson({'week': '2026-W44'});
      expect(r.people, isEmpty);
      expect((r.pair.thisWeek.points, r.challenge), (0, null));
    });
  });

  group('listening sync', () {
    Future<(TestApp, StubAdapter)> open(
      WidgetTester tester, {
      bool linked = true,
      required DateTime Function() clock,
    }) async {
      final server = fullServer()
        ..on('GET /api/me', StubResponse(200, linked ? _linkedMe() : meJson()))
        ..on('POST /api/me/audiobookshelf/sync', const StubResponse(200, _syncBody));
      final app = TestApp(tester, server);
      await app.pump(const TodayScreen());
      return (app, server);
    }

    testWidgets('syncs when linked, then reloads Today, and not within a minute', (tester) async {
      final (app, server) = await open(tester, clock: () => testNow);
      final syncer = app.container.read(listeningSyncProvider);
      final reads = server.to('GET /api/today').length;

      final f1 = syncer.syncThenRefreshToday();
      await app.settle();
      await f1;
      expect(server.to('POST /api/me/audiobookshelf/sync'), hasLength(1));
      expect(server.to('GET /api/today').length, reads + 1);

      final f2 = syncer.syncThenRefreshToday();
      await app.settle();
      await f2;
      expect(server.to('POST /api/me/audiobookshelf/sync'), hasLength(1), reason: 'throttled');
      expect(
        server.to('GET /api/today').length,
        reads + 2,
        reason: 'a pull to refresh still reloads',
      );
    });

    testWidgets('does nothing for someone who has not linked', (tester) async {
      final (app, server) = await open(tester, linked: false, clock: () => testNow);
      final f = app.container.read(listeningSyncProvider).sync();
      await app.settle();
      expect(await f, isFalse);
      expect(server.to('POST /api/me/audiobookshelf/sync'), isEmpty);
    });

    testWidgets('a failed sync is swallowed and Today still reloads', (tester) async {
      final (app, server) = await open(tester, clock: () => testNow);
      server.on(
        'POST /api/me/audiobookshelf/sync',
        const StubResponse(404, {'code': 'abs_not_linked', 'error': 'x'}),
      );
      final reads = server.to('GET /api/today').length;
      final f = app.container.read(listeningSyncProvider).syncThenRefreshToday();
      await app.settle();
      await f;
      expect(server.to('GET /api/today').length, reads + 1);
    });

    testWidgets('app open syncs once for a linked person', (tester) async {
      final server = fullServer()
        ..on('GET /api/me', StubResponse(200, _linkedMe()))
        ..on('POST /api/me/audiobookshelf/sync', const StubResponse(200, _syncBody));
      await TestApp(tester, server).pump(const HomeShell());
      expect(server.to('POST /api/me/audiobookshelf/sync'), hasLength(1));
    });

    testWidgets('after a minute the next attempt goes through', (tester) async {
      var now = testNow;
      final server = fullServer()
        ..on('GET /api/me', StubResponse(200, _linkedMe()))
        ..on('POST /api/me/audiobookshelf/sync', const StubResponse(200, _syncBody));
      final app = TestApp(tester, server);
      await app.pump(const TodayScreen(), clock: () => now);
      final syncer = app.container.read(listeningSyncProvider);
      final a = syncer.sync();
      await app.settle();
      await a;
      now = now.add(const Duration(seconds: 61));
      final b = syncer.sync();
      await app.settle();
      await b;
      expect(server.to('POST /api/me/audiobookshelf/sync'), hasLength(2));
    });
  });

  group('the recap screen', () {
    testWidgets('leads with the couple, then each person, then the challenge and suggestions', (
      tester,
    ) async {
      final server = fullServer()
        ..on(
          'GET /api/recap',
          const StubResponse(200, {
            'week': '2026-W43',
            'from': '2026-10-19',
            'to': '2026-10-25',
            'complete': true,
            'people': [
              {
                'userId': 2,
                'name': 'Sam',
                'color': 'violet',
                'this': {'points': 900, 'steps': 60000},
                'previous': {'points': 800, 'steps': 70000},
                'bestDay': {'date': '2026-10-22', 'points': 210},
                'suggestion': 'Walk after dinner.',
              },
              {
                'userId': 1,
                'name': 'Ana',
                'color': 'amber',
                'this': {'points': 700},
                'previous': {'points': 750},
                'suggestion': 'Beat 700 points.',
              },
            ],
            'pair': {
              'this': {'points': 1600},
              'previous': {'points': 1550},
              'bestDay': {'date': '2026-10-22', 'points': 330},
            },
            'challenge': {
              'kind': 'steps',
              'title': 'Walk 100,000 steps together',
              'target': 100000,
              'progress': 100000,
              'completed': true,
            },
          }),
        );
      final app = TestApp(tester, server, surfaceHeight: 4000);
      await app.pump(const RecapScreen());

      expect(find.text('Oct 19 - Oct 25'), findsOneWidget);
      final order = [
        find.text('Together'),
        find.text('Best day together'),
        find.text('Challenge done'),
        find.text('For next week'),
        find.text('Each of you'),
      ];
      final tops = [for (final f in order) tester.getTopLeft(f).dy];
      expect([...tops]..sort(), tops);
      expect(find.text('Walk after dinner.'), findsOneWidget);
      expect(find.text('For Ana'), findsOneWidget);
      expect(find.textContaining('+50 points each'), findsOneWidget);
      expect(
        find.textContaining('+100', findRichText: true),
        findsWidgets,
        reason: 'Sam points up 100',
      );
      expect(
        find.textContaining('-10,000', findRichText: true),
        findsOneWidget,
        reason: 'Sam steps down, with its own sign',
      );
      expect(
        find.textContaining(RegExp('win|lose|behind|rank', caseSensitive: false)),
        findsNothing,
      );
    });

    testWidgets('a running week shows last week instead of a misleading change', (tester) async {
      final server = fullServer()
        ..on(
          'GET /api/recap',
          const StubResponse(200, {
            'week': '2026-W44',
            'from': '2026-10-26',
            'to': '2026-11-01',
            'complete': false,
            'people': <Object>[],
            'pair': {
              'this': {'points': 200},
              'previous': {'points': 1000},
            },
            'challenge': {
              'kind': 'steps',
              'title': 'Walk',
              'target': 100,
              'progress': 20,
              'completed': false,
            },
          }),
        );
      final app = TestApp(tester, server, surfaceHeight: 2000);
      await app.pump(const RecapScreen());
      expect(find.text('This week is still running.'), findsOneWidget);
      expect(find.textContaining('last week 1,000'), findsOneWidget);
      expect(find.text('Challenge so far'), findsOneWidget);
    });

    testWidgets('a failure offers to try again', (tester) async {
      final server = fullServer()
        ..on('GET /api/recap', const StubResponse(422, {'error': 'no week'}));
      final app = TestApp(tester, server);
      await app.pump(const RecapScreen());
      expect(find.text('no week'), findsOneWidget);
      expect(find.text('TRY AGAIN'), findsOneWidget);
    });

    testWidgets('fits at text scale 2.0', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 2.0;
      addTearDown(tester.view.reset);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final server = fullServer()
        ..on(
          'GET /api/recap',
          const StubResponse(200, {
            'week': '2026-W43',
            'from': '2026-10-19',
            'to': '2026-10-25',
            'complete': true,
            'people': [
              {
                'userId': 2,
                'name': 'Sam',
                'color': 'violet',
                'this': {'points': 900, 'sleepAvgMin': 440, 'sleepNights': 6},
                'previous': {'points': 800, 'sleepAvgMin': 420, 'sleepNights': 6},
                'suggestion': 'Walk after dinner.',
              },
            ],
            'pair': {
              'this': {'points': 900},
              'previous': {'points': 800},
            },
          }),
        );
      final app = TestApp(tester, server);
      await app.pump(const RecapScreen(), tall: false);
      expect(tester.takeException(), isNull);
      await tester.drag(find.byType(Scrollable).first, const Offset(0, -3000));
      await app.settle();
      expect(tester.takeException(), isNull);
    });
  });

  group('notification switches', () {
    testWidgets('five new switches with the server defaults, each sending a partial PATCH', (
      tester,
    ) async {
      final server = fullServer()
        ..on(
          'PATCH /api/me',
          StubResponse(200, {
            ...meJson(),
            'notifications': {'behindPace': true},
          }),
        );
      final app = TestApp(tester, server, surfaceHeight: 2000);
      await app.pump(const NotificationsPage());

      final labels = ['Steps to go', 'Close to done', 'Wind down', 'Morning plan', 'Weekly recap'];
      for (final l in labels) {
        expect(find.text(l), findsOneWidget);
      }
      final values = tester.widgetList<Switch>(find.byType(Switch)).map((s) => s.value).toList();
      expect(values.skip(8), [false, true, false, true, true, true]);

      await app.tap(find.text('Steps to go'));
      expect(app.body('PATCH /api/me'), {
        'notifications': {'behindPace': true},
      });
      expect(
        find.text('At most two of these a day. Quiet from 23:00 to 07:10, and on away days.'),
        findsOneWidget,
      );
    });
  });

  group('the Us tab badge', () {
    testWidgets('lights for an unseen cheer and clears when it is dismissed', (tester) async {
      final today = richTodayJson(stepsEverSynced: true)
        ..['cheers'] = [
          {'from': 1, 'fromName': 'Ana', 'kind': 'fire', 'at': '2026-10-26T13:00:00Z'},
        ];
      final server = fullServer()..on('GET /api/today', StubResponse(200, today));
      final app = TestApp(tester, server);
      await app.pump(const HomeShell());
      expect(find.byKey(const Key('nav-badge')), findsOneWidget);

      await app.tap(find.byIcon(Icons.close_rounded));
      expect(find.byKey(const Key('nav-badge')), findsNothing);
    });

    testWidgets('a quiet day has no badge', (tester) async {
      await TestApp(tester, fullServer()).pump(const HomeShell());
      expect(find.byKey(const Key('nav-badge')), findsNothing);
    });
  });

  test('the notifications row counts every switch', () {
    expect(kNotificationSwitches, 14);
    expect(notificationsOn(const NotificationPrefs()), 12);
  });
}
