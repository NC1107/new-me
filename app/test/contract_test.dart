import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:newme/api/api_client.dart';
import 'package:newme/api/models.dart';

import 'test_support.dart';

/// The wire contract with the real server. Every file in test/contract is an exchange recorded
/// from the server by tool/capture_contract.mjs, so a model or request that drifts from what the
/// server actually says fails here instead of on a phone.
class _Exchange {
  _Exchange(this.name, Json file)
    : method = file['method'] as String,
      uri = Uri.parse('https://x.invalid${file['path']}'),
      status = file['status'] as int,
      request = file['request'],
      body = file['body'] as Json;

  final String name;
  final String method;
  final Uri uri;
  final int status;
  final Object? request;
  final Json body;

  bool get succeeded => status < 300;
}

_Exchange _load(String name) {
  final file = File('test/contract/$name.json');
  return _Exchange(name, jsonDecode(file.readAsStringSync()) as Json);
}

/// What the app does with an exchange: send the recorded request and parse the answer back into
/// the JSON the models can reproduce.
typedef _Call = Future<Object?> Function(ApiClient client, _Exchange x);

Object? _tojson(Object? model) => switch (model) {
  final ServerInfo m => m.toJson(),
  final JoinResult m => m.toJson(),
  final InviteCheck m => m.toJson(),
  final Invite m => m.toJson(),
  final Me m => m.toJson(),
  final Today m => m.toJson(),
  final Board m => m.toJson(),
  final LogResult m => m.toJson(),
  final LogDeleteResult m => m.toJson(),
  final HealthDailyResult m => m.toJson(),
  final HealthTrend m => m.toJson(),
  _ => throw ArgumentError('no JSON for $model'),
};

LogDraft _draftOf(Json request) {
  final id = request['clientOpId'] as String;
  final date = request['date'] as String?;
  if (request['kind'] == 'meal') {
    return MealDraft(
      clientOpId: id,
      name: request['name'] as String,
      kcal: request['kcal'] as int,
      protein: request['protein'] as num,
      carbs: request['carbs'] as num,
      fat: request['fat'] as num,
      fiber: request['fiber'] as num,
      date: date,
    );
  }
  return ActivityDraft(
    clientOpId: id,
    type: request['type'] as String,
    quantity: request['quantity'] as int,
    unit: request['unit'] as String,
    date: date,
  );
}

List<HealthItem> _healthItemsOf(Json request) => [
  for (final item in (request['items'] as List).cast<Json>())
    HealthItem(
      date: item['date'] as String,
      metric: item['metric'] as String,
      value: (item['value'] as num).toDouble(),
      source: item['source'] as String,
      measuredAt: DateTime.parse(item['measuredAt'] as String),
    ),
];

MePatch _patchOf(Json request) {
  final targets = request['targets'] as Json? ?? const {};
  return MePatch(
    kcalTarget: targets['kcal'] as int?,
    proteinTarget: targets['protein'] as int?,
    carbsTarget: targets['carbs'] as int?,
    fatTarget: targets['fat'] as int?,
    questTemplates: [
      for (final q in (request['questTemplates'] as List? ?? const []).cast<Json>())
        QuestEdit(
          key: q['key'] as String,
          enabled: q['enabled'] as bool?,
          target: q['target'] as int?,
          targetAlt: q['targetAlt'] as int?,
        ),
    ],
  );
}

Json _request(_Exchange x) => x.request! as Json;

/// A list endpoint wrapped back into the server's object, so it compares with the recording.
Object? _logsAsJson(List<LogEntry> logs, _Exchange x) => {
  'date': x.body['date'],
  'logs': [for (final l in logs) l.toJson()],
};

