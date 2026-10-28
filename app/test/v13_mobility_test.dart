import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:newme/api/models.dart';
import 'package:newme/features/training/exercises_page.dart';
import 'package:newme/features/training/guided_session.dart';
import 'package:newme/features/training/mobility_page.dart';
import 'package:newme/features/training/mobility_session.dart';
import 'package:newme/features/training/train_screen.dart';
import 'package:newme/widgets/chunky_button.dart';
import 'package:newme/widgets/mascot.dart';

import 'fixtures.dart';
import 'test_support.dart';

/// test/contract_v9 holds real server responses (server/internal/api/v9_contract_test.go).
Map<String, dynamic> _load(String name) =>
    jsonDecode(File('test/contract_v9/$name.json').readAsStringSync()) as Map<String, dynamic>;

// A 1x1 PNG, enough for Image.memory to decode.
final _png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==',
);

ExerciseCatalog get _catalog => ExerciseCatalog.parse(_load('exercises'));

StubAdapter _server() {
  final server = fullServer()
    ..on('GET /api/exercises', StubResponse(200, _load('exercises')))
    ..on('GET /api/training/profile', StubResponse(200, _load('training_profile_empty')))
    ..on('GET /api/training/today', StubResponse(200, _load('training_today_none')))
    ..on('POST /api/logs', StubResponse(201, logResultJson()));
  for (final e in _catalog.exercises.where((e) => e.stretch)) {
    for (final url in e.imageUrls) {
      server.on('GET $url', StubResponse.bytes(200, _png));
    }
  }
  return server;
}

Finder _button(String label) => find.text(label.toUpperCase());

/// The big countdown number, not a step number that happens to read the same.
Finder _digits(String value) => find.byWidgetPredicate(
  (w) => w is Text && w.data == value && w.style?.fontSize == 72,
  description: 'countdown $value',
);

Finder _action(String label) => find.widgetWithText(TextButton, label);

class _Recorder {
  final haptics = <String>[];
  final announcements = <String>[];

  void install(WidgetTester tester) {
    final messenger = tester.binding.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'HapticFeedback.vibrate') haptics.add(call.arguments as String);
      return null;
    });
    messenger.setMockDecodedMessageHandler<dynamic>(SystemChannels.accessibility, (message) async {
      final map = message as Map;
      if (map['type'] == 'announce') {
        announcements.add(((map['data'] as Map)['message']) as String);
      }
      return null;
    });
    addTearDown(() {
      messenger.setMockMethodCallHandler(SystemChannels.platform, null);
      messenger.setMockDecodedMessageHandler<dynamic>(SystemChannels.accessibility, null);
    });
  }
}

Future<void> _seconds(WidgetTester tester, int n) async {
  for (var i = 0; i < n; i++) {
    await tester.pump(const Duration(seconds: 1));
  }
}

