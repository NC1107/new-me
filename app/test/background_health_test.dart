import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:newme/api/api_client.dart';
import 'package:newme/health/background_health_bridge.dart';
import 'package:newme/health/fake_health_source.dart';
import 'package:newme/health/health_source_factory.dart';
import 'package:newme/state/clock.dart';
import 'package:newme/state/health_sync.dart';
import 'package:newme/state/local_prefs.dart';
import 'package:newme/state/session.dart';

import 'test_support.dart';

void main() {
  final calls = <MethodCall>[];

  setUp(() {
    FakeStorage().install();
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      kBackgroundChannel,
      (call) async {
        calls.add(call);
        return null;
      },
    );
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      kBackgroundChannel,
      null,
    );
  });

  ProviderContainer build({Session? session = testSession}) {
    final adapter = StubAdapter()
      ..on('PUT /api/health/daily', const StubResponse(200, {'days': []}))
      ..on('DELETE /api/devices/me', const StubResponse(200, {}));
    return testContainer(
      overrides: [
        sessionProvider.overrideWith(() => SessionController.seeded(session)),
        apiClientFactoryProvider.overrideWithValue(stubFactory(adapter)),
        healthSourceProvider.overrideWithValue(FakeHealthSource()),
        clockProvider.overrideWithValue(() => DateTime(2026, 10, 26, 14)),
      ],
    );
  }

  Future<void> boot(ProviderContainer c) async {
    c.listen(healthSyncProvider, (_, _) {});
    await c.read(healthSyncProvider.notifier).ready;
  }

  test('a session is handed to the native side with the app key and client version', () async {
    final c = build();
    await boot(c);

    final configure = calls.firstWhere((m) => m.method == 'configure');
    expect(configure.arguments, {
      'baseUrl': 'https://me.invalid',
      'token': 'tok',
      'appKey': kAppKey,
      'clientVersion': kClientVersion,
    });
  });

  test('without a session the native config is cleared, not configured', () async {
    final c = build(session: null);
    await boot(c);

    expect(calls.map((m) => m.method), contains('clear'));
    expect(calls.map((m) => m.method), isNot(contains('configure')));
  });

  test('a new token is configured again', () async {
    final c = build();
    await boot(c);
    calls.clear();

    await c
        .read(sessionProvider.notifier)
        .signIn(
          const Session(
            baseUrl: 'https://me.invalid',
            token: 'tok2',
            userId: 2,
            userName: 'Sam',
            color: 'violet',
          ),
        );
    await Future<void>.delayed(Duration.zero);

    final configure = calls.firstWhere((m) => m.method == 'configure');
    expect((configure.arguments as Map)['token'], 'tok2');
  });

  test('observers stay off until Health access has been asked for', () async {
    final c = build();
    await boot(c);
    expect(calls.map((m) => m.method), isNot(contains('enable')));

    await c.read(healthSyncProvider.notifier).connect();

    expect(calls.map((m) => m.method), contains('enable'));
  });

  test('observers are registered at start when Health was already prompted', () async {
    await LocalPrefs.setHealthPrompted();
    final c = build();
    await boot(c);

    expect(calls.map((m) => m.method), contains('enable'));
  });

  test('sign-out clears the native config', () async {
    final c = build();
    await boot(c);
    calls.clear();

    await c.read(sessionProvider.notifier).signOut();

    expect(calls.map((m) => m.method), contains('clear'));
  });

  test('a missing native plugin is not an error', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      kBackgroundChannel,
      null,
    );
    const bridge = BackgroundHealthBridge();

    await bridge.configure(baseUrl: 'https://me.invalid', token: 'tok');
    await bridge.enable();
    await bridge.clear();
  });
}
