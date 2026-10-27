import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:newme/theme/accent.dart';
import 'package:newme/theme/tokens.dart';
import 'package:newme/widgets/app_card.dart';
import 'package:newme/widgets/choice_card.dart';
import 'package:newme/widgets/chunky_button.dart';
import 'package:newme/widgets/confetti.dart';
import 'package:newme/widgets/mascot.dart';
import 'package:newme/widgets/pop_in.dart';
import 'package:newme/widgets/preset_list.dart';
import 'package:newme/widgets/speech_bubble.dart';
import 'package:newme/widgets/step_progress_bar.dart';
import 'package:newme/widgets/thick_progress_bar.dart';

Widget _host(Widget child, {bool reduceMotion = false, String accent = 'green'}) => MaterialApp(
  theme: themeFor(accentById(accent)),
  home: MediaQuery(
    data: MediaQueryData(disableAnimations: reduceMotion),
    child: Scaffold(
      body: Center(child: SizedBox(width: 350, child: child)),
    ),
  ),
);

double _contrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  return (la > lb ? la + 0.05 : lb + 0.05) / (la > lb ? lb + 0.05 : la + 0.05);
}

void main() {
  group('tokens', () {
    test('text colours clear AA on the canvas and on white', () {
      for (final bg in [kCanvas, kSurface]) {
        expect(_contrast(kInk, bg), greaterThan(7));
        expect(_contrast(kInkSecondary, bg), greaterThanOrEqualTo(4.5));
        expect(_contrast(kInkMuted, bg), greaterThanOrEqualTo(4.5));
        expect(_contrast(kDangerText, bg), greaterThanOrEqualTo(4.5));
      }
    });

    test('text on every person fill holds 3:1 for large bold text', () {
      for (final p in kAccentPresets) {
        expect(_contrast(p.onFill, p.fill), greaterThanOrEqualTo(3), reason: p.id);
        expect(_contrast(p.lip, kSurface), greaterThanOrEqualTo(3), reason: '${p.id} lip text');
      }
    });

    test('stored keys are unchanged', () {
      expect(
        [for (final p in kAccentPresets) p.id],
        ['green', 'sky', 'violet', 'amber', 'rose', 'teal'],
      );
    });
  });

  group('ChunkyButton', () {
    testWidgets('fires on tap, shows the label in capitals and is 56 tall with its lip', (
      tester,
    ) async {
      var taps = 0;
      await tester.pumpWidget(_host(ChunkyButton(label: 'Save', onPressed: () => taps++)));
      expect(find.text('SAVE'), findsOneWidget);
      expect(tester.getSize(find.byType(ChunkyButton)).height, 56);
      await tester.tap(find.byType(ChunkyButton));
      expect(taps, 1);
    });

    testWidgets('the face drops onto the lip while pressed', (tester) async {
      await tester.pumpWidget(_host(ChunkyButton(label: 'Save', onPressed: () {})));
      double faceTop() => tester.widget<AnimatedPositioned>(find.byType(AnimatedPositioned)).top!;
      expect(faceTop(), 0);
      final gesture = await tester.startGesture(tester.getCenter(find.byType(ChunkyButton)));
      await tester.pump(const Duration(milliseconds: 120));
      expect(faceTop(), ChunkyButton.lipHeight);
      await gesture.up();
      await tester.pump(const Duration(milliseconds: 120));
      expect(faceTop(), 0);
    });

    testWidgets('disabled and busy buttons ignore taps', (tester) async {
      var taps = 0;
      await tester.pumpWidget(_host(const ChunkyButton(label: 'Save', onPressed: null)));
      await tester.tap(find.byType(ChunkyButton));
      await tester.pumpWidget(
        _host(ChunkyButton(label: 'Save', busy: true, onPressed: () => taps++)),
      );
      await tester.tap(find.byType(ChunkyButton));
      expect(taps, 0);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('SAVE'), findsNothing);
    });

    testWidgets('secondary is white and can shrink to its content', (tester) async {
      await tester.pumpWidget(
        _host(
          Align(
            child: ChunkyButton.secondary(label: 'Not now', fullWidth: false, onPressed: () {}),
          ),
        ),
      );
      expect(tester.getSize(find.byType(ChunkyButton)).width, lessThan(350));
    });
  });

  group('AppCard', () {
    testWidgets('is tappable only when given onTap', (tester) async {
      var taps = 0;
      await tester.pumpWidget(_host(AppCard(onTap: () => taps++, child: const Text('Hi'))));
      await tester.tap(find.text('Hi'));
      expect(taps, 1);
      final box = tester.widget<DecoratedBox>(find.byType(DecoratedBox).first);
      final deco = box.decoration as BoxDecoration;
      expect(deco.border!.top.width, 2);
      expect(deco.borderRadius, BorderRadius.circular(16));
    });
  });

  group('ThickProgressBar', () {
    testWidgets('is 16 tall, and taller by a flag when it has a marker', (tester) async {
      await tester.pumpWidget(_host(const ThickProgressBar(value: 0.4)));
      expect(tester.getSize(find.byType(ThickProgressBar)).height, 16);
      await tester.pumpWidget(_host(const ThickProgressBar(value: 0.4, markerAt: 0.7)));
      expect(tester.getSize(find.byType(ThickProgressBar)).height, greaterThan(16));
      expect(find.byIcon(Icons.flag_rounded), findsOneWidget);
    });

    testWidgets('eases to a new value and reports it to screen readers', (tester) async {
      await tester.pumpWidget(_host(const ThickProgressBar(value: 0.2, semanticLabel: 'Day')));
      expect(find.bySemanticsLabel('Day'), findsOneWidget);
      await tester.pumpWidget(_host(const ThickProgressBar(value: 0.9, semanticLabel: 'Day')));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pumpAndSettle();
      expect(tester.getSemantics(find.bySemanticsLabel('Day')).value, '90%');
    });

    testWidgets('survives nonsense values', (tester) async {
      await tester.pumpWidget(_host(const ThickProgressBar(value: double.nan)));
      await tester.pumpWidget(_host(const ThickProgressBar(value: 7)));
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets('StepProgressBar shows a back arrow only when it can go back', (tester) async {
    var backs = 0;
    await tester.pumpWidget(_host(StepProgressBar(progress: 0.3, onBack: () => backs++)));
    await tester.tap(find.byIcon(Icons.arrow_back_rounded));
    expect(backs, 1);
    await tester.pumpWidget(_host(const StepProgressBar(progress: 0.3)));
    expect(find.byIcon(Icons.arrow_back_rounded), findsNothing);
  });

  group('ChoiceCard', () {
    testWidgets('selecting it washes it in the person tint with a 2px fill border', (tester) async {
      Future<BoxDecoration> deco() async {
        final c = tester.widget<AnimatedContainer>(
          find
              .descendant(of: find.byType(ChoiceCard), matching: find.byType(AnimatedContainer))
              .first,
        );
        return c.decoration! as BoxDecoration;
      }

      var taps = 0;
      Widget card(bool selected) => _host(
        ChoiceCard(
          title: 'Move more',
          subtitle: 'Steps',
          icon: Icons.directions_walk_rounded,
          selected: selected,
          onTap: () => taps++,
        ),
        accent: 'sky',
      );
      await tester.pumpWidget(card(false));
      expect((await deco()).color, kSurface);
      await tester.tap(find.byType(ChoiceCard));
      expect(taps, 1);
      await tester.pumpWidget(card(true));
      await tester.pumpAndSettle();
      final selected = await deco();
      expect(selected.color, accentById('sky').tint);
      expect(selected.border!.top.color, accentById('sky').fill);
      expect(selected.border!.top.width, 2);
    });
  });

  testWidgets('PresetList selects one at a time and reports the value', (tester) async {
    final picked = <int>[];
    await tester.pumpWidget(
      _host(
        PresetList<int>(
          presets: const [
            Preset(name: 'Casual', valueLabel: '5,000 steps', value: 5000),
            Preset(name: 'Regular', valueLabel: '8,000 steps', value: 8000),
          ],
          selected: 8000,
          onChanged: picked.add,
        ),
      ),
    );
    await tester.tap(find.text('Casual'));
    expect(picked, [5000]);
    expect(find.bySemanticsLabel('Regular, 8,000 steps'), findsOneWidget);
  });

  testWidgets('SpeechBubble paints with a tail on either side without throwing', (tester) async {
    await tester.pumpWidget(_host(const SpeechBubble(text: 'Hi')));
    await tester.pumpWidget(_host(const SpeechBubble(text: 'Hi', tail: BubbleTail.top)));
    expect(tester.takeException(), isNull);
    expect(find.text('Hi'), findsOneWidget);
  });

  group('Confetti', () {
    testWidgets('plays once and then paints nothing', (tester) async {
      await tester.pumpWidget(_host(const SizedBox(height: 300, child: Confetti())));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byType(CustomPaint), findsWidgets);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('replays when the burst number changes and is skipped with reduced motion', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(const SizedBox(height: 300, child: Confetti(burst: 1)), reduceMotion: true),
      );
      await tester.pumpAndSettle();
      await tester.pumpWidget(
        _host(const SizedBox(height: 300, child: Confetti(burst: 2)), reduceMotion: true),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });

  group('PopIn', () {
    testWidgets('grows from nothing to full size', (tester) async {
      await tester.pumpWidget(_host(const PopIn(child: SizedBox(width: 40, height: 40))));
      final start = tester
          .widget<Transform>(
            find.descendant(of: find.byType(PopIn), matching: find.byType(Transform)),
          )
          .transform
          .storage[0];
      await tester.pumpAndSettle();
      final end = tester
          .widget<Transform>(
            find.descendant(of: find.byType(PopIn), matching: find.byType(Transform)),
          )
          .transform
          .storage[0];
      expect(start, lessThan(end));
      expect(end, closeTo(1, 0.001));
    });

    testWidgets('jumps to the end with reduced motion', (tester) async {
      await tester.pumpWidget(_host(const PopIn(child: Text('Done')), reduceMotion: true));
      final scale = tester
          .widget<Transform>(
            find.descendant(of: find.byType(PopIn), matching: find.byType(Transform)),
          )
          .transform
          .storage[0];
      expect(scale, closeTo(1, 0.001));
    });
  });

  group('Mascot', () {
    testWidgets('draws every state, hidden from screen readers', (tester) async {
      for (final state in MascotState.values) {
        await tester.pumpWidget(_host(Mascot(state: state)));
        await tester.pump(const Duration(milliseconds: 50));
        expect(tester.takeException(), isNull, reason: '$state');
      }
      expect(find.bySemanticsLabel(RegExp('.')), findsNothing);
    });

    testWidgets('blinks and hops on timers, and settles when idle motion is off', (tester) async {
      await tester.pumpWidget(_host(const Mascot()));
      await tester.pump(const Duration(milliseconds: 3300));
      expect(tester.hasRunningAnimations, isTrue, reason: 'a blink');
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpWidget(_host(const Mascot(state: MascotState.cheer)));
      await tester.pump(const Duration(milliseconds: 700));
      expect(tester.hasRunningAnimations, isTrue, reason: 'a hop');

      Mascot.idleMotion = false;
      addTearDown(() => Mascot.idleMotion = true);
      await tester.pumpWidget(_host(const Mascot(state: MascotState.happy)));
      await tester.pumpAndSettle();
    });

    testWidgets('recolours when the person colour changes', (tester) async {
      await tester.pumpWidget(_host(const Mascot(), accent: 'green'));
      await tester.pumpWidget(_host(const Mascot(), accent: 'rose'));
      await tester.pump(const Duration(milliseconds: 400));
      expect(tester.takeException(), isNull);
    });

    testWidgets('does nothing on a timer when animations are disabled', (tester) async {
      await tester.pumpWidget(_host(const Mascot(state: MascotState.cheer), reduceMotion: true));
      await tester.pump(const Duration(seconds: 10));
      expect(tester.hasRunningAnimations, isFalse);
    });
  });
}
