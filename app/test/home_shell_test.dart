import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:newme/features/board/board_screen.dart';
import 'package:newme/features/food/food_screen.dart';
import 'package:newme/features/me/me_screen.dart';
import 'package:newme/features/shell/home_shell.dart';
import 'package:newme/features/shell/home_tab.dart';
import 'package:newme/features/today/today_screen.dart';
import 'package:newme/features/training/train_screen.dart';
import 'package:newme/state/session.dart';
import 'package:newme/theme/accent.dart';
import 'package:newme/widgets/mascot.dart';

import 'fixtures.dart';
import 'test_support.dart';

void main() {
  setUp(() {
    FakeStorage().install();
    Mascot.idleMotion = false;
  });

  testWidgets('renders five tabs, no centre button, and tapping switches the visible body', (
    tester,
  ) async {
    final adapter = fullServer()
      ..on('GET /api/today', StubResponse(200, richTodayJson()..['food'] = restingFoodJson()));
    final app = TestApp(tester, adapter);
    await app.pump(const HomeShell());

    for (final tab in ['today', 'food', 'train', 'us', 'me']) {
      expect(find.byKey(Key('nav-$tab')), findsOneWidget);
    }
    expect(find.byType(FloatingActionButton), findsNothing);
    expect(app.container.read(homeTabProvider), HomeTab.today);

    for (final (key, tab, screen) in [
      ('food', HomeTab.food, FoodScreen),
      ('train', HomeTab.train, TrainScreen),
      ('us', HomeTab.board, BoardScreen),
      ('me', HomeTab.me, MeScreen),
    ]) {
      await app.tap(find.byKey(Key('nav-$key')));
      expect(app.container.read(homeTabProvider), tab);
      expect(find.byType(screen), findsOneWidget, reason: 'only the selected tab is on stage');
      expect(find.byType(TodayScreen), findsNothing);
    }
    await app.tap(find.byKey(const Key('nav-today')));
    expect(app.container.read(homeTabProvider), HomeTab.today);
  });

  testWidgets('the tabs show Today, Food, Train, Us and Me in that order', (tester) async {
    final app = TestApp(tester, fullServer());
    await app.pump(const HomeShell());

    final labels = ['Today', 'Food', 'Train', 'Us', 'Me'];
    final lefts = [
      for (final l in labels)
        tester
            .getTopLeft(
              find.descendant(
                of: find.byKey(Key('nav-${l.toLowerCase()}')),
                matching: find.text(l),
              ),
            )
            .dx,
    ];
    expect(lefts, [...lefts]..sort());
    expect(
      tester
          .widget<IndexedStack>(find.byType(IndexedStack).first)
          .children
          .map((w) => w.runtimeType),
      [TodayScreen, FoodScreen, TrainScreen, BoardScreen, MeScreen],
    );
  });

  testWidgets('the selected tab sits in a tinted square bordered in the person colour', (
    tester,
  ) async {
    final app = TestApp(tester, fullServer());
    await app.pump(const HomeShell());
    final person = accentById(app.accent);

    BoxDecoration decorationOf(String tab) {
      final box = tester.widget<AnimatedContainer>(
        find.descendant(of: find.byKey(Key('nav-$tab')), matching: find.byType(AnimatedContainer)),
      );
      return box.decoration! as BoxDecoration;
    }

    final selected = decorationOf('today');
    expect(selected.color, person.tint);
    expect((selected.border! as Border).top.color, person.fill);
    expect((selected.border! as Border).top.width, 2);
    expect(decorationOf('us').color, Colors.transparent);

    await app.tap(find.byKey(const Key('nav-us')));
    expect(decorationOf('us').color, person.tint);
    expect(decorationOf('today').color, Colors.transparent);
  });

  testWidgets('each tab is at least 44pt tall', (tester) async {
    final app = TestApp(tester, fullServer());
    await app.pump(const HomeShell());
    for (final tab in ['today', 'food', 'train', 'us', 'me']) {
      expect(tester.getSize(find.byKey(Key('nav-$tab'))).height, greaterThanOrEqualTo(44));
    }
  });

  testWidgets('a tab left under the offline banner reloads when it is opened again', (
    tester,
  ) async {
    final adapter = fullServer();
    final app = TestApp(tester, adapter);
    await app.pump(const HomeShell(), key: UniqueKey());

    adapter.on('GET /api/me', const StubResponse.unreachable());
    await app.pump(const HomeShell(), key: UniqueKey());
    await app.tap(find.byKey(const Key('nav-me')));
    expect(find.textContaining('Offline, updated'), findsOneWidget);

    adapter.on('GET /api/me', StubResponse(200, meJson()));
    await app.tap(find.byKey(const Key('nav-us')));
    await app.tap(find.byKey(const Key('nav-me')));

    expect(find.textContaining('Offline, updated'), findsNothing);
  });

  testWidgets('a new session starts on Today instead of the tab the last one left', (tester) async {
    final app = TestApp(tester, fullServer());
    await app.pump(const HomeShell());
    await app.tap(find.byKey(const Key('nav-me')));
    expect(app.container.read(homeTabProvider), HomeTab.me);

    await app.container.read(sessionProvider.notifier).signIn(testSession);
    await app.settle();
    expect(app.container.read(homeTabProvider), HomeTab.me, reason: 'same person, same tab');

    await app.container
        .read(sessionProvider.notifier)
        .signIn(
          const Session(
            baseUrl: 'https://me.invalid',
            token: 'other',
            userId: 9,
            userName: 'Ana',
            color: 'amber',
          ),
        );
    await app.settle();
    expect(app.container.read(homeTabProvider), HomeTab.today);
  });

  testWidgets('coming back to the app reloads a Today that crossed midnight', (tester) async {
    final adapter = fullServer();
    final app = TestApp(tester, adapter);
    await app.pump(const HomeShell());
    expect(find.text('Monday, Oct 26'), findsOneWidget);

    adapter.on(
      'GET /api/today',
      StubResponse(
        200,
        richTodayJson()..addAll({'date': '2026-10-27', 'localToday': '2026-10-27'}),
      ),
    );
    final binding = TestWidgetsFlutterBinding.instance;
    binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await app.settle();

    expect(find.text('Tuesday, Oct 27'), findsOneWidget);
    expect(find.text('Monday, Oct 26'), findsNothing);
  });

  testWidgets("the next person never sees the previous person's Today while theirs loads", (
    tester,
  ) async {
    final adapter = fullServer();
    final app = TestApp(tester, adapter);
    await app.pump(const HomeShell());
    expect(find.text('150'), findsOneWidget);

    final gate = Completer<void>();
    adapter.routes['GET /api/today'] = (_) async {
      await gate.future;
      return StubResponse(200, richTodayJson(points: 999));
    };
    await app.container
        .read(sessionProvider.notifier)
        .signIn(
          const Session(
            baseUrl: 'https://me.invalid',
            token: 'other',
            userId: 9,
            userName: 'Ana',
            color: 'amber',
          ),
        );
    await app.settle();
    expect(find.text('150'), findsNothing);
    expect(find.text('Monday, Oct 26'), findsNothing);

    gate.complete();
    await app.settle();
    expect(find.text('999'), findsOneWidget);
  });
}
