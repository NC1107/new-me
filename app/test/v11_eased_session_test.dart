import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:newme/api/models.dart';
import 'package:newme/features/training/session_page.dart';
import 'package:newme/features/training/training_card.dart';
import 'package:newme/widgets/mascot.dart';

import 'fixtures.dart';
import 'test_support.dart';

const _reason = 'Your HRV is below its usual level, so today is one set lighter.';

Map<String, dynamic> _load(String name) =>
    jsonDecode(File('test/contract_v9/$name.json').readAsStringSync()) as Map<String, dynamic>;

/// Today's session as the server sends it on an Easy morning; [started] keeps the logged set.
Map<String, dynamic> _eased({bool started = false}) {
  final today = _load('training_today');
  final session = today['session'] as Map<String, dynamic>;
  session['eased'] = true;
  session['easedReason'] = _reason;
  if (!started) {
    for (final e in session['exercises'] as List) {
      (e as Map<String, dynamic>)['logged'] = <dynamic>[];
    }
  }
  return today;
}

StubAdapter _server(Map<String, dynamic> today) => fullServer()
  ..on('GET /api/training/today', StubResponse(200, today))
  ..on('GET /api/exercises', StubResponse(200, _load('exercises')))
  ..on('GET /api/training/profile', StubResponse(200, _load('training_profile')));

Finder _full() => find.text('Do the full session');

void main() {
  setUp(() {
    FakeStorage().install();
    Mascot.idleMotion = false;
  });

  test('the session parses eased and its reason, and a plain one is not eased', () {
    final eased = TrainingToday.parse(_eased()).session!;
    expect(eased.eased, isTrue);
    expect(eased.easedReason, _reason);
    final again = TrainingSession.tryParse(jsonDecode(jsonEncode(eased.toJson())))!;
    expect(again.eased, isTrue);
    expect(again.easedReason, _reason);
    final plain = TrainingToday.parse(_load('training_today')).session!;
    expect(plain.eased, isFalse);
    expect(plain.canTakeFull, isFalse);
  });

  group('TrainingSlot', () {
    testWidgets('shows the eased line and the full-session action before the first set', (
      tester,
    ) async {
      final app = TestApp(tester, _server(_eased()));
      await app.pump(const TrainingSlot(localToday: '2026-11-02', onTrainTab: true));
      await tester.pumpAndSettle();
      expect(find.text(_reason), findsOneWidget);
      expect(_full(), findsOneWidget);
    });

    testWidgets('no eased line on a normal day', (tester) async {
      final app = TestApp(tester, _server(_load('training_today')));
      await app.pump(const TrainingSlot(localToday: '2026-11-02', onTrainTab: true));
      await tester.pumpAndSettle();
      expect(find.text(_reason), findsNothing);
      expect(_full(), findsNothing);
    });

    testWidgets('once a set is logged the line stays and the action goes', (tester) async {
      final app = TestApp(tester, _server(_eased(started: true)));
      await app.pump(const TrainingSlot(localToday: '2026-11-02', onTrainTab: true));
      await tester.pumpAndSettle();
      expect(find.text(_reason), findsOneWidget);
      expect(_full(), findsNothing);
    });

    testWidgets('taking the full session posts the choice and shows the full session', (
      tester,
    ) async {
      final full = _load('training_today');
      final server = _server(_eased())
        ..on('POST /api/training/today/full', StubResponse(200, full));
      final app = TestApp(tester, server);
      await app.pump(const TrainingSlot(localToday: '2026-11-02', onTrainTab: true));
      await tester.pumpAndSettle();

      await tester.tap(_full());
      await tester.pumpAndSettle();
      expect(server.to('POST /api/training/today/full'), hasLength(1));
      expect(find.text(_reason), findsNothing);
      expect(_full(), findsNothing);
    });
  });

  group('SessionPage', () {
    testWidgets('leads with the eased line and offers the full session', (tester) async {
      final server = _server(_eased())
        ..on('POST /api/training/today/full', StubResponse(200, _load('training_today')));
      final app = TestApp(tester, server);
      await app.pump(const SessionPage());
      await tester.pumpAndSettle();
      expect(find.text(_reason), findsOneWidget);

      await tester.tap(_full());
      await tester.pumpAndSettle();
      expect(server.to('POST /api/training/today/full'), hasLength(1));
      expect(find.text(_reason), findsNothing);
    });

    testWidgets('a started eased session keeps its line without the action', (tester) async {
      final app = TestApp(tester, _server(_eased(started: true)));
      await app.pump(const SessionPage());
      await tester.pumpAndSettle();
      expect(find.text(_reason), findsOneWidget);
      expect(_full(), findsNothing);
    });
  });
}
