import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:newme/api/api_client.dart';
import 'package:newme/api/models.dart';
import 'package:newme/features/me/targets_logic.dart';
import 'package:newme/health/health_math.dart';
import 'package:newme/health/fake_health_source.dart';
import 'package:newme/health/health_source.dart';

import 'fixtures.dart';
import 'test_support.dart';

/// The v8 wire shapes. The files in test/contract_v8 are hand-checked against
/// server/internal/api/targets.go and docs/design.md (Endpoints, v8 additions).
Map<String, dynamic> _load(String name) =>
    jsonDecode(File('test/contract_v8/$name.json').readAsStringSync()) as Map<String, dynamic>;

/// The models keep a null a server sends explicitly, so a round trip compares without them.
Object? _withoutNulls(Object? json) => switch (json) {
  final Map<String, dynamic> m => {
    for (final e in m.entries)
      if (e.value != null) e.key: _withoutNulls(e.value),
  },
  final List<dynamic> l => [for (final v in l) _withoutNulls(v)],
  _ => json,
};

ApiClient _client(StubAdapter stub, String name) {
  final x = _load(name);
  stub.on('${x['method']} ${x['path']}', StubResponse(x['status'] as int, x['body'] as Object));
  return ApiClient(baseUrl: 'https://x.invalid', token: 't', adapter: stub);
}

