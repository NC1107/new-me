import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:newme/api/api_client.dart';
import 'package:newme/api/models.dart';
import 'package:newme/util/errors.dart';
import 'package:newme/widgets/chunky_icon_button.dart';

import 'fixtures.dart';
import 'test_support.dart';

void main() {
  setUp(() => ApiClient.retryDelay = Duration.zero);
  tearDown(() => ApiClient.retryDelay = const Duration(milliseconds: 1500));

  test('a proxy 404 during a restart is retried once and then succeeds', () async {
    var calls = 0;
    final stub = StubAdapter({
      'GET /api/me': (_) => ++calls == 1
          ? const StubResponse.text(404, '404 page not found')
          : StubResponse(200, meJson()),
    });
    final client = ApiClient(baseUrl: 'https://me.invalid', token: 't', adapter: stub);
    final me = await client.me();
    expect(me.user.name, isNotEmpty);
    expect(calls, 2);
  });

  test('a restart that outlasts the retry reads as updating, not as a raw 404', () async {
    final stub = StubAdapter({'PATCH /api/me': (_) => const StubResponse.text(502, 'Bad Gateway')});
    final client = ApiClient(baseUrl: 'https://me.invalid', token: 't', adapter: stub);
    try {
      await client.patchMe(const MePatch(name: 'Nadia'));
      fail('expected an error');
    } on ApiException catch (e) {
      expect(e.kind, ApiErrorKind.offline);
      expect(errorCopy(e), 'New Me is updating. Try again in a moment.');
    }
    expect(stub.to('PATCH /api/me'), hasLength(2));
  });

  test('a POST is never retried, since it may not be safe to repeat', () async {
    final stub = StubAdapter({'POST /api/join': (_) => const StubResponse.text(503, '')});
    final client = ApiClient(baseUrl: 'https://me.invalid', adapter: stub);
    await expectLater(
      client.join(
        const JoinRequest.first(name: 'Nadia', color: 'violet', timezone: 'America/New_York'),
      ),
      throwsA(isA<ApiException>().having((e) => e.code, 'code', 'unavailable')),
    );
    expect(stub.to('POST /api/join'), hasLength(1));
  });

  test('the server own 404 stays a real not found', () async {
    final stub = StubAdapter({
      'GET /api/me': (_) =>
          const StubResponse(404, {'code': 'not_found', 'error': 'no such thing'}),
    });
    final client = ApiClient(baseUrl: 'https://me.invalid', token: 't', adapter: stub);
    try {
      await client.me();
      fail('expected an error');
    } on ApiException catch (e) {
      expect(e.kind, ApiErrorKind.other);
      expect(e.statusCode, 404);
      expect(stub.to('GET /api/me'), hasLength(1));
    }
  });

  testWidgets('an icon button leaves room for its lip, so a row never clips it', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: ChunkyIconButton(
            icon: Icons.add,
            semanticLabel: 'More',
            size: 44,
            onPressed: () {},
          ),
        ),
      ),
    );
    expect(tester.getSize(find.byType(ChunkyIconButton)).height, closeTo(44 + 4.4, 0.01));
  });
}
