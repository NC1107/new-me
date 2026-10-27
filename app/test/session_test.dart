import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:newme/state/local_prefs.dart';
import 'package:newme/state/session.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'test_support.dart';

void main() {
  final storage = FakeStorage();
  setUp(storage.install);

  test('a seeded controller is restored with its session and builds a client', () {
    final container = testContainer(
      overrides: [sessionProvider.overrideWith(() => SessionController.seeded(testSession))],
    );
    expect(container.read(sessionProvider).restored, isTrue);
    expect(container.read(sessionProvider).session!.userName, 'Sam');
    expect(container.read(apiClientProvider), isNotNull);
  });

  test('empty storage restores to signed out', () async {
    final container = testContainer();
    expect(container.read(sessionProvider).restored, isFalse);
    await container.read(sessionProvider.notifier).restoreDone;
    expect(container.read(sessionProvider).restored, isTrue);
    expect(container.read(sessionProvider).session, isNull);
    expect(container.read(apiClientProvider), isNull);
  });

  test('the whole session is one JSON blob under a single secure key', () async {
    final first = testContainer();
    await first.read(sessionProvider.notifier).signIn(testSession);

    expect(storage.values.keys, [kSessionKey]);
    expect(jsonDecode(storage.values[kSessionKey]!), {
      'baseUrl': 'https://me.invalid',
      'userId': 2,
      'userName': 'Sam',
      'color': 'violet',
      'token': 'tok',
    });
    expect(storage.calls.where((c) => c.startsWith('write')), ['write session']);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getKeys(), isEmpty, reason: 'nothing secret or session-shaped in prefs');

    final second = testContainer();
    await second.read(sessionProvider.notifier).restoreDone;
    final restored = second.read(sessionProvider).session!;
    expect((restored.token, restored.userId, restored.color), ('tok', 2, 'violet'));
  });

  test('an unreadable blob restores to signed out instead of crashing', () async {
    storage.values[kSessionKey] = '{"baseUrl": 3';
    final container = testContainer();
    await container.read(sessionProvider.notifier).restoreDone;
    expect(container.read(sessionProvider).session, isNull);
    expect(container.read(sessionProvider).restored, isTrue);
  });

  test('prefs hold the non-secret values', () async {
    await LocalPrefs.setHealthPrompted();
    await LocalPrefs.setLastSyncedAt(DateTime.utc(2026, 10, 26, 9));
    await LocalPrefs.setLastLogKind('meal');
    expect(await LocalPrefs.healthPrompted(), isTrue);
    expect(await LocalPrefs.lastSyncedAt(), DateTime.utc(2026, 10, 26, 9));
    expect(await LocalPrefs.lastLogKind(), 'meal');
  });

  test('leaving deletes the blob, cached screens, and revokes the device', () async {
    final adapter = StubAdapter()..on('DELETE /api/devices/me', const StubResponse(204));
    final container = testContainer(
      overrides: [apiClientFactoryProvider.overrideWithValue(stubFactory(adapter))],
    );
    final controller = container.read(sessionProvider.notifier);
    await controller.signIn(testSession);
    await LocalPrefs.setLastLogKind('meal');
    (await SharedPreferences.getInstance()).setString('cache.today', '{}');

    await controller.signOut();

    expect(container.read(sessionProvider).session, isNull);
    expect(container.read(sessionProvider).signedOutFrom, isNull);
    expect(storage.values, isEmpty);
    expect(adapter.to('DELETE /api/devices/me').single.headers['Authorization'], 'Bearer tok');
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('cache.today'), isNull);
    expect(await LocalPrefs.lastLogKind(), isNull);
  });

  test('leaving still works when the server is unreachable', () async {
    final adapter = StubAdapter()..on('DELETE /api/devices/me', const StubResponse.unreachable());
    final container = testContainer(
      overrides: [apiClientFactoryProvider.overrideWithValue(stubFactory(adapter))],
    );
    final controller = container.read(sessionProvider.notifier);
    await controller.signIn(testSession);
    await controller.signOut();
    expect(storage.values, isEmpty);
    expect(container.read(sessionProvider).session, isNull);
  });

  test('a rejected token signs out without calling the server again', () async {
    final adapter = StubAdapter()..on('GET /api/me', const StubResponse(401, {'error': 'revoked'}));
    final container = testContainer(
      overrides: [apiClientFactoryProvider.overrideWithValue(stubFactory(adapter))],
    );
    await container.read(sessionProvider.notifier).signIn(testSession);
    await container.read(apiClientProvider)!.me().then((_) {}, onError: (_) {});
    await Future<void>.delayed(Duration.zero);

    final state = container.read(sessionProvider);
    expect(state.session, isNull);
    expect(state.signedOutFrom, 'https://me.invalid');
    expect(adapter.to('DELETE /api/devices/me'), isEmpty);
    expect(storage.values, isEmpty);
  });

  test('a late 401 for a replaced token does not sign out the new session', () async {
    final adapter = StubAdapter()..on('GET /api/me', const StubResponse(401, {'error': 'revoked'}));
    final container = testContainer(
      overrides: [apiClientFactoryProvider.overrideWithValue(stubFactory(adapter))],
    );
    final controller = container.read(sessionProvider.notifier);
    await controller.signIn(testSession);
    final oldClient = container.read(apiClientProvider)!;
    await controller.signIn(
      const Session(
        baseUrl: 'https://me.invalid',
        token: 'new',
        userId: 9,
        userName: 'Ana',
        color: 'amber',
      ),
    );

    await oldClient.me().then((_) {}, onError: (_) {});
    await Future<void>.delayed(Duration.zero);

    expect(container.read(sessionProvider).session?.userId, 9);
  });

  test('a renamed profile keeps the same API client', () async {
    final container = testContainer(
      overrides: [sessionProvider.overrideWith(() => SessionController.seeded(testSession))],
    );
    final before = container.read(apiClientProvider);
    await container.read(sessionProvider.notifier).updateProfile(name: 'Samantha', color: 'amber');
    expect(container.read(apiClientProvider), same(before));
  });
}
