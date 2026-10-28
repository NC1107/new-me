import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:newme/api/api_client.dart';
import 'package:newme/api/models.dart';
import 'package:newme/features/me/audiobookshelf_page.dart';
import 'package:newme/features/me/me_screen.dart';
import 'package:newme/features/today/today_screen.dart';
import 'package:newme/theme/accent.dart';
import 'package:newme/widgets/chunky_button.dart';
import 'package:newme/widgets/mascot.dart';
import 'package:newme/widgets/quest_card.dart';

import 'fixtures.dart';
import 'test_support.dart';

Map<String, dynamic> _link({
  bool linked = true,
  String? username = 'nick',
  String? syncedAt = '2026-10-26T13:55:00Z',
  String? lastError,
}) => {'linked': linked, 'username': username, 'syncedAt': syncedAt, 'lastError': lastError};

Map<String, dynamic> _meWith(Object? audiobookshelf, {bool present = true}) => {
  ...meJson(),
  if (present) 'audiobookshelf': audiobookshelf,
};

StubAdapter _server(Object? audiobookshelf, {bool present = true}) =>
    fullServer()..on('GET /api/me', StubResponse(200, _meWith(audiobookshelf, present: present)));

Finder _chunky(String label) =>
    find.byWidgetPredicate((w) => w is ChunkyButton && w.label == label);

Future<void> _fill(TestApp app, String user, String password) async {
  Finder field(bool obscure) => find.byWidgetPredicate(
    (w) => w is TextField && w.obscureText == obscure,
    skipOffstage: false,
  );
  for (final (obscure, text) in [(false, user), (true, password)]) {
    // At large text a field can sit below a lazily built list's cache extent.
    for (var i = 0; i < 30 && field(obscure).evaluate().isEmpty; i++) {
      await app.tester.drag(find.byType(Scrollable).first, const Offset(0, -150));
      await app.settle(2);
    }
    await app.tester.ensureVisible(field(obscure));
    await app.enter(field(obscure), text);
  }
}

