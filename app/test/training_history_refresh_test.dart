import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:newme/api/models.dart';
import 'package:newme/state/log_actions.dart';
import 'package:newme/state/training.dart';

import 'fixtures.dart';
import 'test_support.dart';

const _history = {'month': '2026-10', 'days': <Map<String, dynamic>>[]};
const _exerciseHistory = {
  'metric': 'reps',
  'estimated': false,
  'points': <Map<String, dynamic>>[],
  'maxTests': <Map<String, dynamic>>[],
};

void main() {
  late StubAdapter server;

  setUp(() {
    FakeStorage().install();
    server = fullServer()
      ..on('GET /api/training/history', const StubResponse(200, _history))
      ..on('GET /api/exercises/push_up/history', const StubResponse(200, _exerciseHistory))
      ..on('POST /api/logs', StubResponse(201, logResultJson()))
      ..on('DELETE /api/logs/77', StubResponse(200, deleteLogJson()))
      ..on('POST /api/pushups/max', const StubResponse(201, {'date': '2026-10-26', 'reps': 25}));
  });

  Future<(TestApp, LogActions)> open(WidgetTester tester) async {
    final app = TestApp(tester, server);
    await app.pump(const SizedBox());
    final container = app.container;
    container.listen(trainingHistoryProvider('2026-10'), (_, _) {});
    container.listen(exerciseHistoryProvider('push_up'), (_, _) {});
    await app.settle();
    expect(server.to('GET /api/training/history'), hasLength(1));
    expect(server.to('GET /api/exercises/push_up/history'), hasLength(1));
    return (app, container.read(logActionsProvider));
  }

  const yoga = ActivityDraft(clientOpId: 'op-1', type: 'yoga', quantity: 12, unit: 'minutes');

  testWidgets('a yoga log reloads the training calendar', (tester) async {
    final (app, actions) = await open(tester);
    unawaited(actions.create(yoga));
    await app.settle();
    expect(server.to('GET /api/training/history'), hasLength(2));
  });

  testWidgets('deleting a log reloads the training calendar', (tester) async {
    final (app, actions) = await open(tester);
    final entry = ActivityLog(
      id: 77,
      localDate: '2026-10-26',
      loggedAt: DateTime.utc(2026, 10, 26, 13, 30),
      type: 'yoga',
      quantity: 12,
      unit: 'minutes',
    );
    unawaited(actions.delete(entry));
    await app.settle();
    expect(server.to('GET /api/training/history'), hasLength(2));
  });

  testWidgets('a push-up max test reloads the strength chart', (tester) async {
    final (app, actions) = await open(tester);
    unawaited(actions.recordPushupMax(25));
    await app.settle();
    expect(server.to('GET /api/exercises/push_up/history'), hasLength(2));
  });
}
