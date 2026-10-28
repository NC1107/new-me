import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:newme/api/models.dart';
import 'package:newme/features/training/exercises_page.dart';
import 'package:newme/features/training/how_to_sheet.dart';
import 'package:newme/features/training/session_page.dart';
import 'package:newme/features/training/set_assist.dart';
import 'package:newme/features/log/big_number_stepper.dart';
import 'package:newme/features/training/set_form.dart';
import 'package:newme/widgets/chunky_button.dart';
import 'package:newme/widgets/mascot.dart';
import 'package:newme/widgets/pressable.dart';

import 'fixtures.dart';
import 'test_support.dart';

/// test/contract_v9 holds real server responses (server/internal/api/v9_contract_test.go).
Map<String, dynamic> _load(String name) =>
    jsonDecode(File('test/contract_v9/$name.json').readAsStringSync()) as Map<String, dynamic>;

// A 1x1 PNG, enough for Image.memory to decode.
final _png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==',
);

StubAdapter _server() {
  final server = fullServer()
    ..on('GET /api/training/today', StubResponse(200, _load('training_today')))
    ..on('GET /api/exercises', StubResponse(200, _load('exercises')))
    ..on('GET /api/sets', StubResponse(200, _load('sets')))
    ..on('POST /api/sets', StubResponse(201, _load('set_created')));
  for (final key in ['push_up', 'pull_up', 'db_row', 'db_overhead_press', 'plank', 'dead_hang']) {
    for (final n in [0, 1]) {
      server.on('GET /api/exercises/$key/images/$n', StubResponse.bytes(200, _png));
    }
  }
  return server;
}

Finder _button(String label) => find.text(label.toUpperCase());

Finder _howTo(String name) =>
    find.byWidgetPredicate((w) => w is HowToButton && w.name == name, description: 'How to $name');

Finder get _countTarget =>
    find.descendant(of: find.byType(RepCounter), matching: find.byType(Pressable));

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

