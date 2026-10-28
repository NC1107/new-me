import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:newme/features/me/me_screen.dart';
import 'package:newme/features/setup/about_you.dart';
import 'package:newme/features/setup/about_you_page.dart';
import 'package:newme/features/setup/setup_card.dart';
import 'package:newme/features/today/right_now.dart';
import 'package:newme/features/today/today_screen.dart';
import 'package:newme/state/right_now.dart';
import 'package:newme/api/models.dart';
import 'package:newme/widgets/chunky_button.dart';
import 'package:newme/widgets/dismiss_x.dart';
import 'package:newme/widgets/mascot.dart';

import 'fixtures.dart';
import 'test_support.dart';

Map<String, dynamic> _fixture(String name) =>
    (jsonDecode(File('test/contract_v8/$name.json').readAsStringSync()) as Map)['body']!
        as Map<String, dynamic>;

/// The targets report with the named inputs blanked, as the server answers when they are missing.
Map<String, dynamic> _targetsWithout(Set<String> inputs) {
  final body = _fixture('targets');
  for (final i in body['inputs'] as List) {
    final input = i as Map<String, dynamic>;
    if (inputs.contains(input['key'])) {
      input
        ..['value'] = null
        ..['source'] = 'missing';
    }
  }
  return body;
}

StubAdapter _server({Map<String, dynamic>? targets, Map<String, dynamic>? me}) => fullServer()
  ..on('GET /api/me', StubResponse(200, me ?? meJson()))
  ..on('GET /api/targets', StubResponse(200, targets ?? _fixture('targets')))
  ..on('PATCH /api/me', StubResponse(200, me ?? meJson()))
  ..on('PUT /api/health/daily', const StubResponse(200, {'days': <Object>[]}))
  ..on(
    'POST /api/targets/apply',
    StubResponse(200, {
      ...meJson(),
      'applied': ['calories'],
    }),
  );

/// Pushes the page the way the app does, so closing the flow has a route to return to.
class _Launcher extends StatelessWidget {
  const _Launcher(this.start);

  final AboutQuestion start;

  @override
  Widget build(BuildContext context) => Center(
    child: TextButton(
      onPressed: () =>
          Navigator.of(context)
              .push(MaterialPageRoute<void>(builder: (_) => AboutYouPage(start: start))),
      child: const Text('Open'),
    ),
  );
}

Future<TestApp> _open(
  WidgetTester tester,
  StubAdapter server, {
  AboutQuestion start = AboutQuestion.birthYear,
  double scale = 1,
}) async {
  tester.platformDispatcher.textScaleFactorTestValue = scale;
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  final app = TestApp(tester, server, surfaceHeight: 844);
  await app.pump(_Launcher(start), tall: false);
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await app.tap(find.text('Open'));
  return app;
}

Future<void> _tapButton(TestApp app, String label) => app.tap(find.text(label.toUpperCase()));

Future<void> _type(TestApp app, String text) async {
  await app.tester.enterText(find.byType(TextField).first, text);
  await app.tester.pump();
}

bool _enabled(WidgetTester tester, String label) =>
    tester
        .widget<ChunkyButton>(find.byWidgetPredicate((w) => w is ChunkyButton && w.label == label))
        .onPressed !=
    null;

String _field(WidgetTester tester) =>
    tester.widget<TextField>(find.byType(TextField)).controller!.text;

