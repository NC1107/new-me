import 'package:newme/util/time_format.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:newme/features/shell/update_required_screen.dart';
import 'package:newme/state/cached_resource.dart';
import 'package:newme/theme/accent.dart';
import 'package:newme/theme/accent_picker.dart';
import 'package:newme/widgets/offline_banner.dart';

Widget _host(Widget child) => MaterialApp(
  theme: themeFor(kAccentPresets.first),
  home: Scaffold(body: child),
);

void main() {
  testWidgets('the accent picker reports taps and ignores taken colors', (tester) async {
    final picked = <String>[];
    await tester.pumpWidget(
      _host(AccentPicker(selected: 'green', taken: const {'sky'}, onChanged: picked.add)),
    );

    await tester.tap(find.text('Iris'));
    await tester.tap(find.text('Sky'));
    expect(picked, ['violet']);
    expect(find.byIcon(Icons.check_rounded), findsOneWidget);
    expect(find.byIcon(Icons.block_rounded), findsOneWidget);
  });

  testWidgets('all six swatches share one row even in a narrow card', (tester) async {
    await tester.pumpWidget(
      _host(
        Center(
          child: SizedBox(
            width: 326,
            child: AccentPicker(selected: 'green', onChanged: (_) {}, swatchSize: 40),
          ),
        ),
      ),
    );

    final circles = find.byType(AnimatedContainer);
    expect(circles, findsNWidgets(kAccentPresets.length));
    final tops = {
      for (final c in circles.evaluate()) tester.getTopLeft(find.byWidget(c.widget)).dy,
    };
    expect(tops, hasLength(1));
  });

  testWidgets('the offline banner shows when the screen was last updated', (tester) async {
    await tester.pumpWidget(
      _host(OfflineBanner(info: OfflineInfo(updatedAt: DateTime(2026, 10, 26, 14, 2)))),
    );
    expect(find.text('Offline - updated 2:02 PM'), findsOneWidget);
  });

  testWidgets('the offline banner follows a 24-hour phone', (tester) async {
    use24HourClock = true;
    addTearDown(() => use24HourClock = false);
    await tester.pumpWidget(
      _host(OfflineBanner(info: OfflineInfo(updatedAt: DateTime(2026, 10, 26, 14, 2)))),
    );
    expect(find.text('Offline - updated 14:02'), findsOneWidget);
  });

  testWidgets('the update screen offers no way past it', (tester) async {
    await tester.pumpWidget(_host(const UpdateRequiredScreen()));
    expect(find.text('Update required'), findsOneWidget);
    expect(find.byType(FilledButton), findsNothing);
    expect(find.byType(TextButton), findsNothing);
  });
}
