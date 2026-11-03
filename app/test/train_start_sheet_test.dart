import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:newme/features/training/calisthenics_page.dart';
import 'package:newme/features/training/mobility_page.dart';
import 'package:newme/features/training/session_page.dart';
import 'package:newme/features/training/train_screen.dart';
import 'package:newme/features/training/yoga_page.dart';

import 'fixtures.dart';
import 'hit_targets.dart';
import 'test_support.dart';

Map<String, dynamic> _load(String name) =>
    jsonDecode(File('test/contract_v9/$name.json').readAsStringSync()) as Map<String, dynamic>;

StubAdapter _server(String today) => fullServer()
  ..on('GET /api/training/today', StubResponse(200, _load(today)))
  ..on('GET /api/training/profile', StubResponse(200, _load('training_profile_empty')))
  ..on('GET /api/exercises', StubResponse(200, _load('exercises')))
  ..on('GET /api/yoga/plan', StubResponse(200, _load('yoga_plan')));

final _start = find.text('START A WORKOUT');

void main() {
  setUp(() => FakeStorage().install());

  testWidgets('the Train tab has one start button and no routine cards', (tester) async {
    final app = TestApp(tester, _server('training_today_none'), surfaceHeight: 1800);
    await app.pump(const TrainScreen());
    await tester.pumpAndSettle();
    expect(_start, findsOneWidget);
    for (final kind in ['Yoga', 'Calisthenics', 'Mobility']) {
      expect(find.text(kind), findsNothing);
    }
    expect(smallTargets(tester), isEmpty);
  });

  testWidgets('the sheet lists today\'s session first, each kind with a short caption', (
    tester,
  ) async {
    final app = TestApp(tester, _server('training_today'), surfaceHeight: 1800);
    await app.pump(const TrainScreen());
    await tester.pumpAndSettle();
    await tester.tap(_start);
    await tester.pumpAndSettle();
    expect(find.text('Start a workout'), findsOneWidget);

    final captions = [
      'Continue today',
      '10 to 30 min flows',
      'No equipment',
      '10 stretches, 11 min',
    ];
    for (final c in captions) {
      expect(find.text(c), findsOneWidget);
      expect(c.split(' ').length, lessThanOrEqualTo(5));
    }
    expect(smallTargets(tester), isEmpty);
    await tester.tap(find.text('Full body A').last);
    await tester.pumpAndSettle();
    expect(find.byType(SessionPage), findsOneWidget);
  });

  testWidgets('the sheet leaves out a session on a day without one', (tester) async {
    final app = TestApp(tester, _server('training_today_none'), surfaceHeight: 1800);
    await app.pump(const TrainScreen());
    await tester.pumpAndSettle();
    await tester.tap(_start);
    await tester.pumpAndSettle();
    expect(find.text("Today's session"), findsNothing);
    expect(find.text('Continue today'), findsNothing);
    expect(find.text('Yoga'), findsOneWidget);
  });

  for (final (kind, page) in <(String, Type)>[
    ('Yoga', YogaPage),
    ('Calisthenics', CalisthenicsPage),
    ('Mobility', MobilityPage),
  ]) {
    testWidgets('$kind in the sheet opens its page', (tester) async {
      final app = TestApp(tester, _server('training_today_none'), surfaceHeight: 1800);
      await app.pump(const TrainScreen());
      await tester.pumpAndSettle();
      await tester.tap(_start);
      await tester.pumpAndSettle();
      await tester.tap(find.text(kind));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(find.byType(page), findsOneWidget);
    });
  }

  testWidgets('the Calisthenics page keeps its citations behind the info row', (tester) async {
    final app = TestApp(tester, _server('training_today_none'), surfaceHeight: 2800);
    await app.pump(const CalisthenicsPage());
    await tester.pumpAndSettle();
    expect(find.textContaining('et al.'), findsNothing);
    expect(smallTargets(tester), isEmpty);
    await tester.tap(find.text('Sources and safety'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Garber et al.'), findsOneWidget);
    expect(find.textContaining('Tabata et al.'), findsOneWidget);
  });
}
