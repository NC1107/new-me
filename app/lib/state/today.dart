import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/api_client.dart';
import '../api/models.dart';
import 'cached_notifier.dart';
import 'cached_resource.dart';
import 'caches.dart';
import 'clock.dart';

class TodayNotifier extends CachedNotifier<Today> {
  @override
  ResponseCache<Today> get cache => todayCache;

  @override
  Future<Today> fetch(ApiClient client) => client.today();

  /// Shows a just-saved entry without a second GET. Entries for another day only refresh.
  Future<void> applyLog(LogResult result) async {
    final today = state.value?.data;
    if (today == null || result.log.localDate != today.localToday) return refresh();
    final log = result.log;
    await replace(
      today.copyWith(
        day: result.day,
        quests: result.quests,
        food: log is MealLog ? today.food.plusMeal(log) : null,
      ),
    );
  }

  /// Applies the day scores a health push returned, so no second GET /today is needed.
  Future<void> applyRescored(HealthDailyResult result) async {
    final today = state.value?.data;
    if (today == null) return;
    for (final rescored in result.days) {
      if (rescored.date != today.localToday) continue;
      await replace(
        today.copyWith(
          day: rescored.day,
          quests: rescored.quests,
          health: HealthStatus(hasSteps: true, syncedAt: ref.read(clockProvider)().toUtc()),
        ),
      );
      return;
    }
  }
}

final todayProvider = AsyncNotifierProvider<TodayNotifier, Cached<Today>>(TodayNotifier.new);
