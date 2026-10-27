import 'package:flutter/material.dart';

import '../../api/models.dart';

/// Friendly names and icons for the workout types, kept in one place so lists, charts and the
/// detail sheet always agree.
String workoutTypeName(String type) => switch (type) {
  WorkoutType.walking => 'Walk',
  WorkoutType.running => 'Run',
  WorkoutType.cycling => 'Ride',
  WorkoutType.strength => 'Strength',
  WorkoutType.hiit => 'HIIT',
  WorkoutType.yoga => 'Yoga',
  WorkoutType.swimming => 'Swim',
  WorkoutType.hiking => 'Hike',
  WorkoutType.dance => 'Dance',
  WorkoutType.climbing => 'Climb',
  _ => 'Workout',
};

IconData workoutTypeIcon(String type) => switch (type) {
  WorkoutType.walking => Icons.directions_walk_rounded,
  WorkoutType.running => Icons.directions_run_rounded,
  WorkoutType.cycling => Icons.directions_bike_rounded,
  WorkoutType.strength => Icons.fitness_center_rounded,
  WorkoutType.hiit => Icons.bolt_rounded,
  WorkoutType.yoga => Icons.self_improvement_rounded,
  WorkoutType.swimming => Icons.pool_rounded,
  WorkoutType.hiking => Icons.hiking_rounded,
  WorkoutType.dance => Icons.music_note_rounded,
  WorkoutType.climbing => Icons.terrain_rounded,
  _ => Icons.sports_score_rounded,
};
