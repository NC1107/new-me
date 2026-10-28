import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:newme/api/models.dart';
import 'package:newme/features/training/guided_session.dart';
import 'package:newme/features/training/mobility_page.dart';
import 'package:newme/features/training/yoga_flows.dart';
import 'package:newme/features/training/guided_page.dart';
import 'package:newme/widgets/mascot.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fixtures.dart';
import 'test_support.dart';

dynamic _load(String name) => jsonDecode(File('test/contract_v9/$name.json').readAsStringSync());

final _png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==',
);

ExerciseCatalog get _catalog => ExerciseCatalog.parse(_load('exercises'));

StubAdapter _server() {
  final server = fullServer()
    ..on('GET /api/exercises', StubResponse(200, _load('exercises')))
    ..on('GET /api/yoga/plan', StubResponse(200, _load('yoga_plan')))
    ..on('POST /api/logs', StubResponse(201, logResultJson()));
  for (final e in _catalog.exercises.where((e) => !e.strength)) {
    for (final url in e.imageUrls) {
      server.on('GET $url', StubResponse.bytes(200, _png));
    }
  }
  return server;
}

Finder _button(String label) => find.text(label.toUpperCase());

Future<void> _seconds(WidgetTester tester, int n) async {
  for (var i = 0; i < n; i++) {
    await tester.pump(const Duration(seconds: 1));
  }
}

Finder _speaker() => find.bySemanticsLabel(RegExp(r'^Sounds'));

GuidedRoutine get _flow10 => yogaRoutine(kYogaFlows.first);

Future<TestApp> _open(
  WidgetTester tester, {
  GuidedRoutine? routine,
  double width = 390,
  double height = 844,
  StubAdapter? server,
}) async {
  final app = TestApp(tester, server ?? _server(), surfaceHeight: height, surfaceWidth: width);
  await app.pump(GuidedPage(routine: routine ?? _flow10));
  await tester.pumpAndSettle();
  await tester.tap(_button('Start'));
  await tester.pump();
  return app;
}

/// The page's own list, which must not need scrolling when the text is at its normal size.
void _expectOnOneScreen(WidgetTester tester, String where) {
  final error = tester.takeException();
  expect(error, isNull, reason: '$where: ${error is FlutterError ? error.toStringDeep() : error}');
  final scroll = tester.state<ScrollableState>(find.byType(Scrollable).first);
  expect(scroll.position.maxScrollExtent, 0, reason: '$where needs scrolling');
}

/// The real Nunito, so the fit tests measure the text as a phone would, not in the test font's
/// square glyphs.
Future<void> _loadNunito() async {
  TestWidgetsFlutterBinding.ensureInitialized();
  final loader = FontLoader('Nunito');
  for (final weight in ['Regular', 'SemiBold', 'Bold', 'ExtraBold', 'Black']) {
    loader.addFont(
      File('assets/fonts/Nunito-$weight.ttf').readAsBytes().then((b) => ByteData.sublistView(b)),
    );
  }
  await loader.load();
}

/// Lets photo requests finish, then drops the page, so no request timer outlives the test.
Future<void> _leave(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 100));
  await tester.pumpWidget(const SizedBox());
}

/// The pose on screen: the one whose name is the heading, not part of a "Next:" line.
Exercise? _poseNow(WidgetTester tester) {
  for (final e in _catalog.exercises) {
    if (e.yoga && find.text(e.name).evaluate().length == 1) return e;
  }
  return null;
}