void main() {
  group('TargetsReport', () {
    test('GET /targets parses every part and round-trips to the wire', () async {
      final report = await _client(StubAdapter(), 'targets').targets();
      expect(report.asOf, '2026-10-27');
      expect(report.disclaimer, 'This is general guidance, not medical advice.');
      expect(report.targets, hasLength(13));
      expect(report.inputs.map((i) => i.key), [
        'weightKg',
        'heightCm',
        'age',
        'sex',
        'goal',
        'steps14',
      ]);
      expect(
        _withoutNulls(jsonDecode(jsonEncode(report.toJson()))),
        _withoutNulls(_load('targets')['body']),
      );

      final calories = report.target('calories')!;
      expect(calories.value, 2350);
      expect(calories.current, 2200);
      expect(calories.label, TargetLabel.derivation);
      expect(calories.applicable, isTrue);
      expect(calories.canUse, isTrue);
      expect(calories.sources, ['hall2011', 'helms2014', 'jensen2014']);
      expect(report.citation('hall2011'), contains('Lancet 2011;378:826'));
      expect(report.target('maintenance')!.label, TargetLabel.convention);
      expect(report.target('restingEnergy')!.applicable, isFalse);
      expect(report.target('steps')!.details['incrementSteps'], 1000);
      expect(report.input('heightCm')!.source, 'health');
    });

    test('a target equal to its setting, or with no value, cannot be used', () {
      final same = Target.tryParse({
        'key': 'fat',
        'value': 70,
        'current': 70,
        'unit': 'g',
        'applicable': true,
      })!;
      expect(same.isApplied, isTrue);
      expect(same.canUse, isFalse);
      final empty = Target.tryParse({'key': 'fat', 'value': null, 'applicable': true})!;
      expect(empty.canUse, isFalse);
      final readOnly = Target.tryParse({'key': 'fiber', 'value': 30, 'applicable': false})!;
      expect(readOnly.canUse, isFalse);
    });

    test('missing inputs and a null value parse, and the goal is not a missing input', () {
      final report = TargetsReport.parse(_load('targets_missing')['body']);
      expect(report.missingInputs.map((i) => i.key), ['heightCm', 'sex']);
      expect(report.target('calories')!.value, isNull);
      expect(report.target('calories')!.missing, ['heightCm', 'sex']);
      expect(report.target('pushups')!.missing, ['pushupMax']);
    });

    test('parsing tolerates an older server, junk and unknown labels', () {
      expect(TargetsReport.parse(null).targets, isEmpty);
      expect(TargetsReport.parse('x').disclaimer, '');
      final report = TargetsReport.parse({
        'targets': [
          {
            'key': 'fat',
            'value': 'n/a',
            'label': 'brand-new',
            'sources': [1, 'a'],
            'missing': 3,
          },
          'junk',
          {'value': 3},
        ],
        'inputs': [
          {'key': 'sex', 'value': 'female', 'source': 'profile'},
          5,
        ],
        'sources': {'a': 'A citation', 'b': 4},
      });
      expect(report.targets.single.value, isNull);
      expect(report.targets.single.label, TargetLabel.derivation);
      expect(report.targets.single.sources, ['a']);
      expect(report.targets.single.missing, isEmpty);
      expect(report.inputs.single.value, 'female');
      expect(report.sources, {'a': 'A citation'});
      expect(report.citation('zzz'), 'zzz');
    });
  });

  group('profile fields', () {
    test('the user carries height, sex and goal, and older servers leave them null', () {
      final user = AccountUser.fromJson({
        'id': 1,
        'name': 'Nick',
        'color': 'green',
        'timezone': 'UTC',
        'isAdmin': true,
        'heightCm': 180.5,
        'sex': 'male',
        'goal': {'kind': 'gain', 'paceKgPerWeek': 0.25},
      });
      expect(user.heightCm, 180.5);
      expect(user.sex, 'male');
      expect(user.goalSetting, const GoalSetting(kind: GoalKind.gain, paceKgPerWeek: 0.25));
      expect(user.toJson()['goal'], {'kind': 'gain', 'paceKgPerWeek': 0.25});

      final old = AccountUser.fromJson({
        'id': 1,
        'name': 'N',
        'color': 'green',
        'timezone': 'UTC',
        'isAdmin': false,
        'heightCm': null,
        'sex': null,
      });
      expect(old.heightCm, isNull);
      expect(old.goal, isNull);
      expect(old.goalSetting.kind, GoalKind.maintain);
      expect(old.toJson().containsKey('goal'), isFalse);
    });

    test('a goal from the future still reads as maintain, with no pace', () {
      final g = GoalSetting.parse({'kind': 'recomp', 'paceKgPerWeek': 1});
      expect(g.kind, GoalKind.maintain);
      expect(g.paceKgPerWeek, 0);
    });

    test('MePatch sends height, sex and the goal, null to clear, and nothing by default', () {
      expect(const MePatch(heightCm: 181.5).toJson(), {'heightCm': 181.5});
      expect(const MePatch(clearHeight: true).toJson(), {'heightCm': null});
      expect(const MePatch(sex: 'female').toJson(), {'sex': 'female'});
      expect(const MePatch(clearSex: true).toJson(), {'sex': null});
      expect(const MePatch(goal: GoalSetting(kind: GoalKind.lose, paceKgPerWeek: 0.5)).toJson(), {
        'goal': {'kind': 'lose', 'paceKgPerWeek': 0.5},
      });
      expect(const MePatch(name: 'A').toJson(), {'name': 'A'});
    });
  });

  group('ApiClient', () {
    test('POST /targets/apply sends the keys and reads the refreshed profile', () async {
      final stub = StubAdapter()
        ..on(
          'POST /api/targets/apply',
          StubResponse(200, {
            ...meJson(),
            'applied': ['calories', 'protein'],
          }),
        );
      final client = ApiClient(baseUrl: 'https://x.invalid', token: 't', adapter: stub);
      final result = await client.applyTargets(['calories', 'protein']);
      expect(result.applied, ['calories', 'protein']);
      expect(result.me.targets.kcal, 2200);
      expect(stub.to('POST /api/targets/apply').single.data, {
        'keys': ['calories', 'protein'],
      });
    });

    test('a rejected apply surfaces the server message', () async {
      final stub = StubAdapter()
        ..on(
          'POST /api/targets/apply',
          const StubResponse(422, {'error': 'steps has no value yet: steps14 missing'}),
        );
      final client = ApiClient(baseUrl: 'https://x.invalid', token: 't', adapter: stub);
      await expectLater(
        client.applyTargets(['steps']),
        throwsA(isA<ApiException>().having((e) => e.message, 'message', contains('no value yet'))),
      );
    });

    test('POST /pushups/max sends reps and an optional date', () async {
      final stub = StubAdapter();
      final client = _client(stub, 'pushups_max');
      final result = await client.recordPushupMax(reps: 24);
      expect((result.date, result.reps), ('2026-10-27', 24));
      expect(stub.to('POST /api/pushups/max').single.data, {'reps': 24});
      await client.recordPushupMax(reps: 20, date: '2026-10-26');
      expect(stub.to('POST /api/pushups/max').last.data, {'reps': 20, 'date': '2026-10-26'});
    });
  });

  group('targets logic', () {
    final full = TargetsReport.parse(_load('targets')['body']);
    final missing = TargetsReport.parse(_load('targets_missing')['body']);

    test('values read with their unit, and sleep reads as hours', () {
      expect(formatTargetValue(2350, 'kcal'), '2,350 kcal');
      expect(formatTargetValue(450, 'min'), '7 h 30 min');
      expect(formatTargetValue(150, 'min a week'), '150 min a week');
      expect(formatTargetValue(7000, ''), '7,000');
    });

    test('missing inputs list once each, in the order they are needed', () {
      expect(missingItems(full), isEmpty);
      expect(missingItems(missing).map((m) => m.key), ['heightCm', 'sex', 'pushupMax']);
      expect(missingItems(missing).map((m) => m.fix), [
        FixAt.profile,
        FixAt.profile,
        FixAt.pushupMax,
      ]);
    });

    test('Use all covers the targets that have a value that is not already the setting', () {
      expect(usable(full).map((t) => t.key), [
        'calories',
        'protein',
        'fat',
        'carbs',
        'sleep',
        'steps',
        'pushups',
      ]);
      expect(usable(missing).map((t) => t.key), ['protein', 'sleep', 'steps']);
    });

    test('the toast names what starts tomorrow', () {
      final applied = [full.target('calories')!, full.target('sleep')!];
      expect(appliedToast(applied), 'Starts tomorrow: Calories 2,350 kcal, Sleep 7 h 30 min');
      expect(appliedToast(const []), 'Nothing to change');
    });

    test('detail lines carry the sleep extras and the push-up max', () {
      expect(detailLines(full.target('sleep')!), [
        'Bedtime 11:15 PM (11:45 PM on days off)',
        'Last 7 nights: 5 h short of your target',
        'Information only; catch-up sleep has weak evidence, so there is no recovery plan.',
        'Sleep Regularity Index 82 of 100',
        'Keep sleep and wake times regular; there is no threshold.',
        contains('Phillips 2017'),
      ]);
      expect(detailLines(full.target('pushups')!), [
        'Latest max test: 24 reps (70 to 80% is 17 to 19)',
        'Retest every 2 to 4 weeks',
      ]);
      expect(detailLines(full.target('protein')!), [
        'About 0.4 g/kg a meal, 33 g, across 4 meals.',
      ]);
    });
  });

  group('Health height', () {
    test('HealthKit metres become centimetres inside the server range', () {
      expect(heightCm(1.8), closeTo(180, 1e-9));
      expect(heightCm(1.0), 100);
      expect(heightCm(2.5), 250);
      expect(heightCm(0.9), isNull);
      expect(heightCm(18), isNull);
    });

    test('the fake source answers 180 cm and the metric is one the app syncs', () async {
      final totals = await FakeHealthSource().totals(
        DateTime(2026, 10, 27),
        DateTime(2026, 10, 27, 9),
      );
      expect(totals![HealthMetric.heightCm], 180);
      expect(HealthMetric.all, contains('height_cm'));
    });
  });
}
