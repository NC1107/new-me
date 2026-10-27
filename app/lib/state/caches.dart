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

Future<void> clearResponseCaches() async {
  await todayCache.clear();
  await boardCache.clear();
  await meCache.clear();
}
