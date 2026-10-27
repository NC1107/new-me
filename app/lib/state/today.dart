import 'dart:async';

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
        day: result.day.score,
        quests: result.day.quests,
        food: log is MealLog ? today.food.plusMeal(log) : null,
      ),
    );
    _reloadStreakIfDayFlipped(today, result.day.score);
  }

  /// Applies a rescored day another write answered with, such as a logged set or a completed
  /// training session. Another day only refreshes.
  Future<void> applyDay(DayDetail day) async {
    final today = state.value?.data;
    if (today == null || day.date != today.localToday) return refresh();
    await replace(today.copyWith(day: day.score, quests: day.quests));
    _reloadStreakIfDayFlipped(today, day.score);
  }

  /// Applies the day scores a health push returned, so no second GET /today is needed.
  /// [burnedByDate] carries the active energy that was pushed, which the scores do not repeat.
  Future<void> applyRescored(
    HealthDailyResult result, {
    Map<String, num> burnedByDate = const {},
    Map<String, Map<String, double>> metricsByDate = const {},
  }) async {
    final today = state.value?.data;
    if (today == null) return;
    for (final rescored in result.days) {
      if (rescored.date != today.localToday) continue;
      final burned = burnedByDate[rescored.date];
      await replace(
        today.copyWith(
          day: rescored.score,
          quests: rescored.quests,
          food: burned == null ? null : today.food.withBurned(burned),
          health: today.health.synced(
            ref.read(clockProvider)().toUtc(),
            metrics: metricsByDate[rescored.date] ?? const {},
          ),
        ),
      );
      _reloadStreakIfDayFlipped(today, rescored.score);
      return;
    }
  }

  /// The streak is the server's to derive, so a day that just started or stopped counting
  /// fetches it instead of guessing.
  void _reloadStreakIfDayFlipped(Today before, DayScore after) {
    if (before.day.counted != after.counted) unawaited(refresh());
  }
}

final todayProvider = AsyncNotifierProvider<TodayNotifier, Cached<Today>>(TodayNotifier.new);
