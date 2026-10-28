import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:newme/api/api_client.dart';
import 'package:newme/api/models.dart';
import 'package:newme/companion/companion_bridge.dart';
import 'package:newme/companion/companion_snapshot.dart';
import 'package:newme/state/companion.dart';
import 'package:newme/state/habit_marks.dart';
import 'package:newme/state/session.dart';
import 'package:newme/state/today.dart';

import 'habit_fixtures.dart';
import 'test_support.dart';

Map<String, dynamic> _todayWithHabits() => todayJson()..['habits'] = dueHabits();

void main() {
  group('companionSnapshot', () {
    test('carries the score, the session and one entry per tappable habit', () {
      final today = Today.fromJson(_todayWithHabits());

      final snapshot = companionSnapshot(
        session: testSession,
        today: today,
        appKey: 'key',
        clientVersion: '1.2.3',
      );

      expect(snapshot['version'], kCompanionSnapshotVersion);
      expect(snapshot['date'], '2026-10-26');
      expect(snapshot['points'], 120);
      expect(snapshot['percent'], 35);
      expect(snapshot['streakLine'], 100);
      expect(snapshot['streak'], 3);
      expect(snapshot['accent'], {'fill': '#7B6CD9', 'tint': '#EEEBFA'});
      expect(snapshot['quests'], [
        {'key': 'steps', 'title': 'Steps', 'done': false},
      ]);
      expect(snapshot['session'], {
        'baseUrl': 'https://me.invalid',
        'token': 'tok',
        'appKey': 'key',
        'clientVersion': '1.2.3',
      });
      final habits = (snapshot['habits']! as List).cast<Map<String, Object?>>();
      expect(habits.map((h) => '${h['habitId']}:${h['slot']}'), [
        '1:0',
        '1:1',
        '2:0',
        '3:0',
        '4:null',
      ]);
      expect(habits.first, {
        'habitId': 1,
        'slot': 0,
        'name': 'Brush teeth',
        'label': 'Morning',
        'icon': 'brush',
        'done': false,
        'count': 0,
        'target': null,
        'time': '07:30',
      });
      expect(habits.last, {
        'habitId': 4,
        'slot': null,
        'name': 'Water',
        'label': '',
        'icon': 'water_drop',
        'done': false,
        'count': 0,
        'target': 8,
        'time': null,
      });
    });

    test('a count habit at its target is done', () {
      final json = todayJson()..['habits'] = [countState(4, 'Water', target: 8, count: 8)];

      final snapshot = companionSnapshot(session: testSession, today: Today.fromJson(json));

      expect((snapshot['habits']! as List).single, containsPair('done', true));
      expect(
        (snapshot['session']! as Map)['appKey'],
        kAppKey,
        reason: 'the build key is the default',
      );
    });
  });

  group('CompanionController', () {
    final calls = <MethodCall>[];

    setUp(() {
      FakeStorage().install();
      calls.clear();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
        kCompanionChannel,
        (call) async {
          calls.add(call);
          return null;
        },
      );
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
        kCompanionChannel,
        null,
      );
    });

    StubAdapter server() => StubAdapter()
      ..on('GET /api/today', StubResponse(200, _todayWithHabits()))
      ..on(
        'PUT /api/habits/1/marks/2026-10-26',
        StubResponse(
          200,
          markResponse([
            checkState(1, 'Brush teeth', 'brush', [
              stateSlot(0, 'Morning', '07:30', done: true),
              stateSlot(1, 'Evening', '22:00'),
            ]),
          ]),
        ),
      )
      ..on('DELETE /api/devices/me', const StubResponse(200, {}))
      ..on('DELETE /api/devices/me/push', const StubResponse(200, {}));

    Future<ProviderContainer> boot() async {
      final c = testContainer(
        overrides: [
          sessionProvider.overrideWith(() => SessionController.seeded(testSession)),
          apiClientFactoryProvider.overrideWithValue(stubFactory(server())),
        ],
      );
      c.read(companionProvider);
      await c.read(todayProvider.future);
      await pumpEventQueue();
      return c;
    }

    List<Map<String, dynamic>> updates() => [
      for (final call in calls)
        if (call.method == 'update') jsonDecode(call.arguments as String) as Map<String, dynamic>,
    ];

    test('writes the snapshot once Today has loaded', () async {
      await boot();

      expect(updates(), hasLength(1));
      expect(updates().single['date'], '2026-10-26');
      expect((updates().single['session'] as Map)['token'], 'tok');
    });

    test('a marked habit writes a new snapshot, an unchanged Today does not', () async {
      final c = await boot();
      calls.clear();

      await c.read(habitMarksProvider).setSlot(1, 0, done: true);
      await pumpEventQueue();

      final habits = (updates().first['habits'] as List).cast<Map<String, dynamic>>();
      expect(habits.first['done'], true);
      final sent = updates().length;

      await c.read(todayProvider.notifier).replace(c.read(todayProvider).value!.data);
      await pumpEventQueue();

      expect(updates(), hasLength(sent));
    });

    test('signing out clears the widgets and the Watch', () async {
      final c = await boot();
      calls.clear();

      await c.read(sessionProvider.notifier).signOut();
      await pumpEventQueue();

      expect(calls.map((m) => m.method), contains('clear'));
      expect(updates(), isEmpty);
    });

    test('a missing native plugin is not an error', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
        kCompanionChannel,
        null,
      );
      const bridge = CompanionBridge();

      await bridge.update('{}');
      await bridge.clear();
    });
  });
}