final _calls = <String, _Call>{
  'server_info_fresh': (c, x) => c.serverInfo(),
  'server_info': (c, x) => c.serverInfo(),
  'join_first': (c, x) => c.join(
    JoinRequest.first(
      name: _request(x)['name'] as String,
      color: _request(x)['color'] as String,
      timezone: _request(x)['timezone'] as String,
    ),
  ),
  'join_member': (c, x) => c.join(
    JoinRequest.member(
      code: _request(x)['code'] as String,
      name: _request(x)['name'] as String,
      color: _request(x)['color'] as String,
      timezone: _request(x)['timezone'] as String,
    ),
  ),
  'join_repair': (c, x) => c.join(
    JoinRequest.repair(code: _request(x)['code'] as String, userId: _request(x)['userId'] as int),
  ),
  'invite_check_valid': (c, x) => c.checkInvite(_request(x)['code'] as String),
  'invite_check_invalid': (c, x) => c.checkInvite(_request(x)['code'] as String),
  'invite': (c, x) => c.createInvite(),
  'me': (c, x) => c.me(),
  'me_patched': (c, x) => c.patchMe(_patchOf(_request(x))),
  'today_fresh': (c, x) => c.today(),
  'today': (c, x) => c.today(),
  'board': (c, x) => c.board(),
  'log_pushups': (c, x) => c.createLog(_draftOf(_request(x))),
  'log_reading': (c, x) => c.createLog(_draftOf(_request(x))),
  'log_yoga': (c, x) => c.createLog(_draftOf(_request(x))),
  'log_meal': (c, x) => c.createLog(_draftOf(_request(x))),
  'log_meal_replay': (c, x) => c.createLog(_draftOf(_request(x))),
  'logs': (c, x) async => _logsAsJson(await c.logs(date: x.uri.queryParameters['date']!), x),
  'meals_recent': (c, x) async => {
    'meals': [for (final m in await c.recentMeals()) m.toJson()],
  },
  'log_deleted': (c, x) => c.deleteLog(
    // Only the id travels, so any entry with the recorded one is enough.
    ActivityLog(
      id: int.parse(x.uri.pathSegments.last),
      localDate: '',
      loggedAt: DateTime.utc(2026),
      type: 'pushups',
      quantity: 1,
      unit: 'reps',
    ),
  ),
  'health_daily': (c, x) => c.putHealthDaily(_healthItemsOf(_request(x))),
  'health_trends': (c, x) =>
      c.healthTrends(x.uri.queryParameters['metric']!, int.parse(x.uri.queryParameters['days']!)),
  'cheer_created': _sendCheer,
  'cheer_repeat': _sendCheer,
  'reward_created': (c, x) async => {
    'reward': (await c.createReward(
      name: _request(x)['name'] as String,
      price: _request(x)['price'] as int,
    )).toJson(),
  },
  'reward_claimed': (c, x) async => {
    'reward': (await c.claimReward(int.parse(x.uri.pathSegments[2]))).toJson(),
  },
  'rewards_empty': _rewards,
  'rewards_active': _rewards,
  'rewards_reached': _rewards,
  'push_put': (c, x) async {
    await c.putPushToken(_request(x)['token'] as String);
    return <String, dynamic>{};
  },
  'push_delete': (c, x) async {
    await c.deletePushToken();
    return <String, dynamic>{};
  },
};

Future<Object?> _sendCheer(ApiClient c, _Exchange x) async {
  final cheer = await c.sendCheer(
    to: _request(x)['to'] as int,
    kind: CheerKind.parse(_request(x)['kind'])!,
  );
  return {'cheer': cheer.toJson(), 'to': _request(x)['to']};
}

Future<Object?> _rewards(ApiClient c, _Exchange x) async {
  final list = await c.rewards();
  return {
    'reward': list.active?.toJson(),
    'history': [for (final r in list.history) r.toJson()],
  };
}

/// Recordings of failures, with what the app must make of each.
final _failures = <String, void Function(ApiException e)>{
  'log_closed': (e) =>
      expect((e.kind, e.statusCode, e.code), (ApiErrorKind.dateClosed, 422, 'date_closed')),
  'health_daily_closed': (e) =>
      expect((e.kind, e.statusCode, e.code), (ApiErrorKind.dateClosed, 422, 'date_closed')),
  'error_bad_app_key': (e) =>
      expect((e.kind, e.statusCode, e.code), (ApiErrorKind.badAppKey, 403, 'bad_app_key')),
  'error_unauthorized': (e) =>
      expect((e.kind, e.statusCode, e.code), (ApiErrorKind.other, 401, 'unauthorized')),
  'error_update_required': (e) => expect(
    (e.kind, e.statusCode, e.minClientVersion),
    (ApiErrorKind.updateRequired, 426, '9.0.0'),
  ),
  'error_invalid_json': (e) =>
      expect((e.kind, e.statusCode, e.code), (ApiErrorKind.other, 400, 'invalid_json')),
  'cheer_invalid': (e) =>
      expect((e.kind, e.statusCode, e.code), (ApiErrorKind.other, 422, 'invalid_request')),
  'reward_active': (e) =>
      expect((e.kind, e.statusCode, e.code), (ApiErrorKind.other, 409, 'reward_active')),
  'reward_claim_early': (e) =>
      expect((e.kind, e.statusCode, e.code), (ApiErrorKind.other, 409, 'reward_not_reached')),
};

