import 'package:flutter_test/flutter_test.dart';
import 'package:newme/features/coach/coach_chat_page.dart';
import 'package:newme/features/me/coach_knows_page.dart';
import 'package:newme/widgets/mascot.dart';

import 'fixtures.dart';
import 'hit_targets.dart';
import 'test_support.dart';

Map<String, dynamic> _proposal({String status = 'pending', bool canUndo = false}) => {
  'id': 5,
  'kind': 'quest_target',
  'summary': 'Steps goal 8,000 steps -> 10,000 steps',
  'changes': [
    {'label': 'Steps goal', 'from': '8,000 steps', 'to': '10,000 steps'},
  ],
  'why': 'The top of where the benefit levels off for your age (Paluch 2022, Ding 2025)',
  'source': 'guideline',
  'status': status,
  'expiresAt': '2099-01-01T00:00:00Z',
  'canUndo': canUndo,
};

StubAdapter _server({List<Map<String, dynamic>> actions = const []}) => fullServer()
  ..on(
    'GET /api/me',
    StubResponse(200, {
      ...meJson(),
      'features': {'mealEstimate': false, 'planPolish': false, 'coachChat': true},
    }),
  )
  ..on('GET /api/insights', const StubResponse(500, {'error': 'x'}))
  ..on(
    'POST /api/coach/chat',
    StubResponse(200, {'reply': 'I suggest 10,000 steps.', 'actions': actions}),
  );

Future<TestApp> _openWithProposal(WidgetTester tester, StubAdapter server) async {
  final app = TestApp(tester, server);
  await app.pump(const CoachChatPage());
  await app.tap(find.text('How was my week?'));
  return app;
}

void main() {
  setUp(() {
    FakeStorage().install();
    Mascot.idleMotion = false;
  });

  group('Coach proposal card', () {
    testWidgets('shows the change and changes nothing until Apply', (tester) async {
      final server = _server(
        actions: [
          {'type': 'proposal', 'proposal': _proposal()},
        ],
      );
      final app = await _openWithProposal(tester, server);

      expect(find.text('Steps goal'), findsOneWidget);
      expect(find.text('8,000 steps'), findsOneWidget);
      expect(find.text('10,000 steps'), findsOneWidget);
      expect(find.textContaining('Paluch 2022'), findsOneWidget);
      expect(find.text('From published guidance'), findsOneWidget);
      expect(find.text('APPLY'), findsOneWidget);
      expect(find.text('NOT NOW'), findsOneWidget);
      expect(app.adapter.to('POST /api/coach/proposals/5/apply'), isEmpty);
      expect(
        find.bySemanticsLabel(RegExp('Suggested change: Steps goal, 8,000 steps to 10,000 steps')),
        findsOneWidget,
      );
    });

    testWidgets('Apply says Changed and offers Undo, which puts it back', (tester) async {
      final server =
          _server(
              actions: [
                {'type': 'proposal', 'proposal': _proposal()},
              ],
            )
            ..on(
              'POST /api/coach/proposals/5/apply',
              StubResponse(200, _proposal(status: 'applied', canUndo: true)),
            )
            ..on(
              'POST /api/coach/proposals/5/undo',
              StubResponse(200, _proposal(status: 'undone')),
            );
      final app = await _openWithProposal(tester, server);

      await app.tap(find.text('APPLY'));
      expect(app.adapter.to('POST /api/coach/proposals/5/apply'), hasLength(1));
      expect(find.text('Changed.'), findsOneWidget);
      expect(find.text('APPLY'), findsNothing);
      expect(find.text('Undo'), findsOneWidget);
      expect(smallTargets(tester).where((t) => t.contains('Undo')), isEmpty);

      await app.tap(find.text('Undo'));
      expect(app.adapter.to('POST /api/coach/proposals/5/undo'), hasLength(1));
      expect(find.text('Back to how it was.'), findsOneWidget);
      expect(find.text('Undo'), findsNothing);
    });

    testWidgets('Not now settles the card without applying', (tester) async {
      final server =
          _server(
            actions: [
              {'type': 'proposal', 'proposal': _proposal()},
            ],
          )..on(
            'POST /api/coach/proposals/5/dismiss',
            StubResponse(200, _proposal(status: 'dismissed')),
          );
      final app = await _openWithProposal(tester, server);

      await app.tap(find.text('NOT NOW'));
      expect(find.text('Not now.'), findsOneWidget);
      expect(app.adapter.to('POST /api/coach/proposals/5/apply'), isEmpty);
    });

    testWidgets('an expired card says so and shows the server sentence', (tester) async {
      final server =
          _server(
            actions: [
              {'type': 'proposal', 'proposal': _proposal()},
            ],
          )..on(
            'POST /api/coach/proposals/5/apply',
            const StubResponse(410, {
              'code': 'proposal_expired',
              'error': 'this suggestion expired, ask the coach again',
            }),
          );
      final app = await _openWithProposal(tester, server);

      await app.tap(find.text('APPLY'));
      expect(find.textContaining('Expired'), findsOneWidget);
      expect(find.text('this suggestion expired, ask the coach again'), findsOneWidget);
    });

    testWidgets('a saved fact shows a note, and no gems are called points', (tester) async {
      final server = _server(
        actions: [
          {
            'type': 'fact_saved',
            'fact': {'id': 3, 'category': 'injury', 'text': 'Sore left knee'},
          },
        ],
      );
      await _openWithProposal(tester, server);

      expect(find.text('Saved to your profile: Sore left knee'), findsOneWidget);
      expect(find.textContaining('points'), findsNothing);
    });
  });

  group('What the coach knows', () {
    StubAdapter facts() => _server()
      ..on(
        'GET /api/coach/facts',
        const StubResponse(200, {
          'max': 40,
          'facts': [
            {
              'id': 1,
              'category': 'injury',
              'text': 'Sore left knee',
              'createdAt': '2026-11-01T00:00:00Z',
            },
            {
              'id': 2,
              'category': 'equipment',
              'text': 'Two 15 kg dumbbells',
              'createdAt': '2026-11-01T00:00:00Z',
            },
          ],
        }),
      )
      ..on('DELETE /api/coach/facts/1', const StubResponse(204))
      ..on('DELETE /api/coach/facts/2', const StubResponse(204));

    testWidgets('lists facts and forgets one with its button', (tester) async {
      final app = TestApp(tester, facts());
      await app.pump(const CoachKnowsPage());

      expect(find.text('Sore left knee'), findsOneWidget);
      expect(find.text('Equipment'), findsOneWidget);
      expect(smallTargets(tester), isEmpty);

      await app.tap(find.byTooltip('Forget').first);
      expect(app.adapter.to('DELETE /api/coach/facts/1'), hasLength(1));
      expect(find.text('Sore left knee'), findsNothing);
      expect(find.text('Two 15 kg dumbbells'), findsOneWidget);
    });

    testWidgets('swiping a fact away forgets it', (tester) async {
      final app = TestApp(tester, facts());
      await app.pump(const CoachKnowsPage());

      await tester.drag(find.text('Two 15 kg dumbbells'), const Offset(-400, 0));
      await app.settle();
      expect(app.adapter.to('DELETE /api/coach/facts/2'), hasLength(1));
      expect(find.text('Two 15 kg dumbbells'), findsNothing);
    });

    testWidgets('an empty list explains itself', (tester) async {
      final server = _server()
        ..on('GET /api/coach/facts', const StubResponse(200, {'facts': [], 'max': 40}));
      final app = TestApp(tester, server);
      await app.pump(const CoachKnowsPage());
      expect(find.textContaining('Nothing yet'), findsOneWidget);
    });
  });
}
