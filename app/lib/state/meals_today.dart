import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/models.dart';
import 'log_actions.dart';
import 'today.dart';

/// Today's meals, newest first. Refetched whenever today's food totals move, which is what a
/// logged, edited or deleted meal does.
final mealsTodayProvider = FutureProvider.autoDispose<List<MealLog>>((ref) async {
  final key = ref.watch(
    todayProvider.select((v) {
      final t = v.value?.data;
      return t == null ? null : (t.localToday, t.food.kcal, t.food.protein);
    }),
  );
  if (key == null) return const [];
  final entries = await ref.read(logActionsProvider).entriesFor(key.$1);
  return [...entries.whereType<MealLog>()]..sort((a, b) => b.loggedAt.compareTo(a.loggedAt));
});
