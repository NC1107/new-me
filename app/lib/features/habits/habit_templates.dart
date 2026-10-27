import '../../api/habit_models.dart';

const kEveryDay = [1, 2, 3, 4, 5, 6, 7];
const kWeekdays = [1, 2, 3, 4, 5];

/// A starting point for the editor, so the usual habits take a pick and a save.
class HabitTemplate {
  const HabitTemplate({
    required this.name,
    required this.icon,
    this.weekdays = kEveryDay,
    this.slots = const [],
    this.target,
    this.custom = false,
  });

  final String name;
  final String icon;
  final List<int> weekdays;
  final List<HabitSlot> slots;

  /// Set for a count habit.
  final int? target;
  final bool custom;

  bool get isCount => target != null;
}

const kHabitTemplates = <HabitTemplate>[
  HabitTemplate(
    name: 'Brush teeth',
    icon: 'brush',
    slots: [
      HabitSlot(label: 'Morning', time: '07:30'),
      HabitSlot(label: 'Evening', time: '22:00'),
    ],
  ),
  HabitTemplate(
    name: 'Creatine',
    icon: 'bolt',
    slots: [HabitSlot(label: 'Daily', time: '08:00')],
  ),
  HabitTemplate(
    name: 'Huel',
    icon: 'lunch_dining',
    weekdays: kWeekdays,
    slots: [HabitSlot(label: 'Lunch', time: '12:00')],
  ),
  HabitTemplate(name: 'Water', icon: 'water_drop', target: 8),
  HabitTemplate(
    name: 'Vitamins',
    icon: 'medication',
    slots: [HabitSlot(label: 'Morning', time: '08:00')],
  ),
  HabitTemplate(
    name: 'Floss',
    icon: 'clean_hands',
    slots: [HabitSlot(label: 'Evening', time: '22:00')],
  ),
  HabitTemplate(
    name: 'Stretch',
    icon: 'self_improvement',
    slots: [HabitSlot(label: 'Daily')],
  ),
  HabitTemplate(
    name: '',
    icon: 'check_circle',
    slots: [HabitSlot(label: 'Daily')],
    custom: true,
  ),
];
