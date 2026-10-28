import 'package:flutter/material.dart';

/// Words in a USDA food category, in order, and the icon each is drawn with. Order settles
/// categories that name two things: "Fruit & Vegetable Juice" is a drink and "Peanut butter and
/// jelly sandwiches" a sandwich. Dairy has no fitting icon, so "Dairy and Egg Products" stops
/// before the egg.
const _rules = <(List<String>, IconData?)>[
  (['dairy and egg'], null),
  // SR Legacy files whole fruit here too, and an apple is no drink.
  (['fruits and fruit juices'], Icons.eco_rounded),
  (['egg'], Icons.egg_rounded),
  (['pizza'], Icons.local_pizza_rounded),
  (['sandwich', 'burger', 'fast food'], Icons.lunch_dining_rounded),
  (['wine', 'liquor', 'alcohol'], Icons.wine_bar_rounded),
  (['beer'], Icons.sports_bar_rounded),
  (['coffee', 'tea'], Icons.local_cafe_rounded),
  (['ice cream', 'frozen dessert', 'frozen dairy'], Icons.icecream_rounded),
  (
    ['juice', 'milk', 'drink', 'beverage', 'soda', 'smoothie', 'shake', 'water'],
    Icons.local_drink_rounded,
  ),
  (['cookie', 'brownie'], Icons.cookie_rounded),
  (['cake', 'pie', 'candy', 'sweet', 'dessert', 'chocolate'], Icons.cake_rounded),
  (
    ['bread', 'bun', 'baked', 'bagel', 'tortilla', 'cracker', 'muffin', 'biscuit'],
    Icons.bakery_dining_rounded,
  ),
  (['cereal', 'oat', 'grain'], Icons.breakfast_dining_rounded),
  (['rice'], Icons.rice_bowl_rounded),
  (['pasta', 'noodle'], Icons.ramen_dining_rounded),
  (['soup', 'broth'], Icons.soup_kitchen_rounded),
  (['fish', 'seafood', 'shellfish'], Icons.set_meal_rounded),
  (
    [
      'sausage',
      'hotdog',
      'bacon',
      'beef',
      'pork',
      'chicken',
      'turkey',
      'poultry',
      'meat',
      'luncheon',
      'cold cut',
      'salami',
      'lamb',
    ],
    Icons.kebab_dining_rounded,
  ),
  (['nut', 'seed', 'peanut', 'legume', 'bean'], Icons.grain_rounded),
  (
    ['fruit', 'vegetable', 'salad', 'apple', 'citrus', 'broccoli', 'berr', 'potato', 'produce'],
    Icons.eco_rounded,
  ),
  (['chips', 'snack', 'popcorn', 'pretzel'], Icons.fastfood_rounded),
];

/// The icon for a USDA food category, or null when none fits and the plain food icon is shown.
/// Words match at the start of a word, so "veggie" is no egg and "doughnut" no nut.
IconData? foodCategoryIcon(String? category) {
  final c = category?.toLowerCase();
  if (c == null || c.isEmpty) return null;
  for (final (words, icon) in _rules) {
    if (words.any((w) => RegExp('\\b${RegExp.escape(w)}').hasMatch(c))) return icon;
  }
  return null;
}
