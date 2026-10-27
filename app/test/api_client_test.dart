import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:newme/api/api_client.dart';
import 'package:newme/api/models.dart';

import 'test_support.dart';

ApiClient _client(StubAdapter stub, {String? token, void Function()? onUnauthorized}) => ApiClient(
  baseUrl: 'https://x.invalid',
  token: token,
  adapter: stub,
  onUnauthorized: onUnauthorized,
);

Future<ApiException> _failure(Future<void> Function() call) async {
  try {
    await call();
  } on ApiException catch (e) {
    return e;
  }
  fail('expected an ApiException');
}

void main() {
  const info = {'name': 'Us', 'initialized': true, 'joinOpen': true, 'minClientVersion': '0.1.0'};

  test('requests carry the app key and client version, and a token when signed in', () async {
    final stub = StubAdapter()..on('GET /api/server-info', const StubResponse(200, info));
    await _client(stub, token: 't1').serverInfo();
    expect(stub.last!.headers['X-App-Key'], kAppKey);
    expect(stub.last!.headers['X-Client-Version'], kClientVersion);
    expect(stub.last!.headers['Authorization'], 'Bearer t1');
  });

  test('server-info is parsed', () async {
    final stub = StubAdapter()..on('GET /api/server-info', const StubResponse(200, info));
    final parsed = await _client(stub).serverInfo();
    expect(
      (parsed.name, parsed.initialized, parsed.joinOpen, parsed.minClientVersion),
      ('Us', true, true, '0.1.0'),
    );
  });

  group('error mapping', () {
    ApiClient failing(StubResponse response, {void Function()? onUnauthorized, String? token}) {
      final stub = StubAdapter()..on('GET /api/me', response);
      return _client(stub, token: token, onUnauthorized: onUnauthorized);
    }

    test('403 bad_app_key', () async {
      final e = await _failure(
        () => failing(const StubResponse(403, {'error': 'x', 'code': 'bad_app_key'})).me(),
      );
      expect(e.kind, ApiErrorKind.badAppKey);
    });

    test('a 403 without the code is an ordinary rejection', () async {
      final e = await _failure(
        () => failing(const StubResponse(403, {'error': 'admins only'})).me(),
      );
      expect((e.kind, e.message), (ApiErrorKind.other, 'admins only'));
    });

    test('426 update required', () async {
      final e = await _failure(() => failing(const StubResponse(426, {'error': 'old'})).me());
      expect(e.kind, ApiErrorKind.updateRequired);
    });

    test('422 date_closed', () async {
      final e = await _failure(
        () => failing(const StubResponse(422, {'error': 'closed', 'code': 'date_closed'})).me(),
      );
      expect(e.kind, ApiErrorKind.dateClosed);
    });

    test('other 422 keeps the server message', () async {
      final e = await _failure(
        () => failing(const StubResponse(422, {'error': 'reps too high'})).me(),
      );
      expect((e.kind, e.message), (ApiErrorKind.other, 'reps too high'));
    });

    test('5xx and network failures are offline', () async {
      for (final response in const [
        StubResponse(500, {'error': 'boom'}),
        StubResponse(502),
        StubResponse(503, {'error': 'redeploying'}),
        StubResponse.unreachable(),
      ]) {
        final e = await _failure(() => failing(response).me());
        expect(e.kind, ApiErrorKind.offline, reason: '${response.status}');
      }
    });

    test('only a 401 with a token triggers onUnauthorized', () async {
      var calls = 0;
      for (final response in const [
        StubResponse(403, {'error': 'x', 'code': 'bad_app_key'}),
        StubResponse(426),
        StubResponse(500),
        StubResponse.unreachable(),
        StubResponse(422, {'error': 'x', 'code': 'date_closed'}),
      ]) {
        await _failure(() => failing(response, token: 't', onUnauthorized: () => calls++).me());
      }
      expect(calls, 0);

      await _failure(
        () =>
            failing(const StubResponse(401, {'error': 'nope'}), onUnauthorized: () => calls++).me(),
      );
      expect(calls, 0, reason: 'no token was sent');

      final e = await _failure(
        () => failing(
          const StubResponse(401, {'error': 'nope'}),
          token: 't',
          onUnauthorized: () => calls++,
        ).me(),
      );
      expect((calls, e.statusCode), (1, 401));
    });

    test('426 reaches onUpdateRequired', () async {
      var gated = 0;
      final stub = StubAdapter()..on('GET /api/me', const StubResponse(426));
      final client = ApiClient(
        baseUrl: 'https://x.invalid',
        adapter: stub,
        onUpdateRequired: () => gated++,
      );
      await _failure(client.me);
      expect(gated, 1);
    });

    test('server-info on something that is not New Me is a wrong server', () async {
      for (final response in const [
        StubResponse(404, {'error': 'not found'}),
        StubResponse(200, '<html>hello</html>'),
        StubResponse(200, {'status': 'ok'}),
      ]) {
        final stub = StubAdapter()..on('GET /api/server-info', response);
        final e = await _failure(_client(stub).serverInfo);
        expect(e.kind, ApiErrorKind.wrongServer, reason: '${response.status} ${response.body}');
      }
    });
  });

  test('endpoints send the documented shapes', () async {
    final stub = StubAdapter()
      ..on(
        'POST /api/join',
        const StubResponse(201, {
          'user': {'id': 3, 'name': 'Ana', 'color': 'sky'},
          'token': 'abc',
        }),
      )
      ..on(
        'POST /api/invites/check',
        const StubResponse(200, {
          'users': [
            {'id': 1, 'name': 'Nick', 'color': 'green'},
          ],
        }),
      )
      ..on('PUT /api/health/daily', const StubResponse(200, {'days': []}))
      ..on('DELETE /api/devices/me', const StubResponse(204));
    final client = _client(stub, token: 't');

    final joined = await client.join(
      const JoinRequest.member(code: 'C0DE', name: 'Ana', color: 'sky', timezone: 'Europe/Paris'),
    );
    expect((joined.user.id, joined.token), (3, 'abc'));
    expect(stub.last!.data, {
      'code': 'C0DE',
      'name': 'Ana',
      'color': 'sky',
      'timezone': 'Europe/Paris',
    });

    final check = await client.checkInvite('C0DE');
    expect(check.users.single.name, 'Nick');

    await client.putHealthDaily([
      HealthItem(
        date: '2026-10-26',
        metric: 'steps',
        value: 1200,
        source: 'healthkit',
        measuredAt: DateTime.utc(2026, 10, 26, 14),
      ),
    ]);
    expect(stub.last!.data, {
      'items': [
        {
          'date': '2026-10-26',
          'metric': 'steps',
          'value': 1200.0,
          'source': 'healthkit',
          'measuredAt': '2026-10-26T14:00:00.000Z',
        },
      ],
    });

    await client.deleteDevice();
    expect(stub.last!.method, 'DELETE');
  });

  test('a log round-trips through the tagged union', () {
    final meal = LogEntry.fromJson({
      'id': 4,
      'kind': 'meal',
      'localDate': '2026-10-26',
      'loggedAt': '2026-10-26T12:00:00Z',
      'name': 'Soup',
      'kcal': 300,
      'proteinG': 12.5,
      'carbsG': 30,
      'fatG': 8,
      'fiberG': 4,
    });
    expect(meal, isA<MealLog>());
    expect(LogEntry.fromJson(meal.toJson()).toJson(), meal.toJson());
    expect(() => LogEntry.fromJson({'id': 1, 'kind': 'nope'}), throwsA(isA<FormatException>()));
  });

  test('today and board survive a JSON round trip', () {
    expect(Today.fromJson(todayJson()).toJson(), Today.fromJson(todayJson()).toJson());
    final today = Today.fromJson(todayJson());
    expect(Today.fromJson(today.toJson()).quests.single.actual, 2000);
    final board = Board.fromJson(boardJson());
    expect(Board.fromJson(board.toJson()).users.single.last7.single.percent, 80);
  });

  test('the reported client version is the version actually being built', () {
    // Nothing derives the header from the build at runtime, so this stops silent drift.
    final pubspec = File('pubspec.yaml').readAsLinesSync();
    final declared = pubspec.firstWhere((l) => l.startsWith('version:')).split(':')[1].trim();
    expect(declared.split('+').first, kClientVersion);
  });
}
