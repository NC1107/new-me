import 'package:flutter/material.dart';

import 'accent.dart';

/// Quests read the same for both people, so each key owns a fixed colour and icon.
/// The colour appears only in the icon circle tint and the progress fill.
AccentPalette questPalette(String key) => accentById(switch (key) {
  'steps' => 'sky',
  'exercise' => 'rose',
  'pushups' => 'amber',
  'reading' => 'violet',
  'meals_logged' || 'meals' => 'green',
  'protein' => 'teal',
  'sleep' => 'violet',
  'yoga' => 'teal',
  'water' => 'sky',
  _ => 'sky',
});

IconData questIcon(String key) => switch (key) {
  'steps' => Icons.directions_walk_rounded,
  'exercise' => Icons.local_fire_department_rounded,
  'pushups' => Icons.fitness_center_rounded,
  'reading' => Icons.menu_book_rounded,
  'meals_logged' || 'meals' => Icons.restaurant_rounded,
  'protein' => Icons.egg_alt_rounded,
  'sleep' => Icons.bedtime_rounded,
  'yoga' => Icons.self_improvement_rounded,
  'water' => Icons.water_drop_rounded,
  _ => Icons.star_rounded,
};
