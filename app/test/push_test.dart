import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:newme/features/shell/home_tab.dart';
import 'package:newme/push/push_bridge.dart';
import 'package:newme/reminders/reminder_scheduler.dart';
import 'package:newme/state/push.dart';
import 'package:newme/state/reminders.dart';
import 'package:newme/state/session.dart';

import 'fake_reminder_scheduler.dart';
import 'test_support.dart';

void main() {
  final calls = <String>[];
  String? launchTap;

  setUp(() {
    FakeStorage().install();
    calls.clear();
    launchTap = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      kPushChannel,
      (call) async {
        calls.add(call.method);
        if (call.method == 'takeTap') return launchTap;
        return null;
      },
    );
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      kPushChannel,
      null,
    );
  });

  Future<void> native(String method, Object? arg) async {
    await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.handlePlatformMessage(
      kPushChannel.name,
      const StandardMethodCodec().encodeMethodCall(MethodCall(method, arg)),
      (_) {},
    );
    await _flush();
  }

  ({ProviderContainer container, StubAdapter adapter, FakeReminderScheduler scheduler}) build({
    bool allowed = true,
    Session? session = testSession,
  }) {
    final adapter = StubAdapter()
      ..on('PUT /api/devices/me/push', const StubResponse(204))
      ..on('DELETE /api/devices/me/push', const StubResponse(204))
      ..on('DELETE /api/devices/me', const StubResponse(200))
      ..on('GET /api/board', const StubResponse(500));
    final scheduler = FakeReminderScheduler(allowed: allowed);
    final container = testContainer(
      overrides: [
        sessionProvider.overrideWith(() => SessionController.seeded(session)),
        apiClientFactoryProvider.overrideWithValue(stubFactory(adapter)),
        reminderSchedulerProvider.overrideWithValue(scheduler),
        pushBridgeProvider.overrideWithValue(const PushBridge()),
      ],
    )..listen(pushProvider, (_, _) {});
    return (container: container, adapter: adapter, scheduler: scheduler);
  }

  test('nothing is registered until notification permission is granted', () async {
    final t = build(allowed: false);
    await _flush();
    expect(calls, isNot(contains('register')));

    t.scheduler.allowed = true;
    await t.container.read(remindersProvider.notifier).refreshPermission();
    await _flush();
    expect(calls, contains('register'));
  });

  test('with permission it registers once and sends the hex token to the server', () async {
    final t = build();
    await _flush();
    expect(calls.where((c) => c == 'register'), hasLength(1));

    await native('token', 'ab12cd');
    final puts = t.adapter.to('PUT /api/devices/me/push').toList();
    expect(puts.single.data, {'token': 'ab12cd'});
    expect(t.container.read(pushProvider), 'ab12cd');
  });

  test('the same token is not sent twice, a changed one is', () async {
    final t = build();
    await _flush();
    await native('token', 'ab12cd');
    await native('token', 'ab12cd');
    expect(t.adapter.to('PUT /api/devices/me/push'), hasLength(1));

    await native('token', 'ff00ee');
    expect(t.adapter.to('PUT /api/devices/me/push'), hasLength(2));
  });

  test('a rejected token is retried when it arrives again', () async {
    final t = build();
    t.adapter.on('PUT /api/devices/me/push', const StubResponse(500, {'error': 'down'}));
    await _flush();
    await native('token', 'ab12cd');

    t.adapter.on('PUT /api/devices/me/push', const StubResponse(204));
    await native('token', 'ab12cd');
    expect(t.adapter.to('PUT /api/devices/me/push'), hasLength(2));
  });

  test('a registration error from iOS is survivable', () async {
    final t = build();
    await _flush();
    await native('error', 'no entitlement');
    expect(t.adapter.to('PUT /api/devices/me/push'), isEmpty);
  });

  test('signing out asks iOS to unregister and forgets the token', () async {
    final t = build();
    await _flush();
    await native('token', 'ab12cd');

    await t.container.read(sessionProvider.notifier).signOut();
    await _flush();
    expect(calls, contains('unregister'));
    expect(t.container.read(pushProvider), isNull);
    expect(t.adapter.to('DELETE /api/devices/me/push'), hasLength(1));
    expect(t.adapter.to('DELETE /api/devices/me'), hasLength(1));
  });

  test('a failing push token delete does not stop the device from being revoked', () async {
    final t = build();
    t.adapter.on('DELETE /api/devices/me/push', const StubResponse(500, {'error': 'down'}));
    await _flush();
    await t.container.read(sessionProvider.notifier).signOut();
    await _flush();
    expect(t.adapter.to('DELETE /api/devices/me'), hasLength(1));
  });

  test('tapping a push opens Us, whatever the event', () async {
    final t = build();
    await _flush();
    for (final kind in ['cheer', 'challenge', 'reward', 'partner_done']) {
      t.container.read(homeTabProvider.notifier).select(HomeTab.me);
      await native('tapped', kind);
      expect(t.container.read(homeTabProvider), HomeTab.board, reason: kind);
    }
  });

  test('a push tapped while the app was closed opens Us once it is up', () async {
    launchTap = 'cheer';
    final t = build();
    await _flush();
    expect(t.container.read(homeTabProvider), HomeTab.board);
  });

  test('without a session nothing is asked of iOS', () async {
    build(session: null);
    await _flush();
    expect(calls, isEmpty);
  });
}

Future<void> _flush() async {
  for (var i = 0; i < 8; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}
