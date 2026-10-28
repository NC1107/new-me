import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:newme/features/shell/home_shell.dart';
import 'package:newme/features/today/day_counted_sheet.dart';
import 'package:newme/widgets/chunky_button.dart';
import 'package:newme/widgets/chunky_icon_button.dart';
import 'package:newme/widgets/mascot.dart';

import 'fixtures.dart';
import 'test_support.dart';

Map<String, dynamic> _fullDay({bool counted = false}) {
  final today = richTodayJson(stepsEverSynced: true, counted: counted);
  today['quests'] = [
    ...today['quests']! as List<dynamic>,
    quest('protein', 'Protein', {'unit': 'g', 'target': 130, 'actual': 82, 'basePoints': 30}),
    quest('yoga', 'Yoga', {'unit': 'minutes', 'target': 20}),
    quest('sleep', 'Sleep', {'unit': 'min', 'target': 450, 'actual': 400, 'basePoints': 40}),
    quest('exercise', 'Exercise', {'unit': 'min', 'target': 30}),
  ];
  today['health'] = {
    'stepsEverSynced': true,
    'syncedAt': '2026-10-26T11:00:00Z',
    'metrics': {
      'sleep_minutes': 432,
      'resting_hr': 58,
      'exercise_minutes': 34,
      'weight_kg': 82.4,
      'hrv_ms': 47,
      'vo2max': 42.1,
    },
    'latest': {
      'weight_kg': {'value': 82.4, 'date': '2026-10-20'},
      'vo2max': {'value': 42.1, 'date': '2026-10-19'},
    },
  };
  return today;
}

StubAdapter _server({bool counted = false}) => fullServer()
  ..on('GET /api/today', StubResponse(200, _fullDay(counted: counted)))
  ..on(
    'GET /api/board',
    StubResponse(
      200,
      board([
        boardUser(2, 'Sam', 'violet', points: 1234, season: 12345),
        boardUser(1, 'Alexandria-Long-Name', 'amber', points: 2400, percent: 88),
      ]),
    ),
  )
  ..on(
    'GET /api/health/trends',
    const StubResponse(200, {
      'metric': 'weight_kg',
      'points': [
        {'date': '2026-10-20', 'value': 82.8},
        {'date': '2026-10-26', 'value': 82.4},
      ],
    }),
  )
  ..on('POST /api/logs', StubResponse(201, logResultJson()))
  ..on('GET /api/me', StubResponse(200, meJson(admin: true, yoga: true)));

Finder _chunky(String label) =>
    find.byWidgetPredicate((w) => w is ChunkyButton && w.label == label);

Finder _plus(String label) =>
    find.byWidgetPredicate((w) => w is ChunkyIconButton && w.semanticLabel == label);

/// Today builds its cards lazily, so a card far down is scrolled into existence before a tap.
Future<void> _tapOnToday(WidgetTester tester, TestApp app, Finder target) async {
  await tester.drag(find.byType(Scrollable).first, const Offset(0, 6000));
  await app.settle();
  await tester.scrollUntilVisible(target, 300, scrollable: find.byType(Scrollable).first);
  await tester.ensureVisible(target);
  await app.settle(2);
  await app.tap(target);
}

