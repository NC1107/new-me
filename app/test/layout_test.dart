import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:newme/features/shell/home_shell.dart';

import 'fixtures.dart';
import 'test_support.dart';

StubAdapter _server() => fullServer()
  ..on('GET /api/today', StubResponse(200, richTodayJson(hasSteps: true)))
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
  ..on('POST /api/logs', StubResponse(201, logResultJson()))
  ..on('GET /api/me', StubResponse(200, meJson(admin: true, yoga: true)));

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
    await app.tap(find.text('Day 3'));
    noOverflow('streak sheet');
    await app.closeSheet();

    await tester.drag(find.byType(ListView).first, const Offset(0, -2000));
    await app.settle();
    noOverflow('Today scrolled');

    await app.tap(find.text('Food'));
    noOverflow('day detail sheet');
    await app.closeSheet();

    await app.tap(find.byIcon(Icons.add));
    noOverflow('log pushups');
    for (final label in ['Reading', 'Yoga', 'Meal']) {
      await app.tap(find.text(label).last);
      noOverflow('log $label');
    }
    await app.tap(find.text('More'));
    noOverflow('log meal more');
    await app.tap(find.text('1.5'));
    noOverflow('log meal portion');
    await app.closeSheet();

    await app.tap(find.text('Board'));
    noOverflow('Board');
    await tester.drag(find.byType(ListView).first, const Offset(0, -2000));
    await app.settle();
    noOverflow('Board scrolled');

    await app.tap(find.text('Me'));
    noOverflow('Me');
    await tester.drag(find.byType(ListView).first, const Offset(0, -6000));
    await app.settle();
    noOverflow('Me scrolled');
  });
}

void main() {
  setUp(FakeStorage().install);

  _layoutSuite(1);
  _layoutSuite(1.3);

  testWidgets('the waiting placeholder, time zone and empty states fit at 390x844', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final adapter = _server()
      ..on('GET /api/board', StubResponse(200, board([boardUser(2, 'Sam', 'violet')])))
      ..on('GET /api/today', StubResponse(200, richTodayJson(streak: 0, points: 0, percent: 0)));
    final app = TestApp(tester, adapter);
    await app.pump(const HomeShell(), tall: false);
    expect(tester.takeException(), isNull);

    await app.tap(find.text('Board'));
    expect(tester.takeException(), isNull);
    await app.tap(find.text('Waiting for your partner'));
    expect(tester.takeException(), isNull);
    await app.closeSheet();

    await app.tap(find.text('Me'));
    await app.tap(find.text('Time zone'));
    expect(tester.takeException(), isNull);
  });
}
