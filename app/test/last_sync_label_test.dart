import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:newme/state/clock.dart';

void main() {
  testWidgets('the last sync label moves on with the clock instead of freezing at just now', (
    tester,
  ) async {
    var now = DateTime(2026, 10, 28, 9, 0);
    final synced = now;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [clockProvider.overrideWithValue(() => now)],
        child: MaterialApp(
          home: Consumer(builder: (context, ref, _) => Text(lastSyncLabel(ref, synced))),
        ),
      ),
    );
    expect(find.text('Last sync just now'), findsOneWidget);

    now = now.add(const Duration(minutes: 12));
    await tester.pump(const Duration(minutes: 12));
    expect(find.text('Last sync 12m ago'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
  });
}
