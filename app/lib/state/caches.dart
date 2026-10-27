import 'package:shared_preferences/shared_preferences.dart';

import '../api/models.dart';
import 'cached_resource.dart';

final todayCache = ResponseCache<Today>(
  key: 'cache.today',
  fromJson: Today.fromJson,
  toJson: (v) => v.toJson(),
);

final boardCache = ResponseCache<Board>(
  key: 'cache.board',
  fromJson: Board.fromJson,
  toJson: (v) => v.toJson(),
);

final meCache = ResponseCache<Me>(
  key: 'cache.me',
  fromJson: Me.fromJson,
  toJson: (v) => v.toJson(),
);

final insightsCache = ResponseCache<Insights>(
  key: 'cache.insights',
  fromJson: Insights.fromJson,
  toJson: (v) => v.toJson(),
);

const _workoutsCachePrefix = 'cache.workouts.';

/// One cache per window, since a 7 day answer must not stand in for a 90 day one.
ResponseCache<WorkoutList> workoutsCache(int days) => ResponseCache<WorkoutList>(
  key: '$_workoutsCachePrefix$days',
  fromJson: WorkoutList.fromJson,
  toJson: (v) => v.toJson(),
);

Future<void> clearResponseCaches() async {
  await todayCache.clear();
  await boardCache.clear();
  await meCache.clear();
  await insightsCache.clear();
  final prefs = await SharedPreferences.getInstance();
  for (final key in prefs.getKeys().where((k) => k.startsWith(_workoutsCachePrefix))) {
    await prefs.remove(key);
  }
}
