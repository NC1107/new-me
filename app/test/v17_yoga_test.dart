import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:newme/api/models.dart';
import 'package:newme/features/training/exercises_page.dart';
import 'package:newme/features/training/guided_session.dart';
import 'package:newme/features/training/train_screen.dart';
import 'package:newme/features/training/yoga_flows.dart';
import 'package:newme/features/training/yoga_page.dart';
import 'package:newme/widgets/mascot.dart';

import 'fixtures.dart';
import 'test_support.dart';

/// test/contract_v9 holds real server responses (server/internal/api/v9_contract_test.go).
dynamic _load(String name) => jsonDecode(File('test/contract_v9/$name.json').readAsStringSync());

Map<String, dynamic> _plan({
  bool todayDone = true,
  int? offer,
  bool withPlan = true,
  int done = 1,
}) {
  final json = jsonDecode(jsonEncode(_load('yoga_plan'))) as Map<String, dynamic>;
  if (!withPlan) {
    json['plan'] = null;
    json['week'] = null;
    json['today'] = {'planned': false, 'done': false, 'flowMinutes': 0};
    return json;
  }
  (json['today'] as Map)['done'] = todayDone;
  (json['week'] as Map)['done'] = done;
  if (offer != null) json['progression'] = {'offer': true, 'nextMinutes': offer};
  return json;
}

// A 1x1 PNG, enough for Image.memory to decode.
final _png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==',
);

ExerciseCatalog get _catalog => ExerciseCatalog.parse(_load('exercises'));

StubAdapter _server({Map<String, dynamic>? plan}) {
  final server = fullServer()
    ..on('GET /api/exercises', StubResponse(200, _load('exercises')))
    ..on('GET /api/training/profile', StubResponse(200, _load('training_profile_empty')))
    ..on('GET /api/training/today', StubResponse(200, _load('training_today_none')))
    ..on('GET /api/yoga/plan', StubResponse(200, plan ?? _plan()))
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

/// Records what the platform was asked to open, in place of a browser.
List<String> _launched(WidgetTester tester) {
  final urls = <String>[];
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    const MethodChannel('plugins.flutter.io/url_launcher'),
    (call) async {
      if (call.method == 'launch') urls.add((call.arguments as Map)['url'] as String);
      return true;
    },
  );
  addTearDown(
    () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/url_launcher'),
      null,
    ),
  );
  return urls;
}

void _noOverflow(WidgetTester tester) {
  final error = tester.takeException();
  expect(error, isNull, reason: error is FlutterError ? error.toStringDeep() : '$error');
}

