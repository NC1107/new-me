import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:newme/api/food_models.dart';
import 'package:newme/features/log/food_search.dart';

SavedFood _food({String? imageUrl, String? sourceUrl}) => SavedFood(
  name: 'Apple sauce',
  servingText: '1 cup',
  kcal: 100,
  source: FoodSource.openfoodfacts,
  imageUrl: imageUrl,
  sourceUrl: sourceUrl,
);

Future<void> _pump(WidgetTester tester, Widget tile) => tester.pumpWidget(
  MaterialApp(
    home: Scaffold(
      body: Center(child: SizedBox(width: 340, child: tile)),
    ),
  ),
);

void main() {
  test('parses imageUrl and sourceUrl, null when absent', () {
    final withLinks = SavedFood.fromJson({
      'name': 'x',
      'imageUrl': 'https://images.openfoodfacts.org/a.jpg',
      'sourceUrl': 'https://world.openfoodfacts.org/product/1',
    });
    expect(withLinks.imageUrl, 'https://images.openfoodfacts.org/a.jpg');
    final without = SavedFood.fromJson({'name': 'x', 'imageUrl': null});
    expect(without.imageUrl, isNull);
    expect(without.sourceUrl, isNull);
  });

  testWidgets('a food with a photo shows a 44pt rounded thumbnail and the source link', (
    tester,
  ) async {
    String? opened;
    await _pump(
      tester,
      FoodTile(
        food: _food(
          imageUrl: 'https://images.openfoodfacts.org/a.jpg',
          sourceUrl: 'https://world.openfoodfacts.org/product/1',
        ),
        enabled: true,
        onTap: () {},
        onOpenSource: (url) => opened = url,
      ),
    );
    final image = tester.widget<Image>(find.byType(Image));
    expect((image.image as ResizeImage).imageProvider, isA<NetworkImage>());
    expect(tester.getSize(find.byType(FoodThumbnail)), const Size(44, 44));
    expect(find.byType(ClipRRect), findsOneWidget);

    await tester.tap(find.text('Open Food Facts'));
    expect(opened, 'https://world.openfoodfacts.org/product/1');
  });

  testWidgets('a failed photo falls back to the food icon', (tester) async {
    await _pump(
      tester,
      FoodTile(
        food: _food(imageUrl: 'https://images.openfoodfacts.org/a.jpg'),
        enabled: true,
        onTap: () {},
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.restaurant_rounded), findsOneWidget);
  });

  testWidgets('a food without a photo has no thumbnail or link, and reserves space on request', (
    tester,
  ) async {
    await _pump(tester, FoodTile(food: _food(), enabled: true, onTap: () {}));
    expect(find.byType(Image), findsNothing);
    expect(find.text('Open Food Facts'), findsNothing);
    final plainLeft = tester.getTopLeft(find.text('Apple sauce')).dx;

    await _pump(
      tester,
      FoodTile(food: _food(), enabled: true, onTap: () {}, reserveThumbnail: true),
    );
    expect(tester.getTopLeft(find.text('Apple sauce')).dx, plainLeft + 54);
  });

  testWidgets('tapping the tile adds the food', (tester) async {
    var taps = 0;
    await _pump(tester, FoodTile(food: _food(), enabled: true, onTap: () => taps++));
    await tester.tap(find.text('Apple sauce'));
    expect(taps, 1);
  });
}
