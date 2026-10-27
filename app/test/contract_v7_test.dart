import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:newme/api/api_client.dart';
import 'package:newme/api/models.dart';

import 'test_support.dart';

/// The v7 wire contract. The files in test/contract_v7 were read from the running v7 server
/// (today, board, me, insights, progress, lookback and milestones_empty) or shaped like them with
/// every new field filled in (the *_rich files, away and cover bodies, whose shapes come from
/// server/internal/api/streaks.go and docs/design.md).
Map<String, dynamic> _load(String name) =>
    jsonDecode(File('test/contract_v7/$name.json').readAsStringSync()) as Map<String, dynamic>;

ApiClient _client(String name, StubAdapter stub) {
  final x = _load(name);
  stub.on('${x['method']} ${x['path']}', StubResponse(x['status'] as int, x['body'] as Object));
  return ApiClient(baseUrl: 'https://x.invalid', token: 't', adapter: stub);
}

Object? _withoutNulls(Object? json) => switch (json) {
  final Map<String, dynamic> m => {
    for (final e in m.entries)
      if (e.value != null) e.key: _withoutNulls(e.value),
  },
  final List<dynamic> l => [for (final v in l) _withoutNulls(v)],
  _ => json,
};

/// The models leave a new field out while it holds its default, so the wire is compared without
/// the defaults the v7 server always sends.
Object? _withoutDefaults(Object? json) => switch (json) {
  final Map<String, dynamic> m => {
    for (final e in m.entries)
      if (!_isDefault(e.key, e.value)) e.key: _withoutDefaults(e.value),
  },
  final List<dynamic> l => [for (final v in l) _withoutDefaults(v)],
  _ => json,
};

bool _isDefault(String key, Object? value) {
  if (value == false && const {'frozen', 'away', 'repaired'}.contains(key)) return true;
  if (value == true && const {'milestones', 'lookback'}.contains(key)) return true;
  if (value is Map) {
    if (key == 'freezes') return value['held'] == 0 && value['earnedTowardNext'] == 0;
    if (key == 'sharedStreak') return value['current'] == 0 && value['best'] == 0;
    if (key == 'away') {
      return value['today'] == false &&
          value['current'] == null &&
          (value['upcoming'] as List).isEmpty;
    }
  }
  if (key == 'newMilestones' && value is List) return value.isEmpty;
  return false;
}

Object? _wire(Object? json) => canonicalInstants(_withoutNulls(_withoutDefaults(json)));

Future<ApiException> _failure(String name, Future<Object?> Function(ApiClient c) call) async {
  try {
    await call(_client(name, StubAdapter()));
  } on ApiException catch (e) {
    return e;
  }
  throw TestFailure('expected a failure');
}