void main() {
  setUp(() {
    FakeStorage().install();
    Mascot.idleMotion = false;
  });

  group('About you flow', () {
    testWidgets('asks one question per screen, each with a why-line and Skip, last with Use all', (
      tester,
    ) async {
      final app = await _open(tester, _server());
      const questions = [
        ('What year were you born?', 'Used by the Mifflin-St Jeor equation for your resting'),
        ('What is your sex?', 'Used by the Mifflin-St Jeor equation for your resting energy, and'),
        ('How tall are you?', 'Used by the Mifflin-St Jeor equation for your resting energy, and'),
        ('What do you weigh?', 'Used by the Mifflin-St Jeor equation for your resting energy and'),
        ('What is your weight goal?', 'Sets how far your calories sit from maintenance'),
      ];
      for (final (title, why) in questions) {
        expect(find.text(title), findsOneWidget);
        expect(find.textContaining(why), findsOneWidget, reason: title);
        expect(find.text('SKIP'), findsOneWidget);
        await _tapButton(app, 'Skip');
      }
      expect(find.text('Your daily targets'), findsOneWidget);
      expect(find.text('SKIP'), findsNothing);
      expect(find.text('USE ALL'), findsOneWidget);
      expect(find.text('NOT NOW'), findsOneWidget);
      expect(app.adapter.to('PATCH /api/me'), isEmpty, reason: 'skipping saves nothing');
      expect(app.adapter.to('PUT /api/health/daily'), isEmpty);
    });

    testWidgets('birth year is checked and saved', (tester) async {
      final app = await _open(tester, _server(me: meJson()));
      expect(_enabled(tester, 'Continue'), isFalse);
      await _type(app, '1850');
      expect(find.text('Between 1900 and 2026'), findsOneWidget);
      expect(_enabled(tester, 'Continue'), isFalse);
      await _type(app, '1990');
      await _tapButton(app, 'Continue');
      expect(app.body('PATCH /api/me'), {'birthYear': 1990});
      expect(find.text('What is your sex?'), findsOneWidget);
    });

    testWidgets('sex is saved as male or female', (tester) async {
      final app = await _open(tester, _server(), start: AboutQuestion.sex);
      expect(_enabled(tester, 'Continue'), isFalse);
      await app.tap(find.text('Female'));
      await _tapButton(app, 'Continue');
      expect(app.body('PATCH /api/me'), {'sex': 'female'});
    });

    testWidgets('height and weight come from Health, say so, and save nothing when kept', (
      tester,
    ) async {
      final app = await _open(tester, _server(), start: AboutQuestion.height);
      expect(_field(tester), '180');
      expect(find.text('From Apple Health'), findsOneWidget);
      await _tapButton(app, 'Continue');

      expect(find.text('What do you weigh?'), findsOneWidget);
      expect(_field(tester), '82.4');
      expect(find.text('From Apple Health'), findsOneWidget);
      await _tapButton(app, 'Continue');

      expect(app.adapter.to('PATCH /api/me'), isEmpty, reason: 'Health keeps supplying height');
      expect(app.adapter.to('PUT /api/health/daily'), isEmpty);
      expect(find.text('What is your weight goal?'), findsOneWidget);
    });

    testWidgets('editing a prefilled height saves it to the profile', (tester) async {
      final app = await _open(tester, _server(), start: AboutQuestion.height);
      await _type(app, '181,5');
      expect(find.text('From Apple Health'), findsNothing);
      await _tapButton(app, 'Continue');
      expect(app.body('PATCH /api/me'), {'heightCm': 181.5});
    });

    testWidgets('a height outside 100 to 250 cm cannot be saved', (tester) async {
      final app = await _open(
        tester,
        _server(targets: _targetsWithout({'heightCm'})),
        start: AboutQuestion.height,
      );
      expect(_field(tester), isEmpty);
      expect(find.text('From Apple Health'), findsNothing);
      await _type(app, '99');
      expect(find.text('Between 100 and 250 cm'), findsOneWidget);
      expect(_enabled(tester, 'Continue'), isFalse);
      await _type(app, '178');
      await _tapButton(app, 'Continue');
      expect(app.body('PATCH /api/me'), {'heightCm': 178});
    });

    testWidgets('a weight typed by hand is saved as a manual reading for today', (tester) async {
      final app = await _open(
        tester,
        _server(targets: _targetsWithout({'weightKg'})),
        start: AboutQuestion.weight,
      );
      expect(_field(tester), isEmpty);
      expect(find.text('From Apple Health'), findsNothing);
      await _type(app, '75,46');
      await _tapButton(app, 'Continue');

      final item = ((app.body('PUT /api/health/daily')['items'] as List).single as Map);
      expect(item['metric'], 'weight_kg');
      expect(item['source'], 'manual');
      expect(item['value'], 75.5);
      expect(item['date'], '2026-10-26');
      expect(DateTime.parse(item['measuredAt'] as String).isUtc, isTrue);
      expect(find.text('What is your weight goal?'), findsOneWidget);
    });

    testWidgets('a refused save says why and stays', (tester) async {
      final server = _server(targets: _targetsWithout({'weightKg'}))
        ..on('PUT /api/health/daily', const StubResponse(422, {'error': 'weight is out of range'}));
      final app = await _open(tester, server, start: AboutQuestion.weight);
      await _type(app, '75');
      await _tapButton(app, 'Continue');
      expect(find.text('weight is out of range'), findsOneWidget);
      expect(find.text('What do you weigh?'), findsOneWidget);
    });

    testWidgets('lose and gain offer their paces and the cap explanation', (tester) async {
      final app = await _open(tester, _server(), start: AboutQuestion.goal);
      expect(find.text('Pace'), findsNothing, reason: 'maintain has no pace');
      await app.tap(find.text('Lose'));
      expect(find.text('Pace'), findsOneWidget);
      expect(find.text('0.25 kg a week'), findsOneWidget);
      expect(find.text('0.5 kg a week'), findsOneWidget);
      expect(find.text('0.1 kg a week'), findsNothing);
      expect(find.textContaining('capped at 1% of your body weight a week'), findsOneWidget);

      await app.tap(find.text('Gain'));
      for (final pace in ['0.1', '0.25', '0.5']) {
        expect(find.text('$pace kg a week'), findsOneWidget);
      }
      expect(find.textContaining('held to 0.5% of your body weight a week'), findsOneWidget);

      await app.tap(find.text('Maintain'));
      expect(find.text('Pace'), findsNothing);
    });

    testWidgets('the goal is saved with its pace', (tester) async {
      final me = meJson();
      final app = await _open(tester, _server(me: me), start: AboutQuestion.goal);
      await app.tap(find.text('Lose'));
      await app.tap(find.text('0.5 kg a week'));
      await _tapButton(app, 'Continue');
      expect(app.body('PATCH /api/me'), {
        'goal': {'kind': 'lose', 'paceKgPerWeek': 0.5},
      });
    });

    testWidgets('Use all applies the targets that differ and closes the flow', (tester) async {
      final app = await _open(tester, _server(), start: AboutQuestion.review);
      for (final label in ['Calories', 'Protein', 'Fat', 'Carbohydrate', 'Fiber', 'Sleep']) {
        expect(find.text(label), findsOneWidget, reason: label);
      }
      expect(find.text('2,350 kcal'), findsOneWidget);
      expect(find.text('165 g'), findsOneWidget);
      expect(find.text('7 h 30 min'), findsOneWidget);

      await _tapButton(app, 'Use all');
      expect(app.body('POST /api/targets/apply'), {
        'keys': ['calories', 'protein', 'fat', 'carbs', 'sleep'],
      });
      expect(find.byType(AboutYouPage), findsNothing);
    });

    testWidgets('Not now leaves everything as it was', (tester) async {
      final app = await _open(tester, _server(), start: AboutQuestion.review);
      await _tapButton(app, 'Not now');
      expect(app.adapter.to('POST /api/targets/apply'), isEmpty);
      expect(find.byType(AboutYouPage), findsNothing);
    });

    testWidgets('a refused apply says why and stays', (tester) async {
      final server = _server()
        ..on(
          'POST /api/targets/apply',
          const StubResponse(422, {'error': 'calories has no value'}),
        );
      final app = await _open(tester, server, start: AboutQuestion.review);
      await _tapButton(app, 'Use all');
      expect(find.text('calories has no value'), findsOneWidget);
      expect(find.byType(AboutYouPage), findsOneWidget);
    });

    testWidgets('missing inputs show as not yet, named at the bottom', (tester) async {
      final app = await _open(
        tester,
        _server(targets: _fixture('targets_missing')),
        start: AboutQuestion.review,
      );
      expect(find.text('Not yet'), findsWidgets);
      expect(find.textContaining('Still needed: Height, Sex'), findsOneWidget);
      expect(app.adapter.to('GET /api/targets'), isNotEmpty);
    });

    testWidgets('opening at a question starts there and Back at the first question leaves', (
      tester,
    ) async {
      final app = await _open(tester, _server(), start: AboutQuestion.sex);
      expect(find.text('What is your sex?'), findsOneWidget);
      await app.tap(find.bySemanticsLabel('Back'));
      expect(find.byType(AboutYouPage), findsNothing);
    });

    testWidgets('Back inside the flow returns to the question before', (tester) async {
      final app = await _open(tester, _server(), start: AboutQuestion.height);
      await _tapButton(app, 'Skip');
      expect(find.text('What do you weigh?'), findsOneWidget);
      await app.tap(find.bySemanticsLabel('Back'));
      expect(find.text('How tall are you?'), findsOneWidget);
    });

    for (final scale in [1.0, 2.0]) {
      testWidgets('every screen fits 390 wide at text scale $scale with 44pt targets', (
        tester,
      ) async {
        final app = await _open(tester, _server(), scale: scale);
        for (final q in AboutQuestion.values) {
          expect(tester.takeException(), isNull, reason: '$q');
          for (final b in tester.widgetList<ChunkyButton>(find.byType(ChunkyButton))) {
            expect(tester.getSize(find.byWidget(b)).height, greaterThanOrEqualTo(44), reason: '$q');
          }
          for (final f in tester.widgetList<TextField>(find.byType(TextField))) {
            expect(tester.getSize(find.byWidget(f)).height, greaterThanOrEqualTo(44), reason: '$q');
          }
          for (final c in tester.widgetList<Semantics>(
            find.byWidgetPredicate((w) => w is Semantics && (w.properties.button ?? false)),
          )) {
            final size = tester.getSize(find.byWidget(c));
            if (size.isEmpty) continue;
            expect(size.height, greaterThanOrEqualTo(44), reason: '$q $c');
          }
          if (q != AboutQuestion.review) await _tapButton(app, 'Skip');
        }
        expect(tester.getSize(find.byType(Scaffold).first).width, 390);
      });
    }

    testWidgets('the goal screen at text scale 2.0 shows pace chips at 44pt', (tester) async {
      final app = await _open(tester, _server(), start: AboutQuestion.goal, scale: 2);
      await app.tap(find.text('Lose'));
      expect(tester.takeException(), isNull);
      for (final label in ['0.25 kg a week', '0.5 kg a week']) {
        expect(tester.getSize(find.text(label)).height, greaterThan(0));
        final chip = find.ancestor(of: find.text(label), matching: find.byType(AnimatedContainer));
        expect(tester.getSize(chip.first).height, greaterThanOrEqualTo(44));
      }
    });
  });

  group('Finish your setup', () {
    final tuesday3pm = DateTime(2026, 10, 27, 15);

    Future<TestApp> openToday(WidgetTester tester, StubAdapter server, {DateTime? at}) async {
      final app = TestApp(tester, server, surfaceHeight: 3600);
      await app.pump(const TodayScreen(), key: UniqueKey(), now: at ?? tuesday3pm);
      return app;
    }

    testWidgets('shows what is missing and opens the flow at the first missing question', (
      tester,
    ) async {
      final server = _server(targets: _targetsWithout({'sex', 'heightCm'}));
      final app = await openToday(tester, server);
      expect(find.text('Finish your setup'), findsOneWidget);
      expect(find.textContaining('Add your sex and height'), findsOneWidget);

      await app.tap(find.text('Open About you'));
      expect(find.byType(AboutYouPage), findsOneWidget);
      expect(find.text('What is your sex?'), findsOneWidget);
    });

    testWidgets('does not show when nothing is missing', (tester) async {
      await openToday(tester, _server());
      expect(find.text('Finish your setup'), findsNothing);
    });

    testWidgets('dismissing hides it for seven days and then it comes back', (tester) async {
      final server = _server(targets: _targetsWithout({'weightKg'}));
      final app = await openToday(tester, server);
      expect(find.text('Finish your setup'), findsOneWidget);
      await app.tap(
        find.descendant(of: find.byType(SetupNowCard), matching: find.byType(DismissX)),
      );
      expect(find.text('Finish your setup'), findsNothing);
      final memory = app.container.read(rightNowMemoryProvider);
      expect(memory.has(setupDismissKey('2026-10-26')), isTrue);

      final dismissed = {setupDismissKey('2026-10-26')};
      expect(setupDismissed(dismissed, DateTime(2026, 10, 27, 15)), isTrue);
      expect(setupDismissed(dismissed, DateTime(2026, 11, 1, 23, 59)), isTrue);
      expect(setupDismissed(dismissed, DateTime(2026, 11, 2)), isFalse);
      expect(setupDismissed({'readiness|2026-10-26'}, DateTime(2026, 10, 27)), isFalse);
    });
  });

  group('pickRightNow and the setup card', () {
    final now = DateTime(2026, 10, 27, 15);
    final monday = DateTime(2026, 10, 26, 9);
    const missing = [AboutQuestion.height, AboutQuestion.weight];
    const cheer = Cheer(from: 1, fromName: 'Nadia', kind: CheerKind.fire);
    final repair = Repair(date: '2026-10-26', until: DateTime(2026, 10, 28), progressPercent: 0);

    test('shows when something is missing and nothing more urgent is there', () {
      final picked = pickRightNow(now: now, setupMissing: missing);
      expect(picked, isA<RightNowSetup>());
      expect((picked! as RightNowSetup).missing, missing);
    });

    test('is nothing when nothing is missing', () {
      expect(pickRightNow(now: now), isNull);
    });

    test('a cheer beats it', () {
      expect(pickRightNow(now: now, setupMissing: missing, cheers: [cheer]), isA<RightNowCheers>());
    });

    test('a repair beats it', () {
      expect(pickRightNow(now: now, setupMissing: missing, repair: repair), isA<RightNowRepair>());
    });

    test('Monday goals come before it, a dismissal gives way to nothing', () {
      const proposal = GoalProposal(
        key: 'steps',
        title: 'Steps',
        unit: 'steps',
        current: 8000,
        proposed: 9000,
        reason: 'r',
      );
      expect(
        pickRightNow(now: monday, setupMissing: missing, proposals: [proposal]),
        isA<RightNowGoals>(),
      );
      expect(pickRightNow(now: now, setupMissing: missing, setupDismissed: true), isNull);
    });

    test('it comes before the recap', () {
      const recap = Recap(
        week: '2026-W43',
        from: '2026-10-19',
        to: '2026-10-25',
        complete: true,
        people: [],
        pair: RecapPair(thisWeek: RecapStats(points: 200), previous: RecapStats(points: 100)),
      );
      expect(pickRightNow(now: monday, setupMissing: missing, recap: recap), isA<RightNowSetup>());
      expect(pickRightNow(now: monday, recap: recap), isA<RightNowRecap>());
    });

    test('the list reads naturally', () {
      expect(missingList([AboutQuestion.weight]), 'weight');
      expect(missingList([AboutQuestion.sex, AboutQuestion.height]), 'sex and height');
      expect(
        missingList([AboutQuestion.birthYear, AboutQuestion.sex, AboutQuestion.weight]),
        'birth year, sex and weight',
      );
    });

    test('the first missing question comes from the inputs the server lists', () {
      final report = TargetsReport.parse(_targetsWithout({'sex', 'weightKg'}));
      expect(firstMissingQuestion(report), AboutQuestion.sex);
      expect(missingQuestions(report), {AboutQuestion.sex, AboutQuestion.weight});
      expect(firstMissingQuestion(TargetsReport.parse(_fixture('targets'))), isNull);
    });
  });

  group('Me', () {
    testWidgets('has one About you row that opens the page with name, colour and body', (
      tester,
    ) async {
      final app = TestApp(tester, _server(), surfaceHeight: 3000);
      await app.pump(const MeScreen());
      await app.tap(find.text('About you'));
      expect(find.text('Name'), findsOneWidget);
      expect(find.text('Color'), findsOneWidget);
      expect(find.text('Birth year (optional)'), findsOneWidget);
      expect(find.text('Profile'), findsNothing);
    });
  });
}
