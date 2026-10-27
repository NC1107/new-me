import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:newme/api/models.dart';
import 'package:newme/features/log/log_kind.dart';
import 'package:newme/features/log/log_sheet.dart';
import 'package:newme/features/me/me_screen.dart';
import 'package:newme/features/me/profile_page.dart';
import 'package:newme/features/me/targets_page.dart';
import 'package:newme/features/setup/about_you_page.dart';
import 'package:newme/features/today/food_card.dart';
import 'package:newme/widgets/chunky_button.dart';
import 'package:newme/widgets/mascot.dart';

import 'fixtures.dart';
import 'test_support.dart';

Map<String, dynamic> _fixture(String name) =>
    (jsonDecode(File('test/contract_v8/$name.json').readAsStringSync()) as Map)['body']!
        as Map<String, dynamic>;

StubAdapter _server({String targets = 'targets'}) => fullServer()
  ..on('GET /api/targets', StubResponse(200, _fixture(targets)))
  ..on(
    'POST /api/targets/apply',
    StubResponse(200, {
      ...meJson(),
      'applied': ['calories'],
    }),
  );

Future<TestApp> _open(WidgetTester tester, StubAdapter server, {double scale = 1}) async {
  tester.platformDispatcher.textScaleFactorTestValue = scale;
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  final app = TestApp(tester, server, surfaceHeight: 6000);
  await app.pump(const TargetsPage());
  return app;
}

Finder _chip(String label) => find.bySemanticsLabel(label);

void _expectTapTargets(WidgetTester tester, Iterable<Finder> finders) {
  for (final f in finders) {
    expect(f, findsWidgets);
    for (final e in f.evaluate()) {
      final size = tester.getSize(find.byElementPredicate((x) => x == e));
      expect(size.height, greaterThanOrEqualTo(44), reason: '$f height');
      expect(size.width, greaterThanOrEqualTo(44), reason: '$f width');
    }
  }
}

