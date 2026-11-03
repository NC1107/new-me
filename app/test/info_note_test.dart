import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:newme/widgets/info_note.dart';

void main() {
  const info = InfoContent(
    title: 'Where this comes from',
    paragraphs: ['The longer explanation.'],
    source: 'Kodama et al., JAMA 2009.',
  );

  Future<void> pumpNote(WidgetTester tester) => tester.pumpWidget(
    const MaterialApp(
      home: Scaffold(body: InfoNote('A short line.', info: info)),
    ),
  );

  testWidgets('the citation stays behind the icon until it is tapped', (tester) async {
    await pumpNote(tester);

    expect(find.text('A short line.'), findsOneWidget);
    expect(find.textContaining('Kodama'), findsNothing);

    await tester.tap(find.text('A short line.'));
    await tester.pumpAndSettle();

    expect(find.text('The longer explanation.'), findsOneWidget);
    expect(find.text('Kodama et al., JAMA 2009.'), findsOneWidget);
  });

  testWidgets('the target is at least 44 points high and labelled', (tester) async {
    await pumpNote(tester);

    expect(tester.getSize(find.byType(InfoNote)).height, greaterThanOrEqualTo(44));
    final semantics = tester.getSemantics(find.byType(InfoNote));
    expect(semantics.label, 'A short line.. More about Where this comes from');
  });
}
