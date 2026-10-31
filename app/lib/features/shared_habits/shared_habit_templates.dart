import '../../api/shared_habit_models.dart';

/// A starting point for the chore sheet, so the usual household jobs take a pick and a save.
class SharedHabitTemplate {
  const SharedHabitTemplate({required this.name, required this.icon, required this.schedule});

  final String name;
  final String icon;
  final SharedSchedule schedule;
}

const kSharedHabitTemplates = <SharedHabitTemplate>[
  SharedHabitTemplate(
    name: 'Do the laundry',
    icon: 'local_laundry_service',
    schedule: SharedSchedule(kind: SharedKind.weekly),
  ),
  SharedHabitTemplate(
    name: 'Do the dishes',
    icon: 'restaurant',
    schedule: SharedSchedule(kind: SharedKind.daily),
  ),
  SharedHabitTemplate(
    name: 'Clean the bathroom',
    icon: 'bathtub',
    schedule: SharedSchedule(kind: SharedKind.weekly),
  ),
  SharedHabitTemplate(
    name: 'Vacuum',
    icon: 'cleaning_services',
    schedule: SharedSchedule(kind: SharedKind.weekly),
  ),
  SharedHabitTemplate(
    name: 'Take out the trash',
    icon: 'delete',
    schedule: SharedSchedule(kind: SharedKind.everyN, everyDays: 3),
  ),
  SharedHabitTemplate(
    name: 'Change the sheets',
    icon: 'bedtime',
    schedule: SharedSchedule(kind: SharedKind.everyN, everyDays: 14),
  ),
  SharedHabitTemplate(
    name: 'Groceries',
    icon: 'shopping_cart',
    schedule: SharedSchedule(kind: SharedKind.weekly),
  ),
  SharedHabitTemplate(
    name: 'Water the plants',
    icon: 'eco',
    schedule: SharedSchedule(kind: SharedKind.everyN, everyDays: 3),
  ),
];