void main() {
  group('reads parse and re-encode to the wire', () {
    test('GET /today from the v7 server carries freezes, no repair and no away', () async {
      final today = await _client('today', StubAdapter()).today();
      expect(_wire(today.toJson()), _wire(_load('today')['body']));
      expect(today.freezes.held, 2);
      expect(today.repair, isNull);
      expect(today.away.today, isFalse);
      expect(today.newMilestones, isEmpty);
    });

    test('GET /today with a repair window, upcoming away days and milestones', () async {
      final today = await _client('today_rich', StubAdapter()).today();
      expect(_wire(today.toJson()), _wire(_load('today_rich')['body']));
      expect(today.freezes.held, 1);
      expect(today.freezes.earnedTowardNext, 4);
      expect(today.repair?.date, '2026-10-26');
      expect(today.repair?.until, DateTime.utc(2026, 10, 28, 2));
      expect(today.repair?.progressPercent, 36);
      expect(today.away.upcoming.single.note, 'Lisbon');
      expect(today.newMilestones.map((m) => m.title), ['7 days together', '7-day streak']);
      expect(today.newMilestones.first.shared, isTrue);
    });

    test('GET /board carries the shared streak, freezes and the challenge shares', () async {
      final b = await _client('board', StubAdapter()).board();
      expect(_wire(b.toJson()), _wire(_load('board')['body']));
      expect(b.users.first.freezes.held, 2);
      expect(b.users.first.last7.every((d) => !d.frozen && !d.away && !d.repaired), isTrue);
      final shares = b.challenge!.people;
      expect(shares.map((s) => (s.name, s.target, s.progress)), [
        ('Nick', 62000, 13221),
        ('Nadia', 51000, 9200),
      ]);
      expect(b.challenge!.target, 113000);
    });

    test('GET /board with frozen, away and repaired days and an away partner', () async {
      final b = await _client('board_rich', StubAdapter()).board();
      expect(_wire(b.toJson()), _wire(_load('board_rich')['body']));
      expect((b.sharedStreak.current, b.sharedStreak.best), (9, 21));
      final nick = b.users.first.last7;
      expect(nick[1].frozen, isTrue);
      expect(nick[3].away, isTrue);
      expect(nick[4].repaired, isTrue);
      expect(b.users[1].away.today, isTrue);
      expect(b.users[1].away.current?.note, 'Flu');
      expect(b.users[1].freezes.held, 0);
    });

    test('GET /me carries the schedule and the protein target', () async {
      final me = await _client('me', StubAdapter()).me();
      expect(_wire(me.toJson()), _wire(_load('me')['body']));
      expect(me.schedule.workdays, [1, 2, 3, 4, 5]);
      expect(me.schedule.workday.wake, 6 * 60 + 30);
      expect(me.schedule.dayOff.wake, 7 * 60);
      expect(me.schedule.firstNotificationOffsetMin, 15);
      expect(me.protein.suggested, 130);
      expect(me.protein.effective, 100);
      expect(me.notifications.milestones, isTrue);
      expect(me.notifications.lookback, isTrue);
    });

    test('GET /insights carries weight, the WHO summary and the protein hit rate', () async {
      final i = await _client('insights', StubAdapter()).insights();
      expect(_wire(i.toJson()), _wire(_load('insights')['body']));
      expect(i.weight.smoothedKg, 82.4);
      expect(i.weight.weeklyRateKg, isNull);
      expect(i.activity.moderateEquivalentMin, 285);
      expect(i.activity.meetsAerobic && i.activity.meetsStrength, isTrue);
      expect(i.protein.hitRate7, isNull);

      final rich = await _client('insights_rich', StubAdapter()).insights();
      expect(_wire(rich.toJson()), _wire(_load('insights_rich')['body']));
      expect(rich.weight.weeklyRateKg, -0.4);
      expect(rich.weight.points.length, 12);
      expect((rich.protein.daysHit7, rich.protein.days7), (5, 7));
    });

    test('GET /progress sends the window and parses every metric', () async {
      final stub = StubAdapter();
      final p = await _client('progress', stub).progress();
      expect(stub.last!.queryParameters, {'window': 30});
      expect(_wire(p.toJson()), _wire(_load('progress')['body']));
      expect(p.people.map((x) => x.name), ['Nick', 'Nadia']);
      expect(p.people.first.metrics.length, 12);
      final weight = p.people.first.metrics.firstWhere((m) => m.key == 'weight_kg');
      expect(weight.goodDirection, GoodDirection.none);
    });

    test('GET /progress with changes and weekly series', () async {
      final p = await _client('progress_rich', StubAdapter()).progress(window: 60);
      expect(_wire(p.toJson()), _wire(_load('progress_rich')['body']));
      final steps = p.people.first.metrics.firstWhere((m) => m.key == 'steps');
      expect(steps.changeFromPrevious?.better, isFalse);
      expect(steps.changeFromFirst?.better, isTrue);
      expect(steps.series.length, 8);
      final vo2 = p.people.first.metrics.firstWhere((m) => m.key == 'vo2max');
      expect(vo2.current, isNull);
      expect(vo2.series.every((s) => s.value == null), isTrue);
    });

    test('GET /lookback defaults to the last month and sends one when asked', () async {
      final stub = StubAdapter();
      final lb = await _client('lookback', stub).lookback();
      expect(stub.last!.queryParameters, isEmpty);
      expect((lb.month, lb.label, lb.complete), ('2026-09', 'September 2026', true));
      expect(lb.people.length, 2);
      expect(lb.hasImprovements, isFalse);

      final stub2 = StubAdapter();
      final rich = await _client('lookback_rich', stub2).lookback(month: '2026-09');
      expect(stub2.last!.queryParameters, {'month': '2026-09'});
      expect(rich.couple.improvements.length, 3);
      expect(rich.people.first.improvements.first.title, 'Push-ups');
      expect(rich.couple.bothCountedDays, 19);
      expect(rich.hasImprovements, isTrue);
    });

    test('GET /milestones, empty and newest first', () async {
      expect(await _client('milestones_empty', StubAdapter()).milestones(), isEmpty);
      final list = await _client('milestones', StubAdapter()).milestones();
      expect(list.map((m) => m.kind), [
        'shared_streak',
        'streak',
        'first_10k_steps',
        'first_all_quests',
        'first_full_week',
      ]);
      expect(list.first.shared, isTrue);
      expect(list[1].shared, isFalse);
    });
  });

  group('writes send the contract bodies', () {
    test('POST /away sends the span and answers with the state', () async {
      final stub = StubAdapter();
      final created = await _client(
        'away_created',
        stub,
      ).createAway(from: '2026-10-30', to: '2026-11-01', note: 'Lisbon');
      expect(stub.last!.data, _load('away_created')['request']);
      expect(created.span.id, 3);
      expect(created.state.upcoming.single.to, '2026-11-01');
      expect(created.state.today, isFalse);
    });

    test('DELETE /away/{id}', () async {
      final stub = StubAdapter()..on('DELETE /api/away/3', const StubResponse(204));
      await ApiClient(baseUrl: 'https://x.invalid', token: 't', adapter: stub).deleteAway(3);
      expect(stub.to('DELETE /api/away/3'), hasLength(1));
    });

    test('POST /streak/cover sends the date and answers with the freezes left', () async {
      final stub = StubAdapter();
      final left = await _client('cover_done', stub).coverStreak('2026-10-26');
      expect(stub.last!.data, _load('cover_done')['request']);
      expect((left.held, left.earnedTowardNext), (0, 4));
    });

    test('PATCH /me sends the schedule as one object', () async {
      final stub = StubAdapter()..on('PATCH /api/me', StubResponse(200, _load('me')['body']!));
      final client = ApiClient(baseUrl: 'https://x.invalid', token: 't', adapter: stub);
      await client.patchMe(
        const MePatch(
          schedule: Schedule(
            workdays: [1, 2, 3],
            workday: DayTimes(wake: 6 * 60, bed: 22 * 60 + 30),
            dayOff: DayTimes(wake: 8 * 60, bed: 23 * 60 + 30),
            firstNotificationOffsetMin: 30,
          ),
        ),
      );
      expect(stub.last!.data, {
        'schedule': {
          'workdays': [1, 2, 3],
          'workday': {'wake': '06:00', 'bed': '22:30'},
          'dayOff': {'wake': '08:00', 'bed': '23:30'},
          'firstNotificationOffsetMin': 30,
        },
      });
    });

    test('POST /logs sends a free-named activity with its intensity', () async {
      final stub = StubAdapter()..on('POST /api/logs', const StubResponse(500));
      final client = ApiClient(baseUrl: 'https://x.invalid', token: 't', adapter: stub);
      try {
        await client.createLog(
          const ActivityDraft.other(
            clientOpId: 'op-1',
            name: 'Swimming',
            minutes: 40,
            intensity: 'hard',
          ),
        );
      } on ApiException {
        // Only the request matters here.
      }
      expect(stub.last!.data, {
        'kind': 'activity',
        'clientOpId': 'op-1',
        'type': 'other',
        'quantity': 40,
        'unit': 'minutes',
        'name': 'Swimming',
        'intensity': 'hard',
      });
    });
  });

  group('failures are told apart by code', () {
    test('an overlapping away span', () async {
      final e = await _failure(
        'away_overlap',
        (c) => c.createAway(from: '2026-10-30', to: '2026-11-01'),
      );
      expect((e.statusCode, e.code), (409, 'away_overlap'));
    });

    test('a cover that is closed, and one with no freeze to spend', () async {
      final closed = await _failure('cover_closed', (c) => c.coverStreak('2026-10-26'));
      expect((closed.statusCode, closed.code), (422, 'cover_closed'));
      final none = await _failure('cover_no_freeze', (c) => c.coverStreak('2026-10-26'));
      expect((none.statusCode, none.code), (422, 'no_freeze'));
    });
  });
}
