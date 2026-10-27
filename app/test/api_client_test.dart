import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:newme/api/api_client.dart';

class _StubAdapter implements HttpClientAdapter {
  _StubAdapter(this.status, this.body);

  final int status;
  final Map<String, dynamic> body;
  RequestOptions? last;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    last = options;
    return ResponseBody.fromString(
      jsonEncode(body),
      status,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  test('requests carry the app key and client version, and a token when signed in', () async {
    final stub = _StubAdapter(200, {'name': 'Us', 'initialized': true, 'users': []});
    await ApiClient(baseUrl: 'https://x.invalid', token: 't1', adapter: stub).serverInfo();
    expect(stub.last!.headers['X-App-Key'], kAppKey);
    expect(stub.last!.headers['X-Client-Version'], kClientVersion);
    expect(stub.last!.headers['Authorization'], 'Bearer t1');
  });

  test('server-info is parsed into users', () async {
    final stub = _StubAdapter(200, {
      'name': 'Us',
      'initialized': true,
      'users': [
        {'id': 1, 'name': 'A', 'color': 'sky'},
      ],
    });
    final info = await ApiClient(baseUrl: 'https://x.invalid', adapter: stub).serverInfo();
    expect(info.name, 'Us');
    expect(info.users.single.color, 'sky');
  });

  test('a 401 signs out only when a token was sent', () async {
    var calls = 0;
    final stub = _StubAdapter(401, {'error': 'nope'});
    final anon = ApiClient(
      baseUrl: 'https://x.invalid',
      adapter: stub,
      onUnauthorized: () => calls++,
    );
    await expectLater(anon.serverInfo(), throwsA(isA<ApiException>()));
    expect(calls, 0);

    final authed = ApiClient(
      baseUrl: 'https://x.invalid',
      token: 't',
      adapter: stub,
      onUnauthorized: () => calls++,
    );
    await expectLater(
      authed.serverInfo(),
      throwsA(
        isA<ApiException>()
            .having((e) => e.statusCode, 'statusCode', 401)
            .having((e) => e.message, 'message', 'nope'),
      ),
    );
    expect(calls, 1);
  });

  test('the reported client version is the version actually being built', () {
    // Nothing derives the header from the build at runtime, so this stops silent drift.
    final pubspec = File('pubspec.yaml').readAsLinesSync();
    final declared = pubspec.firstWhere((l) => l.startsWith('version:')).split(':')[1].trim();
    expect(declared.split('+').first, kClientVersion);
  });
}