/// The call that provoked each recorded failure.
final _failingCalls = <String, _Call>{
  'log_closed': (c, x) => c.createLog(_draftOf(_request(x))),
  'health_daily_closed': (c, x) => c.putHealthDaily(_healthItemsOf(_request(x))),
  'error_bad_app_key': (c, x) => c.serverInfo(),
  'error_unauthorized': (c, x) => c.me(),
  'error_update_required': (c, x) => c.me(),
  'error_invalid_json': (c, x) => c.patchMe(const MePatch()),
  'cheer_invalid': (c, x) =>
      c.sendCheer(to: _request(x)['to'] as int, kind: CheerKind.parse(_request(x)['kind'])!),
  'reward_active': (c, x) =>
      c.createReward(name: _request(x)['name'] as String, price: _request(x)['target'] as int),
  'reward_claim_early': (c, x) => c.claimReward(int.parse(x.uri.pathSegments[2])),
};

/// The v13 reward fields the recordings predate (rewards were a single points goal then); the
/// models still read the old shape, and rewards_v13_test.dart checks the new one.
const _v13Keys = {
  'price',
  'status',
  'focus',
  'ready',
  'proposedBy',
  'proposedByName',
  'rewards',
  'bank',
  'priceHelp',
};

/// The v6 fields the recordings predate. contract_v6_test.dart checks them against hand-checked
/// exchanges, so this file compares everything else exactly.
const _v6Keys = {
  'doneBy',
  'readiness',
  'plan',
  'features',
  'behindPace',
  'closeToDone',
  'windDown',
  'morningPlan',
  'weeklyRecap',
};

Object? _withoutV6(Object? json) => switch (json) {
  final Map<String, dynamic> m => {
    for (final e in m.entries)
      if (!_v6Keys.contains(e.key) &&
          !_v13Keys.contains(e.key) &&
          !(e.key == 'syncedAt' && m.containsKey('minutes')))
        e.key: _withoutV6(e.value),
  },
  final List<dynamic> l => [for (final v in l) _withoutV6(v)],
  _ => json,
};

Object? _normalized(Object? json) => canonicalInstants(_withoutV6(json));

