import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:newme/health/fake_health_source.dart';
import 'package:newme/health/health_source_factory.dart';
import 'package:newme/main.dart';
import 'package:newme/state/session.dart';
import 'package:newme/state/timezone.dart';

import 'test_support.dart';

const _info = {'name': 'Us', 'initialized': true, 'joinOpen': true, 'minClientVersion': '0.1.0'};

const _nick = {'id': 1, 'name': 'Nick', 'color': 'green'};

class _App {
  _App(this.tester, this.adapter);

  final WidgetTester tester;
  final StubAdapter adapter;
  final health = FakeHealthSource();
  final storage = FakeStorage();

  Future<void> launch({SessionController Function()? session}) async {
    storage.install();
    await tester.pumpWidget(
      ProviderScope(
        retry: (_, _) => null,
        overrides: [
          apiClientFactoryProvider.overrideWithValue(stubFactory(adapter)),
          deviceTimezoneProvider.overrideWithValue(() async => 'America/New_York'),
          healthSourceProvider.overrideWithValue(health),
          if (session != null) sessionProvider.overrideWith(session),
        ],
        child: const NewMeApp(),
      ),
    );
    await settle();
  }

  Future<void> settle() async {
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> enter(int fieldIndex, String text) async {
    await tester.enterText(find.byType(TextField).at(fieldIndex), text);
    await tester.pump();
  }

  Future<void> tap(Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.tap(finder);
    await settle();
  }

  Future<void> tapText(String text) => tap(find.text(text));

  Future<void> tapButton(String label) => tap(find.widgetWithText(FilledButton, label));

  Map<String, dynamic> lastBody(String route) =>
      (adapter.to(route).last.data as Map).cast<String, dynamic>();

  Future<void> expectSignedIn() async {
    expect(find.text('Today'), findsWidgets);
    expect(find.byIcon(Icons.add), findsOneWidget);
  }
}

StubAdapter _server({Map<String, dynamic> info = _info}) => StubAdapter()
  ..on('GET /api/server-info', StubResponse(200, info))
  ..on(
    'POST /api/join',
    const StubResponse(201, {
      'user': {'id': 2, 'name': 'Ana', 'color': 'sky'},
      'token': 'new-token',
    }),
  )
  ..on(
    'POST /api/invites/check',
    const StubResponse(200, {
      'users': [_nick],
    }),
  );

void main() {
  testWidgets('first join asks for a name and a color, then offers Health and lands in the app', (
    tester,
  ) async {
    final adapter = _server(info: {..._info, 'initialized': false});
    final app = _App(tester, adapter);
    await app.launch();

    expect(find.text('What should we call you?'), findsOneWidget);
    expect(find.text('Change server'), findsOneWidget, reason: 'the field stays out of the way');
    expect(find.byType(TextField), findsOneWidget);
    expect(adapter.to('GET /api/server-info').single.uri.host, 'new-me.npc-server.top');
    expect(find.widgetWithText(FilledButton, 'Create profile'), findsOneWidget);
    expect(
      tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Create profile')).onPressed,
      isNull,
    );

    await app.enter(0, 'Ana');
    await app.tapText('Sky');
    await app.tapButton('Create profile');

    expect(app.lastBody('POST /api/join'), {
      'name': 'Ana',
      'color': 'sky',
      'timezone': 'America/New_York',
    });
    expect(app.storage.values[kSessionKey], contains('new-token'));
    expect(
      find.text('Connect Health'),
      findsWidgets,
      reason: 'the session exists but onboarding stays',
    );

    await app.tapText('Skip for now');
    await app.expectSignedIn();
    expect(app.health.accessRequests, 0);
  });

  testWidgets('a pairing code leads to "I\'m new", with taken colors disabled', (tester) async {
    final adapter = _server();
    final app = _App(tester, adapter);
    await app.launch();

    expect(find.text('Enter your code'), findsOneWidget);
    expect(find.text('You were signed out. Enter a code to come back.'), findsNothing);
    await app.enter(0, ' K7QM-2XPA ');
    await app.tapButton('Continue');
    expect(app.lastBody('POST /api/invites/check'), {'code': 'K7QM-2XPA'});

    expect(find.text('Who are you?'), findsOneWidget);
    await app.tapButton("I'm new");

    await app.enter(0, 'Ana');
    await app.tapText('Onyx Green');
    expect(find.bySemanticsLabel('Onyx Green, taken'), findsOneWidget);
    await app.tapText('Violet');
    await app.tapButton('Join');

    expect(app.lastBody('POST /api/join'), {
      'code': 'K7QM-2XPA',
      'name': 'Ana',
      'color': 'violet',
      'timezone': 'America/New_York',
    });
    await app.tapButton('Connect Health');
    expect(app.health.accessRequests, 1);
    await app.expectSignedIn();
  });

  testWidgets('a returning person taps their chip to re-pair', (tester) async {
    final adapter = _server();
    final app = _App(tester, adapter);
    await app.launch();

    await app.enter(0, 'CODE');
    await app.tapButton('Continue');
    await app.tapText('Nick');

    expect(app.lastBody('POST /api/join'), {
      'code': 'CODE',
      'userId': 1,
      'timezone': 'America/New_York',
    });
    await app.tapText('Skip for now');
    await app.expectSignedIn();
  });

  testWidgets('a code the server rejects explains itself and stays editable', (tester) async {
    final adapter = _server()
      ..on('POST /api/invites/check', const StubResponse(401, {'error': 'invalid code'}));
    final app = _App(tester, adapter);
    await app.launch();

    await app.enter(0, 'NOPE');
    await app.tapButton('Continue');

    expect(find.text('That code did not work. Ask for a fresh one.'), findsOneWidget);
    expect(find.text('Enter your code'), findsOneWidget);
  });

  testWidgets('an unreachable server shows the field and recovers after changing the address', (
    tester,
  ) async {
    final adapter = _server()
      ..routes['GET /api/server-info'] = (request) => request.uri.host == 'new-me.npc-server.top'
          ? const StubResponse.unreachable()
          : const StubResponse(200, _info);
    final app = _App(tester, adapter);
    await app.launch();

    expect(
      find.text('Cannot reach the server. Check your connection or the address.'),
      findsOneWidget,
    );
    expect(find.widgetWithText(FilledButton, 'Connect'), findsOneWidget);

    await app.enter(0, 'http://192.168.1.5:8080/');
    await app.tapButton('Connect');

    expect(
      adapter.to('GET /api/server-info').last.uri.toString(),
      'http://192.168.1.5:8080/api/server-info',
    );
    expect(find.text('Enter your code'), findsOneWidget);
  });

  testWidgets('a host that is not New Me gets the wrong-address copy', (tester) async {
    final adapter = _server()
      ..on('GET /api/server-info', const StubResponse(404, {'error': 'nope'}));
    final app = _App(tester, adapter);
    await app.launch();
    expect(find.text('That address does not look like a New Me server.'), findsOneWidget);
  });

  testWidgets('a server that wants a newer client says so', (tester) async {
    final adapter = _server(info: {..._info, 'minClientVersion': '9.0.0'});
    final app = _App(tester, adapter);
    await app.launch();
    expect(
      find.text('This version of New Me is too old for the server. Update it from TestFlight.'),
      findsOneWidget,
    );

    adapter.on('GET /api/server-info', const StubResponse(426, {'error': 'old'}));
    await app.tapButton('Connect');
    expect(find.textContaining('too old for the server'), findsOneWidget);
  });

  testWidgets('after a forced sign-out the code screen says what happened', (tester) async {
    final adapter = _server();
    final app = _App(tester, adapter);
    await app.launch(session: () => SessionController.seeded(testSession));
    await app.expectSignedIn();
    adapter.on('GET /api/me', const StubResponse(401, {'error': 'revoked'}));

    final container = ProviderScope.containerOf(tester.element(find.byType(MaterialApp)));
    unawaited(container.read(apiClientProvider)!.me().then((_) {}, onError: (_) {}));
    await app.settle();

    expect(find.text('You were signed out. Enter a code to come back.'), findsOneWidget);
    expect(adapter.to('GET /api/server-info').last.uri.host, 'me.invalid');
  });

  testWidgets('a 426 anywhere in the app blocks it with the update screen', (tester) async {
    final adapter = _server()..on('GET /api/me', const StubResponse(426, {'error': 'old'}));
    final app = _App(tester, adapter);
    await app.launch(session: () => SessionController.seeded(testSession));

    final container = ProviderScope.containerOf(tester.element(find.byType(MaterialApp)));
    unawaited(container.read(apiClientProvider)!.me().then((_) {}, onError: (_) {}));
    await app.settle();

    expect(find.text('Update required'), findsOneWidget);
    expect(find.text('Today'), findsNothing);
  });
}
