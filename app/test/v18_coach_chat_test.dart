import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:newme/api/coach_models.dart';
import 'package:newme/features/coach/coach_chat_page.dart';
import 'package:newme/features/today/today_screen.dart';
import 'package:newme/state/coach_chat.dart';
import 'package:newme/widgets/mascot.dart';

import 'fixtures.dart';
import 'test_support.dart';

StubAdapter _server({bool coach = true}) => fullServer()
  ..on(
    'GET /api/me',
    StubResponse(200, {
      ...meJson(),
      'features': {'mealEstimate': false, 'planPolish': false, 'coachChat': coach},
    }),
  )
  ..on('GET /api/insights', const StubResponse(500, {'error': 'x'}))
  ..on('POST /api/coach/chat', const StubResponse(200, {'reply': 'Your steps averaged 7,422.'}));

Finder get _typing =>
    find.byWidgetPredicate((w) => w is Semantics && w.properties.label == 'Coach is typing');

List<dynamic> _sent(TestApp app, {bool first = false}) =>
    app.body('POST /api/coach/chat', first: first)['messages'] as List<dynamic>;

void main() {
  setUp(() {
    FakeStorage().install();
    Mascot.idleMotion = false;
  });

  group('Coach chat page', () {
    testWidgets('offers the starter questions and sends the one picked', (tester) async {
      final app = TestApp(tester, _server());
      await app.pump(const CoachChatPage());

      for (final q in kCoachStarters) {
        expect(find.text(q), findsOneWidget);
      }
      await app.tap(find.text('What should I improve first?'));

      expect(_sent(app), [
        {'role': 'user', 'text': 'What should I improve first?'},
      ]);
      expect(find.text('Your steps averaged 7,422.'), findsOneWidget);
      // The starters give way to the conversation.
      expect(find.text(kCoachStarters.first), findsNothing);
    });

    testWidgets('shows a typing state while the coach works and sends the whole thread', (
      tester,
    ) async {
      final reply = Completer<StubResponse>();
      final server = _server()..routes['POST /api/coach/chat'] = (_) => reply.future;
      final app = TestApp(tester, server);
      await app.pump(const CoachChatPage());

      await app.enter(find.byType(TextField), 'How was my week?');
      await app.tap(find.bySemanticsLabel('Send').first);
      expect(_typing, findsOneWidget);
      expect(find.text('How was my week?'), findsOneWidget);
      expect(tester.widget<TextField>(find.byType(TextField)).controller!.text, isEmpty);

      reply.complete(const StubResponse(200, {'reply': 'A steady week.'}));
      await app.settle();
      expect(_typing, findsNothing);
      expect(find.text('A steady week.'), findsOneWidget);

      server.on('POST /api/coach/chat', const StubResponse(200, {'reply': 'Sleep, mostly.'}));
      await app.enter(find.byType(TextField), 'Why?');
      await app.tap(find.bySemanticsLabel('Send').first);
      expect(_sent(app), [
        {'role': 'user', 'text': 'How was my week?'},
        {'role': 'assistant', 'text': 'A steady week.'},
        {'role': 'user', 'text': 'Why?'},
      ]);
    });

    testWidgets('an empty message cannot be sent', (tester) async {
      final app = TestApp(tester, _server());
      await app.pump(const CoachChatPage());
      await app.enter(find.byType(TextField), '   ');
      await app.tap(find.bySemanticsLabel('Send').first);
      expect(app.adapter.to('POST /api/coach/chat'), isEmpty);
    });

    testWidgets('a failure keeps the question and Try again asks it once more', (tester) async {
      final server = _server()
        ..on(
          'POST /api/coach/chat',
          const StubResponse(502, {
            'code': 'coach_unavailable',
            'error': 'the coach could not answer right now, try again in a moment',
          }),
        );
      final app = TestApp(tester, server);
      await app.pump(const CoachChatPage());

      await app.tap(find.text('How was my week?'));
      expect(find.textContaining('could not answer right now'), findsOneWidget);
      expect(find.text('How was my week?'), findsOneWidget);

      server.on('POST /api/coach/chat', const StubResponse(200, {'reply': 'Fine.'}));
      await app.tap(find.text('TRY AGAIN'));
      expect(find.textContaining('could not answer right now'), findsNothing);
      expect(find.text('Fine.'), findsOneWidget);
      expect(app.adapter.to('POST /api/coach/chat'), hasLength(2));
      expect(_sent(app), [
        {'role': 'user', 'text': 'How was my week?'},
      ]);
    });

    testWidgets('a rate limit says to wait', (tester) async {
      final server = _server()
        ..on(
          'POST /api/coach/chat',
          const StubResponse(429, {'code': 'rate_limited', 'error': 'slow down'}),
        );
      final app = TestApp(tester, server);
      await app.pump(const CoachChatPage());
      await app.tap(find.text('How was my week?'));
      expect(find.textContaining('Too many requests'), findsOneWidget);
    });

    testWidgets(
      'the thread comes back when the page is reopened the same day, and New chat clears it',
      (tester) async {
        final app = TestApp(tester, _server());
        await app.pump(const CoachChatPage());
        await app.tap(find.text('How was my week?'));
        expect(find.text('Your steps averaged 7,422.'), findsOneWidget);

        await app.pump(const CoachChatPage(), key: UniqueKey());
        expect(find.text('How was my week?'), findsOneWidget);
        expect(find.text('Your steps averaged 7,422.'), findsOneWidget);

        await app.tap(find.byTooltip('New chat'));
        expect(find.text('Ask about your days'), findsOneWidget);
        await app.pump(const CoachChatPage(), key: UniqueKey());
        expect(find.text('Ask about your days'), findsOneWidget);
      },
    );

    testWidgets('yesterday\'s thread is not restored', (tester) async {
      final app = TestApp(tester, _server());
      await app.pump(const CoachChatPage(), now: DateTime(2026, 10, 25, 9));
      await app.tap(find.text('How was my week?'));

      await app.pump(const CoachChatPage(), key: UniqueKey(), now: DateTime(2026, 10, 26, 9));
      expect(find.text('Ask about your days'), findsOneWidget);
    });
  });

  group('Coach window', () {
    ChatMessage u(int i) => ChatMessage(ChatRole.user, 'q$i');
    ChatMessage a(int i) => ChatMessage(ChatRole.assistant, 'a$i');

    test('is bounded and starts with the person', () {
      final all = [
        for (var i = 0; i < 15; i++) ...[u(i), a(i)],
      ];
      final window = CoachChat.window(all);
      expect(window.length, lessThanOrEqualTo(kCoachWindow));
      expect(window.first.isUser, isTrue);
      expect(window.last, all.last);
      expect(CoachChat.window([u(1)]), [isA<ChatMessage>()]);
    });
  });

  group('Entries', () {
    testWidgets('Today shows the coach button only when the server can answer', (tester) async {
      final on = TestApp(tester, _server());
      await on.pump(const TodayScreen());
      expect(find.byIcon(Icons.chat_bubble_rounded), findsOneWidget);
      await on.tap(find.byIcon(Icons.chat_bubble_rounded));
      expect(find.byType(CoachChatPage), findsOneWidget);
    });

    testWidgets('Today has no coach button without the feature', (tester) async {
      await TestApp(tester, _server(coach: false)).pump(const TodayScreen());
      expect(find.byIcon(Icons.chat_bubble_rounded), findsNothing);
    });
  });
}