void main() {
  setUp(() {
    FakeStorage().install();
    Mascot.idleMotion = false;
  });

  group('models', () {
    test('Me tolerates a server without the field and one with the feature off', () {
      expect(Me.fromJson(meJson()).audiobookshelf, isNull);
      expect(Me.fromJson({...meJson(), 'audiobookshelf': null}).audiobookshelf, isNull);
      expect(Me.fromJson(meJson()).toJson().containsKey('audiobookshelf'), isFalse);
    });

    test('Me reads the link state and survives the cache round trip', () {
      final me = Me.fromJson(_meWith(_link(lastError: 'auth_failed')));
      final link = me.audiobookshelf!;
      expect((link.linked, link.username, link.needsSignIn), (true, 'nick', true));
      expect(link.syncedAt, DateTime.utc(2026, 10, 26, 13, 55));
      expect(Me.fromJson(me.toJson()).audiobookshelf!.lastError, 'auth_failed');
    });

    test('an unlinked account has no username, no sync and needs no sign-in', () {
      final link = AudiobookshelfLink.fromJson(
        _link(linked: false, username: null, syncedAt: null),
      );
      expect(
        (link.linked, link.username, link.syncedAt, link.needsSignIn),
        (false, null, null, false),
      );
      expect(AudiobookshelfLink.fromJson(_link(lastError: 'unreachable')).needsSignIn, isFalse);
    });

    test('Today reads listening minutes, defaulting to zero when the server omits them', () {
      final plain = Today.fromJson(richTodayJson());
      expect(plain.listeningMinutes, 0);
      expect(plain.toJson().containsKey('listening'), isFalse);

      final heard = Today.fromJson({
        ...richTodayJson(),
        'listening': {'minutes': 22},
      });
      expect(heard.listeningMinutes, 22);
      expect(Today.fromJson(heard.toJson()).listeningMinutes, 22);
      expect(heard.copyWith(quests: heard.quests).listeningMinutes, 22);
    });
  });

  group('ApiClient', () {
    ApiClient client(StubAdapter adapter) =>
        ApiClient(baseUrl: 'https://x.invalid', token: 't', adapter: adapter);

    test('link sends the credentials and parses the link', () async {
      final adapter = StubAdapter()..on('PUT /api/me/audiobookshelf', StubResponse(200, _link()));
      final link = await client(adapter).linkAudiobookshelf(username: 'nick', password: 'pw');
      expect(adapter.requests.single.data, {'username': 'nick', 'password': 'pw'});
      expect((link.linked, link.username), (true, 'nick'));
    });

    test('unlink deletes', () async {
      final adapter = StubAdapter()..on('DELETE /api/me/audiobookshelf', const StubResponse(204));
      await client(adapter).unlinkAudiobookshelf();
      expect(adapter.requests.single.method, 'DELETE');
    });

    test('server codes survive, including on a 502', () async {
      final adapter = StubAdapter()
        ..on(
          'PUT /api/me/audiobookshelf',
          const StubResponse(422, {'error': 'no', 'code': 'abs_login_failed'}),
        );
      await expectLater(
        client(adapter).linkAudiobookshelf(username: 'a', password: 'b'),
        throwsA(isA<ApiException>().having((e) => e.code, 'code', 'abs_login_failed')),
      );
      adapter.on(
        'PUT /api/me/audiobookshelf',
        const StubResponse(502, {'error': 'down', 'code': 'abs_unavailable'}),
      );
      await expectLater(
        client(adapter).linkAudiobookshelf(username: 'a', password: 'b'),
        throwsA(isA<ApiException>().having((e) => e.code, 'code', 'abs_unavailable')),
      );
    });
  });

  group('the Me row', () {
    testWidgets('is hidden when the feature is off or the server predates it', (tester) async {
      final off = TestApp(tester, _server(null), surfaceHeight: 1600);
      await off.pump(const MeScreen());
      expect(find.text('Audiobookshelf'), findsNothing);

      final old = TestApp(tester, _server(null, present: false), surfaceHeight: 1600);
      await old.pump(const MeScreen(), key: UniqueKey());
      expect(find.text('Audiobookshelf'), findsNothing);
    });

    testWidgets('invites an unlinked person to count listening', (tester) async {
      final app = TestApp(
        tester,
        _server(_link(linked: false, username: null)),
        surfaceHeight: 1600,
      );
      await app.pump(const MeScreen());
      expect(find.text('Audiobookshelf'), findsOneWidget);
      expect(find.text('Not linked'), findsOneWidget);
    });

    testWidgets('names the account and the last sync once linked', (tester) async {
      final app = TestApp(tester, _server(_link()), surfaceHeight: 1600);
      await app.pump(const MeScreen());
      expect(find.text('nick, synced 5m ago'), findsOneWidget);
    });

    testWidgets('says when a new sign-in is needed', (tester) async {
      final app = TestApp(tester, _server(_link(lastError: 'auth_failed')), surfaceHeight: 1600);
      await app.pump(const MeScreen());
      expect(find.text('nick, sign in again'), findsOneWidget);
    });
  });

  group('the page', () {
    testWidgets('links with a username and password and then shows the account', (tester) async {
      final adapter = _server(_link(linked: false, username: null, syncedAt: null))
        ..on('PUT /api/me/audiobookshelf', StubResponse(200, _link()));
      final app = TestApp(tester, adapter);
      await app.pump(const AudiobookshelfPage());

      expect(find.text('Audiobookshelf'), findsOneWidget);
      expect(find.textContaining('does not keep your password'), findsOneWidget);
      expect(tester.widget<ChunkyButton>(_chunky('Link')).onPressed, isNull);

      await _fill(app, ' nick ', 'secret');
      expect(tester.widget<ChunkyButton>(_chunky('Link')).onPressed, isNotNull);
      adapter.on('GET /api/me', StubResponse(200, _meWith(_link())));
      await app.tap(_chunky('Link'));

      expect(adapter.requests.firstWhere((r) => r.method == 'PUT').data, {
        'username': 'nick',
        'password': 'secret',
      });
      expect(find.text('nick'), findsOneWidget);
      expect(find.text('Last sync 5m ago'), findsOneWidget);
      expect(_chunky('Unlink'), findsOneWidget);
      expect(find.byType(TextField), findsNothing);
    });

    testWidgets('keeps the form and explains a rejected password', (tester) async {
      final adapter = _server(_link(linked: false, username: null))
        ..on(
          'PUT /api/me/audiobookshelf',
          const StubResponse(422, {'error': 'x', 'code': 'abs_login_failed'}),
        );
      final app = TestApp(tester, adapter);
      await app.pump(const AudiobookshelfPage());
      await _fill(app, 'nick', 'wrong');
      await app.tap(_chunky('Link'));

      expect(
        find.text('Audiobookshelf did not accept that username and password.'),
        findsOneWidget,
      );
      expect(find.byType(TextField), findsNWidgets(2));

      await app.enter(find.byType(TextField).last, 'wrong2');
      expect(
        find.textContaining('did not accept'),
        findsNothing,
        reason: 'typing clears the error',
      );
    });

    testWidgets('explains an unreachable Audiobookshelf and an offline phone', (tester) async {
      final adapter = _server(_link(linked: false, username: null))
        ..on(
          'PUT /api/me/audiobookshelf',
          const StubResponse(502, {'error': 'x', 'code': 'abs_unavailable'}),
        );
      final app = TestApp(tester, adapter);
      await app.pump(const AudiobookshelfPage());
      await _fill(app, 'nick', 'pw');
      await app.tap(_chunky('Link'));
      expect(find.text('Could not reach Audiobookshelf. Try again in a moment.'), findsOneWidget);

      adapter.on('PUT /api/me/audiobookshelf', const StubResponse.unreachable());
      await app.tap(_chunky('Link'));
      expect(find.textContaining('offline'), findsOneWidget);
    });

    testWidgets('unlinks after a confirmation', (tester) async {
      final adapter = _server(_link())
        ..on('DELETE /api/me/audiobookshelf', const StubResponse(204));
      final app = TestApp(tester, adapter);
      await app.pump(const AudiobookshelfPage());
      expect(find.text('nick'), findsOneWidget);

      adapter.on('GET /api/me', StubResponse(200, _meWith(_link(linked: false, username: null))));
      await app.tap(_chunky('Unlink'));
      expect(adapter.to('DELETE /api/me/audiobookshelf'), isEmpty, reason: 'asks first');
      await app.tap(find.text('Cancel'));
      expect(adapter.to('DELETE /api/me/audiobookshelf'), isEmpty);

      await app.tap(_chunky('Unlink'));
      await app.tap(find.text('Unlink').last);
      expect(adapter.to('DELETE /api/me/audiobookshelf'), hasLength(1));
      expect(_chunky('Link'), findsOneWidget, reason: 'back to the form');
    });

    testWidgets('a rejected session asks for a new sign-in with the username filled in', (
      tester,
    ) async {
      final adapter = _server(_link(lastError: 'auth_failed'))
        ..on('PUT /api/me/audiobookshelf', StubResponse(200, _link()));
      final app = TestApp(tester, adapter);
      await app.pump(const AudiobookshelfPage());

      expect(find.text('Sign-in expired'), findsOneWidget);
      expect(find.textContaining('no longer accepts the saved sign-in'), findsOneWidget);
      expect(find.widgetWithText(TextField, 'nick'), findsOneWidget);
      expect(_chunky('Unlink'), findsOneWidget);
      expect(tester.widget<ChunkyButton>(_chunky('Sign in again')).onPressed, isNull);

      await app.enter(find.byType(TextField).last, 'new password');
      adapter.on('GET /api/me', StubResponse(200, _meWith(_link())));
      await app.tap(_chunky('Sign in again'));
      expect(adapter.requests.firstWhere((r) => r.method == 'PUT').data, {
        'username': 'nick',
        'password': 'new password',
      });
      expect(find.text('Last sync 5m ago'), findsOneWidget);
    });

    testWidgets('mentions an unreachable server without asking for a new sign-in', (tester) async {
      final app = TestApp(tester, _server(_link(lastError: 'unreachable')));
      await app.pump(const AudiobookshelfPage());
      expect(find.textContaining('could not reach Audiobookshelf'), findsOneWidget);
      expect(find.byType(TextField), findsNothing);
    });

    testWidgets('shows a first-time sync as not synced yet', (tester) async {
      final app = TestApp(tester, _server(_link(syncedAt: null)));
      await app.pump(const AudiobookshelfPage());
      expect(find.text('Not synced yet'), findsOneWidget);
    });

    for (final scale in [1.0, 2.0]) {
      for (final state in ['unlinked', 'linked', 'renew', 'unreachable']) {
        testWidgets('fits 390 wide at text scale $scale when $state', (tester) async {
          tester.platformDispatcher.textScaleFactorTestValue = scale;
          addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
          final link = switch (state) {
            'unlinked' => _link(linked: false, username: null, syncedAt: null),
            'renew' => _link(lastError: 'auth_failed', username: 'a-rather-long-username'),
            'unreachable' => _link(lastError: 'unreachable'),
            _ => _link(),
          };
          final adapter = _server(link)
            ..on(
              'PUT /api/me/audiobookshelf',
              const StubResponse(422, {'error': 'x', 'code': 'abs_login_failed'}),
            );
          final app = TestApp(tester, adapter);
          app.tallSurface();
          tester.view.physicalSize = const Size(390, 844);
          await app.pump(const AudiobookshelfPage(), tall: false);
          if (state == 'unlinked' || state == 'renew') {
            await _fill(app, 'nick', 'wrong');
            await app.tap(_chunky(state == 'renew' ? 'Sign in again' : 'Link'));
            expect(find.textContaining('did not accept'), findsOneWidget);
          }
          expect(tester.takeException(), isNull);
        });
      }
    }
  });

  group('the reading quest card', () {
    Widget host({required int minutes, double width = 390}) => MaterialApp(
      theme: themeFor(kAccentPresets.first),
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: width,
            child: QuestCard(
              quest: Quest.fromJson(
                quest('reading', 'Reading', {
                  'unit': 'minutes',
                  'target': 20,
                  'targetAlt': 15,
                  'unitAlt': 'pages',
                  'actual': 18,
                  'actualAlt': 0,
                }),
              ),
              onTap: () {},
              listeningMinutes: minutes,
            ),
          ),
        ),
      ),
    );

    testWidgets('says how many minutes were listened under the progress', (tester) async {
      await tester.pumpWidget(host(minutes: 18));
      expect(find.text('18 min listened'), findsOneWidget);
      final progress = tester.getTopLeft(find.textContaining('min').first).dy;
      expect(tester.getTopLeft(find.text('18 min listened')).dy, greaterThan(progress));
    });

    testWidgets('stays quiet without listening', (tester) async {
      await tester.pumpWidget(host(minutes: 0));
      expect(find.textContaining('listened'), findsNothing);
    });

    for (final scale in [1.0, 2.0]) {
      testWidgets('does not overflow at text scale $scale on a narrow card', (tester) async {
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        await tester.pumpWidget(host(minutes: 123, width: 320));
        expect(tester.takeException(), isNull);
        expect(find.text('123 min listened'), findsOneWidget);
      });
    }

    testWidgets('Today shows it only on the reading quest', (tester) async {
      final today = richTodayJson()..['listening'] = {'minutes': 18};
      final adapter = fullServer()..on('GET /api/today', StubResponse(200, today));
      final app = TestApp(tester, adapter, surfaceHeight: 2800);
      await app.pump(const TodayScreen());
      expect(find.text('18 min listened'), findsOneWidget);
    });
  });
}
