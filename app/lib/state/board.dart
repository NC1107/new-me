import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/api_client.dart';
import '../api/models.dart';
import 'cached_notifier.dart';
import 'cached_resource.dart';
import 'caches.dart';

class BoardNotifier extends CachedNotifier<Board> {
  @override
  ResponseCache<Board> get cache => boardCache;

  @override
  Future<Board> fetch(ApiClient client) => client.board();
}

final boardProvider = AsyncNotifierProvider<BoardNotifier, Cached<Board>>(BoardNotifier.new);