void main() {
  setUp(() {
    FakeStorage().install();
    Mascot.idleMotion = false;
  });

  group('contract', () {
    test('the catalog carries steps, cues and photo paths', () {
      final c = ExerciseCatalog.parse(_load('exercises'));
      final push = c.byKey('push_up')!;
      expect(push.steps.length, inInclusiveRange(3, 6));
      expect(push.cues.length, inInclusiveRange(1, 2));
      expect(push.imageUrls, [
        '/api/exercises/push_up/images/0',
        '/api/exercises/push_up/images/1',
      ]);
      final burpee = c.byKey('burpee')!;
      expect(burpee.steps, isNotEmpty);
      expect(burpee.imageUrls, isEmpty);
      for (final e in c.exercises) {
        expect(e.hasHowTo, isTrue, reason: e.key);
      }
      final again = ExerciseCatalog.parse(jsonDecode(jsonEncode(c.toJson())));
      expect(again.byKey('push_up')!.steps, push.steps);
      expect(again.byKey('push_up')!.imageUrls, push.imageUrls);
    });
  });

  group('how-to', () {
    testWidgets('a session card opens steps, cues and both photos', (tester) async {
      final server = _server();
      final app = TestApp(tester, server, surfaceHeight: 3000);
      await app.pump(const SessionPage());
      await tester.pumpAndSettle();

      final button = _howTo('Push-up');
      expect(button, findsOneWidget);
      expect(tester.getSize(button).width, greaterThanOrEqualTo(44));
      expect(tester.getSize(button).height, greaterThanOrEqualTo(44));
      await tester.tap(button);
      await tester.pumpAndSettle();

      final push = ExerciseCatalog.parse(_load('exercises')).byKey('push_up')!;
      expect(find.text('Works chest'), findsOneWidget);
      expect(find.text('Steps'), findsOneWidget);
      expect(find.text(push.steps.first), findsOneWidget);
      expect(find.text(push.steps.last), findsOneWidget);
      expect(find.text('Form cues'), findsOneWidget);
      expect(find.text(push.cues.first), findsOneWidget);
      expect(find.text('Start'), findsOneWidget);
      expect(find.text('End'), findsOneWidget);
      expect(find.byType(Image), findsNWidgets(2));
      expect(server.to('GET /api/exercises/push_up/images/0'), hasLength(1));
      expect(server.to('GET /api/exercises/push_up/images/1'), hasLength(1));
      // The photos are sent with the same app key and token as every other call.
      expect(
        server.to('GET /api/exercises/push_up/images/0').single.headers['X-App-Key'],
        isNotNull,
      );
    });

    testWidgets('an exercise without a photo shows its steps and no photo area', (tester) async {
      final app = TestApp(tester, _server(), surfaceHeight: 3000);
      await app.pump(const SessionPage());
      await tester.pumpAndSettle();

      await tester.tap(_howTo('Split squat'));
      await tester.pumpAndSettle();
      final split = ExerciseCatalog.parse(_load('exercises')).byKey('split_squat')!;
      expect(split.imageUrls, isEmpty);
      expect(find.text(split.steps.first), findsOneWidget);
      expect(find.text('Start'), findsNothing);
      expect(find.byType(Image), findsNothing);
    });

    testWidgets('the exercises page opens it from a row and from the exercise page', (
      tester,
    ) async {
      final app = TestApp(tester, _server(), surfaceHeight: 8000);
      await app.pump(const ExercisesPage());
      await tester.pumpAndSettle();

      await tester.tap(_howTo('Plank'));
      await tester.pumpAndSettle();
      final plank = ExerciseCatalog.parse(_load('exercises')).byKey('plank')!;
      expect(find.text(plank.steps.first), findsOneWidget);
      await app.closeSheet();

      await tester.tap(find.text('Plank'));
      await tester.pumpAndSettle();
      await tester.tap(_button('How to do it'));
      await tester.pumpAndSettle();
      expect(find.text('Steps'), findsOneWidget);
      expect(find.text(plank.steps.first), findsOneWidget);
    });

    testWidgets('a failed photo shows a placeholder, not an error', (tester) async {
      final server = _server()..on('GET /api/exercises/push_up/images/0', const StubResponse(404));
      final app = TestApp(tester, server, surfaceHeight: 3000);
      await app.pump(const SessionPage());
      await tester.pumpAndSettle();
      await tester.tap(_howTo('Push-up'));
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.image_not_supported_outlined), findsOneWidget);
      expect(find.byType(Image), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('rep counter', () {
    testWidgets('counts taps with haptics, announces every 5, and fills the reps', (tester) async {
      final rec = _Recorder()..install(tester);
      final app = TestApp(tester, _server(), surfaceHeight: 3000);
      SetValues? logged;
      await app.pump(
        SingleChildScrollView(
          child: SetForm(
            timed: false,
            loaded: false,
            initialAmount: 6,
            onLog: (v) async => logged = v,
          ),
        ),
      );

      await tester.tap(_button('Count reps'));
      await tester.pumpAndSettle();
      final target = _countTarget;
      expect(tester.getSize(target).height, greaterThanOrEqualTo(44));
      expect(find.text('Tap for each rep'), findsOneWidget);
      rec.haptics.clear();

      for (var i = 0; i < 7; i++) {
        await tester.tap(target);
        await tester.pump();
      }
      expect(find.text('7'), findsWidgets);
      expect(rec.haptics.where((h) => h == 'HapticFeedbackType.selectionClick'), hasLength(6));
      expect(rec.haptics.where((h) => h == 'HapticFeedbackType.mediumImpact'), hasLength(1));
      expect(rec.announcements, ['5 reps']);

      await tester.tap(find.text('Undo'));
      await tester.pump();
      await tester.tap(_button('Use 6'));
      await tester.pumpAndSettle();
      expect(find.text('Tap for each rep'), findsNothing);
      expect(find.widgetWithText(TextField, '6'), findsOneWidget);

      await tester.tap(_button('Log set'));
      await tester.pumpAndSettle();
      expect(logged!.amount, 6);
    });

    testWidgets('Done stays off until a rep is counted and Cancel keeps the field', (tester) async {
      final app = TestApp(tester, _server());
      await app.pump(
        SingleChildScrollView(
          child: SetForm(timed: false, loaded: false, initialAmount: 8, onLog: (_) async {}),
        ),
      );
      await tester.tap(_button('Count reps'));
      await tester.pumpAndSettle();
      await tester.tap(_button('Done'));
      await tester.pump();
      expect(find.text('Tap for each rep'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(TextField, '8'), findsOneWidget);
      expect(_button('Count reps'), findsOneWidget);
    });

    testWidgets('works from the session sheet with reduced motion', (tester) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue = const FakeAccessibilityFeatures(
        disableAnimations: true,
      );
      addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
      final server = _server();
      final app = TestApp(tester, server, surfaceHeight: 3000);
      await app.pump(const SessionPage());
      await tester.pumpAndSettle();

      await tester.tap(_button('Log set 1 of 2').first);
      await tester.pumpAndSettle();
      await tester.tap(_button('Count reps'));
      await tester.pumpAndSettle();
      for (var i = 0; i < 9; i++) {
        await tester.tap(_countTarget);
        await tester.pump();
      }
      await tester.tap(_button('Use 9'));
      await tester.pumpAndSettle();
      await tester.tap(_button('Log set'));
      await tester.pumpAndSettle(const Duration(milliseconds: 100));

      expect(app.body('POST /api/sets')['reps'], 9);
      expect(app.body('POST /api/sets')['exercise'], 'push_up');
    });
  });

  group('hold timer', () {
    Future<(TestApp, _Recorder, List<SetValues>)> pumpTimed(WidgetTester tester) async {
      final rec = _Recorder()..install(tester);
      final app = TestApp(tester, _server());
      final logged = <SetValues>[];
      await app.pump(
        SingleChildScrollView(
          child: SetForm(
            timed: true,
            loaded: false,
            initialAmount: 5,
            onLog: (v) async => logged.add(v),
          ),
        ),
      );
      return (app, rec, logged);
    }

    testWidgets('leads in for 3 seconds, counts down, buzzes and fills the seconds', (
      tester,
    ) async {
      final (_, rec, logged) = await pumpTimed(tester);
      await tester.tap(_button('Start timer'));
      await tester.pump();
      expect(find.text('Get ready'), findsOneWidget);
      expect(find.text('3'), findsOneWidget);
      expect(rec.announcements.single, startsWith('Get ready'));

      await tester.pump(const Duration(seconds: 1));
      expect(find.text('2'), findsOneWidget);
      await tester.pump(const Duration(seconds: 2));
      expect(find.text('seconds left'), findsOneWidget);
      expect(find.text('5'), findsWidgets);
      expect(rec.announcements.last, 'Go');

      await tester.pump(const Duration(seconds: 1));
      expect(find.text('4'), findsOneWidget);
      rec.haptics.clear();
      await tester.pump(const Duration(seconds: 4));
      await tester.pumpAndSettle();
      expect(rec.haptics, contains('HapticFeedbackType.heavyImpact'));
      expect(rec.announcements.last, 'Time. 5 seconds done');
      expect(find.text('seconds left'), findsNothing);
      expect(find.widgetWithText(TextField, '5'), findsOneWidget);

      await tester.tap(_button('Log set'));
      await tester.pumpAndSettle();
      expect(logged.single.amount, 5);
    });

    testWidgets('stopping early uses the seconds held, and stopping in the lead-in uses none', (
      tester,
    ) async {
      final (_, _, logged) = await pumpTimed(tester);
      await tester.tap(_button('Start timer'));
      await tester.pump(const Duration(seconds: 1));
      await tester.tap(_button('Cancel'));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(TextField, '5'), findsOneWidget);

      await tester.tap(_button('Start timer'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 3));
      await tester.pump(const Duration(seconds: 2));
      expect(find.text('3'), findsWidgets);
      expect(find.byType(BigNumberStepper), findsNothing, reason: 'one big number while timing');
      expect(find.text('seconds left · 2 held'), findsOneWidget);
      await tester.tap(_button('Stop now'));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(TextField, '2'), findsOneWidget);
      await tester.tap(_button('Log set'));
      await tester.pumpAndSettle();
      expect(logged.single.amount, 2);
    });

    testWidgets('needs a time to count down from', (tester) async {
      final app = TestApp(tester, _server());
      await app.pump(
        SingleChildScrollView(child: SetForm(timed: true, loaded: false, onLog: (_) async {})),
      );
      expect(tester.widget<ChunkyButton>(find.byType(ChunkyButton).first).onPressed, isNull);
    });

    testWidgets('the big number does not make the screen read every second', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpTimed(tester);
      await tester.tap(_button('Start timer'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 4));
      expect(find.bySemanticsLabel('Hold timer running'), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp(r'^\d+$')), findsNothing);
      expect(kHoldLeadInSeconds, 3);
      handle.dispose();
    });
  });

  testWidgets('a hold timer catches up on time spent in the background', (tester) async {
    var now = DateTime(2026, 10, 28, 7);
    int? done;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HoldTimer(seconds: 10, onDone: (s) => done = s, onCancel: () {}, now: () => now),
        ),
      ),
    );
    await tester.pump(const Duration(seconds: 3));
    expect(find.text('10'), findsWidgets);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    now = now.add(const Duration(seconds: 4));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(find.text('6'), findsWidgets);

    now = now.add(const Duration(seconds: 20));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(done, isNull, reason: 'no time passed while hidden this time');
  });
}
