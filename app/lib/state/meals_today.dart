import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/models.dart';
import '../util/format.dart';
import 'log_actions.dart';
import 'today.dart';

Future<List<MealLog>> _mealsOn(Ref ref, String date) async {
  final entries = await ref.read(logActionsProvider).entriesFor(date);
  return [...entries.whereType<MealLog>()]..sort((a, b) => b.loggedAt.compareTo(a.loggedAt));
}

/// What a day's meal list refetches on: today's food totals move whenever a meal is logged,
/// edited, moved or deleted.
(String, num, num)? _key(Ref ref) => ref.watch(
  todayProvider.select((v) {
    final t = v.value?.data;
    return t == null ? null : (t.localToday, t.food.kcal, t.food.protein);
  }),
);

/// Today's meals, newest first.
final mealsTodayProvider = FutureProvider.autoDispose<List<MealLog>>((ref) async {
  final key = _key(ref);
  if (key == null) return const [];
  return _mealsOn(ref, key.$1);
});

/// Yesterday's meals, newest first, so one can be logged again or still corrected while its day
/// is open.
final mealsYesterdayProvider = FutureProvider.autoDispose<List<MealLog>>((ref) async {
  final key = _key(ref);
  if (key == null) return const [];
  return _mealsOn(ref, previousDate(key.$1));
});
