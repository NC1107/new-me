import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/api_client.dart';
import '../api/models.dart';
import 'board.dart';
import 'cached_notifier.dart';
import 'cached_resource.dart';
import 'caches.dart';
import 'session.dart';
import 'today.dart';

ApiClient _client(Ref ref) {
  final client = ref.read(apiClientProvider);
  if (client == null) throw StateError('Not signed in');
  return client;
}

/// Every set write moves the day's quests and possibly the board, and a new best set changes the
/// catalog; this keeps them in step.
Future<void> _afterSetWrite(Ref ref, DayDetail day) async {
  await ref.read(todayProvider.notifier).applyDay(day);
  if (ref.exists(boardProvider)) unawaited(ref.read(boardProvider.notifier).refresh());
  if (ref.exists(exercisesProvider)) unawaited(ref.read(exercisesProvider.notifier).refresh());
  if (ref.exists(trainingProgressProvider)) ref.invalidate(trainingProgressProvider);
}

/// GET /training/today: the planned session with its progression targets, or a rest day.
class TrainingTodayNotifier extends CachedNotifier<TrainingToday> {
  @override
  ResponseCache<TrainingToday> get cache => trainingTodayCache;

  @override
  Future<TrainingToday> fetch(ApiClient client) => client.trainingToday();

  /// Logs a set. A set of today's session shows on it at once; the quest follows the day.
  Future<ExerciseSet?> logSet(SetDraft draft) async {
    final result = await _client(ref).logSet(draft);
    final set = result.set;
    final today = state.value?.data;
    final session = today?.session;
    if (set != null && today != null && session != null && set.localDate == today.date) {
      await replace(
        today.withSession(
          session.copyWith(
            exercises: [
              for (final e in session.exercises)
                e.exercise == set.exercise && !e.logged.any((s) => s.id == set.id)
                    ? e.withLogged([...e.logged, set])
                    : e,
            ],
          ),
        ),
      );
    }
    await _afterSetWrite(ref, result.day);
    return set;
  }

  Future<void> deleteSet(ExerciseSet set) async {
    final result = await _client(ref).deleteSet(set.id);
    final today = state.value?.data;
    final session = today?.session;
    if (today != null && session != null) {
      await replace(
        today.withSession(
          session.copyWith(
            exercises: [
              for (final e in session.exercises)
                e.withLogged([
                  for (final s in e.logged)
                    if (s.id != set.id) s,
                ]),
            ],
          ),
        ),
      );
    }
    await _afterSetWrite(ref, result.day);
  }

  /// Completes today's session, which completes the strength quest.
  Future<void> complete() async {
    final today = state.value?.data;
    final session = today?.session;
    if (today == null || session == null) return;
    final day = await _client(ref).completeSession(session.id);
    await replace(today.withSession(session.copyWith(completed: true)));
    await _afterSetWrite(ref, day);
  }
}

final trainingTodayProvider = AsyncNotifierProvider<TrainingTodayNotifier, Cached<TrainingToday>>(
  TrainingTodayNotifier.new,
);

/// GET /exercises: the catalog, custom exercises, best sets and max tests.
class ExercisesNotifier extends CachedNotifier<ExerciseCatalog> {
  @override
  ResponseCache<ExerciseCatalog> get cache => exercisesCache;

  @override
  Future<ExerciseCatalog> fetch(ApiClient client) => client.exercises();

  Future<Exercise> createCustom({
    required String name,
    required String muscle,
    required Measure measure,
    required LoadKind load,
  }) async {
    final created = await _client(ref)
        .createExercise(name: name, primaryMuscles: [muscle], measure: measure, load: load);
    await refresh();
    return created;
  }

  Future<void> deleteCustom(Exercise exercise) async {
    await _client(ref).deleteExercise(exercise.key);
    await refresh();
  }

  Future<void> recordMaxTest(Exercise exercise, int amount) async {
    await _client(ref).recordMaxTest(
      exercise.key,
      reps: exercise.timed ? null : amount,
      seconds: exercise.timed ? amount : null,
    );
    await refresh();
  }
}

final exercisesProvider = AsyncNotifierProvider<ExercisesNotifier, Cached<ExerciseCatalog>>(
  ExercisesNotifier.new,
);

/// The training profile and the active plan, which the Training page edits together.
class TrainingSetup {
  const TrainingSetup({this.profile, this.plan});

  final TrainingProfile? profile;
  final TrainingPlan? plan;
}

class TrainingSetupNotifier extends AsyncNotifier<TrainingSetup> {
  @override
  Future<TrainingSetup> build() async {
    ref.watch(apiClientProvider);
    final client = _client(ref);
    final (profile, today) = await (client.trainingProfile(), client.trainingToday()).wait;
    return TrainingSetup(profile: profile, plan: today.plan);
  }

  Future<void> saveProfile(TrainingProfile profile) async {
    final saved = await _client(ref).saveTrainingProfile(profile);
    state = AsyncData(TrainingSetup(profile: saved, plan: state.value?.plan));
  }

  /// Designs a plan; a rejected plan throws an [ApiException] with its violations.
  Future<void> generate({int? weeks}) =>
      _replacePlan(() => _client(ref).generatePlan(weeks: weeks));

  Future<void> change(PlanChange change, {String detail = ''}) =>
      _replacePlan(() => _client(ref).changePlan(change, detail: detail));

  Future<void> endPlan() async {
    await _client(ref).endPlan();
    state = AsyncData(TrainingSetup(profile: state.value?.profile));
    await _reloadToday();
  }

  Future<void> _replacePlan(Future<TrainingPlan> Function() design) async {
    final plan = await design();
    state = AsyncData(TrainingSetup(profile: state.value?.profile, plan: plan));
    await _reloadToday();
  }

  Future<void> _reloadToday() async {
    if (ref.exists(trainingTodayProvider)) await ref.read(trainingTodayProvider.notifier).refresh();
  }
}

final trainingSetupProvider = AsyncNotifierProvider<TrainingSetupNotifier, TrainingSetup>(
  TrainingSetupNotifier.new,
);

final trainingProgressProvider = FutureProvider<TrainingProgress>(
  (ref) => _client(ref).trainingProgress(),
);

/// The sets of one exercise, oldest first, for its detail page.
final exerciseSetsProvider = FutureProvider.family<List<ExerciseSet>, String>(
  (ref, key) => _client(ref).sets(exercise: key, days: 365),
);