void main() {
  setUp(() {
    FakeStorage().install();
    Mascot.idleMotion = false;
  });

  group('Targets page', () {
    testWidgets('lists each group with value, setting, formula, label and the disclaimer once', (
      tester,
    ) async {
      await _open(tester, _server());

      for (final group in ['Energy', 'Macros', 'Sleep', 'Activity', 'Steps', 'Push-ups']) {
        expect(find.text(group), findsWidgets, reason: group);
      }
      expect(find.text('This is general guidance, not medical advice.'), findsOneWidget);

      expect(find.text('2,350 kcal'), findsOneWidget);
      expect(find.text('Your setting: 2,200 kcal'), findsOneWidget);
      expect(find.text('Your setting: not set'), findsWidgets);
      expect(find.text('7 h 30 min'), findsOneWidget);
      expect(find.text('Your setting: 7 h'), findsOneWidget);
      expect(find.textContaining('Mifflin-St Jeor: 10 x 82.4 kg'), findsOneWidget);
      expect(
        find.textContaining('Maintenance 2,750 kcal (our step-band convention)'),
        findsOneWidget,
      );

      expect(find.text('Guideline'), findsWidgets);
      expect(find.text('Convention'), findsOneWidget);
      expect(find.text('Derivation'), findsWidgets);
      expect(find.text('Needed to work these out'), findsNothing);
    });

    testWidgets('sources are one tap away and show full citations', (tester) async {
      final app = await _open(tester, _server());
      expect(find.textContaining('Am J Clin Nutr 1990;51:241'), findsNothing);

      await app.tap(find.bySemanticsLabel('Sources (2) for Resting energy'));
      expect(find.textContaining('Mifflin MD et al., Am J Clin Nutr 1990;51:241'), findsOneWidget);
      expect(find.textContaining('J Am Diet Assoc 2005;105:775'), findsOneWidget);

      await app.tap(find.bySemanticsLabel('Sources (2) for Resting energy'));
      expect(find.textContaining('Am J Clin Nutr 1990;51:241'), findsNothing);
    });

    testWidgets('the log-based estimate is a secondary line under maintenance', (tester) async {
      await _open(tester, _server());
      expect(find.text('Estimated from your logs: 2,650 kcal'), findsOneWidget);
      expect(find.textContaining('logged intake is commonly under-reported'), findsOneWidget);
      // The estimate is not a row of its own.
      expect(find.text('Estimated from your logs'), findsNothing);
    });

    testWidgets('extra detail lines show bedtime, shortfall and the push-up max', (tester) async {
      await _open(tester, _server());
      expect(find.text('Bedtime 11:15 PM (11:45 PM on days off)'), findsOneWidget);
      expect(find.text('Last 7 nights: 5 h short of your target'), findsOneWidget);
      expect(find.text('Sleep Regularity Index 82 of 100'), findsOneWidget);
      expect(find.text('Latest max test: 24 reps (70 to 80% is 17 to 19)'), findsOneWidget);
      expect(find.text('About 0.4 g/kg a meal, 33 g, across 4 meals.'), findsOneWidget);
    });

    testWidgets('Use this applies one target and the toast says it starts tomorrow', (
      tester,
    ) async {
      final server = _server();
      final app = await _open(tester, server);

      await app.tap(_chip('Use this calories target'));
      expect(app.body('POST /api/targets/apply'), {
        'keys': ['calories'],
      });
      expect(find.text('Starts tomorrow: Calories 2,350 kcal'), findsOneWidget);
    });

    testWidgets('Use all applies every target that differs, in one request', (tester) async {
      final server = _server();
      final app = await _open(tester, server);

      final useAll = find.byWidgetPredicate((w) => w is ChunkyButton && w.label == 'Use all (7)');
      expect(useAll, findsOneWidget);
      await app.tap(useAll);
      expect(app.body('POST /api/targets/apply')['keys'], [
        'calories',
        'protein',
        'fat',
        'carbs',
        'sleep',
        'steps',
        'pushups',
      ]);
    });

    testWidgets('a rejected apply shows the server message and keeps the page', (tester) async {
      final server = _server()
        ..on(
          'POST /api/targets/apply',
          const StubResponse(422, {'error': 'calories has no value yet: heightCm missing'}),
        );
      final app = await _open(tester, server);

      await app.tap(_chip('Use this calories target'));
      expect(find.textContaining('calories has no value yet'), findsOneWidget);
      expect(find.text('Calories'), findsOneWidget);
    });

    testWidgets('missing inputs lead the page with links to fix them', (tester) async {
      final app = await _open(tester, _server(targets: 'targets_missing'));

      expect(find.text('Needed to work these out'), findsOneWidget);
      expect(find.text('Height'), findsOneWidget);
      expect(find.text('Sex'), findsOneWidget);
      expect(find.text('Push-up max test'), findsOneWidget);
      // The rows explain themselves instead of showing a number.
      expect(find.text('Not available yet'), findsWidgets);
      expect(find.textContaining('Needs height, sex to be filled in'), findsWidgets);
      // The estimate has no value, so it shows no line.
      expect(find.textContaining('Estimated from your logs'), findsNothing);

      await app.tap(find.bySemanticsLabel(RegExp('^Height\\.')));
      expect(find.byType(AboutYouPage), findsOneWidget);
      expect(find.text('How tall are you?'), findsOneWidget);
    });

    testWidgets('the push-up max link opens the push-up sheet on Max test', (tester) async {
      final app = await _open(tester, _server(targets: 'targets_missing'));

      await app.tap(find.bySemanticsLabel(RegExp('^Push-up max test\\.')));
      expect(find.text('Log push-ups'), findsOneWidget);
      expect(find.text('SAVE MAX TEST'), findsOneWidget);
    });

    testWidgets('nothing to use hides Use all', (tester) async {
      final body = _fixture('targets');
      for (final t in body['targets'] as List) {
        (t as Map<String, dynamic>)['applicable'] = false;
      }
      final server = _server()..on('GET /api/targets', StubResponse(200, body));
      await _open(tester, server);
      expect(find.textContaining('Use all'), findsNothing);
      expect(find.text('Changes start tomorrow.'), findsNothing);
    });

    testWidgets('a failed first load says so and can retry', (tester) async {
      final server = _server()..on('GET /api/targets', const StubResponse(404));
      final app = await _open(tester, server);
      expect(find.text('Could not load your targets'), findsOneWidget);
      server.on('GET /api/targets', StubResponse(200, _fixture('targets')));
      await app.tap(find.text('Try again'));
      expect(find.text('2,350 kcal'), findsOneWidget);
    });
  });

  group('layout', () {
    for (final scale in [1.0, 2.0]) {
      testWidgets('fits at text scale $scale with every control at least 44 points', (
        tester,
      ) async {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        addTearDown(tester.view.reset);
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        final app = TestApp(tester, _server(targets: 'targets_missing'));
        await app.pump(const TargetsPage(), tall: false, key: UniqueKey());
        await app.settle(20);

        _expectTapTargets(tester, [
          find.bySemanticsLabel(RegExp('^Height\\.')),
          find.bySemanticsLabel('Back'),
        ]);

        final list = find.byType(Scrollable).first;
        var sourceRows = 0;
        for (var i = 0; i < 40; i++) {
          expect(tester.takeException(), isNull, reason: 'while scrolling');
          final rows = find.bySemanticsLabel(RegExp('^Sources'));
          sourceRows += rows.evaluate().length;
          if (rows.evaluate().isNotEmpty) _expectTapTargets(tester, [rows]);
          await tester.drag(list, const Offset(0, -400));
          await app.settle(2);
        }
        expect(sourceRows, greaterThan(0));
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('an expanded source list and the Use buttons fit at scale 2.0', (tester) async {
      final app = await _open(tester, _server(), scale: 2);

      await app.tap(find.text('Sources (2)').first);
      expect(find.textContaining('Am J Clin Nutr 1990;51:241'), findsOneWidget);
      expect(tester.takeException(), isNull);
      _expectTapTargets(tester, [_chip('Use this calories target')]);
    });
  });

  group('Me', () {
    testWidgets('Targets and My foods are always listed, and Targets opens the page', (
      tester,
    ) async {
      final app = TestApp(tester, _server(), surfaceHeight: 2400);
      await app.pump(const MeScreen());
      expect(find.text('My foods'), findsOneWidget);
      expect(find.text('Targets'), findsOneWidget);
      await app.tap(find.text('Targets'));
      expect(find.byType(TargetsPage), findsOneWidget);
      expect(find.text('2,350 kcal'), findsOneWidget);
    });
  });

  group('Profile', () {
    Future<TestApp> openProfile(WidgetTester tester, StubAdapter server) async {
      final app = TestApp(tester, server, surfaceHeight: 2400);
      await app.pump(const ProfilePage());
      return app;
    }

    StubAdapter profileServer({Map<String, dynamic>? user}) => fullServer()
      ..on(
        'GET /api/me',
        StubResponse(200, {
          ...meJson(),
          'user': {...meJson()['user'] as Map<String, dynamic>, ...?user},
        }),
      )
      ..on('PATCH /api/me', StubResponse(200, meJson()));

    testWidgets('height, sex and a lose pace are saved in one patch', (tester) async {
      final app = await openProfile(tester, profileServer());

      await app.enter(find.byType(TextField).at(1), '181.5');
      await app.tap(find.bySemanticsLabel('Female'));
      await app.tap(find.bySemanticsLabel('Lose'));
      await app.tap(find.bySemanticsLabel('0.5 kg a week'));
      await app.tap(find.text('SAVE'));

      expect(app.body('PATCH /api/me'), {
        'heightCm': 181.5,
        'sex': 'female',
        'goal': {'kind': 'lose', 'paceKgPerWeek': 0.5},
      });
    });

    testWidgets('gain offers its own paces and maintain has none', (tester) async {
      final app = await openProfile(tester, profileServer());

      await app.tap(find.bySemanticsLabel('Gain'));
      expect(find.bySemanticsLabel('0.1 kg a week'), findsOneWidget);
      expect(find.bySemanticsLabel('0.25 kg a week'), findsOneWidget);
      await app.tap(find.bySemanticsLabel('0.1 kg a week'));
      await app.tap(find.bySemanticsLabel('Maintain'));
      expect(find.textContaining('kg a week'), findsNothing);
      await app.tap(find.bySemanticsLabel('Gain'));
      await app.tap(find.text('SAVE'));
      expect(app.body('PATCH /api/me')['goal'], {'kind': 'gain', 'paceKgPerWeek': 0.25});
    });

    testWidgets('the saved values show, can be cleared, and a bad height blocks Save', (
      tester,
    ) async {
      final app = await openProfile(
        tester,
        profileServer(
          user: {
            'heightCm': 178.0,
            'sex': 'male',
            'goal': {'kind': 'lose', 'paceKgPerWeek': 0.25},
          },
        ),
      );
      expect(find.widgetWithText(TextField, '178'), findsOneWidget);
      expect(find.text('SAVE'), findsOneWidget);

      await app.enter(find.byType(TextField).at(1), '90');
      expect(find.text('Between 100 and 250 cm'), findsOneWidget);
      expect(
        tester
            .widget<ChunkyButton>(
              find.byWidgetPredicate((w) => w is ChunkyButton && w.label == 'Save'),
            )
            .onPressed,
        isNull,
      );

      await app.enter(find.byType(TextField).at(1), '');
      await app.tap(find.bySemanticsLabel('Male'));
      await app.tap(find.text('SAVE'));
      final body = app.body('PATCH /api/me');
      expect(body, {'heightCm': null, 'sex': null});
    });

    testWidgets('fits at text scale 2.0', (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = 2.0;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final app = await openProfile(tester, profileServer());
      await app.tap(find.bySemanticsLabel('Lose'));
      expect(tester.takeException(), isNull);
      _expectTapTargets(tester, [_chip('Female'), _chip('Lose'), _chip('0.25 kg a week')]);
    });
  });

  group('push-up max test', () {
    Future<TestApp> openSheet(WidgetTester tester, StubAdapter server) async {
      final app = TestApp(tester, server);
      await app.pump(
        Builder(
          builder: (context) => Center(
            child: ElevatedButton(
              onPressed: () => showLogSheet(context, kind: LogKind.pushups),
              child: const Text('Open'),
            ),
          ),
        ),
      );
      await app.tap(find.text('Open'));
      return app;
    }

    StubAdapter maxServer() => fullServer()
      ..on('POST /api/pushups/max', const StubResponse(201, {'date': '2026-10-26', 'reps': 25}))
      ..on('POST /api/logs', StubResponse(201, logResultJson()));

    testWidgets('records through /pushups/max and not as a log entry', (tester) async {
      final server = maxServer();
      final app = await openSheet(tester, server);

      await app.tap(find.bySemanticsLabel('Max test'));
      expect(find.textContaining('One set to near failure'), findsOneWidget);
      await app.tap(find.text('+5'));
      expect(find.text('25'), findsOneWidget);
      await app.tap(find.text('SAVE MAX TEST'));

      expect(app.body('POST /api/pushups/max'), {'reps': 25});
      expect(server.to('POST /api/logs'), isEmpty);
      expect(find.text('Max test saved: 25 push-ups'), findsOneWidget);
      expect(find.text('Log push-ups'), findsNothing);
    });

    testWidgets('a plain set still logs as push-ups', (tester) async {
      final server = maxServer();
      final app = await openSheet(tester, server);

      await app.tap(find.text('SAVE'));
      expect(server.to('POST /api/logs'), hasLength(1));
      expect(server.to('POST /api/pushups/max'), isEmpty);
    });

    testWidgets('a rejected test keeps the sheet and says why', (tester) async {
      final server = maxServer()
        ..on('POST /api/pushups/max', const StubResponse(422, {'error': 'That day is closed'}));
      final app = await openSheet(tester, server);

      await app.tap(find.bySemanticsLabel('Max test'));
      await app.tap(find.text('SAVE MAX TEST'));
      expect(find.text('Log push-ups'), findsOneWidget);
      expect(find.text('That day is closed'), findsOneWidget);
    });
  });

  group('Today food card', () {
    Widget card({Targets targets = const Targets(kcal: 2200, protein: 150, carbs: 250, fat: 70)}) =>
        SingleChildScrollView(
          child: FoodCard(
            food: Food(
              kcal: 900,
              protein: 160,
              carbs: 100,
              fat: 20.4,
              fiber: 5,
              burned: 200,
              targets: targets,
            ),
            onTap: () {},
            onSetTargets: () {},
          ),
        );

    testWidgets('shows what is left of each macro and what is over', (tester) async {
      final app = TestApp(tester, _server());
      await app.pump(card());
      expect(find.text('150 g left'), findsOneWidget);
      expect(find.text('50 g left'), findsOneWidget);
      expect(find.text('10 g over'), findsOneWidget);
    });

    testWidgets('a macro without a target shows no remainder', (tester) async {
      final app = TestApp(tester, _server());
      await app.pump(card(targets: const Targets(kcal: 2200)));
      expect(find.textContaining(' left'), findsNothing);
      expect(find.textContaining(' over'), findsNothing);
    });

    testWidgets('fits at text scale 2.0', (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = 2.0;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final app = TestApp(tester, _server());
      await app.pump(card());
      expect(tester.takeException(), isNull);
      expect(find.text('10 g over'), findsOneWidget);
    });
  });
}