void main() {
  setUp(() {
    FakeStorage().install();
    Mascot.idleMotion = false;
  });

  group('the catalog', () {
    test('stretches are marked and the sequence is real stretches', () {
      final c = _catalog;
      final stretches = c.exercises.where((e) => e.stretch).toList();
      expect(stretches, hasLength(12));
      expect(c.byKey('push_up')!.stretch, isFalse);
      expect(c.byKey('kneeling_hip_flexor_stretch')!.perSide, isTrue);
      expect(c.byKey('cat_stretch')!.perSide, isFalse);
      for (final key in kMobilitySequence) {
        expect(c.byKey(key)?.stretch, isTrue, reason: key);
      }
      final again = ExerciseCatalog.parse(jsonDecode(jsonEncode(c.toJson())));
      expect(again.byKey('kneeling_hip_flexor_stretch')!.perSide, isTrue);
      expect(again.byKey('kneeling_hip_flexor_stretch')!.kind, ExerciseKind.stretch);
    });

    test('the exercise library leaves stretches to Mobility', () {
      final groups = groupExercises(_catalog, '');
      final listed = [for (final (_, list) in groups) ...list];
      expect(listed.where((e) => e.stretch), isEmpty);
      expect(listed, isNotEmpty);
    });
  });

  group('the session clock', () {
    List<GuidedHold> holds() => buildMobilityHolds(_catalog);

    test('has two holds per stretch, one per side where it has sides', () {
      final h = holds();
      expect(h, hasLength(kMobilitySequence.length * 2));
      expect([h[0].label, h[1].label], ['Hold 1 of 2', 'Hold 2 of 2']);
      expect(h[0].exercise.key, 'cat_stretch');
      expect([h[4].label, h[5].label], ['Left side', 'Right side']);
      expect(h[4].exercise.key, 'kneeling_hip_flexor_stretch');
    });

    test('runs a lead-in, a 30 second hold, then advances by itself', () {
      final c = GuidedController(holds());
      expect(c.phase, GuidedPhase.leadIn);
      expect(
        [c.tick(), c.tick(), c.tick()],
        [GuidedEvent.leadInTick, GuidedEvent.leadInTick, GuidedEvent.go],
      );
      expect(c.phase, GuidedPhase.hold);
      expect(c.holdLeft, 30);
      for (var i = 0; i < 29; i++) {
        expect(c.tick(), isNull);
      }
      expect(c.tick(), GuidedEvent.nextHold);
      expect(c.index, 1);
      expect(c.phase, GuidedPhase.leadIn);
      expect(c.leadLeft, 3);
      expect(c.activeSeconds, 33);
    });

    test('finishes after the last hold with about eleven minutes', () {
      final c = GuidedController(holds());
      GuidedEvent? last;
      while (!c.finished) {
        last = c.tick();
      }
      expect(last, GuidedEvent.finished);
      expect(c.activeSeconds, 20 * 33);
      expect(c.minutes, 11);
      expect(c.progress, 1);
      expect(c.tick(), isNull);
    });

    test('pause stops time, skip and back move by stretch', () {
      final c = GuidedController(holds());
      c.pause();
      expect(c.tick(), isNull);
      expect(c.activeSeconds, 0);
      c.resume();
      expect(c.canGoBack, isFalse);
      c.skipStep();
      expect(c.index, 2);
      expect(c.current.exercise.key, 'childs_pose');
      c.tick();
      c.tick();
      c.tick();
      c.tick();
      expect(c.phase, GuidedPhase.hold);
      c.backStep();
      expect(c.index, 2, reason: 'mid stretch, back restarts it');
      expect(c.phase, GuidedPhase.leadIn);
      c.backStep();
      expect(c.index, 0, reason: 'at its start, back goes to the stretch before');
      c.skipStep();
      c.skipStep();
      expect(c.index, 4);
    });

    test('skipping the last stretch finishes', () {
      final c = GuidedController(holds());
      for (var i = 0; i < kMobilitySequence.length; i++) {
        c.skipStep();
      }
      expect(c.finished, isTrue);
      expect(c.minutes, 1);
      expect(c.worthLogging, isFalse);
    });
  });

  group('the page', () {
    testWidgets('says the order is its own and cites ACSM before it starts', (tester) async {
      final app = TestApp(tester, _server(), surfaceHeight: 3000);
      await app.pump(const MobilityPage());
      await tester.pumpAndSettle();
      expect(find.text('Mobility'), findsOneWidget);
      expect(find.textContaining('not from a trial'), findsOneWidget);
      expect(find.textContaining('Garber et al., ACSM position stand'), findsOneWidget);
      expect(find.textContaining('at least 2 days a week'), findsOneWidget);
      expect(find.text('Cat stretch'), findsOneWidget);
      expect(find.text('Triceps stretch'), findsOneWidget);
      expect(_button('Start'), findsOneWidget);
    });

    testWidgets('without stretches on the server it cannot start', (tester) async {
      final server = _server()
        ..on(
          'GET /api/exercises',
          StubResponse(200, {
            'exercises': [for (final e in _catalog.exercises.where((e) => !e.stretch)) e.toJson()],
            'muscles': <String>[],
            'equipment': <String>[],
          }),
        );
      final app = TestApp(tester, server, surfaceHeight: 3000);
      await app.pump(const MobilityPage());
      await tester.pumpAndSettle();
      expect(find.textContaining('no stretches yet'), findsOneWidget);
      expect(tester.widget<ChunkyButton>(find.byType(ChunkyButton)).onPressed, isNull);
    });

    testWidgets('leads in, counts down, advances, and shows photos and steps', (tester) async {
      final recorder = _Recorder()..install(tester);
      final server = _server();
      final app = TestApp(tester, server, surfaceHeight: 3000);
      await app.pump(const MobilityPage());
      await tester.pumpAndSettle();
      await tester.tap(_button('Start'));
      await tester.pump();

      final cat = _catalog.byKey('cat_stretch')!;
      expect(find.text('Stretch 1 of 10'), findsOneWidget);
      expect(find.text(cat.name), findsOneWidget);
      expect(find.text('Hold 1 of 2'), findsOneWidget);
      expect(find.text('Get ready'), findsOneWidget);
      expect(_digits('3'), findsOneWidget);
      expect(find.text(cat.steps.first), findsOneWidget);
      expect(find.text(cat.cues.first), findsOneWidget);
      expect(recorder.announcements.first, contains('Get ready'));
      expect(recorder.announcements.first, contains('Cat stretch'));

      await _seconds(tester, 3);
      expect(find.byType(Image), findsNWidgets(2));
      expect(_digits('30'), findsOneWidget);
      expect(find.text('seconds left'), findsOneWidget);
      expect(recorder.announcements, contains('Go'));
      expect(recorder.haptics, contains('HapticFeedbackType.mediumImpact'));

      await _seconds(tester, 10);
      expect(_digits('20'), findsOneWidget);

      await _seconds(tester, 20);
      expect(find.text('Hold 2 of 2'), findsOneWidget);
      expect(find.text('Get ready'), findsOneWidget);
      expect(recorder.announcements.last, 'Next. Cat stretch, Hold 2 of 2');

      await _seconds(tester, 3 + 30);
      expect(find.text('Stretch 2 of 10'), findsOneWidget);
      expect(find.text("Child's pose"), findsOneWidget);
      expect(server.to('POST /api/logs'), isEmpty);
      await tester.pump(const Duration(milliseconds: 100));
    });

    testWidgets('a stretch with sides says left then right', (tester) async {
      final app = TestApp(tester, _server(), surfaceHeight: 3000);
      await app.pump(const MobilityPage());
      await tester.pumpAndSettle();
      await tester.tap(_button('Start'));
      await tester.pump();
      await tester.tap(_action('Skip'));
      await tester.pump();
      await tester.tap(_action('Skip'));
      await tester.pump();
      expect(find.text('Kneeling hip flexor stretch'), findsOneWidget);
      expect(find.text('Left side'), findsOneWidget);
      await _seconds(tester, 33);
      expect(find.text('Right side'), findsOneWidget);
    });

    testWidgets('pause holds the clock and resume continues it', (tester) async {
      final app = TestApp(tester, _server(), surfaceHeight: 3000);
      await app.pump(const MobilityPage());
      await tester.pumpAndSettle();
      await tester.tap(_button('Start'));
      await _seconds(tester, 5);
      expect(_digits('28'), findsOneWidget);
      await tester.tap(_button('Pause'));
      await tester.pump();
      expect(find.text('Paused'), findsOneWidget);
      await _seconds(tester, 20);
      expect(_digits('28'), findsOneWidget);
      await tester.tap(_button('Resume'));
      await tester.pump();
      await _seconds(tester, 2);
      expect(_digits('26'), findsOneWidget);
    });

    testWidgets('back and skip move between stretches', (tester) async {
      final app = TestApp(tester, _server(), surfaceHeight: 3000);
      await app.pump(const MobilityPage());
      await tester.pumpAndSettle();
      await tester.tap(_button('Start'));
      await tester.pump();
      expect(tester.widget<TextButton>(_action('Previous')).onPressed, isNull);
      await tester.tap(_action('Skip'));
      await tester.pump();
      expect(find.text('Stretch 2 of 10'), findsOneWidget);
      await tester.tap(_action('Previous'));
      await tester.pump();
      expect(find.text('Stretch 1 of 10'), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 100));
    });

    testWidgets('a full session logs its minutes to yoga once', (tester) async {
      final recorder = _Recorder()..install(tester);
      final server = _server();
      final app = TestApp(tester, server, surfaceHeight: 3000);
      await app.pump(const MobilityPage());
      await tester.pumpAndSettle();
      await tester.tap(_button('Start'));
      await _seconds(tester, 20 * 33);
      await tester.pumpAndSettle();

      expect(find.text('Nice work'), findsOneWidget);
      expect(find.text('Logged 11 minutes to your yoga quest.'), findsOneWidget);
      expect(server.to('POST /api/logs'), hasLength(1));
      final body = app.body('POST /api/logs');
      expect(body['kind'], 'activity');
      expect(body['type'], 'yoga');
      expect(body['unit'], 'minutes');
      expect(body['quantity'], 11);
      expect(body['clientOpId'], isNotEmpty);
      expect(recorder.announcements.last, 'Mobility done. 11 minutes');
      expect(recorder.haptics, contains('HapticFeedbackType.heavyImpact'));
    });

    testWidgets('a failed log can be retried with the same id', (tester) async {
      final server = _server();
      var fail = true;
      server.routes['POST /api/logs'] = (_) =>
          fail ? const StubResponse(500, {'error': 'boom'}) : StubResponse(201, logResultJson());
      final app = TestApp(tester, server, surfaceHeight: 3000);
      await app.pump(const MobilityPage());
      await tester.pumpAndSettle();
      await tester.tap(_button('Start'));
      await _seconds(tester, 20 * 33);
      await tester.pumpAndSettle();
      expect(_button('Try again'), findsOneWidget);
      fail = false;
      await tester.tap(_button('Try again'));
      await tester.pumpAndSettle();
      expect(find.text('Logged 11 minutes to your yoga quest.'), findsOneWidget);
      final ids = [for (final r in server.to('POST /api/logs')) (r.data as Map)['clientOpId']];
      expect(ids, hasLength(2));
      expect(ids.toSet(), hasLength(1));
    });

    testWidgets('ending early asks, and logs the minutes done only when confirmed', (tester) async {
      final server = _server();
      final app = TestApp(tester, server, surfaceHeight: 3000);
      await app.pump(const MobilityPage());
      await tester.pumpAndSettle();
      await tester.tap(_button('Start'));
      await _seconds(tester, 100);

      await tester.tap(_action('End'));
      await tester.pumpAndSettle();
      expect(find.text('End Mobility early?'), findsOneWidget);
      expect(find.textContaining('You have done 2 minutes'), findsOneWidget);

      await tester.tap(find.text('Keep going'));
      await tester.pumpAndSettle();
      expect(find.text('End Mobility early?'), findsNothing);
      expect(server.to('POST /api/logs'), isEmpty);
      await _seconds(tester, 1);
      expect(find.text('Stretch 2 of 10'), findsOneWidget);

      await tester.tap(_action('End'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Log 2 min and end'));
      await tester.pumpAndSettle();
      expect(find.text('Logged 2 minutes to your yoga quest.'), findsOneWidget);
      expect(app.body('POST /api/logs')['quantity'], 2);
    });

    testWidgets('ending early without logging leaves quietly', (tester) async {
      final server = _server();
      final app = TestApp(tester, server, surfaceHeight: 3000);
      await app.pump(const MobilityPage());
      await tester.pumpAndSettle();
      await tester.tap(_button('Start'));
      await _seconds(tester, 100);
      await tester.tap(_action('End'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('End without logging'));
      await tester.pumpAndSettle();
      expect(find.byType(MobilityPage), findsNothing);
      expect(server.to('POST /api/logs'), isEmpty);
    });

    testWidgets('stopping in the first seconds confirms and logs nothing', (tester) async {
      final server = _server();
      final app = TestApp(tester, server, surfaceHeight: 3000);
      await app.pump(const MobilityPage());
      await tester.pumpAndSettle();
      await tester.tap(_button('Start'));
      await _seconds(tester, 5);
      await tester.tap(_action('End'));
      await tester.pumpAndSettle();
      expect(find.text('End Mobility?'), findsOneWidget);
      expect(find.textContaining('nothing will be logged'), findsOneWidget);
      await tester.tap(find.widgetWithText(TextButton, 'End').last);
      await tester.pumpAndSettle();
      expect(find.byType(MobilityPage), findsNothing);
      expect(server.to('POST /api/logs'), isEmpty);
    });

    testWidgets('catches up on time spent in the background', (tester) async {
      var now = DateTime(2026, 10, 28, 7);
      final app = TestApp(tester, _server(), surfaceHeight: 3000);
      await app.pump(MobilityPage(now: () => now));
      await tester.pumpAndSettle();
      await tester.tap(_button('Start'));
      await _seconds(tester, 3);
      expect(_digits('30'), findsOneWidget);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      now = now.add(const Duration(seconds: 35));
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(find.text('Hold 2 of 2'), findsOneWidget);
      expect(
        _digits('28'),
        findsOneWidget,
        reason: '35 seconds away: 30 finish the hold, 3 lead in, 2 held',
      );
    });

    testWidgets('time in the background does not count while paused', (tester) async {
      var now = DateTime(2026, 10, 28, 7);
      final app = TestApp(tester, _server(), surfaceHeight: 3000);
      await app.pump(MobilityPage(now: () => now));
      await tester.pumpAndSettle();
      await tester.tap(_button('Start'));
      await _seconds(tester, 3);
      await tester.tap(_button('Pause'));
      await tester.pump();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      now = now.add(const Duration(seconds: 60));
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(_digits('30'), findsOneWidget);
    });

    testWidgets('skipping through every stretch logs nothing', (tester) async {
      final server = _server();
      final app = TestApp(tester, server, surfaceHeight: 3000);
      await app.pump(const MobilityPage());
      await tester.pumpAndSettle();
      await tester.tap(_button('Start'));
      await tester.pump();
      for (var i = 0; i < 10; i++) {
        await tester.tap(_action('Skip'));
        await tester.pump();
      }
      await tester.pumpAndSettle();
      expect(find.text('Nothing logged'), findsOneWidget);
      expect(find.textContaining('Logged'), findsNothing);
      expect(server.to('POST /api/logs'), isEmpty);
      await tester.tap(_button('Done'));
      await tester.pumpAndSettle();
      expect(find.byType(MobilityPage), findsNothing);
    });

    testWidgets('time in the background is counted once when the ticker fires meanwhile', (
      tester,
    ) async {
      var now = DateTime(2026, 10, 28, 7);
      final app = TestApp(tester, _server(), surfaceHeight: 3000);
      await app.pump(MobilityPage(now: () => now));
      await tester.pumpAndSettle();
      await tester.tap(_button('Start'));
      await _seconds(tester, 3);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      for (var i = 0; i < 35; i++) {
        now = now.add(const Duration(seconds: 1));
        await tester.pump(const Duration(seconds: 1));
      }
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(find.text('Hold 2 of 2'), findsOneWidget);
      expect(_digits('28'), findsOneWidget);
      await _seconds(tester, 1);
      expect(_digits('27'), findsOneWidget);
    });

    testWidgets('a log that fails oddly can still be retried', (tester) async {
      final server = _server();
      var fail = true;
      server.routes['POST /api/logs'] = (_) =>
          fail ? const StubResponse(201, {'unexpected': true}) : StubResponse(201, logResultJson());
      final app = TestApp(tester, server, surfaceHeight: 3000);
      await app.pump(const MobilityPage());
      await tester.pumpAndSettle();
      await tester.tap(_button('Start'));
      await _seconds(tester, 20 * 33);
      await tester.pumpAndSettle();
      expect(_button('Try again'), findsOneWidget);
      fail = false;
      await tester.tap(_button('Try again'));
      await tester.pumpAndSettle();
      expect(find.text('Logged 11 minutes to your yoga quest.'), findsOneWidget);
      final ids = [for (final r in server.to('POST /api/logs')) (r.data as Map)['clientOpId']];
      expect(ids.toSet(), hasLength(1));
    });

    testWidgets('the digits are not read every second and controls are 44 points', (tester) async {
      final handle = tester.ensureSemantics();
      final app = TestApp(tester, _server(), surfaceHeight: 3000);
      await app.pump(const MobilityPage());
      await tester.pumpAndSettle();
      await tester.tap(_button('Start'));
      await _seconds(tester, 4);
      expect(find.bySemanticsLabel('Hold timer running'), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp(r'^\d+$')), findsNothing);
      expect(find.bySemanticsLabel('Session progress'), findsOneWidget);
      for (final label in ['Previous', 'End', 'Skip']) {
        final size = tester.getSize(_action(label));
        expect(size.width, greaterThanOrEqualTo(44), reason: label);
        expect(size.height, greaterThanOrEqualTo(44), reason: label);
      }
      handle.dispose();
    });

    testWidgets('reduced motion moves the progress bar at once', (tester) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue = const FakeAccessibilityFeatures(
        disableAnimations: true,
      );
      addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
      final app = TestApp(tester, _server(), surfaceHeight: 3000);
      await app.pump(const MobilityPage());
      await tester.pumpAndSettle();
      await tester.tap(_button('Start'));
      await _seconds(tester, 3 + 15);
      double value() =>
          tester.widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator)).value!;
      expect(value(), closeTo(15 / 600, 1e-9));
    });
  });

  group('the Train tab', () {
    testWidgets('has one Mobility card that opens the routine', (tester) async {
      final app = TestApp(tester, _server(), surfaceHeight: 3000);
      await app.pump(const TrainScreen());
      await tester.pumpAndSettle();
      expect(find.text('Mobility'), findsOneWidget);
      await tester.tap(find.text('Mobility'));
      await tester.pumpAndSettle();
      expect(find.byType(MobilityPage), findsOneWidget);
      expect(find.textContaining('not from a trial'), findsOneWidget);
    });
  });
}
