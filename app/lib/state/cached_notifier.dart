import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/api_client.dart';
import 'cached_resource.dart';
import 'clock.dart';
import 'session.dart';

/// A server read that survives the server being down: the last good response is stored and
/// served under an offline banner when the network or a 5xx gets in the way.
abstract class CachedNotifier<T> extends AsyncNotifier<Cached<T>> {
  ResponseCache<T> get cache;

  Future<T> fetch(ApiClient client);

  @override
  Future<Cached<T>> build() {
    ref.watch(apiClientProvider);
    return _load();
  }

  Future<Cached<T>> _load() async {
    final session = ref.read(sessionProvider).session;
    final client = ref.read(apiClientProvider);
    if (session == null || client == null) throw StateError('Not signed in');
    try {
      final value = await fetch(client);
      await cache.write(
        value,
        userId: session.userId,
        baseUrl: session.baseUrl,
        at: ref.read(clockProvider)(),
      );
      return Cached(value);
    } on ApiException catch (e) {
      if (e.kind != ApiErrorKind.offline) rethrow;
      final stored = await cache.read(userId: session.userId, baseUrl: session.baseUrl);
      if (stored == null) rethrow;
      return stored;
    }
  }

  /// Reloads without dropping the value on screen; a failure keeps it beneath the error.
  Future<void> refresh() async {
    try {
      state = AsyncData(await _load());
    } on Object catch (e, st) {
      state = AsyncError<Cached<T>>(e, st);
    }
  }

  Future<void> replace(T value) async {
    final session = ref.read(sessionProvider).session;
    if (session != null) {
      await cache.write(
        value,
        userId: session.userId,
        baseUrl: session.baseUrl,
        at: ref.read(clockProvider)(),
      );
    }
    state = AsyncData(Cached(value));
  }
}
