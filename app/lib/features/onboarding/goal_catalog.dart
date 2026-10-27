import 'package:flutter/material.dart';

import '../../util/format.dart';

/// One named choice on a daily goal screen.
class GoalOption {
  const GoalOption(this.name, this.value);

  final String name;
  final int value;
}

/// What to ask for one quest: the question, its presets and how a number reads.
/// The Me screen reuses these for its goal pickers.
class GoalSpec {
  const GoalSpec({
    required this.questKey,
    required this.question,
    required this.options,
    required this.defaultValue,
    required this.label,
  });

  final String questKey;
  final String question;
  final List<GoalOption> options;
  final int defaultValue;

  /// "8,000 steps"
  final String Function(int value) label;
}

String _minutes(int v) => '$v min';

String _sleep(int minutes) {
  final h = minutes ~/ 60;
  final m = minutes % 60;
  return m == 0 ? '${h}h' : '${h}h ${m}m';
}

const _four = ['Casual', 'Regular', 'Serious', 'Intense'];

List<GoalOption> _named(List<int> values, [List<String> names = _four]) => [
  for (var i = 0; i < values.length; i++) GoalOption(names[i], values[i]),
];

final Map<String, GoalSpec> kGoalSpecs = {
  for (final s in [
    GoalSpec(
      questKey: 'steps',
      question: 'How many steps a day?',
      options: _named([5000, 8000, 10000, 12000]),
      defaultValue: 8000,
      label: (v) => '${v.formatted} steps',
    ),
    GoalSpec(
      questKey: 'exercise',
      question: 'How long will you work out?',
      options: _named([15, 30, 45, 60]),
      defaultValue: 30,
      label: _minutes,
    ),
    GoalSpec(
      questKey: 'pushups',
      question: 'How many push-ups a day?',
      options: _named([10, 20, 30, 50]),
      defaultValue: 20,
      label: (v) => '$v push-ups',
    ),
    GoalSpec(
      questKey: 'reading',
      question: 'How long will you read?',
      options: _named([10, 20, 30, 45]),
      defaultValue: 20,
      label: _minutes,
    ),
    GoalSpec(
      questKey: 'meals_logged',
      question: 'How many meals will you log?',
      options: _named([2, 3]),
      defaultValue: 2,
      label: (v) => '$v meals',
    ),
    GoalSpec(
      questKey: 'protein',
      question: 'How much protein a day?',
      options: _named([80, 100, 130, 160]),
      defaultValue: 100,
      label: (v) => '$v g',
    ),
    GoalSpec(
      questKey: 'sleep',
      question: 'How much sleep are you aiming for?',
      options: _named([390, 420, 450, 480]),
      defaultValue: 420,
      label: _sleep,
    ),
    GoalSpec(
      questKey: 'yoga',
      question: 'How long will you stretch?',
      options: _named([10, 15, 20, 30]),
      defaultValue: 15,
      label: _minutes,
    ),
  ])
    s.questKey: s,
};

/// Daily calorie presets for the optional food step.
const List<GoalOption> kCalorieOptions = [
  GoalOption('Lighter', 1600),
  GoalOption('Balanced', 2000),
  GoalOption('Active', 2400),
  GoalOption('Hearty', 2800),
];

/// A thing to work on. Picking one turns on its quests and asks for their goals.
class Focus {
  const Focus({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.questKeys,
  });

  final String id;
  final String title;
  final String subtitle;
  final IconData icon;
  final List<String> questKeys;

  /// The category colour comes from the first quest.
  String get colorKey => questKeys.first;
}

const List<Focus> kFocuses = [
  Focus(
    id: 'move',
    title: 'Move more',
    subtitle: 'Hit a daily step goal',
    icon: Icons.directions_walk_rounded,
    questKeys: ['steps'],
  ),
  Focus(
    id: 'workout',
    title: 'Work out',
    subtitle: 'Minutes of exercise each day',
    icon: Icons.local_fire_department_rounded,
    questKeys: ['exercise'],
  ),
  Focus(
    id: 'strength',
    title: 'Get stronger',
    subtitle: 'Push-ups, every day',
    icon: Icons.fitness_center_rounded,
    questKeys: ['pushups'],
  ),
  Focus(
    id: 'read',
    title: 'Read more',
    subtitle: 'A little reading, daily',
    icon: Icons.menu_book_rounded,
    questKeys: ['reading'],
  ),
  Focus(
    id: 'eat',
    title: 'Eat well',
    subtitle: 'Log meals and hit your protein',
    icon: Icons.restaurant_rounded,
    questKeys: ['meals_logged', 'protein'],
  ),
  Focus(
    id: 'sleep',
    title: 'Sleep better',
    subtitle: 'Enough rest, on a schedule',
    icon: Icons.bedtime_rounded,
    questKeys: ['sleep'],
  ),
  Focus(
    id: 'stretch',
    title: 'Stretch',
    subtitle: 'A few minutes of yoga',
    icon: Icons.self_improvement_rounded,
    questKeys: ['yoga'],
  ),
];

/// Every quest key New Me knows, so the plan can switch off the ones nobody picked.
List<String> get kAllQuestKeys => [for (final f in kFocuses) ...f.questKeys];

const kEatFocus = 'eat';
