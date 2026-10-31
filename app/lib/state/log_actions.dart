import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/api_client.dart';
import '../api/models.dart';
import '../util/reps_exercises.dart';
import 'board.dart';
import 'meals_today.dart';
import 'session.dart';
import 'targets.dart';
import 'today.dart';
import 'training.dart';

/// The write side of the log: every save and delete keeps Today and the Board in step.
class LogActions {
  const LogActions(this._ref);

  final Ref _ref;

  ApiClient get _client {
    final client = _ref.read(apiClientProvider);
    if (client == null) throw StateError('Not signed in');
    return client;
  }

  Future<LogResult> create(LogDraft draft) async {
    final result = await _client.createLog(draft);
    await _ref.read(todayProvider.notifier).applyLog(result);
    _refreshBoard();
    _ref.invalidate(trainingHistoryProvider);
    return result;
  }

  /// Records a push-up max test. The push-up target follows the latest test, so the Targets page
  /// is reloaded if it is held.
  Future<PushupMaxResult> recordPushupMax(int reps, {String? date}) async {
    final result = await _client.recordPushupMax(reps: reps, date: date);
    if (_ref.exists(targetsProvider)) unawaited(_ref.read(targetsProvider.notifier).refresh());
    _ref.invalidate(exerciseHistoryProvider);
    return result;
  }

  /// Records a max test of the daily-reps exercise. Push-ups go through the v8 endpoint; any
  /// other exercise through its catalog max test.
  Future<void> recordRepsMax(String exercise, int reps, {String? date}) async {
    if (exercise == kDefaultRepsExercise) {
      await recordPushupMax(reps, date: date);
      return;
    }
    await _client.recordExerciseMax(exercise, reps: reps, date: date);
    if (_ref.exists(targetsProvider)) unawaited(_ref.read(targetsProvider.notifier).refresh());
    _ref.invalidate(exerciseHistoryProvider);
  }

  /// Saves a corrected meal. Today is refetched rather than patched, since the old totals are
  /// not known here, and the meal list is reloaded because a rename moves no total.
  Future<LogResult> updateMeal(MealLog meal, MealEdit edit) async {
    final result = await _client.updateMeal(meal.id, edit);
    await _ref.read(todayProvider.notifier).refresh();
    _ref.invalidate(mealsTodayProvider);
    _refreshBoard();
    return result;
  }

  Future<void> delete(LogEntry entry) async {
    await _client.deleteLog(entry);
    await _ref.read(todayProvider.notifier).refresh();
    _refreshBoard();
    _ref.invalidate(trainingHistoryProvider);
  }

  Future<List<LogEntry>> entriesFor(String date) => _client.logs(date: date);

  Future<List<RecentMeal>> recentMeals() => _client.recentMeals();

  /// Works a meal out from a sentence. Nothing is logged by this call.
  Future<MealBreakdown> estimateMeal(String text) => _client.estimateMeal(text: text);

  Future<FoodSearch> searchFoods(String q, {bool remote = false}) =>
      _client.foods(q: q, remote: remote);

  Future<SavedFood?> foodByBarcode(String code) => _client.foodByBarcode(code);

  Future<SavedFood> saveFood(SavedFood food) => _client.createFood(food);

  Future<SavedFood> updateFood(int id, SavedFood food) => _client.updateFood(id, food);

  Future<void> deleteFood(int id) => _client.deleteFood(id);

  /// After a meal is logged: counts a use of each saved food, and saves database foods (and
  /// estimates the person chose to keep) so the same food has the same numbers next time.
  /// Best effort: the meal is already logged, so a failure here is not worth surfacing.
  Future<void> syncLibrary(List<MealItem> items) async {
    for (final item in items) {
      try {
        if (item.source == FoodSource.library) {
          await _client.useFood(int.parse(item.sourceId));
        } else if (item.willSave) {
          final saved = await _client.createFood(item.toSavedFood());
          if (saved.id != null) await _client.useFood(saved.id!);
        }
      } on Object {
        continue;
      }
    }
  }

  void _refreshBoard() {
    if (_ref.exists(boardProvider)) unawaited(_ref.read(boardProvider.notifier).refresh());
  }
}

final logActionsProvider = Provider<LogActions>(LogActions.new);
