import 'package:flutter_test/flutter_test.dart';
import 'package:newme/api/models.dart';
import 'package:newme/features/log/meal_items.dart';

Map<String, dynamic> _apple({double quantity = 1, int kcal = 95, String source = 'usda'}) => {
  'text': 'an apple',
  'name': 'Apple',
  'brand': '',
  'quantity': quantity,
  'unit': 'medium',
  'grams': 182 * quantity,
  'kcal': kcal,
  'protein': 0.5 * quantity,
  'carbs': 25 * quantity,
  'fat': 0.3 * quantity,
  'fiber': 4.4 * quantity,
  'source': source,
  'sourceId': '171688',
  'matchedName': 'Apples, raw, with skin',
  'confidence': 'high',
  'origin': '',
};

void main() {
  group('MealItem', () {
    test('scales from the per-unit numbers so stepping up and back never drifts', () {
      var item = MealItem.fromJson(_apple());
      expect((item.kcal, item.protein, item.grams), (95, 0.5, 182));
      item = item.withQuantity(1.5);
      expect((item.kcal, item.carbs, item.grams), (143, 37.5, 273));
      for (var i = 0; i < 20; i++) {
        item = item.withQuantity(i.isEven ? 0.25 : 3.5);
      }
      item = item.withQuantity(1);
      expect((item.kcal, item.protein, item.fiber), (95, 0.5, 4.4));
    });

    test('an item that arrives as two units keeps the per-unit numbers', () {
      final item = MealItem.fromJson(_apple(quantity: 2, kcal: 190));
      expect(item.kcal, 190);
      expect(item.withQuantity(1).kcal, 95);
    });

    test('kcal stays inside what the meal log accepts', () {
      final item = MealItem.fromJson(_apple(kcal: 9000)).withQuantity(1000);
      expect(item.kcal, 10000);
    });

    test('database and saved-from-database items count as databases, estimates do not', () {
      expect(MealItem.fromJson(_apple()).fromDatabase, isTrue);
      expect(MealItem.fromJson(_apple(source: 'estimated')).fromDatabase, isFalse);
      expect(
        MealItem.fromJson({..._apple(source: 'library'), 'origin': 'usda'}).fromDatabase,
        isTrue,
      );
      expect(
        MealItem.fromJson({..._apple(source: 'library'), 'origin': 'estimated'}).fromDatabase,
        isFalse,
      );
    });

    test('what gets saved on log: database items, kept estimates, never saved ones', () {
      expect(MealItem.fromJson(_apple()).willSave, isTrue);
      expect(MealItem.fromJson(_apple(source: 'library')).willSave, isFalse);
      final estimated = MealItem.fromJson(_apple(source: 'estimated'));
      expect(estimated.willSave, isFalse);
      expect(estimated.withSave(true).willSave, isTrue);
    });

    test('saving takes the numbers for one unit and the unit weight', () {
      final saved = MealItem.fromJson(_apple(quantity: 2, kcal: 190)).toSavedFood();
      expect(saved.servingText, '1 medium (182 g)');
      expect((saved.kcal, saved.servingGrams, saved.protein), (95, 182, 0.5));
      expect((saved.source, saved.sourceId), (FoodSource.usda, '171688'));
    });

    test('a candidate keeps its own serving wording and counts in the unit without the amount', () {
      final candidate = SavedFood.fromJson({
        'id': null,
        'name': 'Apple',
        'servingText': '1 medium (3" dia)',
        'servingGrams': 182,
        'kcal': 95,
        'source': 'usda',
        'sourceId': '171688',
      });
      final item = MealItem.fromFood(candidate);
      expect(item.unit, 'medium (3" dia)');
      expect(item.toSavedFood().servingText, '1 medium (3" dia)');
      expect(item.source, FoodSource.usda);
      final saved = MealItem.fromFood(
        SavedFood.fromJson({
          'id': 4,
          'name': 'Apple',
          'servingText': '2 tbsp',
          'kcal': 90,
          'source': 'manual',
        }),
      );
      expect((saved.source, saved.sourceId, saved.unit), (FoodSource.library, '4', 'tbsp'));
    });
  });

  group('meal totals', () {
    final items = [
      MealItem.fromJson(_apple()),
      MealItem.fromJson({..._apple(source: 'estimated'), 'name': 'Hot Pocket', 'kcal': 285}),
    ];

    test('sum the items and report the share of kcal from databases', () {
      final t = mealTotals(items);
      expect((t.kcal, t.share), (380, 25));
      expect(t.protein, 1);
    });

    test('an empty meal is zero and the name is the joined item names', () {
      expect(mealTotals(const []).share, 0);
      expect(joinedMealName(items), 'Apple, Hot Pocket');
      expect(joinedMealName(const []), 'Meal');
      final long = [
        for (var i = 0; i < 12; i++) MealItem.fromJson({..._apple(), 'name': 'Food number $i'}),
      ];
      expect(joinedMealName(long).length, lessThanOrEqualTo(80));
    });

    test('quantities print without trailing zeros and weights step in tens', () {
      expect([quantityText(1), quantityText(0.5), quantityText(2.25)], ['1', '0.5', '2.25']);
      expect((quantityStep('g'), quantityStep('medium')), (10, 0.5));
    });
  });

  test('a breakdown from an older server has no items but keeps the single meal', () {
    final b = MealBreakdown.fromJson({
      'name': 'Burrito bowl',
      'kcal': 640,
      'protein': 42,
      'carbs': 58,
      'fat': 24,
      'fiber': 9,
      'confidence': 'medium',
      'notes': 'n',
    });
    expect(b.items, isEmpty);
    expect((b.legacy.name, b.legacy.kcal), ('Burrito bowl', 640));
  });

  test('foods tolerate missing fields and unknown sources', () {
    final f = SavedFood.fromJson({'name': 'x', 'source': 'web'});
    expect(
      (f.saved, f.source, f.servingText, f.kcal),
      (false, FoodSource.estimated, '1 serving', 0),
    );
    expect(FoodSearch.fromJson({}).foods, isEmpty);
  });
}
