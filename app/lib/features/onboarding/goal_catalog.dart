import 'package:flutter/material.dart';

import '../../util/format.dart';
import '../../util/units.dart';

/// One plain number a person can pick on a goal screen. It carries no name: a figure is only
/// described when a published source gives it a meaning.
class GoalOption {
  const GoalOption(this.value);

  final int value;
}

/// How much of fruit and vegetables one serving is, in grams (NHS 5 A Day). The server's
/// `servingGrams` detail carries the same number.
const kProduceServingGrams = 80;

/// What to ask for one quest: the question, a few plain numbers and how a number reads. The Me
/// screen and onboarding put the personal recommendation from GET /api/targets ahead of them.
class GoalSpec {
  const GoalSpec({
    required this.questKey,
    required this.question,
    required this.options,
    required this.defaultValue,
    required this.label,
    this.targetKey,
    this.noResearch,
    this.note,
    this.labelIn,
  });

  final String questKey;
  final String question;

  /// The key of the target in GET /api/targets that recommends this goal, or null when no
  /// published figure exists.
  final String? targetKey;

  /// What the picker says in place of a recommendation. Null for goals another screen sizes.
  final String? noResearch;

  /// One extra line under the recommendation, for goals with something worth knowing up front.
  final String? note;

  /// Plain numbers to pick from when there is no recommendation to lead with.
  final List<GoalOption> options;
  final int defaultValue;

  /// "8,000 steps"
  final String Function(int value) label;

  /// The same label in the person's units, for goals measured in volume or weight.
  final String Function(int value, Units units)? labelIn;

  String describe(int value, Units units) => labelIn?.call(value, units) ?? label(value);
}

String _minutes(int v) => '$v min';

String _sleep(int minutes) {
  final h = minutes ~/ 60;
  final m = minutes % 60;
  return m == 0 ? '$h h' : '$h h $m min';
}

List<GoalOption> _plain(List<int> values) => [for (final v in values) GoalOption(v)];

const _yourCall = 'There is no research figure for this, so the number is your call.';

final Map<String, GoalSpec> kGoalSpecs = {
  for (final s in [
    GoalSpec(
      questKey: 'steps',
      question: 'How many steps a day?',
      targetKey: 'steps',
      options: _plain([5000, 7000, 10000]),
      defaultValue: 7000,
      label: (v) => '${v.formatted} steps',
    ),
    GoalSpec(
      questKey: 'exercise',
      question: 'How long will you work out?',
      targetKey: 'exercise',
      note: 'The guideline is a weekly figure, so a rest day is fine as long as the week adds up.',
      options: _plain([15, 30, 45, 60]),
      defaultValue: 30,
      label: _minutes,
    ),
    GoalSpec(
      questKey: 'pushups',
      question: 'How many push-ups a day?',
      options: _plain([10, 20, 30, 50]),
      defaultValue: 20,
      label: (v) => '$v push-ups',
    ),
    GoalSpec(
      questKey: 'reading',
      question: 'How long will you read?',
      noResearch: _yourCall,
      note: 'Audiobooks count too once you link Audiobookshelf in Me.',
      options: _plain([10, 20, 30, 45]),
      defaultValue: 20,
      label: _minutes,
    ),
    GoalSpec(
      questKey: 'meals_logged',
      question: 'How many meals will you log?',
      noResearch: _yourCall,
      options: _plain([2, 3]),
      defaultValue: 2,
      label: (v) => '$v meals',
    ),
    GoalSpec(
      questKey: 'protein',
      question: 'How much protein a day?',
      targetKey: 'protein',
      options: _plain([80, 100, 130, 160]),
      defaultValue: 100,
      label: (v) => '$v g',
    ),
    GoalSpec(
      questKey: 'sleep',
      question: 'How much sleep are you aiming for?',
      targetKey: 'sleep',
      options: _plain([420, 450, 480, 540]),
      defaultValue: 450,
      label: _sleep,
    ),
    GoalSpec(
      questKey: 'water',
      question: 'How much water a day?',
      targetKey: 'water',
      note: 'Needs rise with activity and heat.',
      options: _plain([1500, 2200, 3000]),
      defaultValue: 2200,
      label: (v) => Units.metric.volume(v),
      labelIn: (v, units) => units.volume(v),
    ),
    GoalSpec(
      questKey: 'sleep_regularity',
      question: 'How close to your usual times?',
      // Research shows regular timing matters (Windred et al. 2024) but gives no window to aim for.
      noResearch:
          'Regular timing matters (Windred 2024), but the research does not name a window, '
          'so the number is your call.',
      note: 'Your usual bed and wake times are the median of your last 7 nights.',
      options: _plain([30, 45, 60, 90]),
      defaultValue: 45,
      label: (v) => 'within $v min',
    ),
    GoalSpec(
      questKey: 'produce',
      question: 'How many servings of fruit and vegetables?',
      targetKey: 'produce',
      note:
          'One serving is 80 g, for example a medium apple or banana, 3 heaped tablespoons of '
          'cooked vegetables or a cereal bowl of salad (NHS 5 A Day). Potatoes do not count.',
      options: _plain([3, 5, 7, 10]),
      defaultValue: 5,
      label: (v) => '$v ${v == 1 ? 'serving' : 'servings'} (${v * kProduceServingGrams} g)',
    ),
    GoalSpec(
      questKey: 'breathing',
      question: 'How many minutes will you breathe?',
      targetKey: 'breathing',
      options: _plain([3, 5, 10, 15]),
      defaultValue: 5,
      label: _minutes,
    ),
    GoalSpec(
      questKey: 'yoga',
      question: 'How long will you do yoga or stretch?',
      noResearch: _yourCall,
      options: _plain([10, 15, 20, 30]),
      defaultValue: 15,
      label: _minutes,
    ),
  ])
    s.questKey: s,
};

/// A thing to work on. Picking one turns on its quests; the daily goals screen sets them.
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
    subtitle: 'A strength workout, a training session or push-ups',
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
    id: 'water',
    title: 'Drink enough water',
    subtitle: 'Logged here or read from Apple Health',
    icon: Icons.water_drop_rounded,
    questKeys: ['water'],
  ),
  Focus(
    id: 'steady',
    title: 'Keep a steady bedtime',
    subtitle: 'Go to bed and get up at about the same time',
    icon: Icons.alarm_on_rounded,
    questKeys: ['sleep_regularity'],
  ),
  Focus(
    id: 'produce',
    title: 'Eat your five a day',
    subtitle: 'Count servings of fruit and vegetables',
    icon: Icons.eco_rounded,
    questKeys: ['produce'],
  ),
  Focus(
    id: 'breathe',
    title: 'Breathe for 5 minutes',
    subtitle: 'A guided session, daily',
    icon: Icons.air_rounded,
    questKeys: ['breathing'],
  ),
  Focus(
    id: 'stretch',
    title: 'Yoga or stretching',
    subtitle: 'Classes, flows or a few minutes at home',
    icon: Icons.self_improvement_rounded,
    questKeys: ['yoga'],
  ),
];

/// Every quest key New Me knows, so the plan can switch off the ones nobody picked.
List<String> get kAllQuestKeys => [for (final f in kFocuses) ...f.questKeys];

const kEatFocus = 'eat';
