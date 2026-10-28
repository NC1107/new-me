import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart' show CustomSemanticsAction;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:newme/api/api_client.dart';
import 'package:newme/companion/companion_bridge.dart';
import 'package:newme/companion/companion_snapshot.dart';
import 'package:newme/api/models.dart';
import 'package:newme/features/log/log_kind.dart';
import 'package:newme/features/log/log_sheet.dart';
import 'package:newme/features/shell/home_shell.dart';
import 'package:newme/features/training/exercises_page.dart';
import 'package:newme/features/training/eased_note.dart';
import 'package:newme/state/log_actions.dart';
import 'package:newme/widgets/chunky_button.dart';
import 'package:newme/widgets/mascot.dart';
import 'package:newme/health/fake_health_source.dart';
import 'package:newme/health/health_source_factory.dart';
import 'package:newme/state/caches.dart';
import 'package:newme/state/clock.dart';
import 'package:newme/state/companion.dart';
import 'package:newme/state/habit_marks.dart';
import 'package:newme/state/health_history.dart';
import 'package:newme/state/health_sync.dart';
import 'package:newme/reminders/reminder_scheduler.dart';
import 'package:newme/state/local_prefs.dart';
import 'package:newme/state/session.dart';
import 'package:newme/state/today.dart';

import 'fake_reminder_scheduler.dart';
import 'fixtures.dart';
import 'habit_fixtures.dart';
import 'test_support.dart';

ProviderContainer _container(StubAdapter adapter, {Session session = testSession}) => testContainer(
  overrides: [
    sessionProvider.overrideWith(() => SessionController.seeded(session)),
    apiClientFactoryProvider.overrideWithValue(stubFactory(adapter)),
  ],
);

