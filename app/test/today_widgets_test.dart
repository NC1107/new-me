import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:newme/features/log/big_number_stepper.dart';
import 'package:newme/theme/accent.dart';
import 'package:newme/theme/tokens.dart';
import 'package:newme/widgets/accent_text.dart';
import 'package:newme/widgets/chunky_icon_button.dart';

double _contrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  return ((la > lb ? la : lb) + 0.05) / ((la > lb ? lb : la) + 0.05);
}

void main() {
  testWidgets('the stepper number is named for screen readers', (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(
      MaterialApp(
        theme: themeFor(kAccentPresets.first),
        home: Scaffold(
          body: BigNumberStepper(
            controller: TextEditingController(text: '15'),
            unitLabel: 'minutes',
            onMinus: () {},
            onPlus: () {},
            onChanged: (_) {},
          ),
        ),
      ),
    );
    expect(find.bySemanticsLabel(RegExp('Amount in minutes')), findsOneWidget);
    handle.dispose();
  });

  test('every person colour has a text shade that clears AA on the canvas and its tint', () {
    for (final p in kAccentPresets) {
      final ink = readableAccent(p);
      expect(_contrast(ink, kCanvas), greaterThanOrEqualTo(4.5), reason: p.name);
      expect(_contrast(ink, kSurface), greaterThanOrEqualTo(4.5), reason: p.name);
      expect(_contrast(ink, p.tint), greaterThanOrEqualTo(4.5), reason: p.name);
    }
  });

  testWidgets('the chunky icon button is a 44pt target even when its disc is smaller', (
    tester,
  ) async {
    var taps = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: themeFor(kAccentPresets.first),
        home: Center(
          child: ChunkyIconButton(
            icon: Icons.add_rounded,
            semanticLabel: 'Add',
            size: 32,
            onPressed: () => taps++,
          ),
        ),
      ),
    );
    final size = tester.getSize(find.bySemanticsLabel('Add'));
    expect(size.width, greaterThanOrEqualTo(44));
    expect(size.height, greaterThanOrEqualTo(44));
    await tester.tapAt(tester.getTopLeft(find.bySemanticsLabel('Add')) + const Offset(2, 2));
    expect(taps, 1);
  });

  testWidgets('a disabled chunky icon button ignores taps', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: themeFor(kAccentPresets.first),
        home: const Center(
          child: ChunkyIconButton(icon: Icons.add_rounded, semanticLabel: 'Add', onPressed: null),
        ),
      ),
    );
    await tester.tap(find.byType(ChunkyIconButton));
    expect(tester.takeException(), isNull);
  });
}
