import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:newme/api/models.dart';
import 'package:newme/features/log/log_kind.dart';
import 'package:newme/features/log/log_sheet.dart';
import 'package:newme/features/me/daily_reps_page.dart';
import 'package:newme/features/me/me_screen.dart';
import 'package:newme/features/me/target_row.dart';
import 'package:newme/features/me/profile_page.dart';
import 'package:newme/features/me/goals_page.dart';
import 'package:newme/features/setup/about_you_page.dart';
import 'package:newme/features/food/food_card.dart';
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
  await app.pump(const GoalsPage());
  return app;
}

Finder _chip(String label) => find.bySemanticsLabel(label);

Finder _row(String name) => find.bySemanticsLabel(RegExp('^$name\\.'));

Finder _button(String label) =>
    find.byWidgetPredicate((w) => w is ChunkyButton && w.label == label);

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

  group('Goals page', () {
    testWidgets('lists the daily goals, the food numbers, the habits and the body figures', (
      tester,
    ) async {
      await _open(tester, _server());

      for (final section in ['Daily goals', 'Food', 'Habits', 'Recommended figures']) {
        expect(find.text(section), findsOneWidget, reason: section);
      }
      expect(find.text('This is general guidance, not medical advice.'), findsNothing);
      // Figures with a goal of their own are not repeated as a second list.
      expect(find.text('Yours'), findsNothing);
      expect(find.text('Estimate'), findsOneWidget);
      // Formulas, labels and sources wait behind a tap on the row.
      expect(find.textContaining('Mifflin-St Jeor'), findsNothing);
      expect(find.text('Guideline'), findsNothing);
      expect(find.text('Add these to work out your goals'), findsNothing);
    });

    testWidgets('the food numbers are edited here and Save appears only once one changes', (
      tester,
    ) async {
      final server = _server()..on('PATCH /api/me', StubResponse(200, meJson()));
      final app = await _open(tester, server);
      expect(_button('Save'), findsNothing);
      expect(_button('Try again'), findsNothing);

      await tester.enterText(find.widgetWithText(TextField, '2200').first, '2300');
      await app.settle(2);
      expect(_button('Save'), findsOneWidget);
      await app.tap(_button('Save'));
      expect(app.body('PATCH /api/me'), {
        'targets': {'kcal': 2300},
      });
    });

    testWidgets('tapping a row explains the formula, its label and full citations', (tester) async {
      final app = await _open(tester, _server());

      await app.tap(_row('Resting energy'));
      expect(find.textContaining('Mifflin-St Jeor: 10 x 82.4 kg'), findsOneWidget);
      expect(find.text('Guideline'), findsOneWidget);
      expect(find.text('Sources'), findsOneWidget);
      expect(find.textContaining('Mifflin MD et al., Am J Clin Nutr 1990;51:241'), findsOneWidget);
      expect(find.textContaining('J Am Diet Assoc 2005;105:775'), findsOneWidget);
    });

    testWidgets('the log-based estimate is explained with maintenance', (tester) async {
      final app = await _open(tester, _server());
      expect(find.textContaining('Estimated from your logs'), findsNothing);

      await app.tap(_row('Maintenance'));
      expect(find.text('Estimated from your logs: 2,650 kcal'), findsOneWidget);
      expect(find.textContaining('logged intake is commonly under-reported'), findsOneWidget);
    });

    testWidgets('Use all applies every target that differs, in one request', (tester) async {
      final server = _server();
      final app = await _open(tester, server);

      final useAll = find.byWidgetPredicate(
        (w) => w is ChunkyButton && w.label == 'Use all recommended (9)',
      );
      expect(useAll, findsOneWidget);
      await app.tap(useAll);
      expect(app.body('POST /api/targets/apply')['keys'], [
        'calories',
        'protein',
        'fat',
        'carbs',
        'sleep',
        'exercise',
        'steps',
        'pushups',
        'water',
      ]);
      expect(find.textContaining('Applied today:'), findsOneWidget);
    });

    testWidgets('a rejected apply shows the server message and keeps the page', (tester) async {
      final server = _server()
        ..on(
          'POST /api/targets/apply',
          const StubResponse(422, {'error': 'calories has no value yet: heightCm missing'}),
        );
      final app = await _open(tester, server);

      await app.tap(find.textContaining('USE ALL RECOMMENDED'));
      expect(find.textContaining('calories has no value yet'), findsOneWidget);
      expect(find.text('Daily goals'), findsOneWidget);
    });

    testWidgets('missing inputs lead the page with links to fix them', (tester) async {
      final app = await _open(tester, _server(targets: 'targets_missing'));

      expect(find.text('Add these to work out your goals'), findsOneWidget);
      expect(find.text('Height'), findsOneWidget);
      expect(find.text('Sex'), findsOneWidget);
      expect(find.text('Daily reps max test'), findsOneWidget);
      // The rows explain themselves instead of showing a number.
      expect(find.text('Not yet'), findsWidgets);
      await app.tap(_row('Resting energy'));
      expect(find.textContaining('Needs height, sex to be filled in'), findsOneWidget);
      Navigator.of(tester.element(find.text('Sources'))).pop();
      await app.settle(4);

      await app.tap(find.bySemanticsLabel(RegExp('^Height\\.')));
      expect(find.byType(AboutYouPage), findsOneWidget);
      expect(find.text('How tall are you?'), findsOneWidget);
    });

    testWidgets('the max link opens the daily reps setup', (tester) async {
      final server = _server(targets: 'targets_missing')
        ..on(
          'GET /api/daily-reps',
          const StubResponse(200, {
            'exercise': 'push_up',
            'target': 30,
            'enabled': true,
            'dayExercise': 'push_up',
            'sets': 3,
            'exercises': <Object>[],
            'sources': <Object>[],
          }),
        );
      final app = await _open(tester, server);

      await app.tap(find.bySemanticsLabel(RegExp('^Daily reps max test\\.')));
      expect(find.byType(DailyRepsPage), findsOneWidget);
    });

    testWidgets('nothing to use hides Use all', (tester) async {
      final body = _fixture('targets');
      for (final t in body['targets'] as List) {
        (t as Map<String, dynamic>)['applicable'] = false;
      }
      final server = _server()..on('GET /api/targets', StubResponse(200, body));
      await _open(tester, server);
      expect(find.textContaining('Use all'), findsNothing);
    });

    testWidgets('without recommendations the goals still load and can be edited', (tester) async {
      final server = _server()
        ..on('GET /api/targets', const StubResponse(404, {'error': 'not found'}));
      await _open(tester, server);
      expect(find.text('Daily goals'), findsOneWidget);
      expect(find.text('Recommended figures'), findsNothing);
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
        await app.pump(const GoalsPage(), tall: false, key: UniqueKey());
        await app.settle(20);

        _expectTapTargets(tester, [
          find.bySemanticsLabel(RegExp('^Height\\.')),
          find.bySemanticsLabel('Back'),
        ]);

        final list = find.byType(Scrollable).first;
        var infoButtons = 0;
        for (var i = 0; i < 40; i++) {
          expect(tester.takeException(), isNull, reason: 'while scrolling');
          final rows = find.byType(TargetRow);
          infoButtons += rows.evaluate().length;
          if (rows.evaluate().isNotEmpty) _expectTapTargets(tester, [rows]);
          await tester.drag(list, const Offset(0, -400));
          await app.settle(2);
        }
        expect(infoButtons, greaterThan(0));
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('a row sheet and the Use all button fit at scale 2.0', (tester) async {
      final app = await _open(tester, _server(), scale: 2);
      _expectTapTargets(tester, [find.byType(ChunkyButton)]);

      await app.tap(_row('Resting energy'));
      expect(find.textContaining('Am J Clin Nutr 1990;51:241'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('Me', () {
    testWidgets('Goals is the one row for goals, habits and insights are not listed', (
      tester,
    ) async {
      final app = TestApp(tester, _server(), surfaceHeight: 2400);
      await app.pump(const MeScreen());
      expect(find.text('My foods'), findsNothing);
      for (final gone in ['Targets', 'Habits', 'Insights', 'Daily goals']) {
        expect(find.text(gone), findsNothing, reason: gone);
      }
      await app.tap(find.text('Goals'));
      expect(find.byType(GoalsPage), findsOneWidget);
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

  group('Food card', () {
    Widget card({
      Targets targets = const Targets(kcal: 2200, protein: 150, carbs: 250, fat: 70),
      num burned = 0,
    }) => SingleChildScrollView(
      child: FoodCard(
        food: Food(
          kcal: 900,
          protein: 160,
          carbs: 100,
          fat: 20.4,
          fiber: 5,
          burned: burned,
          targets: targets,
        ),
      ),
    );

    testWidgets('shows what is left of each macro and what is over', (tester) async {
      final app = TestApp(tester, _server());
      await app.pump(card());
      expect(find.text('150 g left'), findsOneWidget);
      expect(find.text('50 g left'), findsOneWidget);
      expect(find.text('10 g over'), findsOneWidget);
    });

    testWidgets('the header says what was eaten of the target and how much is left', (
      tester,
    ) async {
      final app = TestApp(tester, _server());
      await app.pump(card());
      expect(find.text('900 of 2,200 kcal'), findsOneWidget);
      expect(find.text('1,300 left'), findsOneWidget);
    });

    testWidgets('over the calorie target the header says how far over', (tester) async {
      final app = TestApp(tester, _server());
      await app.pump(card(targets: const Targets(kcal: 800)));
      expect(find.text('900 of 800 kcal'), findsOneWidget);
      expect(find.text('100 over'), findsOneWidget);
    });

    testWidgets('without a calorie target the header is just the total', (tester) async {
      final app = TestApp(tester, _server());
      await app.pump(card(targets: const Targets()));
      expect(find.text('900 kcal'), findsOneWidget);
      expect(find.textContaining(' left'), findsNothing);
    });

    testWidgets('a macro without a target shows no remainder', (tester) async {
      final app = TestApp(tester, _server());
      await app.pump(card(targets: const Targets(kcal: 2200)));
      expect(find.textContaining(' g left'), findsNothing);
      expect(find.textContaining(' g over'), findsNothing);
    });

    testWidgets('the activity line shows only when something was burned', (tester) async {
      final app = TestApp(tester, _server());
      await app.pump(card());
      expect(find.textContaining('burned in activity'), findsNothing);

      await app.pump(card(burned: 200), key: UniqueKey());
      expect(find.text('200 kcal burned in activity'), findsOneWidget);
    });

    testWidgets('fits at text scale 2.0', (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = 2.0;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final app = TestApp(tester, _server());
      await app.pump(card(burned: 200));
      expect(tester.takeException(), isNull);
      expect(find.text('10 g over'), findsOneWidget);
    });
  });
}
