import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/daily_reps_models.dart';
import 'me.dart';
import 'session.dart';
import 'targets.dart';
import 'today.dart';

/// GET /api/daily-reps: the exercises the push-ups quest can count and the person's choice.
final dailyRepsProvider = FutureProvider.autoDispose<DailyReps>((ref) {
  final client = ref.watch(apiClientProvider);
  if (client == null) throw StateError('Not signed in');
  return client.dailyReps();
});

typedef RepsPreviewKey = ({String exercise, int max});

/// The target a max gives, worked out by the server so the formula lives in one place.
final repsPreviewProvider = FutureProvider.autoDispose.family<RepsPreview, RepsPreviewKey>((
  ref,
  key,
) {
  final client = ref.watch(apiClientProvider);
  if (client == null) throw StateError('Not signed in');
  return client.previewDailyReps(exercise: key.exercise, max: key.max);
});

/// Saves the daily-reps choice and keeps every screen that shows the quest in step.
class DailyRepsActions {
  const DailyRepsActions(this._ref);

  final Ref _ref;

  Future<DailyReps> save({required String exercise, int? max, int? repsPerSet}) async {
    final client = _ref.read(apiClientProvider);
    if (client == null) throw StateError('Not signed in');
    final saved = await client.saveDailyReps(exercise: exercise, max: max, repsPerSet: repsPerSet);
    _ref.invalidate(dailyRepsProvider);
    unawaited(_ref.read(meProvider.notifier).refresh());
    if (_ref.exists(todayProvider)) unawaited(_ref.read(todayProvider.notifier).refresh());
    if (_ref.exists(targetsProvider)) unawaited(_ref.read(targetsProvider.notifier).refresh());
    return saved;
  }
}

final dailyRepsActionsProvider = Provider<DailyRepsActions>(DailyRepsActions.new);
