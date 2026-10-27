import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:newme/api/api_client.dart';
import 'package:newme/api/models.dart';

import 'test_support.dart';

/// The v6 wire contract. The files in test/contract_v6 are hand-checked against the server
/// handlers and docs/design.md: today, me, recap, goals_proposals_empty and abs_not_linked were
/// read from the running v6 server, the rest are shaped like the documented bodies. They live
/// apart from test/contract because tool/capture_contract.mjs can only record a freshly reset
/// stack.
Map<String, dynamic> _load(String name) =>
    jsonDecode(File('test/contract_v6/$name.json').readAsStringSync()) as Map<String, dynamic>;

ApiClient _client(String name, StubAdapter stub) {
  final x = _load(name);
  stub.on('${x['method']} ${x['path']}', StubResponse(x['status'] as int, x['body'] as Object));
  return ApiClient(baseUrl: 'https://x.invalid', token: 't', adapter: stub);
}

/// A model drops nothing it was sent when its JSON equals the wire once nulls are ignored; the
/// models leave a missing optional field out where the server sends an explicit null.
Object? _withoutNulls(Object? json) => switch (json) {
  final Map<String, dynamic> m => {
    for (final e in m.entries)
      if (e.value != null) e.key: _withoutNulls(e.value),
  },
  final List<dynamic> l => [for (final v in l) _withoutNulls(v)],
  _ => json,
};

Object? _wire(Object? json) => canonicalInstants(_withoutNulls(json));

void main() {
  group('responses parse and re-encode to the wire', () {
    test('GET /today carries readiness, plan and the listening sync time', () async {
      final stub = StubAdapter();
      final today = await _client('today', stub).today();
      expect(_wire(today.toJson()), _wire(_load('today')['body']));
      expect(today.readiness?.level, ReadinessLevel.ready);
      expect(today.readiness?.sleepOnly, isTrue);
      expect(today.plan?.items, isNotEmpty);
      expect(today.plan?.summary, isNotEmpty);
      expect(today.quests.every((q) => q.doneBy == null), isTrue);
      expect(today.listeningSyncedAt, isNull);
    });

    test('doneBy, an easy readiness and a listening sync time round trip', () async {
      final today = await _client('today_done_by', StubAdapter()).today();
      expect(_wire(today.toJson()), _wire(_load('today_done_by')['body']));
      final by = today.quests[1].doneBy!;
      expect((by.kind, by.type, by.minutes), ('workout', 'strength', 42));
      expect(today.readiness?.level, ReadinessLevel.easy);
      expect(today.readiness?.findings.map((r) => r.kind), ['hrv', 'sleep']);
      expect(today.listeningSyncedAt, DateTime.utc(2026, 10, 27, 15, 19));
      expect(today.listeningMinutes, 12);
    });

    test('GET /me carries the new switches and the features', () async {
      final me = await _client('me', StubAdapter()).me();
      expect(_wire(me.toJson()), _wire(_load('me')['body']));
      expect(me.features.mealEstimate, isFalse);
      expect(me.notifications.behindPace, isFalse);
      expect(me.notifications.windDown, isFalse);
      expect(me.notifications.closeToDone, isTrue);

      final on = await _client('me_features_on', StubAdapter()).me();
      expect(_wire(on.toJson()), _wire(_load('me_features_on')['body']));
      expect((on.features.mealEstimate, on.features.planPolish), (true, true));
      expect(on.notifications.behindPace, isTrue);
      expect(on.audiobookshelf?.linked, isTrue);
    });

    test('GET /recap', () async {
      final recap = await _client('recap', StubAdapter()).recap();
      expect(_wire(recap.toJson()), _wire(_load('recap')['body']));
      expect(recap.week, '2026-W44');
      expect(recap.complete, isFalse);
      expect(recap.people.map((p) => p.name), ['Nick', 'Nadia']);
      expect(recap.pair.thisWeek.points, 200);
      expect(recap.people.first.bestDay?.points, 170);
    });

    test('GET /recap sends the week when asked', () async {
      final stub = StubAdapter();
      await _client('recap', stub).recap(week: '2026-W43');
      expect(stub.last!.queryParameters, {'week': '2026-W43'});
    });

    test('GET /goals/proposals, empty and with both proposals', () async {
      final empty = await _client('goals_proposals_empty', StubAdapter()).goalProposals();
      expect(empty.proposals, isEmpty);
      expect(_wire(empty.toJson()), _wire(_load('goals_proposals_empty')['body']));

      final both = await _client('goals_proposals', StubAdapter()).goalProposals();
      expect(_wire(both.toJson()), _wire(_load('goals_proposals')['body']));
      expect(both.proposals.map((p) => (p.key, p.current, p.proposed)), [
        ('steps', 8000, 9000),
        ('sleep', 480, 450),
      ]);
    });

    test('POST /me/audiobookshelf/sync', () async {
      final stub = StubAdapter();
      final sync = await _client('abs_sync', stub).syncAudiobookshelf();
      expect(stub.last!.method, 'POST');
      expect(_wire(sync.toJson()), _wire(_load('abs_sync')['body']));
      expect((sync.linked, sync.minutesToday), (true, 12));
    });

    test('POST /meals/estimate sends the sentence and parses the meal', () async {
      final stub = StubAdapter();
      final estimate = await _client(
        'estimate',
        stub,
      ).estimateMeal(text: 'chicken burrito bowl, no rice');
      expect(stub.last!.data, {'text': 'chicken burrito bowl, no rice'});
      expect(_wire(estimate.legacy.toJson()), _wire(_load('estimate')['body']));
      expect(estimate.legacy.confidence, EstimateConfidence.medium);
      expect(estimate.items, isEmpty);
    });

    test('accepting a proposal answers with the profile and dismissing sends no body', () async {
      final stub = StubAdapter()
        ..on(
          'POST /api/goals/proposals/steps/accept',
          StubResponse(200, _load('me')['body']! as Object),
        )
        ..on('POST /api/goals/proposals/sleep/dismiss', const StubResponse(204));
      final client = ApiClient(baseUrl: 'https://x.invalid', token: 't', adapter: stub);
      final me = await client.acceptGoalProposal('steps');
      expect(me.user.name, 'Nick');
      await client.dismissGoalProposal('sleep');
      expect(stub.to('POST /api/goals/proposals/sleep/dismiss'), hasLength(1));
    });
  });

  group('failures are told apart by code', () {
    Future<ApiException> failure(String name, Future<Object?> Function(ApiClient c) call) async {
      try {
        await call(_client(name, StubAdapter()));
      } on ApiException catch (e) {
        return e;
      }
      throw TestFailure('expected a failure');
    }

    test('not linked, rate limited, unavailable and disabled', () async {
      final notLinked = await failure('abs_not_linked', (c) => c.syncAudiobookshelf());
      expect((notLinked.statusCode, notLinked.code), (404, 'abs_not_linked'));

      final limited = await failure('estimate_rate_limited', (c) => c.estimateMeal(text: 'oats'));
      expect(
        (limited.kind, limited.statusCode, limited.code),
        (ApiErrorKind.other, 429, 'rate_limited'),
      );

      final down = await failure('estimate_unavailable', (c) => c.estimateMeal(text: 'oats'));
      expect(down.code, 'estimate_unavailable');
      expect(down.statusCode, 502);

      final off = await failure('estimate_disabled', (c) => c.estimateMeal(text: 'oats'));
      expect((off.statusCode, off.code), (404, 'estimate_disabled'));
    });
  });
}