/// Every screen and sheet at an iPhone 14 size, with the text sizes people actually use.
void _layoutSuite(double textScale) {
  testWidgets('no overflow anywhere at 390x844 and text scale $textScale', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = textScale;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    final app = TestApp(tester, _server());
    await app.pump(const HomeShell(), tall: false);
    void noOverflow(String where) {
      final error = tester.takeException();
      expect(error, isNull, reason: 'overflow on $where: $error');
    }

    noOverflow('Today');
    await app.tap(find.bySemanticsLabel(RegExp('day streak')));
    noOverflow('streak sheet');
    await app.closeSheet();

    await tester.drag(find.byType(ListView).first, const Offset(0, -4000));
    await app.settle();
    noOverflow('Today scrolled');
    await tester.drag(find.byType(ListView).first, const Offset(0, 4000));
    await app.settle();

    await _tapOnToday(tester, app, find.text('What I logged today'));
    noOverflow('day detail sheet');
    await app.closeSheet();

    for (final (label, name) in [
      ('Add entry for Get stronger', 'push-ups'),
      ('Add entry for Read 20 min or 15 pages', 'reading'),
      ('Add entry for Yoga or stretch 20 min', 'yoga'),
    ]) {
      await _tapOnToday(tester, app, _plus(label));
      noOverflow('log $name');
      await app.closeSheet();
    }
    await _tapOnToday(tester, app, _plus('Add entry for Read 20 min or 15 pages'));
    await app.tap(find.text('Pages'));
    noOverflow('log pages');
    await app.closeSheet();

    await app.tap(find.byKey(const Key('nav-food')));
    noOverflow('Food');
    await tester.scrollUntilVisible(_chunky('Add'), 300, scrollable: find.byType(Scrollable).first);
    await app.tap(_chunky('Add'));
    noOverflow('add sheet');
    await app.tap(find.text('Meal'));
    noOverflow('log meal');
    await app.tap(find.text('More'));
    noOverflow('log meal more');
    await app.tap(find.text('1.5'));
    noOverflow('log meal portion');
    await app.closeSheet();
    await tester.drag(find.byType(ListView).first, const Offset(0, -4000));
    await app.settle();
    noOverflow('Food scrolled');

    await app.tap(find.byKey(const Key('nav-train')));
    noOverflow('Train');
    await tester.drag(find.byType(ListView).first, const Offset(0, -4000));
    await app.settle();
    noOverflow('Train scrolled');

    await app.tap(find.byKey(const Key('nav-us')));
    noOverflow('Board');
    await tester.drag(find.byType(ListView).first, const Offset(0, -2000));
    await app.settle();
    noOverflow('Board scrolled');

    await app.tap(find.byKey(const Key('nav-me')));
    noOverflow('Me');
    await tester.drag(find.byType(ListView).first, const Offset(0, -6000));
    await app.settle();
    noOverflow('Me scrolled');
  });
}

void main() {
  setUp(() {
    FakeStorage().install();
    Mascot.idleMotion = false;
  });

  _layoutSuite(1);
  _layoutSuite(1.3);
  _layoutSuite(2);

  for (final scale in [1.0, 2.0]) {
    testWidgets('the day-counted celebration fits at 390x844 and text scale $scale', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = scale;
      addTearDown(tester.view.reset);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

      final app = TestApp(tester, _server(counted: true));
      await app.pump(const HomeShell(), tall: false);
      await app.settle(30);
      expect(find.byType(DayCountedSheet), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('the waiting placeholder, schedule and empty states fit at 390x844', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final adapter = _server()
      ..on('GET /api/board', StubResponse(200, board([boardUser(2, 'Sam', 'violet')])))
      ..on('GET /api/today', StubResponse(200, richTodayJson(streak: 0, points: 0, percent: 0)));
    final app = TestApp(tester, adapter);
    await app.pump(const HomeShell(), tall: false);
    expect(tester.takeException(), isNull);

    await app.tap(find.byKey(const Key('nav-us')));
    expect(tester.takeException(), isNull);
    expect(find.text('Waiting for your partner'), findsOneWidget);

    await app.tap(find.byKey(const Key('nav-me')));
    final zone = find.text('Schedule');
    if (zone.evaluate().isEmpty) {
      await tester.scrollUntilVisible(zone, 300, scrollable: find.byType(Scrollable).at(1));
    }
    await app.tap(zone);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the bottom bar keeps its labels above the home indicator at large text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    tester.view.viewPadding = const FakeViewPadding(top: 47, bottom: 34);
    tester.view.padding = const FakeViewPadding(top: 47, bottom: 34);
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    final app = TestApp(tester, _server());
    await app.pump(const HomeShell(), tall: false);

    expect(tester.takeException(), isNull);
    for (final tab in ['today', 'food', 'train', 'us', 'me']) {
      final label = find.descendant(of: find.byKey(Key('nav-$tab')), matching: find.byType(Text));
      expect(tester.getRect(label).bottom, lessThanOrEqualTo(844 - 34));
      expect(tester.getSize(find.byKey(Key('nav-$tab'))).height, greaterThanOrEqualTo(44));
    }
  });
}
