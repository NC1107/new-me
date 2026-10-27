import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:newme/api/api_client.dart';
import 'package:newme/state/board.dart';
import 'package:newme/api/models.dart';
import 'package:newme/state/clock.dart';
import 'package:newme/state/log_actions.dart';
import 'package:newme/state/session.dart';
import 'package:newme/state/today.dart';

import 'fixtures.dart';
import 'test_support.dart';

final _serverNow = DateTime.utc(2026, 10, 26, 14, 2);

ProviderContainer _container(StubAdapter adapter, {DateTime Function()? clock}) => testContainer(
  overrides: [
    sessionProvider.overrideWith(() => SessionController.seeded(testSession)),
    apiClientFactoryProvider.overrideWithValue(stubFactory(adapter)),
    clockProvider.overrideWithValue(clock ?? () => _serverNow),
  ],
);

void main() {
  setUp(FakeStorage().install);

  test(
    'today loads, is cached, and is served under an offline notice when the server is down',
    () async {
      final adapter = StubAdapter()
        ..on('GET /api/today', StubResponse(200, todayJson(points: 120)));
      final online = _container(adapter);
      final first = await online.read(todayProvider.future);
      expect(first.offline, isNull);
      expect(first.data.day.points, 120);

      adapter.on('GET /api/today', const StubResponse.unreachable());
      final restarted = _container(adapter);
      final offline = await restarted.read(todayProvider.future);
      expect(offline.data.day.points, 120);
      expect(offline.offline!.updatedAt, _serverNow);
    },
  );

  test('a 5xx during a redeploy also falls back to the cache', () async {
    final adapter = StubAdapter()..on('GET /api/board', StubResponse(200, boardJson()));
    await _container(adapter).read(boardProvider.future);

    adapter.on('GET /api/board', const StubResponse(503, {'error': 'redeploying'}));
    final offline = await _container(adapter).read(boardProvider.future);
    expect(offline.data.users.single.name, 'Nick');
    expect(offline.offline, isNotNull);
  });

  test('offline with nothing cached is an error the screen can retry', () async {
    final adapter = StubAdapter()..on('GET /api/today', const StubResponse.unreachable());
    final container = _container(adapter);
    await expectLater(
      container.read(todayProvider.future),
      throwsA(isA<ApiException>().having((e) => e.kind, 'kind', ApiErrorKind.offline)),
    );

    adapter.on('GET /api/today', StubResponse(200, todayJson()));
    await container.read(todayProvider.notifier).refresh();
    expect(container.read(todayProvider).requireValue.data.streak.current, 3);
  });

  test('a cache written for someone else is ignored', () async {
    final adapter = StubAdapter()..on('GET /api/today', StubResponse(200, todayJson()));
    await _container(adapter).read(todayProvider.future);

    adapter.on('GET /api/today', const StubResponse.unreachable());
    final other = testContainer(
      overrides: [
        sessionProvider.overrideWith(
          () => SessionController.seeded(
            const Session(
              baseUrl: 'https://me.invalid',
              token: 't',
              userId: 99,
              userName: 'Eve',
              color: 'sky',
            ),
          ),
        ),
        apiClientFactoryProvider.overrideWithValue(stubFactory(adapter)),
      ],
    );
    await expectLater(other.read(todayProvider.future), throwsA(isA<ApiException>()));
  });

  test('a failed refresh keeps the value on screen beneath the error', () async {
    final adapter = StubAdapter()..on('GET /api/today', StubResponse(200, todayJson(points: 120)));
    final container = _container(adapter);
    await container.read(todayProvider.future);

    adapter.on('GET /api/today', const StubResponse(422, {'error': 'weird'}));
    await container.read(todayProvider.notifier).refresh();

    final state = container.read(todayProvider);
    expect(state.hasError, isTrue);
    expect(state.value!.data.day.points, 120);
  });

  test('a successful refresh clears the offline notice', () async {
    final adapter = StubAdapter()..on('GET /api/today', StubResponse(200, todayJson()));
    await _container(adapter).read(todayProvider.future);

    adapter.on('GET /api/today', const StubResponse.unreachable());
    final container = _container(adapter);
    expect((await container.read(todayProvider.future)).offline, isNotNull);

    adapter.on('GET /api/today', StubResponse(200, todayJson(points: 200)));
    await container.read(todayProvider.notifier).refresh();
    final value = container.read(todayProvider).requireValue;
    expect((value.offline, value.data.day.points), (null, 200));
  });

  test('a log that makes the day count reloads Today for the streak the server derives', () async {
    final adapter = StubAdapter()
      ..on('GET /api/today', StubResponse(200, todayJson()))
      ..on('POST /api/logs', StubResponse(201, logResultJson()));
    final container = _container(adapter);
    container.listen(todayProvider, (_, _) {});
    await container.read(todayProvider.future);

    final counted = todayJson()
      ..['streak'] = {'current': 4, 'restAvailable': true}
      ..['day'] = dayJson(points: 170, percent: 70, counted: true);
    adapter.on('GET /api/today', StubResponse(200, counted));
    await container
        .read(logActionsProvider)
        .create(
          const ActivityDraft(clientOpId: 'op-1', type: 'pushups', quantity: 20, unit: 'reps'),
        );
    await Future<void>.delayed(const Duration(milliseconds: 50));

    final today = container.read(todayProvider).requireValue.data;
    expect((today.day.counted, today.streak.current), (true, 4));
  });
}
