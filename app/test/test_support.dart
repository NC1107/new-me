import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:newme/api/api_client.dart';
import 'package:newme/state/session.dart';
import 'package:shared_preferences/shared_preferences.dart';

class StubResponse {
  const StubResponse(this.status, [this.body = const <String, dynamic>{}]) : unreachable = false;

  const StubResponse.unreachable()
    : status = 0,
      body = const <String, dynamic>{},
      unreachable = true;

  final int status;
  final Object body;
  final bool unreachable;
}

typedef StubHandler = FutureOr<StubResponse> Function(RequestOptions request);

/// Answers requests by "METHOD /path"; anything unrouted is a 404.
class StubAdapter implements HttpClientAdapter {
  StubAdapter([Map<String, StubHandler>? routes]) : routes = routes ?? {};

  final Map<String, StubHandler> routes;
  final List<RequestOptions> requests = [];

  void on(String route, StubResponse response) => routes[route] = (_) => response;

  RequestOptions? get last => requests.isEmpty ? null : requests.last;

  Iterable<RequestOptions> to(String route) =>
      requests.where((r) => '${r.method} ${r.path}' == route);

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    final handler = routes['${options.method} ${options.path}'];
    final response = handler == null
        ? const StubResponse(404, {'error': 'no route'})
        : await handler(options);
    if (response.unreachable) {
      throw DioException.connectionError(requestOptions: options, reason: 'unreachable');
    }
    return ResponseBody.fromString(
      response.body is String ? response.body as String : jsonEncode(response.body),
      response.status,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

ApiClientFactory stubFactory(StubAdapter adapter) =>
    ({required baseUrl, token, onUnauthorized, onUpdateRequired}) => ApiClient(
      baseUrl: baseUrl,
      token: token,
      onUnauthorized: onUnauthorized,
      onUpdateRequired: onUpdateRequired,
      adapter: adapter,
    );

const testSession = Session(
  baseUrl: 'https://me.invalid',
  token: 'tok',
  userId: 2,
  userName: 'Sam',
  color: 'violet',
);

/// An in-memory flutter_secure_storage plus empty shared_preferences, reset per test.
class FakeStorage {
  final values = <String, String>{};
  final calls = <String>[];

  void install() {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
      (call) async {
        final args = call.arguments as Map;
        final key = args['key'] as String?;
        calls.add('${call.method} $key');
        switch (call.method) {
          case 'read':
            return values[key];
          case 'write':
            values[key!] = args['value'] as String;
          case 'delete':
            values.remove(key);
        }
        return null;
      },
    );
  }
}

/// Riverpod retries failed providers by default, which leaves timers behind in tests.
ProviderContainer testContainer({List<Override> overrides = const []}) {
  final container = ProviderContainer(retry: (_, _) => null, overrides: overrides);
  addTearDown(container.dispose);
  return container;
}

Map<String, dynamic> todayJson({int points = 120, String localToday = '2026-10-26'}) => {
  'localToday': localToday,
  'serverNow': '2026-10-26T14:00:00Z',
  'backdateUntil': null,
  'day': {'points': points, 'maxPoints': 480, 'percent': 25, 'counted': false, 'threshold': 70},
  'quests': [
    {
      'key': 'steps',
      'title': 'Steps',
      'unit': 'steps',
      'target': 8000,
      'actual': 2000,
      'points': 100,
      'earned': 25,
      'bonus': 0,
      'completed': false,
    },
  ],
  'streak': {'current': 3, 'restAvailable': true},
  'food': {'kcal': 0, 'protein': 0, 'carbs': 0, 'fat': 0, 'burned': 0},
  'health': {'hasSteps': true, 'syncedAt': '2026-10-26T13:00:00Z'},
};

Map<String, dynamic> boardJson() => {
  'season': {'name': 'Season 0', 'startsOn': '2026-10-26', 'endsOn': '2026-12-31'},
  'users': [
    {
      'id': 1,
      'name': 'Nick',
      'color': 'green',
      'today': {'points': 120, 'percent': 25, 'counted': false},
      'week': 300,
      'season': 300,
      'streak': 3,
      'last7': [
        {'date': '2026-10-25', 'percent': 80, 'rest': false},
      ],
      'syncedAt': '2026-10-26T13:00:00Z',
    },
  ],
};
