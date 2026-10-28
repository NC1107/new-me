import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:newme/api/food_models.dart';
import 'package:newme/features/log/food_category_icon.dart';
import 'package:newme/features/log/food_search.dart';

void main() {
  // Categories as USDA returned them on 2026-10-28, across Branded, SR Legacy and FNDDS.
  test('real USDA categories get the icon a person would expect', () {
    final cases = <String, IconData?>{
      'Sausages, Hotdogs & Brats': Icons.kebab_dining_rounded,
      'Fruits and Fruit Juices': Icons.eco_rounded,
      'Fruit & Vegetable Juice, Nectars & Fruit Drinks': Icons.local_drink_rounded,
      'Apples': Icons.eco_rounded,
      'Pre-Packaged Fruit & Vegetables': Icons.eco_rounded,
      'Milk, whole': Icons.local_drink_rounded,
      'Coffee': Icons.local_cafe_rounded,
      'Beer': Icons.sports_bar_rounded,
      'Pizza': Icons.local_pizza_rounded,
      'Peanut butter and jelly sandwiches': Icons.lunch_dining_rounded,
      'Eggs and omelets': Icons.egg_rounded,
      'Ice cream and frozen dairy desserts': Icons.icecream_rounded,
      'Cookies & Biscuits': Icons.cookie_rounded,
      'Breads & Buns': Icons.bakery_dining_rounded,
      'Rice mixed dishes': Icons.rice_bowl_rounded,
      'Finfish and Shellfish Products': Icons.set_meal_rounded,
      'Nut & Seed Butters': Icons.grain_rounded,
      'Chips, Pretzels & Snacks': Icons.fastfood_rounded,
      'Dairy and Egg Products': null,
      'Cheese': null,
      'Doughnuts, sweet rolls, pastries': Icons.cake_rounded,
    };
    for (final MapEntry(key: category, value: icon) in cases.entries) {
      expect(foodCategoryIcon(category), icon, reason: category);
    }
    expect(foodCategoryIcon(null), isNull);
    expect(foodCategoryIcon('Veggie burgers'), Icons.lunch_dining_rounded);
  });

  testWidgets('a USDA result without a photo shows its category icon', (tester) async {
    final food = SavedFood.fromJson({
      'name': 'Sausage links',
      'servingText': '1 serving (50 g)',
      'kcal': 240,
      'source': 'usda',
      'imageUrl': null,
      'category': 'Sausages, Hotdogs & Brats',
    });
    expect(food.category, 'Sausages, Hotdogs & Brats');
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FoodTile(food: food, enabled: true, onTap: () {}),
        ),
      ),
    );
    expect(find.byIcon(Icons.kebab_dining_rounded), findsOneWidget);
  });
}
