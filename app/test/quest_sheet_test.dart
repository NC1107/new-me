import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:newme/api/models.dart';
import 'package:newme/features/me/goal_picker_page.dart';
import 'package:newme/features/today/quest_sheet.dart';
import 'package:newme/state/me.dart';
import 'package:newme/state/today.dart';
import 'package:newme/theme/accent.dart';
import 'package:newme/widgets/chunky_button.dart';
import 'package:newme/widgets/mascot.dart';
import 'package:newme/widgets/quest_card.dart';

import 'fixtures.dart';
import 'test_support.dart';

Map<String, dynamic> _day(String date, bool tracked, {num actual = 0, bool done = false}) => {
  'date': date,
  'tracked': tracked,
  'actual': actual,
  'target': tracked ? 8000 : 0,
  'unit': tracked ? 'steps' : '',
  'done': done,
};

/// The reading target as GET /api/targets sends it for a 20 minute goal.
const _readingTarget = {
  'key': 'reading',
  'value': 19,
  'unit': 'pages',
  'current': 19,
  'formula':
      '20 minutes, or about 19 pages: adults read non-fiction at about 238 words a minute, and a '
      'page is taken as about 250 words (20 x 238 / 250).',
  'sources': ['brysbaert2019', 'acx', 'pagewords'],
  'label': 'guideline',
  'missing': <String>[],
  'applicable': true,
  'details': {
    'minutes': 20,
    'note':
        'An audiobook minute counts as 65% of a reading minute, because a narrator speaks about '
        '155 words a minute against the 238 an adult reads.',
  },
};

Map<String, dynamic> _targetsBody() {
  final body =
      (jsonDecode(File('test/contract_v8/targets.json').readAsStringSync())
              as Map<String, dynamic>)['body']
          as Map<String, dynamic>;
  return {
    ...body,
    'targets': [...(body['targets'] as List), _readingTarget],
    'sources': {
      ...(body['sources'] as Map<String, dynamic>),
      'brysbaert2019': 'Brysbaert, J Mem Lang 2019;109:104047',
      'acx': 'ACX narration guidance, 9,300 words per finished hour',
      'pagewords': '250 words a page is a typesetting convention',
    },
  };
}

StubAdapter _server({List<Map<String, dynamic>>? logs}) => fullServer()
  ..on('GET /api/targets', StubResponse(200, _targetsBody()))
  ..on(
    'GET /api/quests/{key}/history',
    StubResponse(200, {
      'key': 'steps',
      'days': [
        _day('2026-10-24', true, actual: 9000, done: true),
        _day('2026-10-25', true, actual: 3000),
        _day('2026-10-26', true, actual: 2000),
      ],
    }),
  )
  ..on('GET /api/logs', StubResponse(200, logsJson(logs ?? [])))
  ..on('PATCH /api/me', StubResponse(200, meJson()));

Future<TestApp> _open(WidgetTester tester, StubAdapter adapter, String key) async {
  final app = TestApp(tester, adapter, surfaceHeight: 3200);
  await app.pump(
    Builder(
      builder: (context) => TextButton(
        onPressed: () => showQuestSheet(context, questKey: key),
        child: const Text('open quest'),
      ),
    ),
  );
  // Today feeds the sheet, so it is loaded before the sheet opens.
  app.container.read(todayProvider);
  app.container.read(meProvider);
  await app.settle();
  await app.tap(find.text('open quest'));
  return app;
}