void main() {
  setUp(FakeStorage().install);

  group('CachedNotifier', () {
    test('an older response never overwrites a newer one', () async {
      var calls = 0;
      final slow = Completer<void>();
      final adapter = StubAdapter({
        'GET /api/today': (_) async {
          final n = ++calls;
          if (n == 2) await slow.future;
          return StubResponse(200, todayJson(points: n == 2 ? 100 : 200));
        },
      });
      final c = _container(adapter);
      await c.read(todayProvider.future);

      final older = c.read(todayProvider.notifier).refresh();
      await pumpEventQueue();
      await c.read(todayProvider.notifier).refresh();
      expect(c.read(todayProvider).requireValue.data.day.points, 200);

      slow.complete();
      await older;
      expect(c.read(todayProvider).requireValue.data.day.points, 200);
    });

    test('a replace made while a refresh is in flight wins over the refresh', () async {
      final slow = Completer<void>();
      var calls = 0;
      final adapter = StubAdapter({
        'GET /api/today': (_) async {
          if (++calls == 2) await slow.future;
          return StubResponse(200, todayJson(points: 100));
        },
      });
      final c = _container(adapter);
      final notifier = c.read(todayProvider.notifier);
      await c.read(todayProvider.future);

      final refresh = notifier.refresh();
      await pumpEventQueue();
      await notifier.replace(Today.fromJson(todayJson(points: 999)));
      slow.complete();
      await refresh;

      expect(c.read(todayProvider).requireValue.data.day.points, 999);
    });

    test('a refresh that loses to a replace leaves the newer value in the offline cache', () async {
      final slow = Completer<void>();
      var calls = 0;
      final adapter = StubAdapter({
        'GET /api/today': (_) async {
          if (++calls == 2) await slow.future;
          return StubResponse(200, todayJson(points: 100));
        },
      });
      final c = _container(adapter);
      final notifier = c.read(todayProvider.notifier);
      await c.read(todayProvider.future);

      final refresh = notifier.refresh();
      await pumpEventQueue();
      await notifier.replace(Today.fromJson(todayJson(points: 999)));
      slow.complete();
      await refresh;

      final stored = await todayCache.read(
        userId: testSession.userId,
        baseUrl: testSession.baseUrl,
      );
      expect(stored!.data.day.points, 999);
    });

    test('a response that arrives after dispose writes nothing and throws nothing', () async {
      final slow = Completer<void>();
      var calls = 0;
      final adapter = StubAdapter({
        'GET /api/today': (_) async {
          if (++calls == 2) await slow.future;
          return StubResponse(200, todayJson());
        },
      });
      final c = ProviderContainer(
        retry: (_, _) => null,
        overrides: [
          sessionProvider.overrideWith(() => SessionController.seeded(testSession)),
          apiClientFactoryProvider.overrideWithValue(stubFactory(adapter)),
        ],
      );
      await c.read(todayProvider.future);
      final refresh = c.read(todayProvider.notifier).refresh();
      await pumpEventQueue();

      c.dispose();
      slow.complete();
      await refresh;
    });

    test('a response that lands after sign-out is not written to the cache', () async {
      final slow = Completer<void>();
      var calls = 0;
      final adapter = StubAdapter({
        'GET /api/today': (_) async {
          if (++calls == 2) await slow.future;
          return StubResponse(200, todayJson(points: 321));
        },
        'DELETE /api/devices/me': (_) => const StubResponse(200),
        'DELETE /api/devices/me/push': (_) => const StubResponse(200),
      });
      final c = _container(adapter);
      await c.read(todayProvider.future);
      final refresh = c.read(todayProvider.notifier).refresh();
      await pumpEventQueue();

      await c.read(sessionProvider.notifier).signOut();
      slow.complete();
      await refresh;
      await pumpEventQueue();

      expect(await todayCache.read(userId: 2, baseUrl: testSession.baseUrl), isNull);
    });
  });

  group('HabitMarks', () {
    Map<String, dynamic> countAnswer(int count, int points) => {
      ...markResponse([countState(4, 'Water', count: count)], points: points),
    };

    test('the day and quests come only from the newest request', () async {
      final slow = Completer<void>();
      final adapter = StubAdapter({
        'GET /api/today': (_) =>
            StubResponse(200, todayJson()..['habits'] = [countState(4, 'Water')]),
        'GET /api/board': (_) => StubResponse(200, boardJson()),
        'PUT /api/habits/4/marks/2026-10-26': (req) async {
          final count = (req.data as Map)['count'] as int;
          if (count == 1) {
            await slow.future;
            return StubResponse(200, countAnswer(1, 111));
          }
          return StubResponse(200, countAnswer(2, 222));
        },
      });
      final c = _container(adapter);
      await c.read(todayProvider.future);
      final marks = c.read(habitMarksProvider);

      final older = marks.setCount(4, 1);
      await pumpEventQueue();
      expect(await marks.setCount(4, 2), isTrue);
      slow.complete();
      expect(await older, isTrue);

      final today = c.read(todayProvider).requireValue.data;
      expect(today.day.points, 222, reason: 'the older answer must not rescore the day');
    });

    test('when the newest mark fails after an older one succeeded, Today is reloaded', () async {
      final first = Completer<void>();
      final second = Completer<void>();
      var todayGets = 0;
      final adapter = StubAdapter({
        'GET /api/today': (_) {
          todayGets++;
          return StubResponse(200, todayJson()..['habits'] = [countState(4, 'Water')]);
        },
        'GET /api/board': (_) => StubResponse(200, boardJson()),
        'PUT /api/habits/4/marks/2026-10-26': (req) async {
          if ((req.data as Map)['count'] == 1) {
            await first.future;
            return StubResponse(200, countAnswer(1, 111));
          }
          await second.future;
          return const StubResponse(422, {'error': 'no'});
        },
      });
      final c = _container(adapter);
      await c.read(todayProvider.future);
      final marks = c.read(habitMarksProvider);

      final older = marks.setCount(4, 1);
      await pumpEventQueue();
      final newer = marks.setCount(4, 2);
      await pumpEventQueue();
      first.complete();
      expect(await older, isTrue);
      second.complete();
      expect(await newer, isFalse);
      await pumpEventQueue();

      expect(todayGets, 2, reason: 'the skipped score is fetched again');
    });

    test('a refusal puts the habit back after an earlier request settled', () async {
      final adapter = StubAdapter({
        'GET /api/today': (_) =>
            StubResponse(200, todayJson()..['habits'] = [countState(4, 'Water')]),
        'GET /api/board': (_) => StubResponse(200, boardJson()),
        'PUT /api/habits/4/marks/2026-10-26': (_) => const StubResponse(422, {'error': 'no'}),
      });
      final c = _container(adapter);
      await c.read(todayProvider.future);

      expect(await c.read(habitMarksProvider).setCount(4, 3), isFalse);
      expect(c.read(todayProvider).requireValue.data.habits.single.count, 0);
    });
  });

  group('Companion', () {
    final calls = <MethodCall>[];

    setUp(() {
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

    test('the snapshot carries the profile time zone', () {
      final snapshot = companionSnapshot(
        session: testSession,
        today: Today.fromJson(todayJson()),
        timezone: 'Europe/London',
      );
      expect(snapshot['timezone'], 'Europe/London');
      expect(
        companionSnapshot(session: testSession, today: Today.fromJson(todayJson())),
        isNot(contains('timezone')),
      );
    });

    test('another person\'s cached Today is never published under a new session', () async {
      final gate = Completer<void>();
      final adapter = StubAdapter({
        'GET /api/today': (req) async {
          if (req.headers['Authorization'] == 'Bearer tok2') await gate.future;
          return StubResponse(200, todayJson(points: 777));
        },
        'GET /api/me': (_) => StubResponse(200, meJson()),
      });
      final c = _container(adapter);
      c.read(companionProvider);
      await c.read(todayProvider.future);
      await pumpEventQueue();
      calls.clear();

      await c
          .read(sessionProvider.notifier)
          .signIn(
            const Session(
              baseUrl: 'https://me.invalid',
              token: 'tok2',
              userId: 3,
              userName: 'Alex',
              color: 'green',
            ),
          );
      await pumpEventQueue();

      final published = [
        for (final call in calls)
          if (call.method == 'update') jsonDecode(call.arguments as String) as Map<String, dynamic>,
      ];
      expect(published, isEmpty, reason: 'Today still belongs to the previous person');

      gate.complete();
      await pumpEventQueue();
    });
  });

  group('Health history rate limit', () {
    late FakeHealthSource health;
    final waits = <Duration>[];
    final now = DateTime(2026, 11, 2, 12);

    ProviderContainer build(StubAdapter server) => testContainer(
      overrides: [
        sessionProvider.overrideWith(() => SessionController.seeded(testSession)),
        apiClientFactoryProvider.overrideWithValue(stubFactory(server)),
        clockProvider.overrideWithValue(() => now),
        healthSourceProvider.overrideWithValue(health),
        historyBackoffWaitProvider.overrideWithValue((d) async => waits.add(d)),
      ],
    );

    setUp(() async {
      await LocalPrefs.setHealthPrompted();
      waits.clear();
      health = FakeHealthSource()..dataSince = DateTime(2026, 10, 30);
    });

    test('a Retry-After of 0 still waits the minimum pause', () async {
      var puts = 0;
      final server = fullServer()
        ..routes['PUT /api/health/history'] = (req) {
          if (++puts == 1) {
            return const StubResponse.withHeaders(
              429,
              {'error': 'too many requests, slow down', 'code': 'rate_limited'},
              {'retry-after': '0'},
            );
          }
          final items = (req.data as Map)['items'] as List;
          return StubResponse(200, {'stored': items.length, 'received': items.length});
        };
      final c = build(server)..read(healthSyncProvider);
      await Future<void>.delayed(Duration.zero);

      await c.read(healthHistoryProvider.notifier).run();

      expect(waits, [kHistoryBackoffStart]);
    });

    test('a 429 backs off by Retry-After, then by doubling, and carries on', () async {
      var puts = 0;
      final server = fullServer()
        ..routes['PUT /api/health/history'] = (req) {
          puts++;
          if (puts == 1) {
            return const StubResponse.withHeaders(
              429,
              {'error': 'too many requests, slow down', 'code': 'rate_limited'},
              {'retry-after': '3'},
            );
          }
          if (puts == 2) {
            return const StubResponse(429, {
              'error': 'too many requests, slow down',
              'code': 'rate_limited',
            });
          }
          final items = (req.data as Map)['items'] as List;
          return StubResponse(200, {'stored': items.length, 'received': items.length});
        };
      final c = build(server)..read(healthSyncProvider);
      await Future<void>.delayed(Duration.zero);

      await c.read(healthHistoryProvider.notifier).run();

      final state = c.read(healthHistoryProvider);
      expect(state.error, isNull);
      expect(state.done, isTrue);
      expect(waits, [const Duration(seconds: 3), const Duration(seconds: 4)]);
      expect(puts, greaterThanOrEqualTo(3));
    });

    test('when it never lets up the import stops with friendly copy', () async {
      final server = fullServer()
        ..on(
          'PUT /api/health/history',
          const StubResponse(429, {
            'error': 'too many requests, slow down',
            'code': 'rate_limited',
          }),
        );
      final c = build(server)..read(healthSyncProvider);
      await Future<void>.delayed(Duration.zero);

      await c.read(healthHistoryProvider.notifier).run();

      final state = c.read(healthHistoryProvider);
      expect(waits, hasLength(kHistoryRateLimitRetries));
      expect(state.done, isFalse);
      expect(state.error, isNotNull);
      expect(state.error!.toLowerCase(), isNot(contains('too many requests')));
    });

    test('ApiException reads Retry-After and spots a rate limit', () {
      const limited = ApiException(
        'too many requests, slow down',
        statusCode: 429,
        code: 'rate_limited',
        retryAfter: Duration(seconds: 7),
      );
      expect(limited.isRateLimited, isTrue);
      expect(const ApiException('nope', statusCode: 422).isRateLimited, isFalse);
    });
  });

  group('HomeShell resume', () {
    Map<String, dynamic> linkedMe() => {
      ...meJson(),
      'audiobookshelf': {'linked': true, 'username': 'sam', 'syncedAt': null, 'lastError': null},
    };

    void resume() {
      final binding = TestWidgetsFlutterBinding.instance;
      binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    }

    testWidgets('Today reloads before a slow Audiobookshelf sync finishes', (tester) async {
      var now = testNow;
      final gate = Completer<void>();
      final adapter = fullServer()
        ..on('GET /api/me', StubResponse(200, linkedMe()))
        ..on(
          'POST /api/me/audiobookshelf/sync',
          const StubResponse(200, {
            'linked': true,
            'username': 'sam',
            'syncedAt': '2026-10-26T14:00:00Z',
            'lastError': null,
            'minutesToday': 5,
          }),
        );
      final app = TestApp(tester, adapter);
      await app.pump(const HomeShell(), clock: () => now);

      adapter.routes['POST /api/me/audiobookshelf/sync'] = (_) async {
        await gate.future;
        return const StubResponse(200, {
          'linked': true,
          'username': 'sam',
          'syncedAt': '2026-10-26T14:30:00Z',
          'lastError': null,
          'minutesToday': 5,
        });
      };
      now = now.add(const Duration(minutes: 30));
      final before = adapter.to('GET /api/today').length;

      resume();
      await app.settle();

      expect(adapter.to('POST /api/me/audiobookshelf/sync'), hasLength(2));
      expect(
        adapter.to('GET /api/today').length,
        before + 1,
        reason: 'Today must not wait for the sync',
      );
      gate.complete();
      await app.settle();
    });

    testWidgets('a changed device zone is followed on resume and reminders are re-anchored', (
      tester,
    ) async {
      testDeviceTimezone = 'America/New_York';
      addTearDown(() => testDeviceTimezone = 'America/New_York');
      SharedPreferences.setMockInitialValues({'deviceTimezone': 'America/New_York'});
      final scheduler = FakeReminderScheduler();
      final adapter = fullServer()..on('PATCH /api/me', StubResponse(200, meJson()));
      final app = TestApp(tester, adapter, surfaceHeight: 2800);
      await app.pump(
        const HomeShell(),
        overrides: [reminderSchedulerProvider.overrideWithValue(scheduler)],
      );
      expect(adapter.to('PATCH /api/me'), isEmpty);
      expect(scheduler.calls, isNot(contains('timezone')));

      testDeviceTimezone = 'Asia/Tokyo';
      resume();
      await app.settle();

      expect(app.body('PATCH /api/me'), {'timezone': 'Asia/Tokyo'});
      expect(scheduler.calls, contains('timezone'));
    });

    testWidgets('a zone change whose save fails is tried again on the next resume', (tester) async {
      testDeviceTimezone = 'America/New_York';
      addTearDown(() => testDeviceTimezone = 'America/New_York');
      SharedPreferences.setMockInitialValues({'deviceTimezone': 'America/New_York'});
      final scheduler = FakeReminderScheduler();
      final adapter = fullServer()
        ..on('PATCH /api/me', const StubResponse(500, {'error': 'database unavailable'}));
      final app = TestApp(tester, adapter, surfaceHeight: 2800);
      await app.pump(
        const HomeShell(),
        overrides: [reminderSchedulerProvider.overrideWithValue(scheduler)],
      );

      testDeviceTimezone = 'Asia/Tokyo';
      resume();
      await app.settle();
      expect(adapter.to('PATCH /api/me'), hasLength(1));

      adapter.on('PATCH /api/me', StubResponse(200, meJson()));
      resume();
      await app.settle();
      expect(adapter.to('PATCH /api/me'), hasLength(2));
      expect(scheduler.calls, contains('timezone'));
    });
  });

  group('Log sheet', () {
    testWidgets('an unexpected error leaves the sheet usable instead of stuck busy', (
      tester,
    ) async {
      Mascot.idleMotion = false;
      final adapter = fullServer()..on('POST /api/logs', StubResponse(201, logResultJson()));
      final app = TestApp(tester, adapter);
      await app.pump(
        Builder(
          builder: (context) => Center(
            child: ElevatedButton(
              onPressed: () => showLogSheet(context, kind: LogKind.pushups),
              child: const Text('Open'),
            ),
          ),
        ),
        overrides: [logActionsProvider.overrideWith(_ExplodingLogActions.new)],
      );
      await app.tap(find.text('Open'));

      Finder save(String label) =>
          find.byWidgetPredicate((w) => w is ChunkyButton && w.label == label);
      await app.tap(save('Save'));

      expect(find.text('Something went wrong.'), findsOneWidget);
      expect(tester.widget<ChunkyButton>(save('Try again')).onPressed, isNotNull);
    });
  });

  group('Accessibility', () {
    testWidgets('a logged set can be deleted by a screen reader action', (tester) async {
      final handle = tester.ensureSemantics();
      Mascot.idleMotion = false;
      final adapter = fullServer()
        ..on('GET /api/exercises', StubResponse(200, _load('exercises')))
        ..on('GET /api/sets', StubResponse(200, _load('sets')));
      final app = TestApp(tester, adapter, surfaceHeight: 3000);
      await app.pump(const ExercisePage(exerciseKey: 'db_row'));
      await tester.pumpAndSettle();

      final row = tester.getSemantics(find.textContaining('20').last);
      expect(row.getSemanticsData().customSemanticsActionIds, isNotEmpty);
      final label = CustomSemanticsAction.getAction(
        row.getSemanticsData().customSemanticsActionIds!.first,
      );
      expect(label?.label, 'Delete set');
      handle.dispose();
    });

    testWidgets('Do the full session has a 44 point target', (tester) async {
      final raw = _load('training_today')['session'] as Map<String, dynamic>;
      raw['eased'] = true;
      raw['easedReason'] = 'Lighter today.';
      for (final e in raw['exercises'] as List) {
        (e as Map<String, dynamic>)['logged'] = <dynamic>[];
      }
      final session = TrainingSession.tryParse(raw)!;
      final app = TestApp(tester, fullServer());
      await app.pump(EasedNote(session: session));

      final size = tester.getSize(
        find.ancestor(of: find.text('Do the full session'), matching: find.byType(TextButton)),
      );
      expect(size.height, greaterThanOrEqualTo(44));
    });
  });
}

class _ExplodingLogActions extends LogActions {
  _ExplodingLogActions(super.ref);

  @override
  Future<LogResult> create(LogDraft draft) async => throw StateError('boom');
}

Map<String, dynamic> _load(String name) =>
    jsonDecode(File('test/contract_v9/$name.json').readAsStringSync()) as Map<String, dynamic>;