void main() {
  final names = Directory('test/contract')
      .listSync()
      .whereType<File>()
      .map((f) => f.uri.pathSegments.last.replaceAll('.json', ''))
      .toSet();

  test('every recording is exercised, and every exercise has a recording', () {
    expect(names, {..._calls.keys, ..._failures.keys});
    expect(_failures.keys.toSet(), _failingCalls.keys.toSet());
  });

  group('the app sends what the server accepted and parses what it answered', () {
    for (final entry in _calls.entries) {
      test(entry.key, () async {
        final x = _load(entry.key);
        expect(x.succeeded, isTrue, reason: 'a success recording');
        final stub = StubAdapter()..on('${x.method} ${x.uri.path}', StubResponse(x.status, x.body));
        final client = ApiClient(baseUrl: 'https://x.invalid', token: 't', adapter: stub);

        final result = await entry.value(client, x);

        final sent = stub.requests.single;
        expect((sent.method, sent.path), (x.method, x.uri.path));
        expect(
          sent.queryParameters.map((k, v) => MapEntry(k, '$v')),
          x.uri.queryParameters,
          reason: 'query string',
        );
        expect(sent.data, x.request, reason: 'request body');

        final json = result is Json ? result : _tojson(result);
        expect(
          _normalized(json),
          _normalized(x.body),
          reason: 'parsed answer re-encodes to the wire',
        );
      });
    }
  });

  group('failures are told apart by status and code', () {
    for (final entry in _failures.entries) {
      test(entry.key, () async {
        final x = _load(entry.key);
        final stub = StubAdapter()..on('${x.method} ${x.uri.path}', StubResponse(x.status, x.body));
        final client = ApiClient(baseUrl: 'https://x.invalid', adapter: stub);

        final e = await _failingCalls[entry.key]!(
          client,
          x,
        ).then<ApiException?>((_) => null, onError: (Object e) => e as ApiException);

        expect(e, isNotNull, reason: 'the server refused it');
        entry.value(e!);
        if (e.kind == ApiErrorKind.other || e.kind == ApiErrorKind.dateClosed) {
          expect(e.message, x.body['error'], reason: 'the server wording reaches the UI');
        }
      });
    }
  });

  group('values land where the screens read them', () {
    test('the first admin join and a valid code', () {
      final join = JoinResult.fromJson(_load('join_first').body);
      expect(
        (join.user.name, join.user.timezone, join.user.isAdmin),
        ('Nick', 'America/New_York', true),
      );
      expect(join.token, isNotEmpty);

      final check = InviteCheck.fromJson(_load('invite_check_valid').body);
      expect((check.valid, check.canJoinNew), (true, true));
      expect(check.users.map((u) => u.name), ['Nick']);
      final invalid = InviteCheck.fromJson(_load('invite_check_invalid').body);
      expect((invalid.valid, invalid.canJoinNew), (false, false));
      expect(invalid.users, isEmpty);
    });

    test('server info before and after the first join', () {
      expect(ServerInfo.fromJson(_load('server_info_fresh').body).initialized, isFalse);
      final info = ServerInfo.fromJson(_load('server_info').body);
      expect((info.initialized, info.joinOpen, info.minClientVersion), (true, true, '0.0.0'));
    });

    test('me carries the profile, goals and every quest template', () {
      final me = Me.fromJson(_load('me_patched').body);
      expect((me.user.name, me.user.isAdmin), ('Nick', true));
      expect(
        (me.targets.kcal, me.targets.protein, me.targets.carbs, me.targets.fat),
        (2200, 150, 220, 70),
      );
      expect(me.targets.complete, isTrue);
      expect(Me.fromJson(_load('me').body).targets.complete, isFalse);
      final reading = me.questTemplates.firstWhere((q) => q.key == 'reading');
      expect(
        (reading.target, reading.targetAlt, reading.unitAlt, reading.position),
        (20, 15, 'pages', 2),
      );
      final yoga = me.questTemplates.firstWhere((q) => q.key == 'yoga');
      expect((yoga.enabled, yoga.target), (true, 15));
      expect(
        Me.fromJson(_load('me').body).questTemplates.firstWhere((q) => q.key == 'yoga').enabled,
        isFalse,
      );
      expect(me.localToday, matches(RegExp(r'^\d{4}-\d{2}-\d{2}$')));
    });

    test('today scores the day, the quests, the food and the health state', () {
      final today = Today.fromJson(_load('today').body);
      expect(today.date, today.localToday);
      expect(
        (today.day.basePoints, today.day.bonusPoints, today.day.points, today.day.maxBase),
        (347, 30, 377, 450),
      );
      expect((today.day.percent, today.day.counted, today.day.streakLine), (77, true, 70));
      final pushups = today.quests.firstWhere((q) => q.key == 'pushups');
      expect(
        (pushups.points, pushups.basePoints, pushups.bonusPoints, pushups.done, pushups.actual),
        (100, 100, 20, true, 45),
      );
      final reading = today.quests.firstWhere((q) => q.key == 'reading');
      expect((reading.unitAlt, reading.targetAlt, reading.actualAlt), ('pages', 15, 12));
      expect(
        (today.streak.current, today.streak.restAvailable, today.streak.restUsedOn),
        (1, true, null),
      );
      expect(
        (today.food.kcal, today.food.protein, today.food.fiber, today.food.burned),
        (650, 42.5, 7, 410),
      );
      expect((today.food.targets.kcal, today.food.targets.fat), (2200, 70));
      expect(today.health.stepsEverSynced, isTrue);
      expect(today.health.syncedAt, isNotNull);
      expect(Today.fromJson(_load('today_fresh').body).health.stepsEverSynced, isFalse);
    });

    test('the board nests points and streaks and lists the caller first', () {
      final board = Board.fromJson(_load('board').body);
      expect(board.season.name, 'Season 0');
      expect(board.users.map((u) => u.name), ['Nick', 'Sam']);
      final nick = board.users.first;
      expect(
        (nick.today.points, nick.today.percent, nick.today.counted, nick.streak),
        (377, 77, true, 1),
      );
      expect(nick.last7, hasLength(7));
      expect(nick.syncedAt, isNotNull);
      expect((nick.last7.last.counted, nick.last7.last.rest), (true, false));
      expect(board.users.last.syncedAt, isNull);
    });

    test('week, season and streak counters read the nested objects', () {
      final json = _load('board').body;
      final user = (json['users'] as List).first as Json;
      user['week'] = {'points': 310};
      user['season'] = {'points': 905};
      user['streak'] = {'current': 6};
      final parsed = Board.fromJson(json).users.first;
      expect((parsed.week, parsed.season, parsed.streak), (310, 905, 6));
      expect(_normalized(parsed.toJson()), _normalized(user));
    });

    test('a write answers with the stored log and the recomputed day', () {
      final pushups = LogResult.fromJson(_load('log_pushups').body);
      expect(pushups.log, isA<ActivityLog>());
      final activity = pushups.log as ActivityLog;
      expect((activity.type, activity.unit, activity.quantity), ('pushups', 'reps', 45));
      expect(
        (pushups.day.date, pushups.day.score.points, pushups.day.score.maxBase),
        (activity.localDate, 120, 350),
      );
      expect(pushups.day.quests.map((q) => q.key), contains('pushups'));

      final reading = LogResult.fromJson(_load('log_reading').body).log as ActivityLog;
      expect((reading.type, reading.unit, reading.quantity), ('reading', 'pages', 12));

      final meal = LogResult.fromJson(_load('log_meal').body).log as MealLog;
      expect(
        (meal.name, meal.kcal, meal.protein, meal.carbs, meal.fat, meal.fiber),
        ('Chicken bowl', 650, 42.5, 60, 18, 7),
      );
      expect(_load('log_meal').status, 201);
      expect(_load('log_meal_replay').status, 200);
      expect(LogResult.fromJson(_load('log_meal_replay').body).log.id, meal.id);
    });

    test('the day list, recent meals and a delete', () {
      final logs = [
        for (final j in (_load('logs').body['logs'] as List).cast<Json>()) LogEntry.fromJson(j),
      ];
      expect(logs.map((l) => l.kind), ['activity', 'activity', 'activity', 'meal', 'meal']);

      final meals = [
        for (final j in (_load('meals_recent').body['meals'] as List).cast<Json>())
          RecentMeal.fromJson(j),
      ];
      expect((meals.first.name, meals.first.protein, meals.first.fiber), ('Oats', 10, 8));

      final deleted = LogDeleteResult.fromJson(_load('log_deleted').body);
      expect((deleted.day.score.points, deleted.day.score.percent), (299, 76));
      expect(deleted.day.quests.firstWhere((q) => q.key == 'meals_logged').actual, 1);
    });

    test('a health push returns one scored day per affected date', () {
      final result = HealthDailyResult.fromJson(_load('health_daily').body);
      final day = result.days.single;
      expect(
        (day.score.points, day.quests.firstWhere((q) => q.key == 'steps').actual),
        (377, 6200),
      );
    });

    test('an invite comes with its expiry', () {
      final invite = Invite.fromJson(_load('invite').body);
      expect(invite.code, matches(RegExp(r'^[A-Z0-9]{4}(-[A-Z0-9]{4}){3}$')));
      expect(invite.expiresAt.isAfter(DateTime.utc(2026)), isTrue);
    });
  });

  test('the old flat PATCH /me body that the server rejects is no longer built', () {
    final rejected = _load('error_invalid_json').request;
    expect(const MePatch(kcalTarget: 2000).toJson(), isNot(rejected));
    expect(const MePatch(kcalTarget: 2000).toJson(), {
      'targets': {'kcal': 2000},
    });
  });
}
