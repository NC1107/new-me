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

    await tester.tap(find.text('Violet'));
    await tester.tap(find.text('Sky'));
    expect(picked, ['violet']);
    expect(find.byIcon(Icons.check), findsOneWidget);
    expect(find.byIcon(Icons.block), findsOneWidget);
  });

  testWidgets('the offline banner shows when the screen was last updated', (tester) async {
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
