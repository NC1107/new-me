import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:newme/api/models.dart';
import 'package:newme/features/food/food_card.dart';
import 'package:newme/features/today/mini_bar.dart';

Future<void> _pump(WidgetTester tester, Targets targets) => tester.pumpWidget(
  MaterialApp(
    home: Scaffold(
      body: FoodCard(
        food: Food(
          kcal: 138,
          protein: 10.5,
          carbs: 0,
          fat: 0,
          fiber: 0,
          burned: 0,
          targets: targets,
        ),
      ),
    ),
  ),
);

void main() {
  testWidgets('a macro without a target shows no bar, which would read as none eaten', (
    tester,
  ) async {
    await _pump(tester, const Targets());
    expect(find.byType(MiniBar), findsNothing);
    expect(find.text('10.5 g'), findsOneWidget);
  });

  testWidgets('a macro with a target fills its bar', (tester) async {
    await _pump(tester, const Targets(protein: 100, carbs: 250, fat: 70));
    expect(find.byType(MiniBar), findsNWidgets(3));
    expect(tester.widget<MiniBar>(find.byType(MiniBar).first).value, closeTo(0.105, 1e-9));
  });
}
