import 'package:newme/api/habit_models.dart';

import 'fixtures.dart';
import 'test_support.dart';

Map<String, dynamic> stateSlot(int index, String label, String? time, {bool done = false}) => {
  'index': index,
  'label': label,
  'time': time,
  'done': done,
};

Map<String, dynamic> checkState(
  int id,
  String name,
  String icon,
  List<Map<String, dynamic>> slots,
) => {
  'id': id,
  'name': name,
  'icon': icon,
  'kind': 'check',
  'slots': slots,
  'target': null,
  'count': 0,
};

Map<String, dynamic> countState(int id, String name, {int target = 8, int count = 0}) => {
  'id': id,
  'name': name,
  'icon': 'water_drop',
  'kind': 'count',
  'slots': <Map<String, dynamic>>[],
  'target': target,
  'count': count,
};

Map<String, dynamic> habitJson(
  int id,
  String name, {
  String icon = 'brush',
  String kind = 'check',
  List<int> weekdays = const [1, 2, 3, 4, 5, 6, 7],
  List<Map<String, dynamic>>? slots,
  int? target,
  bool paused = false,
  int? points,
  int? minutes,
  int? proposedPoints,
  int? proposedMinutes,
}) => {
  'id': id,
  'name': name,
  'icon': icon,
  'kind': kind,
  'weekdays': weekdays,
  'slots':
      slots ??
      (kind == 'count'
          ? <Map<String, dynamic>>[]
          : [
              {'label': 'Daily', 'time': null},
            ]),
  'target': target,
  'position': id,
  'paused': paused,
  'points': ?points,
  'minutes': minutes,
  'proposedPoints': proposedPoints,
  'proposedMinutes': proposedMinutes,
};

/// Brush teeth twice a day, Huel at noon, floss with no time, water as a count.
List<Map<String, dynamic>> dueHabits() => [
  checkState(1, 'Brush teeth', 'brush', [
    stateSlot(0, 'Morning', '07:30'),
    stateSlot(1, 'Evening', '22:00'),
  ]),
  checkState(2, 'Huel', 'lunch_dining', [stateSlot(0, 'Lunch', '12:00')]),
  checkState(3, 'Floss', 'clean_hands', [stateSlot(0, 'Daily', null)]),
  countState(4, 'Water'),
];

List<Map<String, dynamic>> allHabits() => [
  habitJson(
    1,
    'Brush teeth',
    slots: [
      {'label': 'Morning', 'time': '07:30'},
      {'label': 'Evening', 'time': '22:00'},
    ],
  ),
  habitJson(
    2,
    'Huel',
    icon: 'lunch_dining',
    weekdays: [1, 2, 3, 4, 5],
    slots: [
      {'label': 'Lunch', 'time': '12:00'},
    ],
  ),
  habitJson(3, 'Floss', icon: 'clean_hands'),
  habitJson(4, 'Water', icon: 'water_drop', kind: 'count', target: 8),
];

/// What a mark answers: the day's habit state and the rescored day.
Map<String, dynamic> markResponse(List<Map<String, dynamic>> habits, {int points = 155}) => {
  'date': '2026-10-26',
  'habits': habits,
  'day': {
    'date': '2026-10-26',
    ...dayJson(points: points),
    'quests': (richTodayJson()['quests']! as List),
  },
};

StubAdapter habitsServer({List<Map<String, dynamic>>? due, List<Map<String, dynamic>>? all}) {
  final today = richTodayJson(stepsEverSynced: true)..['habits'] = due ?? dueHabits();
  return fullServer()
    ..on('GET /api/today', StubResponse(200, today))
    ..on('GET /api/habits', StubResponse(200, {'habits': all ?? allHabits()}));
}

HabitState stateOf(Map<String, dynamic> json) => HabitState.fromJson(json);