void main() {
  setUpAll(_loadNunito);
  setUp(() {
    FakeStorage().install();
    Mascot.idleMotion = false;
  });

  group('the runner fits one screen', () {
    for (final (name, width, height) in [
      ('a 390x844 phone', 390.0, 844.0),
      ('an iPhone SE, 375x667', 375.0, 667.0),
    ]) {
      testWidgets('on $name for every pose of Yoga 30', (tester) async {
        final app = await _open(
          tester,
          routine: yogaRoutine(kYogaFlows.last),
          width: width,
          height: height,
        );
        final steps = buildYogaHolds(kYogaFlows.last, _catalog).map((h) => h.stepIndex).toSet();
        for (final i in steps) {
          final e = _poseNow(tester);
          _expectOnOneScreen(tester, '${e?.key} (pose ${i + 1})');
          for (final step in e?.steps ?? const <String>[]) {
            final finder = find.text(step);
            expect(finder, findsOneWidget, reason: '${e?.key}: $step');
            expect(tester.getRect(finder).bottom, lessThanOrEqualTo(height - 80), reason: step);
          }
          if (i != steps.last) {
            await tester.tap(find.widgetWithText(TextButton, 'Skip'));
            await tester.pump();
          }
        }
        expect(app.audio.cues, contains('prepare'));
        await _leave(tester);
      });
    }

    testWidgets('on an iPhone SE for every stretch of Mobility', (tester) async {
      await _open(tester, routine: mobilityRoutine, width: 375, height: 667);
      for (var i = 0; i < 10; i++) {
        _expectOnOneScreen(tester, 'stretch ${i + 1}');
        await tester.tap(find.widgetWithText(TextButton, 'Skip'));
        await tester.pump();
      }
      await _leave(tester);
    });

    testWidgets('at text scale 2.0 nothing overflows and scrolling takes over', (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = 2.0;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await _open(tester, width: 375, height: 667);
      await _seconds(tester, 5);
      expect(tester.takeException(), isNull);
      final scroll = tester.state<ScrollableState>(find.byType(Scrollable).first);
      expect(scroll.position.maxScrollExtent, greaterThan(0));
      await _leave(tester);
    });

    testWidgets('shows one photo, the next pose and the numbered steps', (tester) async {
      await _open(tester);
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byType(Image), findsOneWidget);
      expect(find.text('Next: Cat-cow'), findsOneWidget);
      final easy = _catalog.byKey('yoga_easy')!;
      for (final (i, step) in easy.steps.indexed) {
        expect(find.text(step), findsOneWidget);
        expect(find.text('${i + 1}'), findsWidgets);
      }
      expect(find.textContaining('Photo: '), findsOneWidget);
      await _leave(tester);
    });
  });

  group('sound cues', () {
    testWidgets('prepare at the start and speak the first pose', (tester) async {
      final app = await _open(tester);
      expect(app.audio.cues, ['prepare', 'say: Starting with Easy pose']);
      await _leave(tester);
    });

    testWidgets('tick at 3, 2 and 1, a halfway tone, then a chime and the next pose', (
      tester,
    ) async {
      final app = await _open(tester);
      await _seconds(tester, 3);
      app.audio.cues.clear();

      await _seconds(tester, 14);
      expect(app.audio.cues, isEmpty, reason: 'nothing before the midpoint');
      await _seconds(tester, 1);
      expect(app.audio.cues, ['halfway']);
      app.audio.cues.clear();

      await _seconds(tester, 11);
      expect(app.audio.cues, isEmpty);
      await _seconds(tester, 1);
      await _seconds(tester, 1);
      await _seconds(tester, 1);
      expect(app.audio.cues, ['tick', 'tick', 'tick']);
      app.audio.cues.clear();

      await _seconds(tester, 1);
      expect(app.audio.cues, ['chime', 'say: Next: Cat-cow']);
      await _leave(tester);
    });

    testWidgets('a side is named when the next hold is the other side', (tester) async {
      final app = await _open(tester);
      // Easy, cat-cow, dog, then the low lunge's left side.
      for (var i = 0; i < 3; i++) {
        await tester.tap(find.widgetWithText(TextButton, 'Skip'));
        await tester.pump();
      }
      app.audio.cues.clear();
      await _seconds(tester, 33);
      expect(app.audio.cues.last, 'say: Next: Right side');
      await _leave(tester);
    });

    testWidgets('a whole flow ends on a chime', (tester) async {
      final app = await _open(tester);
      await _seconds(tester, 20 * 33);
      await tester.pumpAndSettle();
      expect(app.audio.cues.where((c) => c == 'chime').length, greaterThan(10));
      expect(app.audio.cues.last, 'chime');
    });

    testWidgets('time spent in the background plays no catch-up cues', (tester) async {
      var now = DateTime(2026, 10, 28, 7);
      final app = TestApp(tester, _server(), surfaceHeight: 844);
      await app.pump(GuidedPage(routine: _flow10, now: () => now));
      await tester.pumpAndSettle();
      await tester.tap(_button('Start'));
      await tester.pump();
      await _seconds(tester, 5);
      app.audio.cues.clear();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      now = now.add(const Duration(seconds: 100));
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(app.audio.cues.where((c) => c == 'tick' || c == 'halfway'), isEmpty);
      await _leave(tester);
    });

    test('a hold under 20 seconds gets no halfway tone', () {
      final e = _catalog.byKey('yoga_easy')!;
      final c = GuidedController([
        GuidedHold(exercise: e, stepIndex: 0, label: 'Hold', firstOfStep: true, seconds: 15),
        GuidedHold(exercise: e, stepIndex: 1, label: 'Hold', firstOfStep: true, seconds: 20),
      ]);
      final events = <GuidedEvent?>[for (var i = 0; i < 3 + 15; i++) c.tick()];
      expect(events, isNot(contains(GuidedEvent.halfway)));
      expect(events.where((e) => e == GuidedEvent.countdown), hasLength(3));
      final second = <GuidedEvent?>[for (var i = 0; i < 3 + 20; i++) c.tick()];
      expect(second.where((e) => e == GuidedEvent.halfway), hasLength(1));
    });
  });

  group('the speaker button', () {
    testWidgets('cycles sounds and voice, tones only, and silent, and is remembered', (
      tester,
    ) async {
      final app = await _open(tester);
      final handle = tester.ensureSemantics();
      await tester.pump();
      expect(find.bySemanticsLabel('Sounds and voice on'), findsOneWidget);
      expect(tester.getSize(_speaker()).width, greaterThanOrEqualTo(44));
      expect(tester.getSize(_speaker()).height, greaterThanOrEqualTo(44));

      await tester.tap(_speaker());
      await tester.pump();
      expect(find.bySemanticsLabel('Sounds on, voice off'), findsOneWidget);
      app.audio.cues.clear();
      await _seconds(tester, 3 + 26 + 3);
      expect(app.audio.cues.where((c) => c == 'tick'), hasLength(3));
      await _seconds(tester, 1);
      expect(app.audio.cues, contains('chime'));
      expect(app.audio.cues.where((c) => c.startsWith('say')), isEmpty);

      await tester.tap(_speaker());
      await tester.pump();
      expect(find.bySemanticsLabel('Sounds off'), findsOneWidget);
      app.audio.cues.clear();
      await _seconds(tester, 3 + 26 + 3 + 1);
      expect(app.audio.cues.where((c) => c != 'stop'), isEmpty);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('guided.sound'), isFalse);
      expect(prefs.getBool('guided.voice'), isFalse);

      await tester.tap(_speaker());
      await tester.pump();
      expect(find.bySemanticsLabel('Sounds and voice on'), findsOneWidget);
      handle.dispose();
      await _leave(tester);
    });

    testWidgets('starts the next session the way it was left', (tester) async {
      SharedPreferences.setMockInitialValues({'guided.sound': false, 'guided.voice': false});
      final app = await _open(tester);
      await tester.pump(const Duration(milliseconds: 50));
      await _seconds(tester, 3 + 27);
      expect(app.audio.cues.where((c) => c == 'tick' || c.startsWith('say')), isEmpty);
      await _leave(tester);
    });

    testWidgets('VoiceOver gets its announcements and no second voice', (tester) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue = const FakeAccessibilityFeatures(
        accessibleNavigation: true,
      );
      addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
      final app = await _open(tester);
      await _seconds(tester, 3 + 30);
      expect(app.audio.cues.where((c) => c.startsWith('say')), isEmpty);
      expect(app.audio.cues, contains('chime'));
      expect(app.audio.cues, contains('tick'));
      await _leave(tester);
    });

    testWidgets('pausing cuts the voice off', (tester) async {
      final app = await _open(tester);
      app.audio.cues.clear();
      await tester.tap(_button('Pause'));
      await tester.pump();
      expect(app.audio.cues, ['stop']);
      await _leave(tester);
    });
  });

  group('the screen', () {
    testWidgets('stays awake while a session runs and lets go when it ends', (tester) async {
      final app = await _open(tester);
      expect(app.awake.on, isTrue);
      await _seconds(tester, 20 * 33);
      await tester.pumpAndSettle();
      expect(app.awake.on, isFalse);
      expect(app.awake.calls, ['enable', 'disable']);
    });

    testWidgets('lets go when the person leaves', (tester) async {
      final app = await _open(tester);
      await _seconds(tester, 5);
      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();
      await tester.tap(_button('End'));
      await tester.pumpAndSettle();
      expect(app.awake.on, isFalse);
    });

    testWidgets('lets go when the page goes away mid-session', (tester) async {
      final app = await _open(tester);
      await _leave(tester);
      expect(app.awake.calls, ['enable', 'disable']);
    });
  });

  group('ending early', () {
    Future<TestApp> endAfter(WidgetTester tester, int seconds) async {
      final app = await _open(tester);
      await _seconds(tester, seconds);
      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();
      return app;
    }

    testWidgets('one minute reads "it" and offers a clear primary action', (tester) async {
      await endAfter(tester, 40);
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.text('End Yoga 10 early?'), findsOneWidget);
      expect(find.text('You\'ve done 1 minute. Log it to your yoga quest?'), findsOneWidget);
      expect(_button('Log 1 min and end'), findsOneWidget);
      expect(_button('End without logging'), findsOneWidget);
      expect(find.text('Keep going'), findsOneWidget);
      for (final finder in [_button('Log 1 min and end'), _button('End without logging')]) {
        expect(tester.getSize(finder).height, greaterThan(0));
      }
      await tester.tap(_button('Log 1 min and end'));
      await tester.pumpAndSettle();
      expect(find.text('Logged 1 minute to your yoga quest.'), findsOneWidget);
    });

    testWidgets('several minutes reads "them"', (tester) async {
      await endAfter(tester, 6 * 60 + 12 * 3);
      expect(find.textContaining('You\'ve done'), findsOneWidget);
      expect(find.textContaining('Log them to your yoga quest?'), findsOneWidget);
    });

    testWidgets('under 30 seconds offers only End and Keep going', (tester) async {
      final server = _server();
      final app = TestApp(tester, server, surfaceHeight: 844);
      await app.pump(GuidedPage(routine: _flow10));
      await tester.pumpAndSettle();
      await tester.tap(_button('Start'));
      await _seconds(tester, 10);
      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();
      expect(find.text('End Yoga 10?'), findsOneWidget);
      expect(find.text('You are under 30 seconds in, so nothing will be logged.'), findsOneWidget);
      expect(_button('End'), findsOneWidget);
      expect(find.text('Keep going'), findsOneWidget);
      expect(find.textContaining('Log '.toUpperCase()), findsNothing);
      await tester.tap(_button('End'));
      await tester.pumpAndSettle();
      expect(server.to('POST /api/logs'), isEmpty);
    });

    testWidgets('dismissing the sheet keeps the session going', (tester) async {
      final app = await endAfter(tester, 40);
      await tester.tapAt(const Offset(195, 40));
      await tester.pumpAndSettle();
      expect(find.text('End Yoga 10 early?'), findsNothing);
      expect(app.awake.on, isTrue);
      await _seconds(tester, 1);
      expect(find.text('Pose 2 of 14'), findsOneWidget);
      await _leave(tester);
    });

    testWidgets('the sheet keeps its buttons 44 points tall at text scale 2.0', (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = 2.0;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await endAfter(tester, 40);
      expect(tester.takeException(), isNull);
      expect(
        tester.getSize(find.widgetWithText(TextButton, 'Keep going')).height,
        greaterThanOrEqualTo(44),
      );
    });
  });
}