void main() {
  setUp(() {
    FakeStorage().install();
    Mascot.idleMotion = false;
  });

  group('the points chip', () {
    Widget host(Widget child) => MaterialApp(
      theme: themeFor(kAccentPresets.first),
      home: Scaffold(body: Center(child: child)),
    );

    testWidgets('shows what the quest is worth, quiet while open', (tester) async {
      await tester.pumpWidget(host(const PointsChip(points: 100, done: false)));
      expect(find.text('+100'), findsOneWidget);
      expect(find.bySemanticsLabel('Worth 100 points'), findsOneWidget);
    });

    testWidgets('says the points are earned once the quest is done', (tester) async {
      await tester.pumpWidget(host(const PointsChip(points: 50, done: true)));
      expect(find.text('+50'), findsOneWidget);
      expect(find.bySemanticsLabel('50 points earned'), findsOneWidget);
    });

    testWidgets('sits on every quest card', (tester) async {
      final q = Quest.fromJson(quest('steps', 'Steps', {'unit': 'steps', 'target': 8000}));
      await tester.pumpWidget(host(QuestCard(quest: q, onTap: () {})));
      expect(find.text('+100'), findsOneWidget);
    });
  });

  group('copy', () {
    test('the worth line is the share of the day, and says earned once done', () {
      final open = Quest.fromJson(quest('steps', 'Steps', {'points': 100}));
      final done = Quest.fromJson(quest('steps', 'Steps', {'points': 100, 'done': true}));
      expect(questWorthLine(open, 420), '+100 points, 24% of today');
      expect(questWorthLine(done, 420), 'Earned +100 points, 24% of today');
      expect(questWorthLine(open, 0), '+100 points');
    });

    test('a quest lists only the entries that feed it', () {
      final meal = LogEntry.fromJson(mealLogJson());
      final water = LogEntry.fromJson({...logJson(), 'type': 'water', 'unit': 'ml'});
      final other = LogEntry.fromJson({...logJson(), 'type': 'other', 'unit': 'min'});
      expect(entryFeedsQuest('protein', meal), isTrue);
      expect(entryFeedsQuest('meals_logged', meal), isTrue);
      expect(entryFeedsQuest('water', meal), isFalse);
      expect(entryFeedsQuest('water', water), isTrue);
      expect(entryFeedsQuest('protein', water), isFalse);
      expect(entryFeedsQuest('exercise', other), isTrue);
      expect(entryFeedsQuest('yoga', other), isFalse);
    });

    test('only quests with published research name a target', () {
      expect(targetKeyForQuest('steps'), 'steps');
      expect(targetKeyForQuest('exercise'), 'activity');
      expect(targetKeyForQuest('reading'), 'reading');
    });
  });

  group('the sheet', () {
    testWidgets('a Health quest shows progress, worth, source, week and why', (tester) async {
      await _open(tester, _server(), 'steps');

      expect(find.text('Walk 8,000 steps'), findsOneWidget);
      expect(find.text('Counted by Apple Health'), findsWidgets);
      // maxBase is 400 in the fixture.
      expect(find.text('+100 points, 25% of today'), findsOneWidget);
      expect(find.textContaining('Nothing to log here'), findsOneWidget);
      expect(find.text('Done on 1 of 3 days'), findsOneWidget);
      expect(find.textContaining('7,000 steps a day'), findsOneWidget);
      expect(find.text('Log water'), findsNothing);
    });

    testWidgets('the reading sheet explains the pages figure and the audiobook credit', (
      tester,
    ) async {
      await _open(tester, _server(), 'reading');

      expect(find.textContaining('20 minutes, or about 19 pages'), findsOneWidget);
      expect(find.textContaining('238 words a minute'), findsOneWidget);
      expect(find.textContaining('An audiobook minute counts as 65%'), findsOneWidget);
      expect(find.textContaining('Brysbaert, J Mem Lang 2019'), findsOneWidget);
      expect(find.textContaining('250 words a page is a typesetting convention'), findsOneWidget);
      // The fixture's pages goal is the old 15, so it is called the person's own.
      expect(find.text('Your pages goal is 15 pages, which is your own pick.'), findsOneWidget);
    });

    testWidgets('a logged quest lists only its own entries, with a log action', (tester) async {
      final app = await _open(
        tester,
        _server(
          logs: [
            mealLogJson(),
            {...logJson(id: 90), 'type': 'water', 'unit': 'ml', 'quantity': 300},
          ],
        ),
        'meals_logged',
      );

      expect(find.text('Chicken bowl'), findsOneWidget);
      expect(find.text('Water'), findsNothing);
      expect(_chunky('Log a meal'), findsOneWidget);
      expect(_chunky('Change goal'), findsOneWidget);
      expect(
        find.text('No published research sets this number. It is the goal you picked.'),
        findsOneWidget,
      );
      expect(app.adapter.to('GET /api/quests/meals_logged/history'), isNotEmpty);
    });

    testWidgets('a quest with nothing logged says so', (tester) async {
      await _open(tester, _server(), 'meals_logged');
      expect(find.text('Nothing logged for this yet.'), findsOneWidget);
    });

    testWidgets('Change goal opens the goal picker', (tester) async {
      final app = await _open(tester, _server(), 'steps');
      await app.tap(_chunky('Change goal'));
      expect(find.byType(GoalPickerPage), findsOneWidget);
    });

    testWidgets('Turn off asks first, then sends the switch and closes the sheet', (tester) async {
      final app = await _open(tester, _server(), 'steps');

      await app.tap(find.text('Turn off this quest'));
      expect(find.text('Turn off Steps?'), findsOneWidget);
      await app.tap(find.text('Cancel'));
      expect(app.adapter.to('PATCH /api/me'), isEmpty);

      await app.tap(find.text('Turn off this quest'));
      await app.tap(find.widgetWithText(TextButton, 'Turn off'));

      expect(app.body('PATCH /api/me'), {
        'questTemplates': [
          {'key': 'steps', 'enabled': false},
        ],
      });
      expect(find.byType(QuestSheet), findsNothing);
    });

    testWidgets('the sheet keeps its buttons at least 48 tall', (tester) async {
      await _open(tester, _server(), 'meals_logged');
      expect(tester.getSize(find.byType(ChunkyButton).first).height, greaterThanOrEqualTo(48));
    });
  });
}

Finder _chunky(String label) =>
    find.byWidgetPredicate((w) => w is ChunkyButton && w.label == label);
