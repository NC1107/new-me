import 'package:flutter/material.dart';

/// The server's icon keys, in the order the picker shows them, each as a rounded Material icon.
const kHabitIcons = <String, IconData>{
  'check_circle': Icons.check_circle_rounded,
  'brush': Icons.brush_rounded,
  'clean_hands': Icons.clean_hands_rounded,
  'bathtub': Icons.bathtub_rounded,
  'medication': Icons.medication_rounded,
  'vaccines': Icons.vaccines_rounded,
  'water_drop': Icons.water_drop_rounded,
  'local_cafe': Icons.local_cafe_rounded,
  'restaurant': Icons.restaurant_rounded,
  'lunch_dining': Icons.lunch_dining_rounded,
  'fitness_center': Icons.fitness_center_rounded,
  'directions_walk': Icons.directions_walk_rounded,
  'directions_run': Icons.directions_run_rounded,
  'directions_bike': Icons.directions_bike_rounded,
  'sports_gymnastics': Icons.sports_gymnastics_rounded,
  'self_improvement': Icons.self_improvement_rounded,
  'spa': Icons.spa_rounded,
  'bedtime': Icons.bedtime_rounded,
  'wb_sunny': Icons.wb_sunny_rounded,
  'menu_book': Icons.menu_book_rounded,
  'edit_note': Icons.edit_note_rounded,
  'favorite': Icons.favorite_rounded,
  'bolt': Icons.bolt_rounded,
  'eco': Icons.eco_rounded,
  'star': Icons.star_rounded,
  'pets': Icons.pets_rounded,
};

const kDefaultHabitIcon = 'check_circle';

/// An unknown key from a newer server still gets a sensible icon.
IconData habitIcon(String key) => kHabitIcons[key] ?? Icons.check_circle_rounded;

/// What a screen reader says for each icon, instead of the Material names.
const _kIconLabels = <String, String>{
  'check_circle': 'Checkmark',
  'brush': 'Toothbrush',
  'clean_hands': 'Washing hands',
  'bathtub': 'Bath',
  'medication': 'Pill bottle',
  'vaccines': 'Syringe',
  'water_drop': 'Water drop',
  'local_cafe': 'Coffee cup',
  'restaurant': 'Fork and knife',
  'lunch_dining': 'Burger',
  'fitness_center': 'Dumbbell',
  'directions_walk': 'Walking',
  'directions_run': 'Running',
  'directions_bike': 'Cycling',
  'sports_gymnastics': 'Stretching',
  'self_improvement': 'Meditation',
  'spa': 'Lotus',
  'bedtime': 'Moon',
  'wb_sunny': 'Sun',
  'menu_book': 'Open book',
  'edit_note': 'Notes',
  'favorite': 'Heart',
  'bolt': 'Lightning bolt',
  'eco': 'Leaf',
  'star': 'Star',
  'pets': 'Paw print',
};

String habitIconLabel(String key) => _kIconLabels[key] ?? key.replaceAll('_', ' ');