void main() {
  setUp(() {
    FakeStorage().install();
    Mascot.idleMotion = false;
  });

  group('the catalog', () {
    test('has 25 poses with credits for every photo', () {
      final poses = _catalog.exercises.where((e) => e.yoga).toList();
      expect(poses, hasLength(25));
      for (final e in poses) {
        expect(e.strength, isFalse, reason: e.key);
        expect(e.pose!.imageCredits, hasLength(e.imageUrls.length), reason: e.key);
        expect(e.pose!.cautions, isNotEmpty, reason: e.key);
        expect(e.steps.length, inInclusiveRange(3, 6), reason: e.key);
      }
      final again = ExerciseCatalog.parse(jsonDecode(jsonEncode(_catalog.toJson())));
      expect(
        again.byKey('yoga_mountain')!.pose!.imageCredits.first.label,
        'Photo: Kennguru, CC BY 3.0',
      );
      expect(again.byKey('yoga_mountain')!.kind, ExerciseKind.yoga);
    });

    test('an unknown kind is strength, so an older app still lists it', () {
      expect(ExerciseKind.parse('mystery'), ExerciseKind.strength);
    });

    test('the strength library leaves poses to the Yoga filter', () {
      final strength = [for (final (_, list) in groupExercises(_catalog, '')) ...list];
      expect(strength.where((e) => !e.strength), isEmpty);
      final poses = groupPoses(_catalog, '');
      expect(
        [for (final (label, _) in poses) label],
        ['Standing', 'Kneeling and all fours', 'Seated', 'On your front', 'On your back'],
      );
      expect(poses.expand((g) => g.$2), hasLength(25));
      expect(groupPoses(_catalog, 'tadasana').expand((g) => g.$2).map((e) => e.name), ['Mountain']);
    });
  });

  group('the flows', () {
    test('are about 10, 20 and 30 minutes and end resting in corpse pose', () {
      for (final flow in kYogaFlows) {
        final holds = buildYogaHolds(flow, _catalog);
        final minutes = guidedTotalSeconds(holds) / 60;
        expect(minutes, closeTo(flow.minutes, 0.75), reason: flow.name);
        expect(holds.last.exercise.key, 'yoga_corpse', reason: flow.name);
        expect(holds.first.exercise.key, 'yoga_easy', reason: flow.name);
      }
    });

    test('every step names a pose the library has', () {
      for (final flow in kYogaFlows) {
        for (final step in flow.steps) {
          expect(_catalog.byKey(step.key)?.yoga, isTrue, reason: '${flow.name} ${step.key}');
        }
      }
    });

    test('longer flows hold more poses and the holds never pass ACSM 30 seconds apiece', () {
      final counts = [
        for (final f in kYogaFlows)
          buildYogaHolds(f, _catalog).map((h) => h.stepIndex).toSet().length,
      ];
      expect(counts[0], lessThan(counts[1]));
      expect(counts[1], lessThan(counts[2]));
      for (final flow in kYogaFlows) {
        for (final h in buildYogaHolds(flow, _catalog)) {
          if (h.exercise.key == 'yoga_corpse' || h.exercise.key == 'yoga_legs_up_wall') continue;
          expect(h.seconds, kYogaHoldSeconds, reason: '${flow.name} ${h.exercise.key}');
        }
      }
    });

    test('a pose done on each side runs left then right, and a repeat stays on its side', () {
      final holds = buildYogaHolds(kYogaFlows[2], _catalog);
      final lunge = holds.where((h) => h.exercise.key == 'yoga_low_lunge').toList();
      expect(
        [for (final h in lunge) h.label],
        [
          'Left side, hold 1 of 2',
          'Left side, hold 2 of 2',
          'Right side, hold 1 of 2',
          'Right side, hold 2 of 2',
        ],
      );
      expect(lunge.where((h) => h.firstOfStep), hasLength(1));
      final warrior = buildYogaHolds(
        kYogaFlows[0],
        _catalog,
      ).where((h) => h.exercise.key == 'yoga_warrior_ii').map((h) => h.label);
      expect(warrior, ['Left side', 'Right side']);
    });

    test('a pose the server lacks is skipped', () {
      final short = ExerciseCatalog(
        exercises: [
          for (final e in _catalog.exercises)
            if (e.key != 'yoga_chair') e,
        ],
      );
      final keys = buildYogaHolds(kYogaFlows[0], short).map((h) => h.exercise.key);
      expect(keys, isNot(contains('yoga_chair')));
      expect(keys, contains('yoga_mountain'));
    });
  });

  group('the library', () {
    testWidgets('filters to yoga and groups the poses', (tester) async {
      final app = TestApp(tester, _server(), surfaceHeight: 6000);
      await app.pump(const ExercisesPage());
      await tester.pumpAndSettle();
      expect(find.text('Mountain'), findsNothing);
      expect(find.text('Push-up'), findsOneWidget);

      await tester.tap(find.text('Yoga'));
      await tester.pumpAndSettle();
      expect(find.text('Push-up'), findsNothing);
      for (final label in [
        'Standing',
        'Kneeling and all fours',
        'Seated',
        'On your front',
        'On your back',
      ]) {
        expect(
          find.text(label.toUpperCase()).evaluate().isNotEmpty ||
              find.text(label).evaluate().isNotEmpty,
          isTrue,
          reason: label,
        );
      }
      expect(find.text('Mountain'), findsOneWidget);
      expect(find.text('Tadasana'), findsOneWidget);
      expect(find.text('Warrior I'), findsOneWidget);
      expect(find.text('Add your own'.toUpperCase()), findsNothing);

      await tester.enterText(find.byType(TextField), 'sphinx');
      await tester.pumpAndSettle();
      expect(find.text('Sphinx'), findsOneWidget);
      expect(find.text('Mountain'), findsNothing);
      await tester.enterText(find.byType(TextField), 'zzz');
      await tester.pumpAndSettle();
      expect(find.text('No pose by that name'), findsOneWidget);
    });

    testWidgets('opens on Yoga when asked', (tester) async {
      final app = TestApp(tester, _server(), surfaceHeight: 6000);
      await app.pump(const ExercisesPage(initialFilter: LibraryFilter.yoga));
      await tester.pumpAndSettle();
      expect(find.text('Mountain'), findsOneWidget);
    });

    testWidgets('fits at text scale 2.0', (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = 2.0;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final app = TestApp(tester, _server(), surfaceHeight: 9000);
      await app.pump(const ExercisesPage(initialFilter: LibraryFilter.yoga));
      await tester.pumpAndSettle();
      _noOverflow(tester);
      final row = find.ancestor(of: find.text('Mountain'), matching: find.byType(InkWell)).first;
      expect(tester.getSize(row).height, greaterThanOrEqualTo(44));
    });
  });

  group('a pose page', () {
    testWidgets('shows steps, cautions and a photo credit that opens the file page', (
      tester,
    ) async {
      final launched = _launched(tester);
      final app = TestApp(tester, _server(), surfaceHeight: 3000);
      await app.pump(const ExercisesPage(initialFilter: LibraryFilter.yoga));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Mountain'));
      await tester.pumpAndSettle();

      final mountain = _catalog.byKey('yoga_mountain')!;
      expect(find.text('Tadasana'), findsOneWidget);
      expect(find.text(mountain.pose!.effect), findsOneWidget);
      expect(find.text(mountain.pose!.holdNote), findsOneWidget);
      expect(find.text(mountain.steps.first), findsOneWidget);
      expect(find.text('Take care'), findsOneWidget);
      expect(find.text(mountain.pose!.cautions.first), findsOneWidget);
      expect(find.textContaining('NCCIH'), findsWidgets);
      expect(find.text('Log a set'.toUpperCase()), findsNothing);
      expect(find.byType(Image), findsOneWidget);

      final credit = find.text('Photo: Kennguru, CC BY 3.0');
      expect(credit, findsOneWidget);
      expect(
        tester.getSize(find.ancestor(of: credit, matching: find.byType(InkWell)).first).height,
        greaterThanOrEqualTo(44),
      );
      await tester.tap(credit);
      await tester.pump();
      expect(launched, [mountain.pose!.imageCredits.first.sourceUrl]);
      expect(launched.single, startsWith('https://commons.wikimedia.org/wiki/File:'));
    });

    testWidgets('a pose with two photos credits both', (tester) async {
      final app = TestApp(tester, _server(), surfaceHeight: 3000);
      await app.pump(const ExercisesPage(initialFilter: LibraryFilter.yoga));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cat-cow'));
      await tester.pumpAndSettle();
      expect(find.byType(Image), findsNWidgets(2));
      expect(find.text('Photo: Mary O\'Neill, Public domain'), findsNWidgets(2));
    });
  });

  group('the yoga page', () {
    testWidgets('counts the week, lists three flows and links the library', (tester) async {
      final app = TestApp(tester, _server(), surfaceHeight: 3000);
      await app.pump(const YogaPage());
      await tester.pumpAndSettle();
      expect(find.text('Yoga this week: 1 of 3'), findsOneWidget);
      expect(find.textContaining('Mon, Wed, Fri'), findsOneWidget);
      expect(find.text('Today\'s yoga is done.'), findsOneWidget);
      expect(find.text('Yoga 10'), findsOneWidget);
      expect(find.text('Yoga 20'), findsOneWidget);
      expect(find.text('Yoga 30'), findsOneWidget);
      expect(find.textContaining('not from a trial'), findsOneWidget);
      expect(find.textContaining('Garber'), findsWidgets);
      await tester.tap(find.text('Pose library'));
      await tester.pumpAndSettle();
      expect(find.text('Mountain'), findsOneWidget);
    });

    testWidgets('offers today\'s planned flow and starts it', (tester) async {
      final app = TestApp(
        tester,
        _server(plan: _plan(todayDone: false, done: 0)),
        surfaceHeight: 3000,
      );
      await app.pump(const YogaPage());
      await tester.pumpAndSettle();
      expect(find.text('Yoga this week: 0 of 3'), findsOneWidget);
      await tester.tap(_button('Today: Yoga 10'));
      await tester.pumpAndSettle();
      expect(find.text('14 poses, about 10 minutes, timed for you.'), findsOneWidget);
    });

    testWidgets('a person without a plan picks days and a flow and saves', (tester) async {
      final server = _server(plan: _plan(withPlan: false));
      server.routes['PUT /api/yoga/plan'] = (_) => StubResponse(200, _plan());
      final app = TestApp(tester, server, surfaceHeight: 3000);
      await app.pump(const YogaPage());
      await tester.pumpAndSettle();
      expect(
        find.text('Plan your week'.toUpperCase()).evaluate().isNotEmpty ||
            find.text('Plan your week').evaluate().isNotEmpty,
        isTrue,
      );
      expect(find.textContaining('at least 2 to 3 days a week'), findsOneWidget);
      await tester.tap(find.bySemanticsLabel('4 days a week'));
      await tester.pump();
      await tester.tap(find.text('20 min'));
      await tester.pump();
      await tester.tap(_button('Save plan'));
      await tester.pumpAndSettle();
      final body = app.body('PUT /api/yoga/plan');
      expect(body, {'daysPerWeek': 4, 'flowMinutes': 20});
      expect(find.text('Yoga this week: 1 of 3'), findsOneWidget);
    });

    testWidgets('offers the next longer flow and takes it only when asked', (tester) async {
      final server = _server(plan: _plan(offer: 20));
      server.routes['PUT /api/yoga/plan'] = (_) => StubResponse(200, _plan());
      final app = TestApp(tester, server, surfaceHeight: 3000);
      await app.pump(const YogaPage());
      await tester.pumpAndSettle();
      expect(find.text('Ready for Yoga 20?'), findsOneWidget);
      expect(server.to('PUT /api/yoga/plan'), isEmpty);
      await tester.tap(_button('Try Yoga 20'));
      await tester.pumpAndSettle();
      expect(app.body('PUT /api/yoga/plan'), {'daysPerWeek': 3, 'flowMinutes': 20});
      expect(find.text('Ready for Yoga 20?'), findsNothing);
    });

    testWidgets('Not now keeps the flow and restarts the count', (tester) async {
      final server = _server(plan: _plan(offer: 20));
      server.routes['PUT /api/yoga/plan'] = (_) => StubResponse(200, _plan());
      final app = TestApp(tester, server, surfaceHeight: 3000);
      await app.pump(const YogaPage());
      await tester.pumpAndSettle();
      expect(
        tester.getSize(find.widgetWithText(TextButton, 'Not now')).height,
        greaterThanOrEqualTo(44),
      );
      await tester.tap(find.text('Not now'));
      await tester.pumpAndSettle();
      expect(app.body('PUT /api/yoga/plan'), {
        'daysPerWeek': 3,
        'flowMinutes': 10,
        'restartLevel': true,
      });
    });

    testWidgets('no offer shows no offer', (tester) async {
      final app = TestApp(tester, _server(), surfaceHeight: 3000);
      await app.pump(const YogaPage());
      await tester.pumpAndSettle();
      expect(find.textContaining('Ready for'), findsNothing);
    });

    testWidgets('explains days placed around heavy leg days', (tester) async {
      final plan = _plan()..['avoidedDays'] = [1, 4];
      final app = TestApp(tester, _server(plan: plan), surfaceHeight: 3000);
      await app.pump(const YogaPage());
      await tester.pumpAndSettle();
      expect(find.textContaining('around your heavy leg days (Mon, Thu)'), findsOneWidget);
    });

    testWidgets('fits at text scale 2.0 with 44 point controls', (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = 2.0;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final app = TestApp(
        tester,
        _server(plan: _plan(offer: 20, todayDone: false, done: 0)),
        surfaceHeight: 8000,
      );
      await app.pump(const YogaPage());
      await tester.pumpAndSettle();
      _noOverflow(tester);
      for (final label in [
        'Not now',
        'Try Yoga 20'.toUpperCase(),
        'Today: Yoga 10'.toUpperCase(),
      ]) {
        final size = tester.getSize(find.text(label).first);
        expect(size.height, greaterThan(0), reason: label);
      }
      for (final segment in find.byType(AnimatedContainer).evaluate()) {
        expect(tester.getSize(find.byWidget(segment.widget)).height, greaterThanOrEqualTo(44));
      }
    });
  });

  group('a guided yoga flow', () {
    testWidgets('runs through its poses, both sides, and logs its minutes once', (tester) async {
      final announcements = <String>[];
      tester.binding.defaultBinaryMessenger.setMockDecodedMessageHandler<dynamic>(
        SystemChannels.accessibility,
        (message) async {
          final map = message as Map;
          if (map['type'] == 'announce') {
            announcements.add(((map['data'] as Map)['message']) as String);
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockDecodedMessageHandler<dynamic>(
          SystemChannels.accessibility,
          null,
        ),
      );
      final server = _server();
      final app = TestApp(tester, server, surfaceHeight: 3000);
      await app.pump(const YogaPage());
      await tester.pumpAndSettle();
      await tester.tap(find.text('Yoga 10'));
      await tester.pumpAndSettle();
      expect(find.text('Yoga 10'), findsOneWidget);
      expect(find.textContaining('not from a trial'), findsOneWidget);
      await tester.tap(_button('Start'));
      await tester.pump();

      expect(find.text('Pose 1 of 14'), findsOneWidget);
      expect(find.text('Easy pose'), findsOneWidget);
      expect(find.text('Hold'), findsOneWidget);
      expect(announcements.first, contains('Yoga 10. 14 poses'));
      expect(find.text('Photo: Joseph RENGER, CC BY-SA 3.0'), findsOneWidget);

      final seen = <String>{};
      for (var i = 0; i < 20 * 33; i++) {
        await tester.pump(const Duration(seconds: 1));
        for (final label in ['Left side', 'Right side']) {
          if (find.text(label).evaluate().isNotEmpty) seen.add(label);
        }
        if (find.text('Nice work').evaluate().isNotEmpty) break;
      }
      await tester.pumpAndSettle();
      expect(seen, {'Left side', 'Right side'});
      expect(find.text('Nice work'), findsOneWidget);
      expect(find.text('Logged 10 minutes to your yoga quest.'), findsOneWidget);
      expect(find.text('10 minutes of yoga.'), findsOneWidget);
      expect(server.to('POST /api/logs'), hasLength(1));
      final body = app.body('POST /api/logs');
      expect(body['type'], 'yoga');
      expect(body['unit'], 'minutes');
      expect(body['quantity'], 10);
      expect(announcements.last, 'Yoga 10 done. 10 minutes');
      expect(
        server.to('GET /api/yoga/plan'),
        hasLength(2),
        reason: 'once to open, once after logging',
      );
    });

    testWidgets('skip moves to the next pose and Previous goes back', (tester) async {
      final app = TestApp(tester, _server(), surfaceHeight: 3000);
      await app.pump(const YogaPage());
      await tester.pumpAndSettle();
      await tester.tap(find.text('Yoga 10'));
      await tester.pumpAndSettle();
      await tester.tap(_button('Start'));
      await _seconds(tester, 5);
      await tester.tap(find.widgetWithText(TextButton, 'Skip'));
      await tester.pump();
      expect(find.text('Pose 2 of 14'), findsOneWidget);
      expect(find.text('Cat-cow'), findsOneWidget);
      expect(find.text('Move with your breath'), findsOneWidget);
      await tester.tap(find.widgetWithText(TextButton, 'Previous'));
      await tester.pump();
      expect(find.text('Pose 1 of 14'), findsOneWidget);
      await tester.pumpAndSettle(const Duration(milliseconds: 50));
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('a flow ended before 30 seconds logs nothing', (tester) async {
      final server = _server();
      final app = TestApp(tester, server, surfaceHeight: 3000);
      await app.pump(const YogaPage());
      await tester.pumpAndSettle();
      await tester.tap(find.text('Yoga 10'));
      await tester.pumpAndSettle();
      await tester.tap(_button('Start'));
      await _seconds(tester, 10);
      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();
      expect(find.text('End Yoga 10?'), findsOneWidget);
      await tester.tap(find.text('END'));
      await tester.pumpAndSettle();
      expect(server.to('POST /api/logs'), isEmpty);
    });

    testWidgets('fits at text scale 2.0 while running', (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = 2.0;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final app = TestApp(tester, _server(), surfaceHeight: 3000);
      await app.pump(const YogaPage());
      await tester.pumpAndSettle();
      await tester.tap(find.text('Yoga 10'));
      await tester.pumpAndSettle();
      _noOverflow(tester);
      await tester.tap(_button('Start'));
      await _seconds(tester, 5);
      _noOverflow(tester);
      for (final label in ['Previous', 'Skip']) {
        final size = tester.getSize(find.widgetWithText(TextButton, label));
        expect(size.width, greaterThanOrEqualTo(44), reason: label);
        expect(size.height, greaterThanOrEqualTo(44), reason: label);
      }
    });
  });

  group('the Train tab', () {
    testWidgets('has a Yoga card beside Mobility that opens the yoga page', (tester) async {
      final app = TestApp(tester, _server(), surfaceHeight: 3000);
      await app.pump(const TrainScreen());
      await tester.pumpAndSettle();
      expect(find.text('Yoga'), findsOneWidget);
      expect(find.text('Mobility'), findsOneWidget);
      await tester.tap(find.text('Yoga'));
      await tester.pumpAndSettle();
      expect(find.text('Yoga this week: 1 of 3'), findsOneWidget);
    });
  });
}
