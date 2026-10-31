import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:newme/api/models.dart';
import 'package:newme/features/log/meal_items.dart';
import 'package:newme/features/today/quest_sheet.dart';
import 'package:newme/state/me.dart';
import 'package:newme/state/today.dart';
import 'package:newme/widgets/mascot.dart';
import 'package:newme/widgets/quest_copy.dart';

import 'fixtures.dart';
import 'test_support.dart';

Map<String, dynamic> _item(
  String name, {
  String kind = '',
  double grams = 100,
  double produce = 0,
  String source = 'usda',
}) => {
  'text': name,
  'name': name,
  'quantity': 1,
  'unit': 'serving',
  'kcal': 50,
  'protein': 1,
  'carbs': 10,
  'fat': 0,
  'fiber': 2,
  'grams': grams,
  'source': source,
  'confidence': 'high',
  'produceKind': kind,
  'produceGrams': produce,
};

Quest _produce({Map<String, dynamic>? detail, num actual = 3}) => Quest.fromJson(
  quest('produce', 'Fruit and vegetables', {
    'unit': 'servings',
    'target': 5,
    'actual': actual,
    'points': 50,
    'basePoints': 30,
    'detail': ?detail,
  }),
);

void main() {
  setUp(() {
    FakeStorage().install();
    Mascot.idleMotion = false;
  });

  group('what a meal item contributes', () {
    test('fruit and vegetables count in the whole-produce bucket, scaled with the amount', () {
      final item = MealItem.fromJson(
        _item('Broccoli', kind: 'vegetable', grams: 150, produce: 150),
      );
      expect(item.produce.produceG, 150);
      expect(item.withQuantity(2).produce.produceG, 300);
    });

    test('juice and pulses go to their own buckets', () {
      final juice = MealItem.fromJson(_item('Orange juice', kind: 'juice', produce: 250));
      final beans = MealItem.fromJson(_item('Black beans', kind: 'pulse', produce: 120));
      expect(juice.produce.juiceG, 250);
      expect(juice.produce.produceG, 0);
      expect(beans.produce.pulseG, 120);
    });

    test('an item with no kind adds nothing, whatever it weighs', () {
      final item = MealItem.fromJson(_item('Chicken', grams: 200));
      expect(item.produce.isEmpty, isTrue);
    });

    test('a library food keeps its kind and counts its serving weight', () {
      final food = const SavedFood(
        id: 4,
        name: 'Apple',
        servingText: '1 medium (182 g)',
        servingGrams: 182,
        kcal: 95,
        source: FoodSource.usda,
        produceKind: ProduceKind.fruit,
      );
      final item = MealItem.fromFood(food);
      expect(item.produce.produceG, 182);
      expect(item.withQuantity(2).produce.produceG, 364);
      expect(item.toSavedFood().produceKind, ProduceKind.fruit);
    });

    test('an estimated item is not saved as produce, because the guess belongs to one meal', () {
      final item = MealItem.fromJson(
        _item('Stew', kind: 'vegetable', produce: 90, source: 'estimated'),
      );
      expect(item.produce.produceG, 90);
      expect(item.toSavedFood().produceKind, ProduceKind.none);
    });

    test('a meal adds up its items and sends only the buckets that have something', () {
      final items = [
        MealItem.fromJson(_item('Broccoli', kind: 'vegetable', produce: 100)),
        MealItem.fromJson(_item('Apple', kind: 'fruit', produce: 180)),
        MealItem.fromJson(_item('Chicken')),
      ];
      final produce = mealProduce(items);
      expect(produce.produceG, 280);
      expect(
        MealDraft(
          clientOpId: 'a',
          name: 'Dinner',
          kcal: 500,
          produce: produce,
        ).toJson()['produceG'],
        280,
      );
      final plain = const MealDraft(clientOpId: 'b', name: 'Toast', kcal: 100).toJson();
      expect(plain.containsKey('produceG'), isFalse);
      expect(plain.containsKey('juiceG'), isFalse);
    });

    test('a logged meal and an undo keep the produce', () {
      final log = MealLog.fromJson({...mealLogJson(), 'produceG': 160.5});
      expect(log.produce.produceG, 160.5);
      final draft = log.toDraft('fresh') as MealDraft;
      expect(draft.produce.produceG, 160.5);
    });
  });

  group('the quest', () {
    test('says where the servings came from', () {
      expect(
        produceSplitLine(_produce(detail: {'fromMeals': 2, 'logged': 1})),
        '2 from meals, 1 you logged',
      );
      expect(produceSplitLine(_produce(detail: {'fromMeals': 3, 'logged': 0})), '3 from meals');
      expect(produceSplitLine(_produce(detail: {'fromMeals': 0, 'logged': 2})), '2 you logged');
      expect(produceSplitLine(_produce(detail: {'fromMeals': 0, 'logged': 0})), isNull);
      expect(produceSplitLine(_produce()), isNull);
    });

    test('lists the meals that have produce in them, and no others', () {
      final withProduce = LogEntry.fromJson({...mealLogJson(), 'produceG': 120});
      final without = LogEntry.fromJson(mealLogJson());
      expect(entryFeedsQuest('produce', withProduce), isTrue);
      expect(entryFeedsQuest('produce', without), isFalse);
    });

    test('has a title that reads as a sentence', () {
      expect(questTitle(_produce()), 'Eat fruit and veg');
      expect(questProgress(_produce()), '3 of 5 servings');
    });

    testWidgets('the sheet shows the split and how meals are counted', (tester) async {
      final today = richTodayJson(stepsEverSynced: true);
      today['quests'] = [
        ...(today['quests']! as List),
        _produce(detail: {'fromMeals': 2, 'logged': 1}).toJson(),
      ];
      final adapter = fullServer()
        ..on('GET /api/today', StubResponse(200, today))
        ..on(
          'GET /api/logs',
          StubResponse(
            200,
            logsJson([
              {...mealLogJson(), 'produceG': 160},
            ]),
          ),
        )
        ..on(
          'GET /api/quests/{key}/history',
          const StubResponse(200, {'key': 'produce', 'days': []}),
        );
      final app = TestApp(tester, adapter, surfaceHeight: 3200);
      await app.pump(
        Builder(
          builder: (context) => TextButton(
            onPressed: () => showQuestSheet(context, questKey: 'produce'),
            child: const Text('open quest'),
          ),
        ),
      );
      app.container.read(todayProvider);
      app.container.read(meProvider);
      await app.settle();
      await app.tap(find.text('open quest'));

      expect(find.text('Eat fruit and veg'), findsOneWidget);
      expect(find.text('2 from meals, 1 you logged'), findsOneWidget);
      expect(find.textContaining('80 g to a serving'), findsOneWidget);
      expect(find.text('Chicken bowl'), findsOneWidget);
    });
  });
}
