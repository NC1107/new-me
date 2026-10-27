import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/api_client.dart';
import '../api/models.dart';
import 'cached_notifier.dart';
import 'cached_resource.dart';
import 'caches.dart';

/// GET /api/insights: steps, sleep and workout insights computed by the server.
class InsightsNotifier extends CachedNotifier<Insights> {
  @override
  ResponseCache<Insights> get cache => insightsCache;

  @override
  Future<Insights> fetch(ApiClient client) => client.insights();
}

final insightsProvider = AsyncNotifierProvider<InsightsNotifier, Cached<Insights>>(
  InsightsNotifier.new,
);

/// GET /api/workouts?days=N for the signed-in person, newest first.
class WorkoutsNotifier extends CachedNotifier<WorkoutList> {
  WorkoutsNotifier(this.days);

  final int days;

  @override
  ResponseCache<WorkoutList> get cache => workoutsCache(days);

  @override
  Future<WorkoutList> fetch(ApiClient client) => client.workouts(days: days);
}

final workoutsProvider = AsyncNotifierProvider.family<WorkoutsNotifier, Cached<WorkoutList>, int>(
  WorkoutsNotifier.new,
);
