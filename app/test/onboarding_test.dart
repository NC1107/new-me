import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:newme/health/fake_health_source.dart';
import 'package:newme/health/health_source_factory.dart';
import 'package:newme/main.dart';
import 'package:newme/state/session.dart';
import 'package:newme/state/timezone.dart';
import 'package:newme/theme/accent.dart';
import 'package:newme/widgets/chunky_button.dart';
import 'package:newme/widgets/mascot.dart';

import 'fixtures.dart';
import 'test_support.dart';

const _info = {'name': 'Us', 'initialized': true, 'joinOpen': true, 'minClientVersion': '0.1.0'};

const _nick = {'id': 1, 'name': 'Nick', 'color': 'green'};

const _code = 'ABCD-EFGH-JKLM-NPQR';

class _App {
  _App(this.tester, this.adapter);

  final WidgetTester tester;
  final StubAdapter adapter;
  final health = FakeHealthSource();
  final storage = FakeStorage();

  Future<void> launch({SessionController Function()? session}) async {
    storage.install();
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
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

  Future<void> tap(Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.tap(finder);
    await settle();
  }

  Future<void> tapText(String text) => tap(find.text(text));

  /// Button labels are shown in capitals.
  Future<void> tapButton(String label) => tap(find.text(label.toUpperCase()));

  Future<void> enter(String text) async {
    await tester.enterText(find.byType(TextField).first, text);
    await tester.pump();
  }

  bool enabled(String label) {
    final button = tester.widget<ChunkyButton>(
      find.byWidgetPredicate((w) => w is ChunkyButton && w.label == label),
    );
    return button.onPressed != null;
  }

  Map<String, dynamic> lastBody(String route) =>
      (adapter.to(route).last.data as Map).cast<String, dynamic>();

  Future<void> expectSignedIn() async {
    expect(find.text('Today'), findsWidgets);
  }
}

StubAdapter _server({Map<String, dynamic> info = _info}) => StubAdapter()
  ..on('GET /api/server-info', StubResponse(200, info))
  ..on(
    'POST /api/join',
    const StubResponse(201, {
      'user': {
        'id': 2,
        'name': 'Ana',
        'color': 'sky',
        'timezone': 'America/New_York',
        'isAdmin': false,
      },
      'token': 'new-token',
    }),
  )
  ..on('PATCH /api/me', StubResponse(200, meJson()))
  ..on(
    'POST /api/invites/check',
    const StubResponse(200, {
      'valid': true,
      'users': [_nick],
      'canJoinNew': true,
    }),
  );

void main() {
  testWidgets(
    'first join walks name, colour, focus and goals, saves one PATCH and lands in the app',
    (tester) async {
      final adapter = _server(info: {..._info, 'initialized': false});
      final app = _App(tester, adapter);
      await app.launch();

      expect(adapter.to('GET /api/server-info').single.uri.host, 'new-me.npc-server.top');
      expect(find.byType(TextField), findsNothing, reason: 'no server address in the normal flow');
      expect(find.text('GET STARTED'), findsOneWidget);
      expect(find.text('I HAVE AN INVITE CODE'), findsNothing, reason: 'nobody to invite from yet');
      await app.tapButton('Get started');

      expect(find.text('What should we call you?'), findsOneWidget);
      expect(app.enabled('Continue'), isFalse);
      await app.enter('Ana');
      await app.tapButton('Continue');

      expect(find.text('Pick your colour'), findsOneWidget);
      await app.tapText('Sky');
      await app.tapButton('Continue');
      expect(app.lastBody('POST /api/join'), {
        'name': 'Ana',
        'color': 'sky',
        'timezone': 'America/New_York',
      });
      expect(app.storage.values[kSessionKey], contains('new-token'));

      expect(find.text('What do you want to work on?'), findsOneWidget);
      expect(app.enabled('Continue'), isFalse, reason: 'one focus is required');
      await app.tapText('Move more');
      await app.tapText('Sleep better');
      await app.tapButton('Continue');

      expect(find.text('How many steps a day?'), findsOneWidget);
      await app.tapText('Serious');
      await app.tapButton('Continue');
      expect(find.text('How much sleep are you aiming for?'), findsOneWidget);
      expect(adapter.to('PATCH /api/me'), isEmpty, reason: 'saved once, after the last goal');
      await app.tapButton('Continue');

      final patch = app.lastBody('PATCH /api/me');
      final templates = {for (final t in patch['questTemplates'] as List) (t as Map)['key']: t};
      expect(templates['steps'], {'key': 'steps', 'enabled': true, 'target': 10000});
      expect(templates['sleep'], {'key': 'sleep', 'enabled': true, 'target': 420});
      expect(templates['exercise'], {'key': 'exercise', 'enabled': false});
      expect(templates['pushups'], {'key': 'pushups', 'enabled': false});
      expect(patch.containsKey('targets'), isFalse);

      expect(find.text('NOT NOW'), findsOneWidget);
      await app.tapButton('Not now');
      expect(app.health.accessRequests, 0);
      expect(find.text("You're in, Ana!"), findsOneWidget);
      expect(find.text('Day 1 starts now.'), findsOneWidget);
      await app.tapButton("Let's go");
      await app.expectSignedIn();
    },
  );

  testWidgets('eating well asks for meals, protein and an optional calorie target', (tester) async {
    final adapter = _server(info: {..._info, 'initialized': false});
    final app = _App(tester, adapter);
    await app.launch();
    await app.tapButton('Get started');
    await app.enter('Ana');
    await app.tapButton('Continue');
    await app.tapButton('Continue');
    await app.tapText('Eat well');
    await app.tapButton('Continue');

    expect(find.text('How many meals will you log?'), findsOneWidget);
    await app.tapText('Regular');
    await app.tapButton('Continue');
    expect(find.text('How much protein a day?'), findsOneWidget);
    await app.tapText('Intense');
    await app.tapButton('Continue');

    expect(find.text('Want a daily calorie target?'), findsOneWidget);
    expect(app.enabled('Continue'), isFalse);
    await app.tapText('Balanced');
    await app.tapButton('Continue');

    final patch = app.lastBody('PATCH /api/me');
    expect(patch['targets'], {'kcal': 2000});
    final templates = {for (final t in patch['questTemplates'] as List) (t as Map)['key']: t};
    expect(templates['meals_logged'], {'key': 'meals_logged', 'enabled': true, 'target': 3});
    expect(templates['protein'], {'key': 'protein', 'enabled': true, 'target': 160});
  });

  testWidgets('skipping the calorie target saves no target', (tester) async {
    final adapter = _server(info: {..._info, 'initialized': false});
    final app = _App(tester, adapter);
    await app.launch();
    await app.tapButton('Get started');
    await app.enter('Ana');
    await app.tapButton('Continue');
    await app.tapButton('Continue');
    await app.tapText('Eat well');
    await app.tapButton('Continue');
    await app.tapButton('Continue');
    await app.tapButton('Continue');
    await app.tapButton('Skip');

    expect(app.lastBody('PATCH /api/me').containsKey('targets'), isFalse);
    expect(find.text('NOT NOW'), findsOneWidget);
  });

  testWidgets('a code leads to "I am new", with taken colours disabled, then connects Health', (
    tester,
  ) async {
    final adapter = _server();
    final app = _App(tester, adapter);
    await app.launch();

    expect(find.text('JOIN WITH A CODE'), findsOneWidget);
    await app.tapButton('Join with a code');
    expect(find.text('Enter your invite code'), findsOneWidget);
    expect(find.text('You were signed out. Enter a code to come back.'), findsNothing);
    expect(app.enabled('Continue'), isFalse);
    await app.enter(' abcd efgh jklm npqr ');
    expect(find.text('ABCD'), findsOneWidget, reason: 'typed codes fill the boxes');
    expect(find.text('NPQR'), findsOneWidget);
    await app.tapButton('Continue');
    expect(app.lastBody('POST /api/invites/check'), {'code': _code});

    expect(find.text('Have you used New Me before?'), findsOneWidget);
    await app.tapText('I am new here');
    await app.enter('Ana');
    await app.tapButton('Continue');

    expect(find.bySemanticsLabel('Fern, taken'), findsOneWidget);
    await app.tapText('Fern');
    expect(app.enabled('Continue'), isTrue, reason: 'a taken colour cannot be picked');
    await app.tapText('Iris');
    await app.tapButton('Continue');
    expect(app.lastBody('POST /api/join'), {
      'code': _code,
      'name': 'Ana',
      'color': 'violet',
      'timezone': 'America/New_York',
    });

    await app.tapText('Read more');
    await app.tapButton('Continue');
    await app.tapButton('Continue');
    await app.tapButton('Connect Apple Health');
    expect(app.health.accessRequests, 1);
    expect(find.text("You're in, Ana!"), findsOneWidget);
  });

  testWidgets('a returning person picks themselves and only the code and id are sent', (
    tester,
  ) async {
    final adapter = _server()
      ..on(
        'POST /api/join',
        const StubResponse(201, {
          'user': {
            'id': 1,
            'name': 'Nick',
            'color': 'amber',
            'timezone': 'America/New_York',
            'isAdmin': true,
          },
          'token': 'repaired-token',
        }),
      );
    final app = _App(tester, adapter);
    await app.launch();

    await app.tapButton('Join with a code');
    await app.enter(_code);
    await app.tapButton('Continue');
    await app.tapText('I have been here before');

    expect(find.text('Who are you?'), findsOneWidget);
    expect(app.enabled('Continue'), isFalse);
    await app.tapText('Nick');
    await app.tapButton('Continue');

    expect(app.lastBody('POST /api/join'), {'code': _code, 'userId': 1});
    expect(adapter.to('PATCH /api/me'), isEmpty, reason: 'a returning person keeps their goals');
    expect(find.text('What do you want to work on?'), findsNothing);
    final button = tester.widget<Theme>(find.byType(Theme).first);
    expect(
      button.data.extension<AccentPalette>()!.id,
      'amber',
      reason: 'the health step already wears the returning person colour',
    );
    await app.tapButton('Not now');
    expect(find.text('Welcome back, Nick!'), findsOneWidget);
    await app.tapButton("Let's go");
    await app.expectSignedIn();
  });

  testWidgets('a code the server does not accept explains itself and stays editable', (
    tester,
  ) async {
    final adapter = _server()
      ..on(
        'POST /api/invites/check',
        const StubResponse(200, {'valid': false, 'users': <Object>[], 'canJoinNew': false}),
      );
    final app = _App(tester, adapter);
    await app.launch();

    await app.tapButton('Join with a code');
    await app.enter(_code);
    await app.tapButton('Continue');

    expect(find.text('That code did not work. Ask for a fresh one.'), findsOneWidget);
    expect(find.text('Enter your invite code'), findsOneWidget);
    expect(app.enabled('Continue'), isTrue);
  });

  testWidgets('a full server offers only the people already on it', (tester) async {
    final adapter = _server()
      ..on(
        'POST /api/invites/check',
        const StubResponse(200, {
          'valid': true,
          'users': [_nick],
          'canJoinNew': false,
        }),
      );
    final app = _App(tester, adapter);
    await app.launch();

    await app.tapButton('Join with a code');
    await app.enter(_code);
    await app.tapButton('Continue');

    expect(find.text('Who are you?'), findsOneWidget);
    expect(find.text('Nick'), findsOneWidget);
    expect(find.text('I am new here'), findsNothing);
  });

  testWidgets('an unreachable server shows a sad mascot and recovers with Try again', (
    tester,
  ) async {
    var up = false;
    final adapter = _server()
      ..routes['GET /api/server-info'] = (request) =>
          up ? const StubResponse(200, _info) : const StubResponse.unreachable();
    final app = _App(tester, adapter);
    await app.launch();

    expect(find.text('New Me cannot be reached right now'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
    expect(tester.widget<Mascot>(find.byType(Mascot)).state, MascotState.sad);

    up = true;
    await app.tapButton('Try again');
    expect(find.text('JOIN WITH A CODE'), findsOneWidget);
  });

  testWidgets('holding the mascot for three seconds opens the server override', (tester) async {
    final adapter = _server()..on('GET /api/server-info', const StubResponse(404, {'error': 'x'}));
    final app = _App(tester, adapter);
    await app.launch();
    expect(find.text('That address does not look like a New Me server.'), findsOneWidget);

    final gesture = await tester.startGesture(tester.getCenter(find.byType(Mascot)));
    await tester.pump(const Duration(seconds: 2));
    expect(find.text('Server'), findsNothing);
    await tester.pump(const Duration(seconds: 2));
    await gesture.up();
    await app.settle();
    expect(find.text('Server'), findsOneWidget);

    adapter.on('GET /api/server-info', const StubResponse(200, _info));
    await tester.enterText(find.byType(TextField), 'http://192.168.1.5:8080/');
    await app.tapButton('Connect');

    expect(
      adapter.to('GET /api/server-info').last.uri.toString(),
      'http://192.168.1.5:8080/api/server-info',
    );
    expect(find.text('JOIN WITH A CODE'), findsOneWidget);
  });

  testWidgets('a server that wants a newer client says so', (tester) async {
    final adapter = _server(info: {..._info, 'minClientVersion': '9.0.0'});
    final app = _App(tester, adapter);
    await app.launch();
    expect(find.text('Time to update'), findsOneWidget);

    adapter.on('GET /api/server-info', const StubResponse(426, {'error': 'old'}));
    await app.tapButton('Try again');
    expect(find.text('Time to update'), findsOneWidget);
  });

  testWidgets('leaving after the profile exists resumes at the first unanswered step', (
    tester,
  ) async {
    final adapter = _server(info: {..._info, 'initialized': false});
    final first = _App(tester, adapter);
    await first.launch();
    await first.tapButton('Get started');
    await first.enter('Ana');
    await first.tapButton('Continue');
    await first.tapButton('Continue');
    await first.tapText('Move more');
    await first.tapText('Read more');
    await first.tapButton('Continue');
    await first.tapButton('Continue');
    expect(find.text('How long will you read?'), findsOneWidget);

    // A relaunch with the stored session and the same preferences.
    await tester.pumpWidget(const SizedBox());
    final relaunch = _App(tester, adapter)..storage.values.addAll(first.storage.values);
    await tester.pumpWidget(
      ProviderScope(
        retry: (_, _) => null,
        overrides: [
          apiClientFactoryProvider.overrideWithValue(stubFactory(adapter)),
          deviceTimezoneProvider.overrideWithValue(() async => 'America/New_York'),
          healthSourceProvider.overrideWithValue(relaunch.health),
        ],
        child: const NewMeApp(),
      ),
    );
    await relaunch.settle();

    expect(find.text('How long will you read?'), findsOneWidget);
    expect(find.text('Today'), findsNothing, reason: 'the app does not open until onboarding ends');
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

  testWidgets('a snackbar from the signed-out session does not follow to onboarding', (
    tester,
  ) async {
    final app = _App(tester, _server());
    await app.launch(session: () => SessionController.seeded(testSession));
    final context = tester.element(find.byType(Scaffold).first);
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Added Meal')));
    await app.settle();
    expect(find.text('Added Meal'), findsOneWidget);

    final container = ProviderScope.containerOf(context);
    unawaited(container.read(sessionProvider.notifier).signOut());
    await app.settle();

    expect(find.text('JOIN WITH A CODE'), findsOneWidget);
    expect(find.text('Added Meal'), findsNothing);
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
